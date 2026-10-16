#!/bin/sh
# Self-check for the crash logging facility: answers "is this really wired up on
# *this* device?" without a PC and without waiting for a crash.
#
#   sh verify_logging.sh
#
# It works in three steps:
#   1. the scripts that make up the facility are installed
#   2. the files the system itself runs — the boot sequence, the launcher and the
#      shutdown path — really do call the hooks
#   3. the whole boot -> launch -> hang -> clean shutdown lifecycle is replayed in
#      a throwaway sandbox under $TMP and its records are read back, then a single
#      probe line is written to the real log directory
#
# Nothing outside the sandbox is modified except that one probe line (named
# verify_logging.log, removed again unless it already existed), so this is safe
# to run on a device in use.  Exit status 0 = healthy, 1 = something is broken.
#
# Off-device (tests) every root can be redirected with the same JUKAMIX_*
# variables the other logging scripts use, plus:
#   JUKAMIX_SCRIPTS         the scripts directory
#   JUKAMIX_POST_START      the boot sequence script
#   JUKAMIX_SHUTDOWN        the shutdown script
#   JUKAMIX_LOAD_LAUNCHER   the launcher shim that wraps every app
#   JUKAMIX_VERIFY_SANDBOX  where to replay the lifecycle (default $JUKAMIX_TMP)
#   JUKAMIX_VERIFY_KEEP=1   keep that sandbox for inspection

SDCARD=${JUKAMIX_SDCARD:-/mnt/SDCARD}
LOGDIR=${JUKAMIX_LOGDIR:-$SDCARD/System/logs}
TMP=${JUKAMIX_TMP:-/tmp}
PROC=${JUKAMIX_PROC:-/proc}
SCRIPTS=${JUKAMIX_SCRIPTS:-$SDCARD/System/usr/trimui/scripts}
POST_START=${JUKAMIX_POST_START:-$SDCARD/System/starts/°post_starts.sh}
SHUTDOWN=${JUKAMIX_SHUTDOWN:-$SDCARD/System/bin/shutdown}
LOAD_LAUNCHER=${JUKAMIX_LOAD_LAUNCHER:-$SCRIPTS/load_launcher.sh}
WATCH_PID=${JUKAMIX_WATCH_PID:-$TMP/log_watch.pid}
WATCH_INTERVAL=${JUKAMIX_WATCH_INTERVAL:-300}
case "$WATCH_INTERVAL" in '' | *[!0-9]*) WATCH_INTERVAL=300 ;; esac
SANDBOX=${JUKAMIX_VERIFY_SANDBOX:-$TMP/verify_logging.$$}
KEEP=${JUKAMIX_VERIFY_KEEP:-0}

LOG_EVENT=${JUKAMIX_LOG_EVENT:-$SCRIPTS/log_event.sh}
CAPTURE=${JUKAMIX_LOG_CAPTURE:-$SCRIPTS/log_capture.sh}
WATCH=$SCRIPTS/log_watch.sh
COLLECT=$SCRIPTS/collect_logs.sh

PASSED=0
FAILED=0
WARNED=0

pass() {
    PASSED=$((PASSED + 1))
    printf 'PASS - %s\n' "$1"
}
fail() {
    FAILED=$((FAILED + 1))
    printf 'FAIL - %s\n' "$1"
}
warn() {
    WARNED=$((WARNED + 1))
    printf 'WARN - %s\n' "$1"
}
section() { printf '\n== %s ==\n' "$1"; }

check_grep() { # <label> <literal> <file>
    if grep -q -F -- "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1 (no [$2] in $3)"; fi
}
check_no_grep() { # <label> <literal> <file>
    if grep -q -F -- "$2" "$3" 2>/dev/null; then fail "$1 (unexpected [$2] in $3)"; else pass "$1"; fi
}
check_absent() { # <label> <path>
    if [ -e "$2" ]; then fail "$1 (still present: $2)"; else pass "$1"; fi
}
check_exists() { # <label> <path>
    if [ -e "$2" ]; then pass "$1"; else fail "$1 (missing: $2)"; fi
}

# A file the system runs must itself call the hook: a hook that nothing invokes
# is the failure this whole self-check exists to catch.
check_hook() { # <file> <literal call> <label>
    if [ ! -f "$1" ]; then
        fail "$3: $1 is missing"
        return 1
    fi
    if grep -q -F -- "$2" "$1" 2>/dev/null; then
        pass "$3"
        return 0
    fi
    fail "$3: $1 never runs [$2]"
    return 1
}

