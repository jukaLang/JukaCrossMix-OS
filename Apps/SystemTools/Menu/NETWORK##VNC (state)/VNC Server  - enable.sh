#!/bin/sh
PATH="/mnt/SDCARD/System/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/System/lib:/mnt/SDCARD/Apps/PortMaster/PortMaster:/usr/trimui/lib:$LD_LIBRARY_PATH"

/mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -m "Applying \"$(basename "$0" .sh)\" by default..."

json_file="/mnt/SDCARD/System/etc/crossmix.json"

if [ ! -f "$json_file" ]; then
    echo "{}" >"$json_file"
fi

/mnt/SDCARD/System/bin/jq '. += {"VNC": 1}' "$json_file" >"/tmp/json_file.tmp" && mv "/tmp/json_file.tmp" "$json_file"

pkill -9 vncserver
pkill -9 gptokeyb2
sleep 0.3

sed -i 's/export NETWORK_VNC="N"/export NETWORK_VNC="Y"/' /mnt/SDCARD/System/etc/ex_config

touch /tmp/dummy.ini
/mnt/SDCARD/Apps/PortMaster/PortMaster/gptokeyb2 -c /tmp/dummy.ini &
sleep 0.5

keyb_input="/dev/input/event3" # Default fallback
for event in /sys/class/input/event*; do
    if [ -f "$event/device/name" ]; then
        if [ "$(cat "$event/device/name")" = "Fake Keyboard" ]; then
            keyb_input="/dev/input/${event##*/}"
            break
        fi
    fi
done

vncserver -k $keyb_input &

# we modify the DB entries to reflect the current state
/mnt/SDCARD/System/usr/trimui/scripts/mainui_state_update.sh "VNC" "enabled"

sleep 1
IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
echo "VNC server IP: $IP"
/mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -m "VNC server IP: $IP" -t 4
