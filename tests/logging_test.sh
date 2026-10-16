#!/bin/sh
# Off-device checks for the logging facility (JukaMix OS):
#
#   System/usr/trimui/scripts/log_event.sh    append with size cap + rotation
#   System/usr/trimui/scripts/log_capture.sh  boot / launch / exit / watchdog
#                                             (state digest + app stall) /
#                                             crash scan / hang autopsy /
#                                             clean shutdown
#   System/usr/trimui/scripts/log_watch.sh    the periodic watchdog
#   System/usr/trimui/scripts/collect_logs.sh the diagnostics report
#   System/usr/trimui/scripts/verify_logging.sh  the on-device self-check
#
# Section 13 also pins the wiring of the hooks into the system files themselves
# (the boot sequence, the launcher shim and the shutdown path), so a hook that
# gets dropped by a future edit is caught here rather than on a device.
#
# Every root is redirected through the JUKAMIX_* overrides, dmesg is stubbed on
# PATH (reading a fixture we can append to), and /proc is a small fake tree, so
# the whole flow runs without a device.
#
#   sh tests/logging_test.sh
#
# Exit status 0 = all checks passed, 1 = at least one failed.

REPO=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$REPO/System/usr/trimui/scripts"

T=${TMPDIR:-/tmp}/logging_test
FAILED=0
CHECKS=0

pass() {
    CHECKS=$((CHECKS + 1))
    printf 'ok   - %s\n' "$1"
}
fail() {
    CHECKS=$((CHECKS + 1))
    FAILED=$((FAILED + 1))
    printf 'FAIL - %s\n' "$1"
}
check_eq() { # label expected actual
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi
}
check_grep() { # label pattern file
    if grep -q -F -- "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1 (missing [$2] in $3)"; fi
}
check_no_grep() { # label pattern file
    if grep -q -F -- "$2" "$3" 2>/dev/null; then fail "$1 (unexpected [$2])"; else pass "$1"; fi
}
check_exists() { # label path
    if [ -e "$2" ]; then pass "$1"; else fail "$1 (missing $2)"; fi
}
check_absent() { # label path
    if [ -e "$2" ]; then fail "$1 (unexpected $2)"; else pass "$1"; fi
}
check_count() { # label expected pattern file
    n=$(grep -c -F -- "$3" "$4" 2>/dev/null)
    [ -n "$n" ] || n=0
    if [ "$2" = "$n" ]; then pass "$1"; else fail "$1 (expected $2 line(s) of [$3], got $n)"; fi
}
check_le() { # label max actual
    if [ "$3" -le "$2" ] 2>/dev/null; then pass "$1"; else fail "$1 (expected <= $2, got $3)"; fi
}

LOGDIR="$T/sdcard/System/logs"

