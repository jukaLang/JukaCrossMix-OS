#!/bin/sh
echo $0 $*

/mnt/SDCARD/System/usr/trimui/scripts/cpu_boost.sh

# Launch tool script file
echo "*** Launching $1 ***"
"$1" 

# we don't memorize System Tools scripts in recent list
recentlist=/mnt/SDCARD/Roms/recentlist.json
sed -i '1d' $recentlist
sync