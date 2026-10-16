#!/bin/sh
# Collect everything needed to debug a crash or an app that "does not work"
# into one timestamped, shareable report.
#
#   sh collect_logs.sh [output-file]
#
# It refreshes the crash scan, then writes the report to
# <SDCARD>/System/logs/diagnostics_<stamp>.txt and prints it to the terminal.
# Only the newest few reports are kept, so the card cannot fill up with them.
#
# Off-device (tests) every root can be redirected, like stick_diag.sh:
#   JUKAMIX_SDCARD JUKAMIX_LOGDIR JUKAMIX_TMP JUKAMIX_ETC JUKAMIX_PROC
#   JUKAMIX_SYS JUKAMIX_UDISK JUKAMIX_LOG_CAPTURE JUKAMIX_REPORT_KEEP

SDCARD=${JUKAMIX_SDCARD:-/mnt/SDCARD}
LOGDIR=${JUKAMIX_LOGDIR:-$SDCARD/System/logs}
TMP=${JUKAMIX_TMP:-/tmp}
ETC=${JUKAMIX_ETC:-/etc}
PROC=${JUKAMIX_PROC:-/proc}
SYS=${JUKAMIX_SYS:-/sys}
UDISK=${JUKAMIX_UDISK:-/mnt/UDISK}
LOG_CAPTURE=${JUKAMIX_LOG_CAPTURE:-$SDCARD/System/usr/trimui/scripts/log_capture.sh}
KEEP_REPORTS=${JUKAMIX_REPORT_KEEP:-10}

out=${1:-$LOGDIR/diagnostics_$(date '+%Y%m%d-%H%M%S').txt}

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n==== %s ====\n' "$1"; }
sub() { printf '%s\n' "-- $1"; }
lines() { # <file> <count>
    if [ -f "$1" ]; then tail -n "${2:-30}" "$1" 2>/dev/null; else printf '%s\n' "-- missing: $1"; fi
}
show() { # <label> <command...>
    label=$1
    shift
    sub "$label: $*"
    "$@" 2>&1 | head -n 50
}
value_of() { # <file> [default]
    if [ -f "$1" ]; then
        v=$(head -n 1 "$1" 2>/dev/null | tr -d '\r\n')
        printf '%s' "${v:-${2:-?}}"
    else
        printf '%s' "${2:-?}"
    fi
}
first_line_of() { # <file>... -> first readable first line, else ?
    for f in "$@"; do
        [ -f "$f" ] || continue
        v=$(head -n 1 "$f" 2>/dev/null | tr -d '\r\n')
        if [ -n "$v" ]; then
            printf '%s' "$v"
            return 0
        fi
    done
    printf '?'
}
uptime_seconds() {
    [ -f "$PROC/uptime" ] && cut -d' ' -f1 <"$PROC/uptime" 2>/dev/null | tr -d '\r\n'
}
count_entries() { # <file> -> number of timestamped entries written by log_event.sh
    if [ -f "$1" ]; then grep -c -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$1" 2>/dev/null; else printf '0'; fi
}
last_of() { # <literal pattern> <file> -> last matching line, else "none"
    v=$(grep -F -- "$1" "$2" 2>/dev/null | tail -n 1)
    [ -n "$v" ] || v="none"
    printf '%s' "$v"
}

# Verdict on how the previous session ended: a marker file is written at boot
# and removed by the shutdown path, so a leftover marker means the device went
# down without shutting down (power pull, hang, crash, watchdog reset).
previous_boot_verdict() {
    [ -f "$LOGDIR/boot.log" ] || {
        printf 'no record (fresh card or logs cleared)'
        return 0
    }
    awk '
        /without a clean shutdown/ { u = $0; ul = NR; next }
        /clean shutdown/           { c = $0; cl = NR }
        END {
            if (ul > cl) { print "NOT clean: " u; exit }
            if (cl > 0)  { print "clean: " c; exit }
            print "no shutdown recorded yet"
        }' "$LOGDIR/boot.log" 2>/dev/null
}

# Did the last thing that started ever come back?  A launch with no matching
# exit line is the signature of a hang or a power pull during a game.
session_verdict() {
    [ -f "$LOGDIR/session.log" ] || {
        printf 'none'
        return 0
    }
    awk '
        BEGIN { sl = 0; el = 0; s = ""; e = "" }
        / start app=/ { s = $0; sl = NR }
        / exit=/      { e = $0; el = NR }
        END {
            if (sl == 0)  { print "nothing launched yet"; exit }
            if (sl > el)  { print "never returned: " s; exit }
            print "last launch returned: " e
        }' "$LOGDIR/session.log" 2>/dev/null
}

# Keep only the newest $1 reports.
prune_reports() {
    keep=$1
    present=0
    for f in "$LOGDIR"/diagnostics_*.txt; do
        [ -f "$f" ] && present=$((present + 1))
    done
    [ "$present" -gt "$keep" ] || return 0
    if have ls; then
        ls -1t "$LOGDIR"/diagnostics_*.txt 2>/dev/null |
            tail -n +"$((keep + 1))" |
            while read -r old; do
                rm -f "$old" 2>/dev/null
            done
    fi
}

# ------------------------------------------------------------------- refresh
mkdir -p "$LOGDIR" 2>/dev/null
sh "$LOG_CAPTURE" scan >/dev/null 2>&1