printf 'JukaMix OS logging self-check\n'
printf 'logs        : %s\n' "$LOGDIR"
printf 'scripts     : %s\n' "$SCRIPTS"
printf 'boot hook   : %s\n' "$POST_START"
printf 'shutdown    : %s\n' "$SHUTDOWN"
printf 'launcher    : %s\n' "$LOAD_LAUNCHER"

# ------------------------------------------------- 1. the scripts are installed
section '1. installed scripts'
for f in "$LOG_EVENT" "$CAPTURE" "$WATCH" "$COLLECT"; do
    if [ -r "$f" ]; then pass "installed: ${f##*/}"; else fail "missing or unreadable: $f"; fi
done

# --------------------------------------------- 2. the system really calls them
section '2. hooks called by the system'
check_hook "$POST_START" 'log_capture.sh boot' 'the boot sequence records the boot'
check_hook "$POST_START" 'log_watch.sh' 'the boot sequence starts the watchdog'
check_hook "$SHUTDOWN" 'log_capture.sh shutdown' 'the shutdown path marks a clean shutdown'
check_hook "$LOAD_LAUNCHER" 'log_capture.sh start' 'the launcher records a launch before the app runs'
check_hook "$LOAD_LAUNCHER" 'log_capture.sh app' 'the launcher records how the app ended'

# ------------------------------------------------------- 3. this device, now
section '3. this device, right now'

probe=$LOGDIR/verify_logging.log
probe_existed=0
[ -f "$probe" ] && probe_existed=1
sh "$LOG_EVENT" verify_logging "self-check wrote this line on $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
if grep -q -F 'self-check wrote this line' "$probe" 2>/dev/null; then
    pass "a timestamped log line can be written to the card"
else
    fail "cannot write to $probe (card read-only, full, or missing?)"
fi
[ "$probe_existed" -eq 1 ] || rm -f "$probe" 2>/dev/null

if [ -f "$LOGDIR/.session_open" ]; then
    pass "this session was opened at boot (the boot hook has run)"
else
    warn "no session marker in $LOGDIR: logging was probably installed after this boot, or the boot hook did not run - reboot and check again"
fi

pid=$(head -n 1 "$WATCH_PID" 2>/dev/null | tr -d '\r\n ')
if [ -z "$pid" ]; then
    warn "the watchdog is not running (no $WATCH_PID): expected until the next boot after installation"
elif kill -0 "$pid" 2>/dev/null; then
    pass "the watchdog is running (pid $pid)"
else
    fail "the watchdog pid file says $pid but that process is gone"
fi

hb=$LOGDIR/watch_status.txt
if [ ! -f "$hb" ]; then
    warn "no heartbeat yet ($hb): the watchdog writes one every ${WATCH_INTERVAL}s"
else
    now=$(date +%s 2>/dev/null)
    mt=$(date -r "$hb" +%s 2>/dev/null)
    age=
    case "${now:-x}${mt:-x}" in
    *[!0-9]*) age= ;;
    *) age=$((now - mt)) ;;
    esac
    limit=$((WATCH_INTERVAL * 2))
    case "$age" in
    '')
        warn "the heartbeat age cannot be measured (this shell has no 'date -r')"
        ;;
    -*)
        warn "the heartbeat is dated in the future: the clock was changed since it was written"
        ;;
    *)
        if [ "$age" -le "$limit" ]; then
            pass "the last heartbeat is fresh (${age}s old)"
        else
            warn "the last heartbeat is ${age}s old (more than twice the ${WATCH_INTERVAL}s interval): the watchdog may have stopped"
        fi
        ;;
    esac
fi

# Logs written to a tmpfs would be wiped by the very reboot we are trying to
# survive, so this is worth knowing - but how the card is mounted is the user's
# choice, hence a warning and not a failure.
if command -v df >/dev/null 2>&1 && [ -d "$LOGDIR" ] && [ -d "$TMP" ]; then
    d_log=$(df -P "$LOGDIR" 2>/dev/null | tail -n 1 | awk '{ print $1 }')
    d_tmp=$(df -P "$TMP" 2>/dev/null | tail -n 1 | awk '{ print $1 }')
    if [ -z "$d_log" ]; then
        warn "the filesystem holding $LOGDIR cannot be identified"
    elif [ "$d_log" = "$d_tmp" ]; then
        warn "logs and $TMP share the filesystem $d_log: they may not survive a reboot"
    else
        pass "the logs live on $d_log, which survives a reboot"
    fi
fi

# --------------------------------- 4. replay the lifecycle in a sandbox under TMP
section '4. the lifecycle, replayed in a sandbox'

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/logs" "$SANDBOX/tmp" "$SANDBOX/etc" "$SANDBOX/bin" \
    "$SANDBOX/proc/sys/kernel/random" "$SANDBOX/sdcard/System/usr/trimui"
