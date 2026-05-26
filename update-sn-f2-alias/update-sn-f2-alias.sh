#!/bin/sh
set -e

BASHRC="/home/nvidia/.bashrc"
TMP="$(mktemp)"

[ -f "$BASHRC" ] || exit 0

OWNER="$(stat -c '%u:%g' "$BASHRC")"

# Already updated → skip
if grep -q 'alias sn-board-f2="sudo i2ctransfer -f -y 1 w1@0x58 0x80 r16 | sed '\''s/0x//g'\''"' "$BASHRC"; then
    echo "Alias already updated, skipping"
    exit 0
fi

SKIP=0

while IFS= read -r line; do
    if [ "$SKIP" -eq 1 ]; then
        SKIP=0
        continue
    fi

    case "$line" in
        alias\ sn-board-f2=*)
            echo 'alias sn-board-f2="sudo i2ctransfer -f -y 1 w1@0x58 0x80 r16 | sed '\''s/0x//g'\''"' >> "$TMP"
            echo "$line" | grep -q '\\$' && SKIP=1
            ;;
        *)
            echo "$line" >> "$TMP"
            ;;
    esac
done < "$BASHRC"

mv "$TMP" "$BASHRC"

# Restore ownership
chown "$OWNER" "$BASHRC"

echo "Alias updated successfully"

exit 0