#!/bin/sh
# Watchdog for the runtime logs: keep them snapshotted on the card while the
# device is running, so a hard hang — or a straight power pull — still leaves a
# trace behind.
#
#   sh log_watch.sh [interval-seconds]      default 300, override JUKAMIX_WATCH_INTERVAL
#
# Started once per boot by the boot sequence.  Every tick it
#   - rewrites watch_status.txt (one line): the last stamp is what lets the next
#     boot say *when* the device stopped answering
#   - rewrites watch_state.txt and keeps the tick before it as
#     watch_state_prev.txt: the session, the launched app and how much CPU the
#     system and the app had spent - after a hang the next boot compares the two
#     and says whether the app or the whole system had frozen
#   - notes an app that stops using CPU across ticks, keeping its process state
#     in last_stall.txt
#   - checks only the kernel-log lines no earlier scan has seen for crashes
#   - copies the volatile tmpfs logs, but only when they changed
#
# It never blocks the boot, a tick is a handful of small reads and writes, and
# it exits immediately if a watchdog from this boot is already running.

SDCARD=${JUKAMIX_SDCARD:-/mnt/SDCARD}
TMP=${JUKAMIX_TMP:-/tmp}
PROC=${JUKAMIX_PROC:-/proc}
PIDFILE=${JUKAMIX_WATCH_PID:-$TMP/log_watch.pid}
CAPTURE=${JUKAMIX_LOG_CAPTURE:-$SDCARD/System/usr/trimui/scripts/log_capture.sh}
INTERVAL=${1:-${JUKAMIX_WATCH_INTERVAL:-300}}

case "$INTERVAL" in '' | *[!0-9]*) INTERVAL=300 ;; esac
[ "$INTERVAL" -ge 30 ] 2>/dev/null || INTERVAL=30

# A watchdog from this boot still running?  A second copy would only duplicate
# the same work.  The pid is cross-checked against /proc when that is readable.
running() { # <pid>
    [ -n "$1" ] || return 1
    kill -0 "$1" 2>/dev/null || return 1
    if [ -r "$PROC/$1/cmdline" ]; then
        grep -q log_watch "$PROC/$1/cmdline" 2>/dev/null || return 1
    fi
    return 0
}

if [ -f "$PIDFILE" ]; then
    other=$(head -n 1 "$PIDFILE" 2>/dev/null | tr -d '\r\n ')
    if running "$other"; then
        exit 0
    fi
fi
printf '%s\n' "$$" >"$PIDFILE" 2>/dev/null

# Leave the card as the working directory: a daemon sitting on the mount can stop
# the shutdown path from unmounting it cleanly.
cd / 2>/dev/null

# Let the boot capture record this boot first, so the two never scan the same
# kernel-log lines at the same time.
sleep 5

while :; do
    sh "$CAPTURE" watch >/dev/null 2>&1
    sleep "$INTERVAL"
done
