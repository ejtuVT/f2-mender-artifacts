#!/bin/bash
set -e

VENV_PYTHON="/home/nvidia/projects/F2-App/.venv/bin/python3"
PY_SCRIPT="/tmp/f2_cert_name.py"

if [ ! -x "$VENV_PYTHON" ]; then
    echo "Venv python not found"
    exit 0
fi

cat > "$PY_SCRIPT" <<'PYTHON'
import asyncio
import aiomqtt
import os
import subprocess

CERT_DIR = "/home/nvidia/projects/F2-App/certs"
ENDPOINT = "a35lkm5jyds64h-ats.iot.us-east-1.amazonaws.com"
PORT = 8883

DEVICE_ID_SCRIPT = "/home/nvidia/tools/f2-maintenance-tools/get-device-id-f2.sh"

TOPIC_BASE = "tele/{device}/logs"
TOPIC_SUFFIX = "cert"


def find_cert(pattern):
    for f in os.listdir(CERT_DIR):
        if pattern in f:
            return os.path.join(CERT_DIR, f)
    return None


async def main():

    device_id = subprocess.check_output(
        [DEVICE_ID_SCRIPT]
    ).decode().strip()

    topic = f"{TOPIC_BASE.format(device=device_id)}/{TOPIC_SUFFIX}"

    ca = os.path.join(CERT_DIR, "AmazonRootCA1.pem")
    cert = find_cert("-certificate.pem.crt")
    key = find_cert("-private.pem.key")

    if not cert or not key:
        return

    cert_name = os.path.basename(cert)

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

            await client.publish(topic, cert_name)

    except Exception:
        pass


asyncio.run(main())
PYTHON

$VENV_PYTHON "$PY_SCRIPT" || true
rm -f "$PY_SCRIPT"

exit 0
