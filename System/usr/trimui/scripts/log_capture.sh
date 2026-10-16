#!/bin/sh
# Snapshot the running system so a crash — or an app that simply "does not
# work" — can still be diagnosed after the fact.
#
#   sh log_capture.sh boot [reboot|poweroff]      record a boot, judge the last one
#   sh log_capture.sh start <launcher> [rom]      a launch is about to happen
#   sh log_capture.sh app <exit> <launcher> [rom] [seconds]
#   sh log_capture.sh watch                       one watchdog tick (log_watch.sh)
#   sh log_capture.sh scan                        look for new kernel crashes
#   sh log_capture.sh shutdown <reason>           a clean shutdown is starting
#
# Everything lands in $JUKAMIX_LOGDIR (default /mnt/SDCARD/System/logs):
#   boot.log            one line per boot, plus the verdict on the one before
#   session.log         every launch, and how it ended
#   crash.log           crash signatures found in the kernel log
#   watch.log           what the watchdog copied, and when something changed
#   watch_status.txt    one rewritten line: the watchdog's last "still alive"
#   watch_state.txt     what the last watchdog tick saw: session, app, top CPU
#   watch_state_prev.txt the tick before it: the pair dates a freeze at boot
#   last_stall.txt      the newest "app stopped using CPU" dump (see check_stall)
#   last_*.log          copies of the volatile runtime logs (see below)
#   .session_open       marker: present only while the device runs cleanly
#
# /tmp is a tmpfs, so the runtime logs are wiped by every reboot: this script is
# what preserves them.  It is best effort, never changes its exit status, and is
# safe to call from the boot sequence and from the game launcher.

SDCARD=${JUKAMIX_SDCARD:-/mnt/SDCARD}
LOGDIR=${JUKAMIX_LOGDIR:-$SDCARD/System/logs}
TMP=${JUKAMIX_TMP:-/tmp}
ETC=${JUKAMIX_ETC:-/etc}
PROC=${JUKAMIX_PROC:-/proc}
LOG_EVENT=${JUKAMIX_LOG_EVENT:-$SDCARD/System/usr/trimui/scripts/log_event.sh}

SESSION_MARKER=$LOGDIR/.session_open
KMSG_CURSOR=$LOGDIR/.kmsg_cursor
SNAP_STATE=$TMP/log_capture_snapstate
SNAP_COPIED=0
# The launch in progress (tmpfs just like the snap state: a reboot should start
# with none) and the app-stall bookkeeping for consecutive watchdog ticks.
SESSION_FILE=$TMP/log_capture_session
STALL_FILE=$TMP/log_capture_stall

# Kernel messages that mean "something crashed or a device misbehaved".
CRASH_PATTERN='segfault|general protection|kernel oops|^BUG:|Call trace|Out of memory|oom-kill|Killed process|Kernel panic|Unable to handle|I/O error|mmc[0-9]:.*error|watchdog|stack corruption'

emit() { # <log-name> <message...>
    sh "$LOG_EVENT" "$@" 2>/dev/null
}

# Same as emit, but skipped when the log already ends with that exact message:
# a status note such as "kernel log not readable" would otherwise be repeated on
# every boot, crash and report.
emit_dedup() { # <log-name> <message...>
    name=$1
    shift
    msg=$*
    last=$(tail -n 1 "$LOGDIR/$name.log" 2>/dev/null | sed 's/^\[[^]]*\] //')
    if [ "$last" = "$msg" ]; then
        return 0
    fi
    emit "$name" "$msg"
}

first_line_of() { # <file>... -> first non-empty first line, else nothing
    for f in "$@"; do
        [ -f "$f" ] || continue
        v=$(head -n 1 "$f" 2>/dev/null | tr -d '\r\n')
        if [ -n "$v" ]; then
            printf '%s' "$v"
            return 0
        fi
    done
    return 1
}

uptime_seconds() {
    if [ -f "$PROC/uptime" ]; then
        cut -d' ' -f1 <"$PROC/uptime" 2>/dev/null | tr -d '\r\n'
    fi
}

