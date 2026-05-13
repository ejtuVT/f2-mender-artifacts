#!/bin/sh
set -e

ETC_DIR="/etc/mender/inventory"
USR_DIR="/usr/share/mender/inventory"

SCRIPT_NAME="mender-inventory-memory-usage"

TARGET_ETC="$ETC_DIR/$SCRIPT_NAME"
TARGET_USR="$USR_DIR/$SCRIPT_NAME"

TMP_FILE="$(mktemp)"

# ------------------------------------------------------------------
# Validate directories
# ------------------------------------------------------------------
[ -d "$ETC_DIR" ] || exit 0
mkdir -p "$USR_DIR"

# ------------------------------------------------------------------
# Create inventory script
# ------------------------------------------------------------------
cat > "$TMP_FILE" << 'EOF'
#!/bin/sh
set -e

_total=$(awk '/MemTotal/     {print $2; exit}' /proc/meminfo)
_avail=$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo)

echo "mem_used_kB=$(( _total - _avail ))"

_disk_total=$(df -k / | awk 'NR==2 {print $2}')
_disk_used=$(df -k /  | awk 'NR==2 {print $3}')

echo "disk_total_kB=$_disk_total"
echo "disk_used_kB=$_disk_used"
EOF

chmod 0755 "$TMP_FILE"

# ------------------------------------------------------------------
# Install into /etc
# ------------------------------------------------------------------
mv "$TMP_FILE" "$TARGET_ETC"

# ------------------------------------------------------------------
# Symlink into /usr
# ------------------------------------------------------------------
ln -sf "$TARGET_ETC" "$TARGET_USR"

echo "Installed $SCRIPT_NAME"

exit 0