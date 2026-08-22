#!/bin/sh
pid=$(pidof MainUI)
if [ -n "$pid" ]; then
    pkill -STOP runtrimui.sh 2>/dev/null
    kill -9 "$pid" &
    read -r current_device </etc/trimui_device.txt
    if [ "$current_device" = "tsps" ]; then
        echo 1 >/sys/class/drm/card0-DSI-1/rotate
        echo 1 >/sys/class/drm/card0-DSI-1/force_rotate
    fi
    /mnt/SDCARD/System/bin/activities gui
    pkill -CONT runtrimui.sh 2>/dev/null
fi
