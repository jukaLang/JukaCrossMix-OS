#!/usr/bin/env sh
PATH="/mnt/SDCARD/System/bin:/mnt/SDCARD/System/usr/trimui/scripts:$PATH"
LD_LIBRARY_PATH="/mnt/SDCARD/System/lib:/usr/trimui/lib:$LD_LIBRARY_PATH"
bin_dir="/mnt/SDCARD/trimui/app"
resources_dir="/mnt/SDCARD/System/resources"
backup_dir="/mnt/SDCARD/System/backups/inputd"
device_file="/etc/trimui_device.txt"
fw_inputd="/usr/trimui/bin/trimui_inputd"

# Modes:
#   (no argument)  apply the polling rate / install the device's daemon
#   verify         make sure the installed daemon matches the running device
#   verify -q      same, but only log when something was repaired
mode="apply"
quiet=""
case "$1" in
verify)
    mode="verify"
    [ "$2" = "-q" ] && quiet=1
    ;;
esac

script_name=$(basename "$0" .sh)
if [ "$mode" != "verify" ] && [ "$script_name" = "inputd_switcher" ]; then
    polling_rate=$(/mnt/SDCARD/System/bin/jq -r '.["POLLING RATE"]' "/mnt/SDCARD/System/etc/crossmix.json")
else
    polling_rate=$script_name
fi

# Which device is running this card?  /etc/trimui_device.txt is written at boot,
# but a card that is used on a device for the first time may not have it yet, so
# fall back to the SoC the same way the firmware does.
device=""
if [ -f "$device_file" ]; then
    read -r device <"$device_file"
fi
case "$device" in
tsp | tsps | brick | brickpro) ;;
*)
    case "$(cat /proc/cpuinfo 2>/dev/null)" in
    *TG5050*) device="tsps" ;;
    *TG5040*) device="tsp" ;;
    *TG3040*) device="brick" ;;
    *TG4040*) device="brickpro" ;;
    *) device="" ;;
    esac
    ;;
esac

if [ -z "$device" ]; then
    [ -n "$quiet" ] || echo "Unknown device, keeping the installed input daemon."
    exit 0
fi

# The Brick keeps the firmware's own daemon (no stick support in the OS builds),
# every other device gets the build that ships on this card.
source_inputd() {
    if [ "$device" = "brick" ]; then
        printf '%s' "$fw_inputd"
    else
        printf '%s' "$resources_dir/${device}_inputd"
    fi
}

###############################################################
# verify: a stale or foreign daemon keeps running until the
# device changes or the OS is updated, which makes the whole
# pad behave incorrectly (wrong UART, wrong button/axis bits).
# Keep the installed daemon in sync with the current device.
###############################################################
# Same file? Uses the crc32 helper the update scripts rely on, cmp as fallback.
files_identical() {
    if command -v crc32 >/dev/null 2>&1; then
        [ "$(crc32 "$1" | awk '{print $1}')" = "$(crc32 "$2" | awk '{print $1}')" ]
    else
        cmp -s "$1" "$2"
    fi
}

# Install a daemon, keeping the one that was there.
install_inputd() { # source
    mkdir -p "$backup_dir"
    if [ -f "$bin_dir/trimui_inputd" ]; then
        cp -f "$bin_dir/trimui_inputd" "$backup_dir/trimui_inputd.$(date +%Y%m%d-%H%M%S).bak"
    fi
    cp -f "$1" "$bin_dir/trimui_inputd"
    chmod a+x "$bin_dir/trimui_inputd"
    sync
}

# Restart the daemon, but only when MainUI is not running yet: restarting it
# under a running MainUI would leave the UI without input.
restart_inputd() {
    pgrep trimui_inputd >/dev/null || return 0
    if pgrep MainUI >/dev/null; then
        echo "MainUI is running, the new daemon will be used after a reboot."
        return 0
    fi
    pkill trimui_inputd
    sleep 0.5
    (cd "$bin_dir" && ./trimui_inputd >>/tmp/trimui_inputd.log 2>&1 &)
    echo "Input daemon restarted."
}

verify_inputd() {
    source=$(source_inputd)

    if [ ! -f "$source" ]; then
        [ -n "$quiet" ] || echo "No daemon available for $device, keeping the installed one."
        return 0
    fi

    if [ -f "$bin_dir/trimui_inputd" ] && files_identical "$source" "$bin_dir/trimui_inputd"; then
        [ -n "$quiet" ] || echo "Input daemon OK for $device."
        return 0
    fi

    # Say what is happening: a daemon built for another device is the usual
    # reason the pad reports wrong buttons or directions after moving a card.
    echo "Input daemon mismatch for $device, installing $(basename "$source")."
    install_inputd "$source"
    restart_inputd
    return 0
}

if [ "$mode" = "verify" ]; then
    verify_inputd
    exit 0
fi

source=$(source_inputd)

if [ ! -f "$source" ]; then
    [ "$script_name" != "inputd_switcher" ] && infoscreen -m "Input daemon not found!"
    exit 1
fi

install_inputd "$source"

if [ "$device" = "brick" ]; then
    [ "$script_name" != "inputd_switcher" ] && infoscreen -m "Feature not supported yet on brick"
    exit 1
fi

if [ "$device" = "brickpro" ]; then
    exit 1 # No configurable polling rate on TrimUI Brick Pro
fi

case "$polling_rate" in
"1ms")
    echo 1000 >"$bin_dir/inputd_polling_rate.cfg"
    ;;
"8ms")
    echo 8000 >"$bin_dir/inputd_polling_rate.cfg"
    ;;
"16ms")
    rm "$bin_dir/inputd_polling_rate.cfg"
    ;;
esac

sync

# Menu modification to reflect the change immediately

# update crossmix.json configuration file
json_file="/mnt/SDCARD/System/etc/crossmix.json"
if [ ! -f "$json_file" ]; then
    echo "{}" >"$json_file"
fi
jq --arg polling_rate "$polling_rate" '. += {"POLLING RATE": $polling_rate}' "$json_file" >"/tmp/json_file.tmp" && mv "/tmp/json_file.tmp" "$json_file"

# update database of "System Tools" database
/mnt/SDCARD/System/usr/trimui/scripts/mainui_state_update.sh "POLLING RATE" "$polling_rate"

/mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -m "Applying $polling_rate polling rate..." -t 1
pkill trimui_inputd
pkill -KILL MainUI
