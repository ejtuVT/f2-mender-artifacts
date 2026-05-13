#!/bin/sh
set -e

ETC_DIR="/etc/mender/inventory"
USR_DIR="/usr/share/mender/inventory"

DEVICE_INFO="/etc/mender/device-info"

ACTIVE_SCRIPT="$ETC_DIR/mender-inventory-active-network"
DEVICE_SCRIPT="$ETC_DIR/mender-inventory-device-info"
TIME_SCRIPT="$ETC_DIR/mender-inventory-check-in-time"

TMP_ACTIVE="$(mktemp)"
TMP_DEVICE="$(mktemp)"
TMP_TIME="$(mktemp)"

# ------------------------------------------------------------------
# Validate directories
# ------------------------------------------------------------------
[ -d "$ETC_DIR" ] || exit 0
mkdir -p "$USR_DIR"

# ------------------------------------------------------------------
# Disable geo script (safe)
# ------------------------------------------------------------------
if [ -f "$ETC_DIR/mender-inventory-geo" ]; then
    chmod -x "$ETC_DIR/mender-inventory-geo" || true
fi

# ------------------------------------------------------------------
# Install ACTIVE NETWORK
# ------------------------------------------------------------------
cat > "$TMP_ACTIVE" << 'EOF'
#!/bin/sh

ACTIVE_IF=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)

if [ -z "$ACTIVE_IF" ]; then
    echo "network_primary_interface=unknown"
    echo "network_primary_type=unknown"
else
    case "$ACTIVE_IF" in
        eth*|en*) TYPE="ethernet" ;;
        wlan*|wl*) TYPE="wifi" ;;
        wwan*|usb*|rmnet*|cdc*) TYPE="cellular" ;;
        *) TYPE="other" ;;
    esac

    echo "network_primary_interface=$ACTIVE_IF"
    echo "network_primary_type=$TYPE"
fi

IF_ORDER="eth1 eth2 eth0"

is_valid_mac() {
    mac="$1"
    iface="$2"

    echo "$mac" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' || return 1
    mac=$(echo "$mac" | tr 'A-F' 'a-f')

    [ "$mac" = "00:00:00:00:00:00" ] && return 1
    [ "$mac" = "ff:ff:ff:ff:ff:ff" ] && return 1
    [ -e "/sys/class/net/$iface/device" ] || return 1

    return 0
}

ETH_IF=""

for IF in $IF_ORDER; do
    addr_file="/sys/class/net/$IF/address"
    [ -r "$addr_file" ] || continue

    mac=$(cat "$addr_file")

    if is_valid_mac "$mac" "$IF"; then
        ETH_IF="$IF"
        break
    fi
done

[ -n "$ETH_IF" ] && echo "network_ethernet_interface=$ETH_IF" || echo "network_ethernet_interface=unknown"

exit 0
EOF

chmod 0755 "$TMP_ACTIVE"
mv "$TMP_ACTIVE" "$ACTIVE_SCRIPT"

# ------------------------------------------------------------------
# Install DEVICE INFO inventory script
# ------------------------------------------------------------------
cat > "$TMP_DEVICE" << 'EOF'
#!/bin/sh

CONFIG_FILE="/etc/mender/device-info"

[ -f "$CONFIG_FILE" ] || exit 0

while IFS= read -r line; do
    case "$line" in
        ""|\#*) continue ;;
        *=*) echo "$line" ;;
    esac
done < "$CONFIG_FILE"

exit 0
EOF

chmod 0755 "$TMP_DEVICE"
mv "$TMP_DEVICE" "$DEVICE_SCRIPT"

# ------------------------------------------------------------------
# Install UTC TIME script
# ------------------------------------------------------------------
cat > "$TMP_TIME" << 'EOF'
#!/bin/sh
echo "device_utc_time=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
EOF

chmod 0755 "$TMP_TIME"
mv "$TMP_TIME" "$TIME_SCRIPT"

# ------------------------------------------------------------------
# Enforce symlinks
# ------------------------------------------------------------------
ln -sf "$ACTIVE_SCRIPT" "$USR_DIR/mender-inventory-active-network"
ln -sf "$DEVICE_SCRIPT" "$USR_DIR/mender-inventory-device-info"
ln -sf "$TIME_SCRIPT" "$USR_DIR/mender-inventory-check-in-time"

# ------------------------------------------------------------------
# Device-info migration (SAFE)
# ------------------------------------------------------------------
[ -f "$DEVICE_INFO" ] || touch "$DEVICE_INFO"

if grep -q '^device_location_name=' "$DEVICE_INFO"; then
    echo "device-info already correct, skipping"
else
    DEVICE_NAME=$(grep '^device_name=' "$DEVICE_INFO" | head -n1 | sed 's/^device_name=//')
    [ -z "$DEVICE_NAME" ] && DEVICE_NAME="unknown"

    printf 'device_location_name=%s\n' "$DEVICE_NAME" > "$DEVICE_INFO"
    echo "device-info updated"
fi

exit 0