kernel_name() {
    uname -r 2>/dev/null || printf 'unknown'
}

# Identifies the current boot.  The kernel log starts over at every boot, so the
# scan cursor below is only meaningful within one boot.
boot_id() {
    if [ -r "$PROC/sys/kernel/random/boot_id" ]; then
        head -n 1 "$PROC/sys/kernel/random/boot_id" 2>/dev/null | tr -d '\r\n'
        return 0
    fi
    up=$(uptime_seconds)
    up=${up%%.*}
    case "$up" in '' | *[!0-9]*) up=0 ;; esac
    printf 'uptime-%s' "$(($(date +%s) - up))"
}

free_mem_kb() {
    v=$(awk '/^MemAvailable:/ { print $2; exit }' "$PROC/meminfo" 2>/dev/null)
    [ -n "$v" ] || v=$(awk '/^MemFree:/ { print $2; exit }' "$PROC/meminfo" 2>/dev/null)
    [ -n "$v" ] || v=0
    printf '%s' "$v"
}

describe_status() { # <exit-status> -> " (crashed: ...)" or ""
    case "$1" in
    0) ;;
    129) printf '%s' ' (killed: SIGHUP)' ;;
    134) printf '%s' ' (crashed: abort/SIGABRT)' ;;
    136) printf '%s' ' (crashed: SIGFPE)' ;;
    137) printf '%s' ' (killed: SIGKILL - out of memory?)' ;;
    139) printf '%s' ' (crashed: SIGSEGV)' ;;
    143) printf '%s' ' (terminated: SIGTERM)' ;;
    *) printf '%s' ' (non-zero exit)' ;;
    esac
}

# Sizes of the runtime logs the watchdog has already copied.  Kept in tmpfs: a
# reboot should always take a fresh snapshot.
snap_size_of() { # <src> -> recorded size, or nothing
    [ -f "$SNAP_STATE" ] || return 1
    awk -F'|' -v k="$1" '$1 == k { v = $2 } END { if (v == "") exit 1; print v }' \
        "$SNAP_STATE" 2>/dev/null
}

snap_size_set() { # <src> <size>
    tmp="$SNAP_STATE.$$"
    if [ -f "$SNAP_STATE" ]; then
        awk -F'|' -v k="$1" '$1 != k' "$SNAP_STATE" >"$tmp" 2>/dev/null
    fi
    printf '%s|%s\n' "$1" "$2" >>"$tmp" 2>/dev/null
    mv -f "$tmp" "$SNAP_STATE" 2>/dev/null
}