setup() {
    rm -rf "$T"
    mkdir -p "$LOGDIR" "$T/tmp/log" "$T/etc" "$T/proc/sys/kernel/random" "$T/sys" "$T/bin" \
        "$T/udisk" "$T/sdcard/System/usr/trimui" "$T/sdcard/System/etc"
    printf 'tsp\n' >"$T/etc/trimui_device.txt"
    printf '1.3.0\n' >"$T/sdcard/System/usr/trimui/crossmix-version.txt"
    printf '1.3.0\n' >"$T/usr_trimui_version.txt"
    printf '1234.56 4321.00\n' >"$T/proc/uptime"
    printf 'test-boot-id\n' >"$T/proc/sys/kernel/random/boot_id"
    printf 'MemTotal:  1048576 kB\nMemAvailable:   512000 kB\n' >"$T/proc/meminfo"
    printf '0.32 0.21 0.10 1/64 12345\n' >"$T/proc/loadavg"
    # A fake process tree and CPU counters: a watchdog tick reads /proc, and the
    # test needs a deterministic "running app" for the state digest to find.  The
    # test shell plays the launcher, its two children are the app and the app's
    # real workload (the busiest descendant is what the digest has to pick).
    printf 'cpu  1500 0 300 9000 60 0 40 0 0 0\n' >"$T/proc/stat"
    mkdir -p "$T/proc/$$" "$T/proc/714" "$T/proc/715"
    printf '%s (sh) S 1 %s %s 0 -1 4194304 0 0 0 0 0 0 0 0 20 0 1 0 1 2 3 0 0 0\n' \
        "$$" "$$" "$$" >"$T/proc/$$/stat"
    printf '714 (emulator.sh) S %s 714 714 0 -1 4194304 0 0 0 0 120 30 0 0 20 0 1 0 1 2 3 0 0 0\n' \
        "$$" >"$T/proc/714/stat"
    printf '715 (heavy.sh) S 714 714 714 0 -1 4194304 0 0 0 0 300 25 0 0 20 0 1 0 1 2 3 0 0 0\n' \
        >"$T/proc/715/stat"
    printf 'Name:\theavy.sh\nState:\tS (sleeping)\nVmRSS:\t 90000 kB\n' >"$T/proc/715/status"
    printf 'do_futex\n' >"$T/proc/715/wchan"
    printf '{ "NightMode": 0 }\n' >"$T/sdcard/System/etc/crossmix.json"

    # Stubbed kernel log: the fixture can be appended to while a test runs.
    cat >"$T/kmsg.txt" <<'FIXTURE'
[    0.000000] Booting Linux
[   12.345678] ra64.trimui[812]: segfault at 0 ip 00000000 sp 00000000 error 4
[   12.345679] sd 0:0:0:0: [sda] Attached SCSI removable disk
FIXTURE
    cat >"$T/bin/dmesg" <<STUB
#!/bin/sh
cat "$T/kmsg.txt" 2>/dev/null
STUB
    chmod +x "$T/bin/dmesg"

    PATH="$T/bin:$PATH"
    export PATH

    export JUKAMIX_SDCARD="$T/sdcard"
    export JUKAMIX_LOGDIR="$LOGDIR"
    export JUKAMIX_TMP="$T/tmp"
    export JUKAMIX_ETC="$T/etc"
    export JUKAMIX_PROC="$T/proc"
    export JUKAMIX_SYS="$T/sys"
    export JUKAMIX_UDISK="$T/udisk"
    export JUKAMIX_LOG_EVENT="$SCRIPTS/log_event.sh"
    export JUKAMIX_LOG_CAPTURE="$SCRIPTS/log_capture.sh"
    export JUKAMIX_WATCH_PID="$T/tmp/log_watch.pid"
}

# ------------------------------------------------------- 1. log_event.sh
printf '\n== log_event.sh ==\n'
setup
sh "$SCRIPTS/log_event.sh" test "first message"
sh "$SCRIPTS/log_event.sh" test "second message"
check_eq "a log holds one line per call" "2" "$(grep -c . "$LOGDIR/test.log")"
check_grep "lines are timestamped" "first message" "$LOGDIR/test.log"
check_grep "a timestamp is prepended" "$(date '+%Y-%m-%d')" "$LOGDIR/test.log"
sh "$SCRIPTS/log_event.sh" >/dev/null 2>&1
check_eq "a missing log name is refused" "2" "$?"

# With a 80 byte cap, the third write rotates the two lines written above.
JUKAMIX_LOG_MAX_BYTES=80
export JUKAMIX_LOG_MAX_BYTES
i=0
while [ "$i" -lt 2 ]; do
    sh "$SCRIPTS/log_event.sh" test "padding line $i padding padding padding"
    i=$((i + 1))
done
check_exists "an oversized log is rotated" "$LOGDIR/test.log.1"
check_grep "the rotated file keeps the previous lines" "first message" "$LOGDIR/test.log.1"
i=0
while [ "$i" -lt 6 ]; do
    sh "$SCRIPTS/log_event.sh" test "more padding $i padding padding padding"
    i=$((i + 1))
done
if [ "$(wc -c <"$LOGDIR/test.log" | tr -d ' ')" -le 200 ]; then
    pass "the live log stays small after rotation"
else
    fail "the live log stays small after rotation ($(wc -c <"$LOGDIR/test.log") bytes)"
fi
unset JUKAMIX_LOG_MAX_BYTES