printf 'verify\n' >"$SANDBOX/etc/trimui_device.txt"
printf '0.0.0-verify\n' >"$SANDBOX/sdcard/System/usr/trimui/crossmix-version.txt"
printf '900.00 800.00\n' >"$SANDBOX/proc/uptime"
printf 'verify-boot-id\n' >"$SANDBOX/proc/sys/kernel/random/boot_id"
printf 'MemTotal: 1048576 kB\nMemAvailable: 300000 kB\n' >"$SANDBOX/proc/meminfo"
printf '0.10 0.20 0.30 1/40 999\n' >"$SANDBOX/proc/loadavg"
printf 'sandbox launcher output\n' >"$SANDBOX/tmp/messages"
# A fake process tree and CPU counters: the watchdog tick runs on /proc, and the
# sandbox needs a running "app" for it to describe.  The verifier itself plays
# the launcher shell, so the app hangs below its own pid.
printf 'cpu  1500 0 300 9000 60 0 40 0 0 0\n' >"$SANDBOX/proc/stat"
mkdir -p "$SANDBOX/proc/$$" "$SANDBOX/proc/601"
printf '%s (sh) S 1 %s %s 0 -1 4194304 0 0 0 0 0 0 0 0 20 0 1 0 1 2 3 0 0 0\n' \
    "$$" "$$" "$$" >"$SANDBOX/proc/$$/stat"
printf '601 (frozen.iso) S %s 601 601 0 -1 4194304 0 0 0 0 120 30 0 0 20 0 1 0 1 2 3 0 0 0\n' \
    "$$" >"$SANDBOX/proc/601/stat"
printf 'Name:\tfrozen.iso\nState:\tS (sleeping)\nVmRSS:\t 90000 kB\n' >"$SANDBOX/proc/601/status"
printf 'do_futex\n' >"$SANDBOX/proc/601/wchan"
cat >"$SANDBOX/kmsg.txt" <<'FIXTURE'
[    0.000000] verify: Booting Linux
[   10.000000] verify-app[42]: segfault at 0 ip 00000000 sp 00000000 error 4
FIXTURE
# A kernel log of our own, so the sandbox never reads (or needs root for) dmesg.
cat >"$SANDBOX/bin/dmesg" <<'STUB'
#!/bin/sh
cat "$JUKAMIX_VERIFY_KMSG" 2>/dev/null
STUB
chmod +x "$SANDBOX/bin/dmesg"

JUKAMIX_VERIFY_KMSG=$SANDBOX/kmsg.txt
PATH=$SANDBOX/bin:$PATH
JUKAMIX_SDCARD=$SANDBOX/sdcard
JUKAMIX_LOGDIR=$SANDBOX/logs
JUKAMIX_TMP=$SANDBOX/tmp
JUKAMIX_ETC=$SANDBOX/etc
JUKAMIX_PROC=$SANDBOX/proc
JUKAMIX_LOG_EVENT=$LOG_EVENT
JUKAMIX_LOG_CAPTURE=$CAPTURE
export JUKAMIX_VERIFY_KMSG PATH JUKAMIX_SDCARD JUKAMIX_LOGDIR JUKAMIX_TMP \
    JUKAMIX_ETC JUKAMIX_PROC JUKAMIX_LOG_EVENT JUKAMIX_LOG_CAPTURE
SL=$SANDBOX/logs

sh "$CAPTURE" boot
check_grep 'the boot is recorded with the device and image' 'boot: image=0.0.0-verify device=verify' "$SL/boot.log"
check_grep 'a crash signature in the kernel log is captured' 'segfault at 0' "$SL/crash.log"
check_grep 'the volatile runtime log is preserved on the card' 'sandbox launcher output' "$SL/last_messages.log"
if [ -f "$SL/.session_open" ]; then
    pass 'the boot opens the session marker'
else
    fail 'the boot did not open the session marker'
fi

# Power pull: the marker is still there, so the next boot must say so and quote
# the heartbeat that dates it.
printf '[2026-01-02 03:04:05] alive uptime=999s free_mem=1kB load=0.00\n' >"$SL/watch_status.txt"
sh "$CAPTURE" boot
check_grep 'a boot after a power pull is flagged as unclean' 'previous session ended without a clean shutdown' "$SL/boot.log"
check_grep 'that flag quotes the last heartbeat, dating the hang' 'uptime=999s' "$SL/boot.log"

sh "$CAPTURE" start default.sh "$SANDBOX/sdcard/Roms/PSP/frozen.iso"
check_grep 'a launch is recorded before the app runs' 'start app=default.sh' "$SL/session.log"

