#!/bin/bash
set -e

VENV_PYTHON="/home/nvidia/projects/F2-App/.venv/bin/python3"
SYSTEM_PYTHON="/usr/bin/python3"

WORKDIR="$(pwd)"
PY_SCRIPT="$WORKDIR/f2_diagnostic_snapshot.py"

if [ ! -x "$VENV_PYTHON" ]; then
    echo "Venv python not found: $VENV_PYTHON"
    exit 0
fi

cat > "$PY_SCRIPT" <<PYTHON
import asyncio
import aiomqtt
import subprocess
import os
import re
import time
import json
from datetime import datetime

CERT_DIR = "/home/nvidia/projects/F2-App/certs"
ENDPOINT = "a35lkm5jyds64h-ats.iot.us-east-1.amazonaws.com"
PORT = 8883

DEVICE_ID_SCRIPT = "/home/nvidia/tools/f2-maintenance-tools/get-device-id-f2.sh"


def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def s16(x):
    return x - 65536 if x >= 32768 else x


def find_cert(pattern):
    for f in os.listdir(CERT_DIR):
        if pattern in f:
            return os.path.join(CERT_DIR, f)
    return None


def can_available():
    try:
        with open("/sys/class/net/can0/operstate") as f:
            return f.read().strip() == "up"
    except:
        return False


def collect_fan_logs():

    logs = []

    code = """
from jtop import jtop
import time
from datetime import datetime

def ts():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

with jtop() as j:
    for _ in range(5):
        print(f"{ts()} {round(j.fan.speed)} {j.fan.rpm}")
        time.sleep(0.1)
"""

    try:

        proc = subprocess.Popen(
            ["python3", "-c", code],
            stdout=subprocess.PIPE,
            text=True
        )

        for line in proc.stdout:

            parts = line.strip().split()

            if len(parts) < 4:
                continue

            ts = parts[0] + " " + parts[1]
            pwm = parts[2]
            rpm = parts[3]

            logs.append({
                "timestamp": ts,
                "pwm_percent": int(pwm),
                "rpm": int(rpm)
            })

        proc.wait()

    except Exception:
        return []

    return logs


def collect_can_logs():

    logs = []

    if not can_available():
        return logs

    try:

        proc = subprocess.Popen(
            ["candump", "can0"],
            stdout=subprocess.PIPE,
            text=True
        )

        rpm = None
        temp = None

        for line in proc.stdout:

            line = re.sub(r'^\([^)]*\)\s+', '', line)
            parts = line.strip().split()

            if len(parts) < 5:
                continue

            canid = parts[1]
            dlc = int(parts[2].strip("[]"))

            if canid == "200" and dlc >= 4:

                b0 = int(parts[3], 16)
                b1 = int(parts[4], 16)
                b2 = int(parts[5], 16)
                b3 = int(parts[6], 16)

                rpm = b0 + 256*b1 + 65536*b2 + 16777216*b3

            elif canid == "201" and dlc >= 2:

                b0 = int(parts[3], 16)
                b1 = int(parts[4], 16)

                raw = s16(b0 + 256*b1)
                temp = raw / 256.0

            if rpm is not None and temp is not None:

                logs.append({
                    "timestamp": timestamp(),
                    "rpm": rpm,
                    "temperature_c": round(temp, 3)
                })

                rpm = None
                temp = None

                if len(logs) >= 5:
                    proc.terminate()
                    proc.wait()
                    break

    except Exception:
        return []

    return logs


async def main():

    fan_logs = collect_fan_logs()
    can_logs = collect_can_logs()

    device_id = subprocess.check_output(
        [DEVICE_ID_SCRIPT]
    ).decode().strip()

    topic = f"tele/{device_id}/logs"

    ca = os.path.join(CERT_DIR, "AmazonRootCA1.pem")
    cert = find_cert("-certificate.pem.crt")
    key = find_cert("-private.pem.key")

    if not cert or not key:
        return

    payload = {
        "device": device_id,
        "fan_log": fan_logs,
        "can_log": can_logs
    }

    try:

        async with aiomqtt.Client(
            ENDPOINT,
            PORT,
            tls_params=aiomqtt.TLSParameters(
                ca_certs=ca,
                certfile=cert,
                keyfile=key
            ),
        ) as client:

            await client.publish(topic, json.dumps(payload))

    except Exception:
        pass


asyncio.run(main())
PYTHON

$VENV_PYTHON "$PY_SCRIPT" || true

rm -f "$PY_SCRIPT"

exit 0