# ------------------------------------------- 2. log_capture.sh: boot
printf '\n== log_capture.sh boot ==\n'
setup
printf 'Loading...\nlauncher exited\n' >"$T/tmp/messages"
sh "$SCRIPTS/log_capture.sh" boot
check_grep "the boot line records the device" "device=tsp" "$LOGDIR/boot.log"
check_grep "the boot line records the image version" "image=1.3.0" "$LOGDIR/boot.log"
check_grep "the boot line records the uptime" "uptime=1234.56s" "$LOGDIR/boot.log"
check_grep "the runtime log is preserved on the card" "launcher exited" "$LOGDIR/last_messages.log"
check_grep "a kernel crash signature is recorded" "segfault at 0" "$LOGDIR/crash.log"
check_no_grep "harmless kernel lines are not recorded" "Attached SCSI removable disk" "$LOGDIR/crash.log"
check_exists "a boot opens a session (clean-shutdown marker)" "$LOGDIR/.session_open"

# ------------------------------------- 3. log_capture.sh: app exit status
printf '\n== log_capture.sh app ==\n'
setup
rm -f "$LOGDIR/last_messages.log"
printf 'crash trace\n' >"$T/tmp/messages"
sh "$SCRIPTS/log_capture.sh" app 139 emulator.sh /mnt/SDCARD/Roms/PSP/game.iso
check_grep "the session line names the launcher" "app=emulator.sh" "$LOGDIR/session.log"
check_grep "a SIGSEGV exit is reported as a crash" "exit=139 (crashed: SIGSEGV)" "$LOGDIR/session.log"
check_grep "the rom is recorded" "rom=/mnt/SDCARD/Roms/PSP/game.iso" "$LOGDIR/session.log"
check_exists "a crashing app preserves the runtime log" "$LOGDIR/last_messages.log"
check_grep "a crashing app refreshes the crash scan" "segfault at 0" "$LOGDIR/crash.log"

rm -f "$LOGDIR/last_messages.log" "$LOGDIR/crash.log" "$LOGDIR/session.log"
sh "$SCRIPTS/log_capture.sh" app 0 launcher.sh /mnt/SDCARD/Roms/PSP/ok.iso
check_grep "a clean exit is recorded without a crash note" "app=launcher.sh exit=0 rom=/mnt/SDCARD/Roms/PSP/ok.iso" "$LOGDIR/session.log"
check_no_grep "a clean exit does not claim a crash" "crashed" "$LOGDIR/session.log"
check_absent "a clean exit does not copy the runtime log" "$LOGDIR/last_messages.log"
check_absent "a clean exit does not rerun the crash scan" "$LOGDIR/crash.log"

sh "$SCRIPTS/log_capture.sh" app
check_grep "a missing status is treated as a clean exit" "exit=0" "$LOGDIR/session.log"

# ---------------------------------- 4. launches, duration and OOM handling
printf '\n== launch records ==\n'
setup
sh "$SCRIPTS/log_capture.sh" start default.sh /mnt/SDCARD/Roms/PSP/game.iso
check_grep "a launch is recorded before the emulator runs" \
    "start app=default.sh rom=/mnt/SDCARD/Roms/PSP/game.iso" "$LOGDIR/session.log"
sh "$SCRIPTS/log_capture.sh" app 139 default.sh /mnt/SDCARD/Roms/PSP/game.iso 42
check_grep "the exit line keeps the crash note" "exit=139 (crashed: SIGSEGV)" "$LOGDIR/session.log"
check_grep "how long the emulator lasted is recorded" "ran=42s" "$LOGDIR/session.log"
sh "$SCRIPTS/log_capture.sh" app 137 default.sh /mnt/SDCARD/Roms/PSP/big.iso 900
check_grep "an OOM kill is called out" "exit=137 (killed: SIGKILL - out of memory?)" "$LOGDIR/session.log"

# ---------------------------------- 5. log_capture.sh: a second kernel source
printf '\n== log_capture.sh with only logread ==\n'
setup
rm -f "$T/bin/dmesg"
cat >"$T/bin/logread" <<'STUB'
#!/bin/sh
echo "[  99.0] Out of memory: Killed process 4242 (MainUI) total-vm:100000kB"
STUB
chmod +x "$T/bin/logread"
sh "$SCRIPTS/log_capture.sh" scan
check_grep "logread is used when dmesg is absent" "Killed process 4242" "$LOGDIR/crash.log"

