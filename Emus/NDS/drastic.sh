#!/bin/sh
. /mnt/SDCARD/System/usr/trimui/scripts/common_launcher.sh
cpufreq.sh ondemand 4 7

DRSTIC_DIR="$EMU_DIR/drastic"
cd "$DRSTIC_DIR" || exit 1
export HOME="$PWD"

# Add LOG_FILE detection
LOG_FILE="/tmp/log/messages"
[ -f "/tmp/messages" ] && LOG_FILE="/tmp/messages"

# The launcher picked in the MainUI "launch options" list is logged by
# load_launcher.sh as "<name> dowork 0x" — take the last entry for this run.
LAUNCHER=$(grep -i "dowork 0x" "$LOG_FILE" 2>/dev/null | tail -n 1)

# Brick / Brick Pro: the A133P ALSA dmix needs a larger period/buffer or
# audio crackles (community fix from the maintained Advanced Drastic pak).
if [ "$current_device" = "brick" ] || [ "$current_device" = "brickpro" ]; then
    export ALSA_CONFIG_PATH="$DRSTIC_DIR/alsa/nds_alsa.conf"
    export ALSA_ASOUNDRC="$DRSTIC_DIR/alsa/.asoundrc"
fi

# Advanced mode: the maintained Advanced Drastic build. The plugin
# (libs/libadvdrastic.so) hooks the binary and needs SDL2_image / SDL2_ttf /
# json-c / libjpeg from libs/ — the image ships everything except SDL2_ttf +
# FreeType. When the stack is complete, preload the plugin (pak mechanism);
# otherwise fall back to the base build (original CrossMix behavior).
if echo "$LAUNCHER" | grep -iq "Advanced"; then
    echo "Launching in Advanced Mode"
    export LD_LIBRARY_PATH="$DRSTIC_DIR/libs:$LD_LIBRARY_PATH"
    if [ -f "$DRSTIC_DIR/libs/libSDL2_ttf-2.0.so.0" ]; then
        export LD_PRELOAD="$DRSTIC_DIR/libs/libadvdrastic.so"
    else
        echo "SDL2_ttf missing - advanced plugin unavailable, running base build."
    fi
    exec ./drastic "$@"
fi

# Overlay modes: preload the freeimage-enabled SDL2 2.0.26 runtime from lib/
# (this is what draws the on-screen bezel/overlay around the DS screens).
if echo "$LAUNCHER" | grep -iq "(Overlay"; then
    if [ -f "$DRSTIC_DIR/lib/libSDL2-2.0.so.0.2600.1" ]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$DRSTIC_DIR/lib"
        export LD_PRELOAD="$DRSTIC_DIR/lib/libSDL2-2.0.so.0.2600.1"
    else
        echo "Overlay SDL2 runtime not found, continuing without overlay."
    fi
fi

# Filter mode (bilinear or nearest)
if echo "$LAUNCHER" | grep -iq "Nearest"; then
    if [ -f ./drastic_2.5.2.2_nearest ]; then
        echo "Using nearest neighbour scaling"
        exec ./drastic_2.5.2.2_nearest "$@"
    else
        echo "Nearest build not found, falling back to bilinear."
    fi
fi

echo "Using bilinear scaling"
exec ./drastic_2.5.2.2 "$@"
