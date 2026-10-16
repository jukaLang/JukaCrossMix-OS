#!/bin/sh
# System Tools -> TOOLS -> "System Logs - Collect"
#
# Builds one diagnostics report (System/logs/diagnostics_<stamp>.txt) covering
# the last crashes, the apps that ran, the preserved runtime logs and the
# current system state, and shows it in the terminal.

if ! pgrep "TermSP" >/dev/null; then
    /mnt/SDCARD/Apps/Terminal/launch_TermSP.sh -s 24 -e "$0"
    exit
fi

/mnt/SDCARD/System/usr/trimui/scripts/collect_logs.sh

echo ""
printf '%s' "Press A to exit"
read -r _
killall -9 "$0"
