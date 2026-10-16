export PATH="/mnt/SDCARD/System/usr/trimui/scripts/:/mnt/SDCARD/System/bin:${PATH:+:$PATH}"
export LD_LIBRARY_PATH="/usr/trimui/lib:${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Resolve symlinks to get the real script path
_REAL0="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# Extract emulator directory from the resolved path
EMU_DIR="$(echo "$_REAL0" | sed -E 's|(.*Emus/[^/]+)/.*|\1|')"

# Fallback: if EMU_DIR is empty, try the unresolved $0
if [ -z "$EMU_DIR" ]; then
    EMU_DIR="$(echo "$0" | sed -E 's|(.*Emus/[^/]+)/.*|\1|')"
fi

ROM_DIR="$(echo "$1" | sed -E 's|(.*Roms/[^/]+)/.*|\1|')"
GAME=$(basename "$1")

export Game_cfg="$ROM_DIR/.games_config/${GAME%.*}.cfg"
export Emu_cfg="$EMU_DIR/launchers.cfg"

# Look for a saved preset
if [ -f "$Game_cfg" ]; then
    export Launcher_name=$(cat "$Game_cfg")
    export Preset_Type="Game"

elif [ -f "$Emu_cfg" ]; then
    export Launcher_name=$(cat "$Emu_cfg")
    export Preset_Type="Emu"

fi
Launcher_name=${Launcher_name#*=}

if [ -n "$Launcher_name" ]; then
    Launcher_command=$(jq -r --arg name "$Launcher_name" \
        '.launchlist[] | select(.name == $name) | .launch' "$EMU_DIR/config.json")
    echo -e "{ \"type\":\"info\", \"size\":2, \"duration\":2000, \"x\":660, \"y\":0,  \"message\":\"$Preset_Type preset: $Launcher_name\",  \"icon\":\"\" }" >/tmp/trimui_osd/osd_toast_msg

else
    # Look for the first valid launcher in launchlist
    if jq -e ".launchlist" "$EMU_DIR/config.json" >/dev/null 2>&1; then
        jq -c '.launchlist[]' "$EMU_DIR/config.json" >/tmp/launchlist.$$
        while read launcher; do
            Launcher_name=$(echo "$launcher" | jq -r '.name')
            Launcher_command=$(echo "$launcher" | jq -r '.launch')
            if [ -n "$Launcher_command" ]; then break; fi
        done < /tmp/launchlist.$$
        rm -f /tmp/launchlist.$$
    else
        # Else use launch.sh as fallback
        Launcher_name=Default
        Launcher_command="launch.sh"
    fi
fi

# Add LOG_FILE detection
LOG_FILE="/tmp/log/messages"
[ -f "/tmp/messages" ] && LOG_FILE="/tmp/messages"

echo "load_launcher.sh : $Launcher_name dowork 0x" >>"$LOG_FILE"
{
    rm "/tmp/trimui_osd/slider_cpu_preset/curpreset"
    echo "0/3" >"/tmp/trimui_osd/slider_cpu_preset/status"
} &
# Record that a launch started: if the emulator never comes back (hang or power
# pull) this is the only trace of what was running.
sh /mnt/SDCARD/System/usr/trimui/scripts/log_capture.sh start "$Launcher_command" "$1" >/dev/null 2>&1
_launch_started=$(date +%s)

"$EMU_DIR/$Launcher_command" "$@"
_launcher_status=$?
_launch_seconds=$(( $(date +%s) - _launch_started ))

# Record how the app ended (139 = crashed, 137 = killed...), how long it lasted,
# and preserve the volatile runtime logs: after a crash that is the only trace
# left behind.
sh /mnt/SDCARD/System/usr/trimui/scripts/log_capture.sh app "$_launcher_status" "$Launcher_command" "$1" "$_launch_seconds" >/dev/null 2>&1
{
    rm "/tmp/trimui_osd/slider_cpu_preset/curpreset"
    echo "0/3" >"/tmp/trimui_osd/slider_cpu_preset/status"
} &