# Copy the volatile (tmpfs) runtime logs onto the card, where they survive a
# reboot.  /tmp/messages holds the TrimUI launcher/MainUI log.
#
#   [changed-only]  skip a file whose size was already copied (watchdog ticks)
#   [quiet]         do not report every file in session.log
#
# The number of files copied is left in $SNAP_COPIED.
snapshot_volatile() { # [changed-only] [quiet]
    mode=$1
    quiet=$2
    saved=0
    for pair in "$TMP/messages:last_messages.log" \
        "$TMP/log/messages:last_log_messages.log" \
        "$TMP/trimui_inputd.log:last_trimui_inputd.log"; do
        src=${pair%%:*}
        dst=$LOGDIR/${pair#*:}
        size=
        [ -f "$src" ] || continue
        [ -s "$src" ] || continue
        size=$(wc -c <"$src" 2>/dev/null | tr -d ' ')
        if [ "$mode" = "changed-only" ]; then
            if [ -n "$size" ] && [ "$(snap_size_of "$src")" = "$size" ]; then
                continue
            fi
        fi
        if cp -f "$src" "$dst" 2>/dev/null; then
            saved=$((saved + 1))
            [ -n "$size" ] && snap_size_set "$src" "$size"
            [ "$quiet" = "quiet" ] ||
                emit session "captured $src (${size:-?} bytes) -> $dst"
        fi
    done
    if [ "$saved" -eq 0 ] && [ "$quiet" != "quiet" ]; then
        emit session "no runtime log found in $TMP"
    fi
    SNAP_COPIED=$saved
}

# Proof of life, rewritten in place (never appended): the next boot reads the
# last stamp to say *when* the device stopped answering.
heartbeat() {
    printf '[%s] alive uptime=%ss free_mem=%skB load=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$(uptime_seconds)" "$(free_mem_kb)" \
        "$(cut -d' ' -f1-3 <"$PROC/loadavg" 2>/dev/null | tr -d '\r\n')" \
        >"$LOGDIR/watch_status.txt" 2>/dev/null
}

# Read the kernel log (dmesg needs privileges on some firmware builds, logread
# reads the syslog the firmware keeps) and record the crash signatures.
#
# Only the lines no earlier scan has seen are inspected: the kernel log keeps
# growing inside one boot, and the watchdog re-reads it every few minutes, so
# re-scanning it as a whole would repeat the same crash forever.
scan_kernel() {
    kmsg="$TMP/log_capture_kmsg.$$"
    : >"$kmsg" 2>/dev/null
    if command -v dmesg >/dev/null 2>&1; then
        dmesg >>"$kmsg" 2>/dev/null
    fi
    if [ ! -s "$kmsg" ] && command -v logread >/dev/null 2>&1; then
        logread >>"$kmsg" 2>/dev/null
    fi
    if [ ! -s "$kmsg" ]; then
        rm -f "$kmsg" 2>/dev/null
        emit_dedup crash "kernel log not readable (dmesg/logread unavailable)"
        return 0
    fi

    total=$(wc -l <"$kmsg" 2>/dev/null | tr -d ' ')
    case "$total" in '' | *[!0-9]*) total=0 ;; esac
    id=$(boot_id)
    seen=0
    if [ -f "$KMSG_CURSOR" ]; then
        prev_id=
        prev_seen=
        read -r prev_id prev_seen <"$KMSG_CURSOR" 2>/dev/null
        if [ "$prev_id" = "$id" ]; then
            case "$prev_seen" in '' | *[!0-9]*) prev_seen=0 ;; esac
            seen=$prev_seen
        fi
    fi
    if [ "$seen" -gt "$total" ]; then
        seen=0 # the kernel log was rotated or truncated
    fi

    fresh=$(tail -n +"$((seen + 1))" "$kmsg" 2>/dev/null)
    printf '%s %s\n' "$id" "$total" >"$KMSG_CURSOR" 2>/dev/null

    hits=$(printf '%s\n' "$fresh" | grep -E -i "$CRASH_PATTERN" 2>/dev/null | tail -n 40)
    rm -f "$kmsg" 2>/dev/null
    [ -n "$hits" ] || return 0
    emit crash "kernel log matches:
$hits"
}

# ------------------------------------------------------ the running system
#
# What turns a hard hang into something diagnosable: which app was running,
# what state it was in, and whether the whole system was still spending CPU at
# the last watchdog tick.

# One pass over /proc: "cpu pid state ppid comm", heaviest first.  cpu is in
# seconds of CPU time (USER_HZ is 100 on every kernel), and comm comes last so
# a whole line can be read with read(1) even when a name contains spaces.
proc_table() {
    awk '
        {
            p = index($0, "(")
            q = 0
            for (i = length($0); i > 0; i--) {
                if (substr($0, i, 1) == ")") { q = i; break }
            }
            if (p == 0 || q <= p) next
            n = split(substr($0, q + 2), f, " ")
            if (n < 13) next
            pid = FILENAME
            sub(/\/stat$/, "", pid)
            sub(/.*\//, "", pid)
            printf "%.2f %s %s %s %s\n", (f[12] + f[13]) / 100, pid, f[1], f[2], substr($0, p + 1, q - p - 1)
        }
    ' "$PROC"/[0-9]*/stat 2>/dev/null | sort -n -r 2>/dev/null
}

# Non-idle CPU jiffies from /proc/stat (USER_HZ = 100/s): the difference between
# two ticks is how much work the device really did in between.
busy_jiffies() {
    awk '/^cpu / { print $2 + $3 + $4 + $7 + $8 + $9; exit }' "$PROC/stat" 2>/dev/null
}

# Value of key=<v> on the first line of a state digest, or nothing.
state_field() { # <file> <key>
    awk -v k="$2" 'NR == 1 {
            for (i = 1; i <= NF; i++) {
                if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit }
            }
        }' "$1" 2>/dev/null
}

