#!/bin/sh
cd $(dirname "$0")

export LD_LIBRARY_PATH=$(dirname "$0")/lib:/mnt/SDCARD/System/lib:/usr/lib:$LD_LIBRARY_PATH

read -r Current_device </etc/trimui_device.txt
if [ "$Current_device" = "tsps" ]; then
    echo 1 >/sys/class/drm/card0-DSI-1/rotate
    echo 1 >/sys/class/drm/card0-DSI-1/force_rotate
fi

./DinguxCommander