# ------------------------------------------- 6. log_capture.sh: no kernel log
printf '\n== kernel log unavailable ==\n'
setup
printf '#!/bin/sh\nexit 1\n' >"$T/bin/dmesg"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/logread"
chmod +x "$T/bin/dmesg" "$T/bin/logread"
sh "$SCRIPTS/log_capture.sh" scan
sh "$SCRIPTS/log_capture.sh" scan
sh "$SCRIPTS/log_capture.sh" boot
check_eq "an unreadable kernel log is reported once, not per scan" "1" \
    "$(grep -c 'kernel log not readable' "$LOGDIR/crash.log" 2>/dev/null)"

# ------------------------------------------- 7. incremental kernel scanning
printf '\n== incremental kernel scan ==\n'
setup
sh "$SCRIPTS/log_capture.sh" boot
check_count "the boot scan records the crash once" "1" "segfault at 0" "$LOGDIR/crash.log"
sh "$SCRIPTS/log_capture.sh" scan
sh "$SCRIPTS/log_capture.sh" scan
check_count "repeated scans do not repeat old kernel lines" "1" "segfault at 0" "$LOGDIR/crash.log"
printf '[  500.000000] mmc0: error -110 whilst initialising SD card\n' >>"$T/kmsg.txt"
sh "$SCRIPTS/log_capture.sh" scan
check_grep "a newly appended crash line is picked up" "mmc0: error -110" "$LOGDIR/crash.log"
check_count "the earlier line is still recorded only once" "1" "segfault at 0" "$LOGDIR/crash.log"

# ------------------------------------------- 8. watchdog tick
printf '\n== log_capture.sh watch (watchdog tick) ==\n'
setup
printf 'line one\n' >"$T/tmp/messages"
sh "$SCRIPTS/log_capture.sh" watch
check_exists "a tick writes the heartbeat file" "$LOGDIR/watch_status.txt"
check_grep "the heartbeat carries the uptime" "uptime=1234.56s" "$LOGDIR/watch_status.txt"
check_grep "the heartbeat carries free memory" "free_mem=512000kB" "$LOGDIR/watch_status.txt"
check_grep "the heartbeat carries the load average" "load=0.32 0.21 0.10" "$LOGDIR/watch_status.txt"
check_grep "the first tick copies the runtime log" "line one" "$LOGDIR/last_messages.log"
check_grep "the first tick logs what it captured" "refreshed runtime log snapshot" "$LOGDIR/watch.log"
check_no_grep "a tick does not spam session.log with copies" "captured" "$LOGDIR/session.log"
rm -f "$LOGDIR/watch.log"
sh "$SCRIPTS/log_capture.sh" watch
check_absent "an unchanged runtime log is not copied again" "$LOGDIR/watch.log"
printf 'line one\nline two\n' >"$T/tmp/messages"
sh "$SCRIPTS/log_capture.sh" watch
check_grep "a changed runtime log is copied again" "refreshed runtime log snapshot" "$LOGDIR/watch.log"
check_grep "the new copy is up to date" "line two" "$LOGDIR/last_messages.log"
check_count "the heartbeat file is rewritten, not appended" "1" "alive" "$LOGDIR/watch_status.txt"