# Value of key=<v> on the digest's "app:" line, or nothing.
app_field() { # <file> <key>
    awk -v k="$2" 'index($0, "app: ") == 1 {
            for (i = 1; i <= NF; i++) {
                if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit }
            }
        }' "$1" 2>/dev/null
}

# Which process is the launched app?  The launcher shell recorded its own pid
# when the launch started; the app is the busiest process below it (a wrapper
# script can put a shell in between, and the caller can be a subshell one level
# up, hence the possible fallback).  A dead launcher leaves nothing to search
# from: then the digest cannot name the app, but the top list still shows the
# heavy processes.  Prints "pid state cpu comm", or "none".
app_of_session() { # <launcher pid>  (process table on stdin)
    awk -v root="$1" '
        { c[NR] = $1; p[NR] = $2; s[NR] = $3; pp[NR] = $4; cmd[NR] = $5; n = NR }
        END {
            inside[root] = 1
            for (round = 1; round <= 8; round++) {
                changed = 0
                for (i = 1; i <= n; i++) {
                    if (inside[pp[i]] && !inside[p[i]]) { inside[p[i]] = 1; changed = 1 }
                }
                if (!changed) break
            }
            best = 0
            for (i = 1; i <= n; i++) {
                if (p[i] == root || !inside[p[i]]) continue
                if (best == 0 || c[i] + 0 > c[best] + 0) best = i
            }
            if (best == 0) { print "none"; exit }
            printf "%s %s %.2f %s\n", p[best], s[best], c[best], cmd[best]
        }' 2>/dev/null
}

# Preserve what the stalled app was doing while it can still be asked.
write_stall_dump() { # <pid> <state> <cpu> <comm> <wchan> <ticks>
    {
        printf 'app stall recorded: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'app: comm=%s pid=%s state=%s cpu=%ss wchan=%s (no CPU progress for %s watchdog ticks)\n' \
            "$4" "$1" "$2" "$3" "$5" "$6"
        printf '\n-- the last two watchdog ticks --\n'
        cat "$LOGDIR/watch_state_prev.txt" 2>/dev/null
        cat "$LOGDIR/watch_state.txt" 2>/dev/null
        printf '\n-- /proc/%s/status --\n' "$1"
        head -n 25 "$PROC/$1/status" 2>/dev/null
        printf '\n-- /proc/%s/wchan --\n' "$1"
        printf '%s\n' "$5"
        printf '\n-- /proc/%s/stack --\n' "$1"
        head -n 12 "$PROC/$1/stack" 2>/dev/null
    } >"$LOGDIR/last_stall.txt" 2>/dev/null
}

