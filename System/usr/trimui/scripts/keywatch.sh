#!/bin/sh

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [KEY_CODE]"
    echo "Example (MENU button): $0 1"
    exit 1
fi

KEY_CODE=$1

KEYBOARD_EVENT="/dev/input/event3" # Default fallback

for event in /sys/class/input/event*; do
    if [ -f "$event/device/name" ]; then
        if [ "$(cat "$event/device/name")" = "TRIMUI Player1" ]; then
            KEYBOARD_EVENT="/dev/input/${event##*/}"
            break
        fi
    fi
done

# Check if the keyboard event file exists
if [ ! -e "$KEYBOARD_EVENT" ]; then
    echo "Input device $KEYBOARD_EVENT is not available."
    exit 1
fi

# Debug: Display the KEY_CODE value
echo "KEY_CODE: $KEY_CODE"

# Use evtest to read keyboard events for 5 seconds
timeout 5 /mnt/SDCARD/System/usr/trimui/scripts/evtest "$KEYBOARD_EVENT" | while IFS= read -r line; do
    # Search for KEY_CODE in the current line
    if echo "$line" | grep -q "type 1 (EV_KEY), code $KEY_CODE"; then
        # Extract key state
        state=$(echo "$line" | awk '{print $NF}')
        echo "Key $KEY_CODE state: $state"
        break
    fi
done
