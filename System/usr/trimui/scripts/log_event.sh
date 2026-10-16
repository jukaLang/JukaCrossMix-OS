#!/bin/sh
# Append one timestamped line to a log file on the SD card.
#
#   sh log_event.sh <log-name> <message...>
#
# Logs live in $JUKAMIX_LOGDIR (default /mnt/SDCARD/System/logs).  A log grows
# to $JUKAMIX_LOG_MAX_BYTES (default 256 KiB) and is then rotated once to
# <name>.log.1, so a script stuck in a loop cannot fill the card.
#
# This is a best-effort helper: problems are reported on stderr and it always
# exits 0, so it is safe to call from hot paths such as the game launcher.

name=$1
shift

if [ -z "$name" ]; then
    echo "Usage: $0 <log name> <message...>" >&2
    exit 2
fi

SDCARD=${JUKAMIX_SDCARD:-/mnt/SDCARD}
LOGDIR=${JUKAMIX_LOGDIR:-$SDCARD/System/logs}
MAX_BYTES=${JUKAMIX_LOG_MAX_BYTES:-262144}

if ! mkdir -p "$LOGDIR" 2>/dev/null; then
    echo "log_event.sh: cannot create $LOGDIR" >&2
    exit 0
fi

file="$LOGDIR/$name.log"

if [ -f "$file" ]; then
    size=$(wc -c <"$file" 2>/dev/null | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -gt "$MAX_BYTES" ] 2>/dev/null; then
        mv -f "$file" "$file.1" 2>/dev/null
    fi
fi

printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$file" 2>/dev/null ||
    echo "log_event.sh: cannot write $file" >&2

exit 0