# The watchdog digests: two ticks are the raw material of the next boot's hang
# autopsy, and an app that never uses CPU has to be named while it is there.
sh "$CAPTURE" watch
check_grep 'the tick names the running app' 'app: comm=frozen.iso' "$SL/watch_state.txt"
check_grep 'the tick names the app pid' 'pid=601' "$SL/watch_state.txt"
check_grep 'the tick records the session it saw' 'session: app=default.sh' "$SL/watch_state.txt"
sh "$CAPTURE" watch
check_exists 'the tick before is kept for the autopsy' "$SL/watch_state_prev.txt"
sh "$CAPTURE" watch
check_grep 'an app that stops using CPU is noted' 'no CPU progress' "$SL/watch.log"
check_grep 'the stall dump keeps the process state' 'do_futex' "$SL/last_stall.txt"

sh "$COLLECT" "$SANDBOX/report.txt" >/dev/null 2>&1
check_grep 'the diagnostics report leads with a summary' '0. summary' "$SANDBOX/report.txt"
check_grep 'a launch that never returned is reported as a hang' 'never returned' "$SANDBOX/report.txt"
check_grep 'the report carries the state at the last tick' 'watch state at the last tick' "$SANDBOX/report.txt"

# Power pull with the digests from the last two ticks still on the card: the next
# boot has to say whether the system was still working and what the app did.
printf '[2026-01-02 03:04:05] epoch=1000 boot=verify-boot-id uptime=100s load=0.10 0.10 0.10 busy=184000 mem=1kB\napp: comm=frozen.iso pid=601 state=S cpu=1.50s\ntop: comm=frozen.iso pid=601 state=S cpu=1.50s\n' >"$SL/watch_state_prev.txt"
printf '[2026-01-02 03:09:05] epoch=1300 boot=verify-boot-id uptime=400s load=0.90 0.90 0.90 busy=184040 mem=1kB\napp: comm=frozen.iso pid=601 state=S cpu=1.50s\ntop: comm=frozen.iso pid=601 state=S cpu=1.50s\n' >"$SL/watch_state.txt"
sh "$CAPTURE" boot
check_grep 'a freeze is dated from the last two ticks' 'had already stopped working' "$SL/boot.log"
check_grep 'the autopsy counts the CPU work in the last interval' '0.4s of CPU work in the last 300s' "$SL/boot.log"
check_grep 'the autopsy names the app that used no CPU' 'used no CPU in between' "$SL/boot.log"

printf '[2026-01-02 03:09:05] epoch=1300 boot=verify-boot-id uptime=400s load=0.90 0.90 0.90 busy=184040 mem=1kB\napp: comm=frozen.iso pid=601 state=R cpu=1.50s\ntop: comm=frozen.iso pid=601 state=R cpu=1.50s\n' >"$SL/watch_state_prev.txt"
printf '[2026-01-02 03:14:05] epoch=1600 boot=verify-boot-id uptime=700s load=1.00 1.00 1.00 busy=190000 mem=1kB\napp: comm=frozen.iso pid=601 state=R cpu=3.00s\ntop: comm=frozen.iso pid=601 state=R cpu=3.00s\n' >"$SL/watch_state.txt"
sh "$CAPTURE" boot
check_grep 'a system still working at the last tick says so' 'was still working' "$SL/boot.log"
check_grep 'the autopsy shows the app was still advancing' 'gained 1.5s of CPU' "$SL/boot.log"

sh "$CAPTURE" shutdown -r
check_absent 'a clean shutdown clears the session marker' "$SL/.session_open"
check_grep 'the clean shutdown is recorded' 'clean shutdown (reboot)' "$SL/boot.log"

rm -f "$SL/boot.log"
sh "$CAPTURE" boot
check_no_grep 'a cleanly closed session is not reported as unclean' 'without a clean shutdown' "$SL/boot.log"

sh "$CAPTURE" watch
check_grep 'a watchdog tick leaves a heartbeat behind' 'alive uptime=' "$SL/watch_status.txt"

if [ "$KEEP" = "1" ]; then
    printf 'NOTE - the sandbox was kept at %s\n' "$SANDBOX"
else
    rm -rf "$SANDBOX" 2>/dev/null
fi

# ---------------------------------------------------------------------- result
section 'result'
printf '%s check(s): %s passed, %s failed, %s warning(s)\n' \
    "$((PASSED + FAILED))" "$PASSED" "$FAILED" "$WARNED"
if [ "$FAILED" -eq 0 ]; then
    printf 'The logging facility is wired up and working; a crash or a power pull will be recorded.\n'
    exit 0
fi
printf 'The FAIL lines above must be fixed, or a crash will leave no usable record.\n'
exit 1
