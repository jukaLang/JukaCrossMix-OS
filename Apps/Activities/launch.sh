#!/bin/sh
echo $0 $*

export PATH="$PATH:/mnt/SDCARD/System/bin"

cd "$(dirname "$0")"
cd /mnt/SDCARD/Apps/Activities/
skins="$(jq -r '.["theme"]' /mnt/UDISK/system.json)"
backgrounds="$(jq -r '.["BACKGROUNDS"]' /mnt/SDCARD/System/etc/crossmix.json)"
sed -iE 's/^skins_theme=.*$/skins_theme='"${skins#*Themes/}"'
  s/^backgrounds_theme=.*$/backgrounds_theme='"$backgrounds/" data/config.ini
sync

read -r current_device </etc/trimui_device.txt
if [ "$current_device" = "tsps" ]; then
    echo 1 >/sys/class/drm/card0-DSI-1/rotate
    echo 1 >/sys/class/drm/card0-DSI-1/force_rotate
fi

/mnt/SDCARD/System/bin/activities gui # -last
