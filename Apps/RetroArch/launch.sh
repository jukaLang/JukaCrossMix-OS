#!/bin/sh
echo "$0" "$*"

export PATH="/mnt/SDCARD/System/usr/trimui/scripts/:/mnt/SDCARD/System/bin:$PM_DIR:${PATH:+:$PATH}"
export LD_LIBRARY_PATH="/usr/trimui/lib:/mnt/SDCARD/System/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
read -r current_device </etc/trimui_device.txt

# Switch audio and set hotkey
ra_audio_switcher.sh
touch /var/trimui_inputd/ra_hotkey

RA_DIR=/mnt/SDCARD/RetroArch
cd "$RA_DIR"

# Auto-detect best binary for this device
files=$(ls /mnt/SDCARD/RetroArch/ra64.trimui_${current_device}_*.bin 2>/dev/null)
BEST_BIN=$(echo "$files" | sort -V | tail -n 1)

# Brick Pro falls back to Brick binary if no dedicated build exists
if [ -z "$BEST_BIN" ] && [ "$current_device" = "brickpro" ]; then
    files=$(ls /mnt/SDCARD/RetroArch/ra64.trimui_brick_*.bin 2>/dev/null)
    BEST_BIN=$(echo "$files" | sort -V | tail -n 1)
fi

# Run the button_state.sh script
/mnt/SDCARD/System/usr/trimui/scripts/button_state.sh Y
if [ $? -eq 10 ]; then

    FILE_LIST=""

    for f in /mnt/SDCARD/RetroArch/ra64.trimui_${current_device}_*.bin; do
        FILE_LIST="$FILE_LIST '$(basename "$f")' "
    done

    # Also include Brick binaries for Brick Pro users
    if [ "$current_device" = "brickpro" ]; then
        for f in /mnt/SDCARD/RetroArch/ra64.trimui_brick_*.bin; do
            FILE_LIST="$FILE_LIST '$(basename "$f")' "
        done
    fi

    if [ -z "$FILE_LIST" ]; then
        echo "No files found for device $current_device."
        exit 1
    fi

    SELECTED_FILE=$(eval /mnt/SDCARD/System/bin/selector -fs 120 -c $FILE_LIST | grep "You selected")
    SELECTED_FILE=$(printf '%s\n' "$SELECTED_FILE" | sed 's/^.*: //')

fi

if [ -z "$SELECTED_FILE" ]; then
    if [ -n "$BEST_BIN" ]; then
        SELECTED_FILE="$(basename "$BEST_BIN")"
    else
        SELECTED_FILE="ra64.trimui"
    fi
fi

HOME="$RA_DIR/" "$RA_DIR/$SELECTED_FILE"
