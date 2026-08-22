#!/bin/sh
PATH="/mnt/SDCARD/System/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/System/lib:/usr/trimui/lib:$LD_LIBRARY_PATH"

silent=false
for arg in "$@"; do
    if [ "$arg" = "-s" ]; then
        silent=true
        break
    fi
done

EmuCleanerPath="$(dirname "$0")/"

if [ "$silent" = false ]; then
    # /mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -i "$EmuCleanerPath/background.jpg" -t 10 &
    /usr/sbin/pic2fb "$EmuCleanerPath/background.jpg"
    /usr/trimui/bin/pic2fb_drm "$EmuCleanerPath/background.jpg" 3000 &
fi

# Run the C binary
# Pass arguments to the binary (like -s)
output=$("$EmuCleanerPath/EmuCleaner" "$@")

# Parse the output for NumAdded and NumRemoved
NumAdded=$(echo "$output" | grep "NUM_ADDED=" | cut -d= -f2)
NumRemoved=$(echo "$output" | grep "NUM_REMOVED=" | cut -d= -f2)

# Display the output (stdout of the binary)
echo -ne "\n=============================\n"
echo -ne "${NumAdded} displayed emulator(s)\n${NumRemoved} hidden emulator(s)\n"
echo -ne "=============================\n\n"

if [ "$silent" = false ]; then
    /mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -i "$EmuCleanerPath/background-info.jpg" -m "${NumAdded} displayed emulator(s).      ${NumRemoved} hidden emulator(s)." -t 2
fi
