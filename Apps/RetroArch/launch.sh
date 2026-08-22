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

# Run the button_state.sh script
/mnt/SDCARD/System/usr/trimui/scripts/button_state.sh Y
if [ $? -eq 10 ]; then

    FILE_LIST=""

    for f in /mnt/SDCARD/RetroArch/ra64.trimui_${current_device}_*.bin; do
        FILE_LIST="$FILE_LIST '$(basename "$f")' "
    done

    if [ -z "$FILE_LIST" ]; then
        echo "No files found for device $current_device."
        exit 1
    fi

    SELECTED_FILE=$(eval /mnt/SDCARD/System/bin/selector -fs 120 -c $FILE_LIST | grep "You selected")
    SELECTED_FILE=$(printf '%s\n' "$SELECTED_FILE" | sed 's/^.*: //')

fi

if [ -z "$SELECTED_FILE" ]; then
    SELECTED_FILE="ra64.trimui"
fi

HOME="$RA_DIR/" "$RA_DIR/$SELECTED_FILE"