# An app that stops spending CPU across watchdog ticks is the signature of a
# hang that has not taken the whole system down yet.  Note it once it is clear
# (two ticks), then hourly, and keep its process state.  The app may simply be
# idle, so the note reports the state and leaves the verdict to the reader.
check_stall() { # <app: "pid state cpu comm", or none>
    pid=${1%% *}
    case "$pid" in
    '' | none | *[!0-9]*)
        rm -f "$STALL_FILE" 2>/dev/null
        return 0
        ;;
    esac
    r1=${1#* }
    state=${r1%% *}
    r2=${r1#* }
    cpu=${r2%% *}
    comm=${r2#* }
    prev_pid=
    prev_cpu=
    ticks=0
    if [ -f "$STALL_FILE" ]; then
        read -r prev_pid prev_cpu ticks <"$STALL_FILE" 2>/dev/null
    fi
    case "$ticks" in '' | *[!0-9]*) ticks=0 ;; esac
    same=$(awk -v a="$prev_pid" -v b="$pid" -v c="$prev_cpu" -v d="$cpu" \
        'BEGIN { print (a == b && c == d) ? 1 : 0 }')
    if [ "$same" = "1" ]; then
        ticks=$((ticks + 1))
    else
        ticks=0
    fi
    printf '%s %s %s\n' "$pid" "$cpu" "$ticks" >"$STALL_FILE" 2>/dev/null
    [ "$ticks" -ge 2 ] || return 0
    if [ "$ticks" -ne 2 ] && [ $((ticks % 12)) -ne 0 ]; then
        return 0
    fi
    wchan=$(head -n 1 "$PROC/$pid/wchan" 2>/dev/null | tr -d '\r\n')
    [ -n "$wchan" ] || wchan=?
    emit watch "app $comm (pid $pid, state $state, wchan=$wchan) shows no CPU progress for $ticks watchdog ticks; preserving its state in last_stall.txt"
    write_stall_dump "$pid" "$state" "$cpu" "$comm" "$wchan" "$ticks"
}

# One tick of what the device is doing: rewrite watch_state.txt and keep the
# tick before it as watch_state_prev.txt, so after a hang the next boot can
# compare the last two snapshots.  One process scan serves both that and the
# stall check.
track_watch_state() {
    now=$(date +%s 2>/dev/null)
    case "$now" in '' | *[!0-9]*) now=0 ;; esac
    table=$(proc_table)
    lp=
    gp=
    started=
    launcher=
    rom=
    if [ -f "$SESSION_FILE" ]; then
        read -r lp gp started launcher rom <"$SESSION_FILE" 2>/dev/null
    fi
    app=none
    if [ -n "$lp" ]; then
        app=$(printf '%s\n' "$table" | app_of_session "$lp")
        if [ "$app" = none ] && [ -n "$gp" ]; then
            app=$(printf '%s\n' "$table" | app_of_session "$gp")
        fi
    fi
    tmp=$LOGDIR/watch_state.txt.$$
    {
        printf '[%s] epoch=%s boot=%s uptime=%ss load=%s busy=%s mem=%skB\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$now" "$(boot_id)" "$(uptime_seconds)" \
            "$(cut -d' ' -f1-3 <"$PROC/loadavg" 2>/dev/null | tr -d '\r\n')" \
            "$(busy_jiffies)" "$(free_mem_kb)"
        if [ -n "$lp" ]; then
            runpart=
            case "$started$now" in
            *[!0-9]*) ;;
            *) runpart=" running=$((now - started))s" ;;
            esac
            printf 'session: app=%s rom=%s launcher_pid=%s%s\n' \
                "${launcher:-unknown}" "${rom:-none}" "$lp" "$runpart"
            if [ "$app" = none ]; then
                printf 'app: pid=none (no process below launcher %s)\n' "$lp"
            else
                app_pid=${app%% *}
                r1=${app#* }
                app_state=${r1%% *}
                r2=${r1#* }
                app_cpu=${r2%% *}
                app_comm=${r2#* }
                printf 'app: comm=%s pid=%s state=%s cpu=%ss\n' \
                    "$app_comm" "$app_pid" "$app_state" "$app_cpu"
            fi
        fi
        printf '%s\n' "$table" | head -n 6 |
            while read -r cpu pid state ppid comm; do
                printf 'top: comm=%s pid=%s state=%s cpu=%ss\n' "$comm" "$pid" "$state" "$cpu"
            done
    } >"$tmp" 2>/dev/null
    if [ -s "$tmp" ]; then
        mv -f "$LOGDIR/watch_state.txt" "$LOGDIR/watch_state_prev.txt" 2>/dev/null
        mv -f "$tmp" "$LOGDIR/watch_state.txt" 2>/dev/null
    fi
    rm -f "$tmp" 2>/dev/null
    check_stall "$app"
}

# ------------------------------------------------------------- after a hang
#
# The two digests are enough to date a freeze: /proc/stat's work counter says
# whether the whole system was still spending CPU between them, and the app line
# says what the app that hung was doing.  Read at boot while the session marker
# is still there, i.e. only after a power pull, a hang or a crash.
watch_gap_note() {
    [ -f "$LOGDIR/watch_state.txt" ] || return 0
    [ -f "$LOGDIR/watch_state_prev.txt" ] || return 0
    prev_boot=$(state_field "$LOGDIR/watch_state_prev.txt" boot)
    cur_boot=$(state_field "$LOGDIR/watch_state.txt" boot)
    [ -n "$prev_boot" ] || return 0
    [ "$prev_boot" = "$cur_boot" ] || return 0
    prev_busy=$(state_field "$LOGDIR/watch_state_prev.txt" busy)
    cur_busy=$(state_field "$LOGDIR/watch_state.txt" busy)
    prev_epoch=$(state_field "$LOGDIR/watch_state_prev.txt" epoch)
    cur_epoch=$(state_field "$LOGDIR/watch_state.txt" epoch)
    case "$prev_busy$cur_busy$prev_epoch$cur_epoch" in
    '' | *[!0-9]*) return 0 ;;
    esac
    wall=$((cur_epoch - prev_epoch))
    [ "$wall" -gt 0 ] || return 0
    [ "$wall" -le 21600 ] || return 0
    [ "$cur_busy" -ge "$prev_busy" ] || return 0
    work=$(awk -v a="$cur_busy" -v b="$prev_busy" 'BEGIN { printf "%.1f", (a - b) / 100 }')
    if awk -v w="$work" 'BEGIN { exit (w + 0 < 1) ? 0 : 1 }'; then
        note="the system had already stopped working before the last heartbeat: ${work}s of CPU work in the last ${wall}s"
    else
        note="the system was still working at the last heartbeat: ${work}s of CPU work in the last ${wall}s"
    fi
    prev_pid=$(app_field "$LOGDIR/watch_state_prev.txt" pid)
    cur_pid=$(app_field "$LOGDIR/watch_state.txt" pid)
    case "$prev_pid$cur_pid" in
    '' | *[!0-9]*) printf '%s' "$note"; return 0 ;;
    esac
    if [ "$prev_pid" != "$cur_pid" ]; then
        printf '%s' "$note"
        return 0
    fi
    prev_cpu=$(app_field "$LOGDIR/watch_state_prev.txt" cpu)
    cur_cpu=$(app_field "$LOGDIR/watch_state.txt" cpu)
    prev_cpu=${prev_cpu%s}
    cur_cpu=${cur_cpu%s}
    state=$(app_field "$LOGDIR/watch_state.txt" state)
    comm=$(sed -n 's/^app: comm=\(.*\) pid=[0-9][0-9]* .*$/\1/p' "$LOGDIR/watch_state.txt" 2>/dev/null | head -n 1)
    [ -n "$comm" ] || comm=app
    same=$(awk -v a="$prev_cpu" -v b="$cur_cpu" 'BEGIN { print (a + 0 == b + 0) ? 1 : 0 }')
    if [ "$same" = "1" ]; then
        note="$note; app $comm (pid $cur_pid, state ${state:-?}) used no CPU in between"
    else
        gained=$(awk -v a="$cur_cpu" -v b="$prev_cpu" 'BEGIN { print (a + 0 > b + 0) ? 1 : 0 }')
        if [ "$gained" = "1" ]; then
            d=$(awk -v a="$cur_cpu" -v b="$prev_cpu" 'BEGIN { printf "%.1f", a - b }')
            note="$note; app $comm (pid $cur_pid) gained ${d}s of CPU"
        fi
    fi
    printf '%s' "$note"
}