# The tick also writes the state digest the next boot's hang autopsy compares,
# and keeps an eye on the launched app.
rm -f "$LOGDIR/watch_state.txt" "$LOGDIR/watch_state_prev.txt" "$LOGDIR/watch.log" "$LOGDIR/last_stall.txt"
sh "$SCRIPTS/log_capture.sh" start default.sh /mnt/SDCARD/Roms/PSP/frozen.iso
check_exists "the launch remembers the shell that runs the app" "$T/tmp/log_capture_session"
sh "$SCRIPTS/log_capture.sh" watch
check_grep "a tick knows which app is running" "app: comm=heavy.sh" "$LOGDIR/watch_state.txt"
check_grep "the busiest descendant is taken as the app" "app: comm=heavy.sh pid=715" "$LOGDIR/watch_state.txt"
check_grep "a tick records the session it saw" "session: app=default.sh" "$LOGDIR/watch_state.txt"
check_grep "a tick records the system CPU work" "busy=1840" "$LOGDIR/watch_state.txt"
check_grep "a tick records the top CPU consumers" "top: comm=heavy.sh pid=715" "$LOGDIR/watch_state.txt"
check_absent "the first tick has no earlier tick to keep" "$LOGDIR/watch_state_prev.txt"
sh "$SCRIPTS/log_capture.sh" watch
check_exists "the tick before is kept for the autopsy" "$LOGDIR/watch_state_prev.txt"
check_grep "the kept tick carries its own counters" "busy=1840" "$LOGDIR/watch_state_prev.txt"
sh "$SCRIPTS/log_capture.sh" watch
check_grep "an app that never uses CPU gets a stall note" "no CPU progress" "$LOGDIR/watch.log"
check_grep "the stall note names the app and its state" "heavy.sh (pid 715, state S" "$LOGDIR/watch.log"
check_grep "the stall dump keeps the process state" "do_futex" "$LOGDIR/last_stall.txt"
check_grep "the stall dump keeps /proc status" "VmRSS:" "$LOGDIR/last_stall.txt"
check_grep "the stall dump quotes both ticks" "the last two watchdog ticks" "$LOGDIR/last_stall.txt"
# An app that starts running again must clear the stall instead of being noted
# forever.
printf '715 (heavy.sh) S 714 714 714 0 -1 4194304 0 0 0 0 400 25 0 0 20 0 1 0 1 2 3 0 0 0\n' \
    >"$T/proc/715/stat"
sh "$SCRIPTS/log_capture.sh" watch
check_count "a recovered app is not reported again" "1" "no CPU progress" "$LOGDIR/watch.log"
sh "$SCRIPTS/log_capture.sh" app 0 default.sh /mnt/SDCARD/Roms/PSP/frozen.iso 60
check_absent "a finished session clears the stall state" "$T/tmp/log_capture_stall"
check_absent "a finished session clears the launch record" "$T/tmp/log_capture_session"

# ------------------------------------- 9. log_watch.sh: single instance
printf '\n== log_watch.sh ==\n'
setup
sh "$SCRIPTS/log_watch.sh" 30 &
watch_pid=$!
i=0
while [ ! -f "$T/tmp/log_watch.pid" ] && [ "$i" -lt 20 ]; do
    sleep 0.1
    i=$((i + 1))
