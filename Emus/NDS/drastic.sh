#!/bin/sh
source /mnt/SDCARD/System/usr/trimui/scripts/common_launcher.sh
cpufreq.sh ondemand 4 7

cd drastic
export HOME="$PWD"

# Add LOG_FILE detection
LOG_FILE="/tmp/log/messages"
[ -f "/tmp/messages" ] && LOG_FILE="/tmp/messages"

LAUNCHER=$(grep -i "dowork 0x" "$LOG_FILE" | tail -n 1)


# Advanced mode
if echo "$LAUNCHER" | grep -iq "Advanced"; then
    echo "Launching in Advanced Mode"
    export LD_LIBRARY_PATH="$PWD/libs:$LD_LIBRARY_PATH"
	exec ./drastic "$@"
fi

# Simple overlay mode
if echo "$LAUNCHER" | grep -iq "(Overlay"; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$PWD/lib"
    export LD_PRELOAD="./lib/libSDL2-2.0.so.0.2600.1"
fi

# Filter mode (bilinear or nearest)
if echo "$LAUNCHER" | grep -iq "Nearest"; then
    echo "Using nearest neighbour scaling"
    exec ./drastic_2.5.2.2_nearest "$@"
else
    echo "Using bilinear scaling"
    exec ./drastic_2.5.2.2 "$@"
fi