main() {
    phase=${1:-scan}
    shift 2>/dev/null

    case "$phase" in
    boot)
        # Did the previous boot end without a clean shutdown?  If the marker is
        # still there the device was powered off hard, hung or crashed.
        if [ -f "$SESSION_MARKER" ]; then
            hb=$(tail -n 1 "$LOGDIR/watch_status.txt" 2>/dev/null | cut -c1-140)
            emit boot "previous session ended without a clean shutdown (power loss, hang or crash); last heartbeat: ${hb:-none}"
            # The last two watchdog ticks say whether that was the app or the
            # whole system: that is what makes a hang diagnosable later.
            gap=$(watch_gap_note)
            [ -n "$gap" ] && emit boot "$gap"
        fi
        device=$(first_line_of "$ETC/trimui_device.txt")
        version=$(first_line_of "$SDCARD/System/usr/trimui/crossmix-version.txt" \
            /usr/trimui/crossmix-version.txt)
        firmware=$(first_line_of "$ETC/trimui_fw_version.txt" \
            "$SDCARD/trimui/firmwares/MinFwVersion.txt")
        emit boot "boot: image=${version:-?} device=${device:-?} firmware=${firmware:-?} kernel=$(kernel_name) uptime=$(uptime_seconds)s"
        # A new boot has a brand new kernel log: start the scan from the top.
        rm -f "$KMSG_CURSOR" 2>/dev/null
        printf 'booted=%s uptime=%ss\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$(uptime_seconds)" >"$SESSION_MARKER" 2>/dev/null
        # A new boot has no launch in progress and nothing stalled.
        rm -f "$SESSION_FILE" "$STALL_FILE" 2>/dev/null
        snapshot_volatile
        scan_kernel
        ;;
    start)
        launcher=${1:-unknown}
        shift 2>/dev/null
        rom=$1
        # Remember the shell that is about to run the app (and the shell above
        # it, in case the caller used a subshell): the watchdog uses them to
        # find the app's process, name it in the state digest, and notice when
        # it stops using CPU.
        lp=$PPID
        gp=$(sed -n 's/.*) //p' "$PROC/$lp/stat" 2>/dev/null | cut -d' ' -f2 | tr -d '\r\n')
        printf '%s %s %s %s %s\n' "$lp" "$gp" "$(date +%s)" "$launcher" "$rom" \
            >"$SESSION_FILE" 2>/dev/null
        rm -f "$STALL_FILE" 2>/dev/null
        emit session "start app=$launcher rom=${rom:-none}"
        ;;
    app)
        rc=$1
        shift 2>/dev/null
        launcher=${1:-unknown}
        shift 2>/dev/null
        rom=$1
        shift 2>/dev/null
        secs=$1
        case "$rc" in
        '' | *[!0-9]*) rc=0 ;;
        esac
        case "$secs" in
        '' | *[!0-9]*) extra= ;;
        *) extra=" ran=${secs}s" ;;
        esac
        emit session "app=$launcher exit=$rc$(describe_status "$rc") rom=${rom:-none}$extra"
        # The session is over: the watchdog has no app to watch any more.
        rm -f "$SESSION_FILE" "$STALL_FILE" 2>/dev/null
        if [ "$rc" -ne 0 ]; then
            snapshot_volatile
            scan_kernel
        fi
        ;;
    watch)
        heartbeat
        scan_kernel
        snapshot_volatile changed-only quiet
        if [ "$SNAP_COPIED" -gt 0 ]; then
            emit watch "refreshed runtime log snapshot ($SNAP_COPIED file(s))"
        fi
        track_watch_state
        ;;
    scan)
        scan_kernel
        ;;
    shutdown)
        # Called from the power-off/reboot path while the card is still mounted:
        # this is what marks a session as cleanly closed.
        [ -f "$SESSION_MARKER" ] || return 0
        case "$1" in
        -r | reboot) what=reboot ;;
        "") what=poweroff ;;
        *) what=$1 ;;
        esac
        emit boot "clean shutdown ($what)"
        rm -f "$SESSION_MARKER" "$SESSION_FILE" "$STALL_FILE" 2>/dev/null
        sync
        ;;
    *)
        echo "Usage: $0 boot | start <launcher> [rom] | app <exit> <launcher> [rom] [seconds] | watch | scan | shutdown <reason>" >&2
        exit 2
        ;;
    esac
}

main "$@"
exit 0