done
check_exists "the watchdog writes a pid file" "$T/tmp/log_watch.pid"
# The first tick waits a few seconds so the boot capture can go first.
i=0
while [ ! -f "$LOGDIR/watch_status.txt" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
done
check_grep "the watchdog recorded a heartbeat" "alive" "$LOGDIR/watch_status.txt"
check_eq "the watchdog is still running after its first tick" "0" \
    "$(kill -0 "$watch_pid" 2>/dev/null; echo $?)"
sh "$SCRIPTS/log_watch.sh" 30
check_eq "a second watchdog exits instead of duplicating work" "0" "$?"
kill "$watch_pid" 2>/dev/null
wait "$watch_pid" 2>/dev/null

# --------------------------------------- 10. clean / unclean session marker
printf '\n== clean and unclean shutdowns ==\n'
setup
sh "$SCRIPTS/log_capture.sh" boot
printf '[2026-01-02 03:04:05] alive uptime=999s free_mem=12000kB load=9.99\n' >"$LOGDIR/watch_status.txt"
sh "$SCRIPTS/log_capture.sh" boot
check_grep "a leftover marker is reported as an unclean session" \
    "previous session ended without a clean shutdown" "$LOGDIR/boot.log"
check_grep "the last heartbeat is quoted so the hang can be dated" "uptime=999s" "$LOGDIR/boot.log"

sh "$SCRIPTS/log_capture.sh" shutdown -r
check_absent "a clean shutdown clears the session marker" "$LOGDIR/.session_open"
check_grep "a clean reboot is recorded" "clean shutdown (reboot)" "$LOGDIR/boot.log"
sh "$SCRIPTS/log_capture.sh" shutdown -r
check_count "a repeated shutdown call is not logged twice" "1" "clean shutdown (reboot)" "$LOGDIR/boot.log"

rm -f "$LOGDIR/boot.log"
sh "$SCRIPTS/log_capture.sh" boot
check_no_grep "a clean previous session is not flagged as unclean" \
    "without a clean shutdown" "$LOGDIR/boot.log"

# What the digest pair is for: after a power pull the next boot has to say
# whether the whole system was still working and what the app was doing, so a
# hang can be blamed on the app rather than on "the device froze".
setup
sh "$SCRIPTS/log_capture.sh" boot
printf '[2026-01-02 03:00:00] epoch=1000 boot=test-boot-id uptime=100s load=0.10 0.10 0.10 busy=184000 mem=1kB\napp: comm=heavy.sh pid=715 state=D cpu=3.25s\ntop: comm=heavy.sh pid=715 state=D cpu=3.25s\n' >"$LOGDIR/watch_state_prev.txt"
printf '[2026-01-02 03:05:00] epoch=1300 boot=test-boot-id uptime=400s load=0.90 0.90 0.90 busy=184040 mem=1kB\napp: comm=heavy.sh pid=715 state=D cpu=3.25s\ntop: comm=heavy.sh pid=715 state=D cpu=3.25s\n' >"$LOGDIR/watch_state.txt"
rm -f "$LOGDIR/boot.log"
sh "$SCRIPTS/log_capture.sh" boot
check_grep "a frozen last tick is reported as the system having stopped" \
    "had already stopped working" "$LOGDIR/boot.log"
check_grep "the autopsy counts the CPU work of the last interval" \
    "0.4s of CPU work in the last 300s" "$LOGDIR/boot.log"
check_grep "the autopsy names the app that used no CPU" \
    "heavy.sh (pid 715, state D) used no CPU in between" "$LOGDIR/boot.log"
sh "$SCRIPTS/collect_logs.sh" "$T/report_frozen.txt" >/dev/null 2>&1
check_grep "the report carries the hang autopsy" "had already stopped working" "$T/report_frozen.txt"
check_grep "the report shows the device state before the end" "device state before the end" "$T/report_frozen.txt"

# When the system was still working, the autopsy says that instead.
printf '[2026-01-02 03:05:00] epoch=1300 boot=test-boot-id uptime=400s load=0.90 0.90 0.90 busy=184040 mem=1kB\napp: comm=heavy.sh pid=715 state=R cpu=3.25s\ntop: comm=heavy.sh pid=715 state=R cpu=3.25s\n' >"$LOGDIR/watch_state_prev.txt"
printf '[2026-01-02 03:10:00] epoch=1600 boot=test-boot-id uptime=700s load=1.00 1.00 1.00 busy=190000 mem=1kB\napp: comm=heavy.sh pid=715 state=R cpu=8.25s\ntop: comm=heavy.sh pid=715 state=R cpu=8.25s\n' >"$LOGDIR/watch_state.txt"
rm -f "$LOGDIR/boot.log"
sh "$SCRIPTS/log_capture.sh" boot
check_grep "a system still working at the last tick is reported as such" \
    "was still working" "$LOGDIR/boot.log"
check_grep "the autopsy shows the app's CPU progress" \
    "heavy.sh (pid 715) gained 5.0s of CPU" "$LOGDIR/boot.log"

# Two digests from different boots must never be paired into a fake autopsy.
printf '[2026-01-02 03:10:00] epoch=1600 boot=other-boot uptime=10s load=0.10 0.10 0.10 busy=50 mem=1kB\n' >"$LOGDIR/watch_state_prev.txt"
printf '[2026-01-02 03:15:00] epoch=1900 boot=test-boot-id uptime=20s load=0.10 0.10 0.10 busy=100 mem=1kB\n' >"$LOGDIR/watch_state.txt"
rm -f "$LOGDIR/boot.log"
sh "$SCRIPTS/log_capture.sh" boot
check_no_grep "digests from different boots are not paired" \
    "CPU work in the last" "$LOGDIR/boot.log"

# The scan cursor must survive a shutdown: re-reading the whole kernel log would
# repeat every crash it already recorded.
setup
sh "$SCRIPTS/log_capture.sh" boot
check_count "the boot scan records the crash once" "1" "segfault at 0" "$LOGDIR/crash.log"
sh "$SCRIPTS/log_capture.sh" shutdown
sh "$SCRIPTS/log_capture.sh" scan
check_count "a scan after a clean shutdown does not re-read the kernel log" "1" \
    "segfault at 0" "$LOGDIR/crash.log"

# ------------------------------------------------- 11. collect_logs.sh
printf '\n== collect_logs.sh ==\n'
setup
sh "$SCRIPTS/log_capture.sh" boot
sh "$SCRIPTS/log_capture.sh" start emulator.sh /mnt/SDCARD/Roms/PSP/game.iso
sh "$SCRIPTS/log_capture.sh" app 139 emulator.sh /mnt/SDCARD/Roms/PSP/game.iso 7
sh "$SCRIPTS/log_capture.sh" watch
sh "$SCRIPTS/collect_logs.sh" "$T/report.txt" >"$T/collect.out" 2>&1
check_exists "the report file is written" "$T/report.txt"
check_grep "the report identifies itself" "JukaMix OS diagnostics" "$T/report.txt"
check_grep "the report names the device" "device      : tsp" "$T/report.txt"
check_grep "the report leads with a summary" "0. summary" "$T/report.txt"
check_grep "the summary counts the crashes" "crash entries recorded    : 1" "$T/report.txt"
check_grep "the summary carries the session verdict" "last launch returned" "$T/report.txt"
check_grep "the summary shows the last app exit" "ran=7s" "$T/report.txt"
check_grep "the report has a crash section" "1. crash signatures (kernel log)" "$T/report.txt"
check_grep "the report has a session section" "2. recent launches and app sessions" "$T/report.txt"
check_grep "the report has a system section" "5. system state" "$T/report.txt"
check_grep "the report has a settings section" "6. settings" "$T/report.txt"
check_grep "the report carries the crash signature" "segfault at 0" "$T/report.txt"
check_grep "the report carries the crashed app" "exit=139 (crashed: SIGSEGV)" "$T/report.txt"
check_grep "the report shows the state at the last watchdog tick" \
    "watch state at the last tick" "$T/report.txt"
check_grep "the report path is printed" "Report saved to: $T/report.txt" "$T/collect.out"
check_no_grep "no credential file is quoted" "wpa_supplicant" "$T/report.txt"

# A launch that never came back is the signature of a hang.
setup
sh "$SCRIPTS/log_capture.sh" boot
sh "$SCRIPTS/log_capture.sh" start emulator.sh /mnt/SDCARD/Roms/PSP/frozen.iso
sh "$SCRIPTS/collect_logs.sh" "$T/report_hang.txt" >/dev/null 2>&1
check_grep "the report flags a launch that never returned" "never returned" "$T/report_hang.txt"
check_grep "the report names the rom that hung" "frozen.iso" "$T/report_hang.txt"

# An unclean previous session is called out at the top of the report.
setup
sh "$SCRIPTS/log_capture.sh" boot
printf '[2026-01-02 03:04:05] alive uptime=999s free_mem=12000kB load=9.99\n' >"$LOGDIR/watch_status.txt"
sh "$SCRIPTS/log_capture.sh" boot
sh "$SCRIPTS/collect_logs.sh" "$T/report_unclean.txt" >/dev/null 2>&1
check_grep "the report flags an unclean previous session" "previous boot             : NOT clean" \
    "$T/report_unclean.txt"
check_grep "the report dates the last heartbeat" "uptime=999s" "$T/report_unclean.txt"

# A clean session is reported as clean.
setup
sh "$SCRIPTS/log_capture.sh" boot
sh "$SCRIPTS/log_capture.sh" app 0 launcher.sh /mnt/SDCARD/Roms/PSP/ok.iso 120
sh "$SCRIPTS/log_capture.sh" shutdown poweroff
sh "$SCRIPTS/log_capture.sh" boot
sh "$SCRIPTS/collect_logs.sh" "$T/report_clean.txt" >/dev/null 2>&1
check_grep "the report shows a clean previous session" "previous boot             : clean:" \
    "$T/report_clean.txt"

# ------------------------------------------- 12. report retention
printf '\n== report retention ==\n'
setup
i=0
while [ "$i" -lt 12 ]; do
    printf 'old report\n' >"$LOGDIR/diagnostics_20260101-0000$i.txt"
    i=$((i + 1))
done
sh "$SCRIPTS/collect_logs.sh" >"$T/collect2.out" 2>&1
check_grep "a default report name is used on the card" "diagnostics_" "$T/collect2.out"
reports=$(ls -1 "$LOGDIR"/diagnostics_*.txt 2>/dev/null | wc -l | tr -d ' ')
check_le "old reports are pruned (newest 10 kept)" 10 "$reports"
check_exists "the newest report survives pruning" "$(ls -1t "$LOGDIR"/diagnostics_*.txt 2>/dev/null | head -n 1)"

# ------------------------------------------------- 13. verify_logging.sh
printf '\n== verify_logging.sh self-check ==\n'
setup
export JUKAMIX_SCRIPTS="$SCRIPTS"
export JUKAMIX_POST_START="$REPO/System/starts/°post_starts.sh"
export JUKAMIX_SHUTDOWN="$REPO/System/bin/shutdown"
export JUKAMIX_LOAD_LAUNCHER="$SCRIPTS/load_launcher.sh"

# A live pid and a just-written heartbeat, so the self-check's "the watchdog is
# running" and heartbeat-age checks are exercised rather than skipped.
printf '%s\n' "$$" >"$T/tmp/watchlive.pid"
printf '[%s] alive uptime=100s free_mem=1kB load=0.00\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
    >"$LOGDIR/watch_status.txt"
sh "$SCRIPTS/log_capture.sh" boot
JUKAMIX_WATCH_PID="$T/tmp/watchlive.pid" sh "$SCRIPTS/verify_logging.sh" >"$T/verify.out" 2>&1
verify_rc=$?
check_eq "the self-check passes on this checkout" "0" "$verify_rc"
check_grep "it finds the boot hook in the boot sequence" \
    "PASS - the boot sequence records the boot" "$T/verify.out"
check_grep "it finds the watchdog start in the boot sequence" \
    "PASS - the boot sequence starts the watchdog" "$T/verify.out"
check_grep "it finds the shutdown hook" \
    "PASS - the shutdown path marks a clean shutdown" "$T/verify.out"
check_grep "it finds both launcher hooks" \
    "PASS - the launcher records how the app ended" "$T/verify.out"
check_grep "it confirms the running session opened at boot" \
    "PASS - this session was opened at boot" "$T/verify.out"
check_grep "it finds the running watchdog through its pid file" \
    "PASS - the watchdog is running (pid $$)" "$T/verify.out"
check_grep "it measures the heartbeat age" "PASS - the last heartbeat is fresh" "$T/verify.out"
check_grep "it replays the lifecycle and spots a power pull" \
    "PASS - a boot after a power pull is flagged as unclean" "$T/verify.out"
check_grep "it spots a launch that never returned" \
    "PASS - a launch that never returned is reported as a hang" "$T/verify.out"
check_grep "it prints a summary with no failures" "0 failed" "$T/verify.out"
check_absent "its card probe line is removed again" "$LOGDIR/verify_logging.log"
check_eq "it cleans up its sandbox" "0" \
    "$(ls -d "$T"/tmp/verify_logging.* 2>/dev/null | wc -l | tr -d ' ')"

# A hook that nothing calls is exactly what the self-check exists to catch, so a
# stripped-down copy of each system file has to make it fail.
sed '/log_capture.sh boot/d' "$REPO/System/starts/°post_starts.sh" >"$T/post_starts_broken.sh"
JUKAMIX_POST_START="$T/post_starts_broken.sh" sh "$SCRIPTS/verify_logging.sh" >"$T/verify_broken.out" 2>&1
broken_rc=$?
check_eq "a missing boot hook fails the self-check" "1" "$broken_rc"
check_grep "the failure names the boot hook" \
    "FAIL - the boot sequence records the boot" "$T/verify_broken.out"

sed '/log_capture.sh shutdown/d' "$REPO/System/bin/shutdown" >"$T/shutdown_broken.sh"
JUKAMIX_SHUTDOWN="$T/shutdown_broken.sh" sh "$SCRIPTS/verify_logging.sh" >"$T/verify_shutdown.out" 2>&1
broken_rc=$?
check_eq "a missing shutdown hook fails the self-check" "1" "$broken_rc"
check_grep "the failure names the shutdown path" \
    "FAIL - the shutdown path marks a clean shutdown" "$T/verify_shutdown.out"

# ------------------------------------------------------------------- summary
printf '\n%d check(s), %d failed\n' "$CHECKS" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
