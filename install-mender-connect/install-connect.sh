#!/bin/bash
set -e

if ! dpkg -l | grep -q mender-connect; then
  apt update
  apt install -y mender-connect
fi

cat <<EOF > /etc/mender/mender-connect.conf
{
  "ShellCommand": "/bin/bash",
  "User": "nvidia"
}
EOF

systemctl enable mender-connect
systemctl restart mender-connect