# -------------------------------------------------------------- build report
{
    printf 'JukaMix OS diagnostics\n'
    printf 'generated   : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'device      : %s\n' "$(first_line_of "$ETC/trimui_device.txt")"
    printf 'image       : %s\n' "$(first_line_of "$SDCARD/System/usr/trimui/crossmix-version.txt")"
    printf 'fw patched  : %s\n' "$(first_line_of /usr/trimui/crossmix-version.txt)"
    printf 'firmware    : %s\n' "$(first_line_of "$ETC/trimui_fw_version.txt" "$SDCARD/trimui/firmwares/MinFwVersion.txt")"
    printf 'kernel      : %s\n' "$(uname -r 2>/dev/null || echo unknown)"
    printf 'uptime      : %s s\n' "$(uptime_seconds)"

    section "0. summary — read this first"
    sub "crash entries recorded    : $(count_entries "$LOGDIR/crash.log")"
    sub "previous boot             : $(previous_boot_verdict)"
    sub "session                   : $(session_verdict)"
    sub "last app exit             : $(last_of ' exit=' "$LOGDIR/session.log")"
    sub "watchdog last heartbeat   : $(last_of 'alive' "$LOGDIR/watch_status.txt")"
    state=$(last_of 'CPU work' "$LOGDIR/boot.log")
    if [ "$state" != "none" ]; then
        sub "device state before the end  : $state"
    fi
    stall=$(last_of 'no CPU progress' "$LOGDIR/watch.log")
    if [ "$stall" != "none" ]; then
        sub "app stall note            : $stall"
    fi
    if have df; then
        sub "card space                : $(df -h "$SDCARD" 2>/dev/null | tail -n 1)"
    fi

    section "1. crash signatures (kernel log)"
    lines "$LOGDIR/crash.log" 40

    section "2. recent launches and app sessions (what ran, how it ended)"
    lines "$LOGDIR/session.log" 40

    section "3. boot history"
    lines "$LOGDIR/boot.log" 10

    section "4. runtime logs preserved from tmpfs"
    sub "watchdog status ($LOGDIR/watch_status.txt) — last time the device was known alive"
    lines "$LOGDIR/watch_status.txt" 2
    sub "watchdog activity ($LOGDIR/watch.log)"
    lines "$LOGDIR/watch.log" 15
    if [ -f "$LOGDIR/watch_state.txt" ]; then
        sub "watch state at the last tick ($LOGDIR/watch_state.txt) — session, app and CPU when the device last answered"
        lines "$LOGDIR/watch_state.txt" 12
        sub "watch state one tick earlier ($LOGDIR/watch_state_prev.txt)"
        lines "$LOGDIR/watch_state_prev.txt" 12
    fi
    if [ -f "$LOGDIR/last_stall.txt" ]; then
        sub "app stall dump ($LOGDIR/last_stall.txt) — an app that stopped using CPU"
        lines "$LOGDIR/last_stall.txt" 30
    fi
    sub "$TMP/messages (TrimUI launcher/MainUI log)"
    lines "$LOGDIR/last_messages.log" 40
    sub "$TMP/log/messages"
    lines "$LOGDIR/last_log_messages.log" 30
    sub "$TMP/trimui_inputd.log"
    lines "$LOGDIR/last_trimui_inputd.log" 20

    section "5. system state"
    [ -f "$PROC/meminfo" ] && show "memory" head -n 6 "$PROC/meminfo"
    have df && show "free space" df -h
    if have mount; then
        sub "card mounts (SDCARD/UDISK)"
        mount 2>/dev/null | grep -E 'SDCARD|UDISK' | head -n 20
    fi
    cores=$(grep -c processor "$PROC/cpuinfo" 2>/dev/null)
    [ -n "$cores" ] || cores=?
    sub "cpu: $cores core(s), governor $(value_of "$SYS/devices/system/cpu/cpu0/cpufreq/scaling_governor")"
    sub "cpu freq: $(value_of "$SYS/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq") .. $(value_of "$SYS/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq") kHz (now $(value_of "$SYS/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"))"
    for z in "$SYS"/class/thermal/thermal_zone*/temp; do
        [ -f "$z" ] || continue
        sub "thermal ${z%/temp}: $(value_of "$z")"
    done
    have ps && show "processes" ps

    section "6. settings"
    sub "$ETC/trimui_device.txt"
    cat "$ETC/trimui_device.txt" 2>/dev/null
    sub "$SDCARD/System/etc/crossmix.json"
    if have jq && [ -f "$SDCARD/System/etc/crossmix.json" ]; then
        jq . "$SDCARD/System/etc/crossmix.json" 2>&1 | head -n 60
    else
        cat "$SDCARD/System/etc/crossmix.json" 2>/dev/null
    fi

    section "7. log inventory"
    have ls && ls -l "$LOGDIR" 2>/dev/null
    if [ -d "$UDISK" ]; then
        sub "$UDISK"
        have ls && ls -l "$UDISK" 2>/dev/null | head -n 20
    fi

    printf '\n==== end of report ====\n'
    printf 'Attach this file when reporting a problem.\n'
    printf 'Only the newest %s reports are kept in %s.\n' "$KEEP_REPORTS" "$LOGDIR"
} >"$out" 2>&1

prune_reports "$KEEP_REPORTS"

cat "$out" 2>/dev/null
printf '\nReport saved to: %s\n' "$out"
