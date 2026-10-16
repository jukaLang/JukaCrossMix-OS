#!/bin/sh
# System Tools -> TOOLS -> "System Logs - Verify"
#
# Checks that the crash logging is really wired up on this device: that the boot
# sequence, the launcher and the shutdown path call the hooks, and that a crash,
# a hang and a power pull all leave a readable record.  Safe to run any time.

if ! pgrep "TermSP" >/dev/null; then
    /mnt/SDCARD/Apps/Terminal/launch_TermSP.sh -s 24 -e "$0"
    exit
fi

/mnt/SDCARD/System/usr/trimui/scripts/verify_logging.sh
status=$?

echo ""
if [ "$status" -ne 0 ]; then
    printf 'Fix the FAIL lines above, then run this check again.\n'
else
    printf 'No failure: crashes, hangs and power pulls will be recorded.\n'
fi

printf '%s' "Press A to exit"
read -r _
killall -9 "$0"
