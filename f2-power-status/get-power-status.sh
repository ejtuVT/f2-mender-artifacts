#!/bin/bash
set -e

VENV_PYTHON="/home/nvidia/projects/F2-App/.venv/bin/python3"
PY_SCRIPT="/tmp/f2_power_snapshot.py"

if [ ! -x "$VENV_PYTHON" ]; then
    echo "Venv python not found"
    exit 0
fi

cat > "$PY_SCRIPT" <<'PYTHON'
import asyncio
import aiomqtt
import subprocess
import os
import json

CERT_DIR = "/home/nvidia/projects/F2-App/certs"
ENDPOINT = "a35lkm5jyds64h-ats.iot.us-east-1.amazonaws.com"
PORT = 8883

DEVICE_ID_SCRIPT = "/home/nvidia/tools/f2-maintenance-tools/get-device-id-f2.sh"

TOPIC_BASE = "tele/{device}/logs"
TOPIC_SUFFIX = "power"


def find_cert(pattern):
    for f in os.listdir(CERT_DIR):
        if pattern in f:
            return os.path.join(CERT_DIR, f)
    return None


def get_power_mode():

    try:

        out = subprocess.check_output(
            ["nvpmodel", "-q"],
            stderr=subprocess.DEVNULL,
            text=True
        )

        mode_name = None
        mode_id = None

        for line in out.splitlines():

            line = line.strip()

            if "NV Power Mode" in line:
                mode_name = line.split(":")[1].strip()

            elif line.isdigit():
                mode_id = int(line)

        return mode_name, mode_id

    except Exception:
        return "unknown", None


async def main():

    device_id = subprocess.check_output(
        [DEVICE_ID_SCRIPT]
    ).decode().strip()

    topic = f"{TOPIC_BASE.format(device=device_id)}/{TOPIC_SUFFIX}"

    mode_name, mode_id = get_power_mode()

    ca = os.path.join(CERT_DIR, "AmazonRootCA1.pem")
    cert = find_cert("-certificate.pem.crt")
    key = find_cert("-private.pem.key")

    if not cert or not key:
        return

    payload = {
        "device": device_id,
        "type": "power",
        "power_mode": mode_name,
        "mode_id": mode_id
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
