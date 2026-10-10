#!/bin/sh
# Off-device checks for inputd_switcher.sh (JukaMix OS).  The script uses
# absolute device paths, so a copy of it is remapped into a temporary tree and
# pgrep/pkill/jq are stubbed.
#
#   sh tests/inputd_switcher_test.sh
#
# Exit status 0 = all checks passed, 1 = at least one failed.

REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO/System/usr/trimui/scripts/inputd_switcher.sh"

T=${TMPDIR:-/tmp}/inputd_switcher_test
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
    if grep -q -F -- "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1 (missing [$2])"; fi
}
check_grep_not() { # label pattern file
    if grep -q -F -- "$2" "$3" 2>/dev/null; then fail "$1 (unexpected [$2])"; else pass "$1"; fi
}
count_lines() { # file-or-dir listing
    printf '%s' "$1" | grep -c . | tr -d ' '
}

# --------------------------------------------------------------------- setup
setup() {
    rm -rf "$T"
    mkdir -p "$T/sdcard/trimui/app" "$T/sdcard/System/resources" \
        "$T/sdcard/System/backups" "$T/sdcard/System/usr/trimui/scripts" \
        "$T/sdcard/System/bin" "$T/sdcard/System/etc" "$T/etc" "$T/proc" "$T/fw"

    # Remap the device paths into the temp tree.  The copy keeps its name, since
    # the polling rate mode reads the rate from crossmix.json only for the
    # script that is called inputd_switcher.
    sed -e "s|/mnt/SDCARD|$T/sdcard|g" \
        -e "s|/etc/trimui_device.txt|$T/etc/trimui_device.txt|g" \
        -e "s|/proc/cpuinfo|$T/proc/cpuinfo|g" \
        -e "s|/usr/trimui/bin/trimui_inputd|$T/fw/trimui_inputd|g" \
        "$SRC" >"$T/sdcard/System/usr/trimui/scripts/inputd_switcher.sh"
    chmod +x "$T/sdcard/System/usr/trimui/scripts/inputd_switcher.sh"

    # Stubs the script picks up through its own PATH.
    printf '#!/bin/sh\ngrep -qx "$1" "$JUKAMIX_TEST_PROC" 2>/dev/null\n' >"$T/sdcard/System/bin/pgrep"
    printf '#!/bin/sh\necho "pkill $*" >>"$JUKAMIX_TEST_PKILL_LOG"\n' >"$T/sdcard/System/bin/pkill"
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in\n'
        printf '*"-r"*) cat "$JUKAMIX_TEST_JQ_ANSWER" ;;\n'
        printf '*) printf \x27{"POLLING RATE": "%%s"}\\n\x27 "$(cat "$JUKAMIX_TEST_JQ_ANSWER")" ;;\n'
        printf 'esac\n'
    } >"$T/sdcard/System/bin/jq"
    chmod +x "$T/sdcard/System/bin/pgrep" "$T/sdcard/System/bin/pkill" "$T/sdcard/System/bin/jq"
    printf '#!/bin/sh\necho "mainui_state_update $*" >>"$JUKAMIX_TEST_CALLS"\n' >"$T/sdcard/System/usr/trimui/scripts/mainui_state_update.sh"
    printf '#!/bin/sh\necho "infoscreen $*" >>"$JUKAMIX_TEST_CALLS"\n' >"$T/sdcard/System/usr/trimui/scripts/infoscreen.sh"
    chmod +x "$T/sdcard/System/usr/trimui/scripts/mainui_state_update.sh" \
        "$T/sdcard/System/usr/trimui/scripts/infoscreen.sh"

    : >"$T/proc_list"
    : >"$T/pkill.log"
    : >"$T/calls.log"
    printf '8ms\n' >"$T/jq.answer"
    printf '{}' >"$T/sdcard/System/etc/crossmix.json"

    export JUKAMIX_TEST_PROC="$T/proc_list"
    export JUKAMIX_TEST_PKILL_LOG="$T/pkill.log"
    export JUKAMIX_TEST_JQ_ANSWER="$T/jq.answer"
    export JUKAMIX_TEST_CALLS="$T/calls.log"

    switcher="$T/sdcard/System/usr/trimui/scripts/inputd_switcher.sh"
    daemon_of_card="$T/sdcard/trimui/app/trimui_inputd"
}

# twodaemon <path> <marker> - a fake daemon: the marker decides identity.
twodaemon() {
    printf 'TRIMUI Input Daemon %s\n' "$2" >"$1"
    chmod +x "$1"
}

marker_of() { # path -> the marker inside a fake daemon
    awk '{print $4}' "$1"
}

# ------------------------------------------- 1. a daemon that matches the device
printf '\n== a card that already holds the daemon for this device ==\n'
setup
printf 'tsp\n' >"$T/etc/trimui_device.txt"
twodaemon "$T/sdcard/System/resources/tsp_inputd" "universal-tsp-tsps"
twodaemon "$daemon_of_card" "universal-tsp-tsps"
sh "$switcher" verify >"$T/out1.txt" 2>&1
check_grep "a matching daemon is reported as OK" "Input daemon OK for tsp" "$T/out1.txt"
check_eq "no backup is made when nothing changes" "0" "$(count_lines "$(ls "$T/sdcard/System/backups" 2>/dev/null)")"
sh "$switcher" verify -q >"$T/out1q.txt" 2>&1
check_eq "quiet mode stays silent when the daemon is fine" "" "$(cat "$T/out1q.txt")"

# ----------------------------------------------- 2. a daemon for another device
printf '\n== a card that carries the daemon of another device ==\n'
setup
printf 'tsps\n' >"$T/etc/trimui_device.txt"
twodaemon "$T/sdcard/System/resources/tsps_inputd" "universal-tsp-tsps"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" verify >"$T/out2.txt" 2>&1
check_grep "the mismatch is reported" "Input daemon mismatch for tsps" "$T/out2.txt"
check_grep "the installed daemon is named" "installing tsps_inputd" "$T/out2.txt"
check_eq "the card now holds the device's daemon" "universal-tsp-tsps" "$(marker_of "$daemon_of_card")"
check_eq "the old daemon is backed up" "1" "$(count_lines "$(ls "$T/sdcard/System/backups")")"

printf '\n== restarting the daemon ==\n'
twodaemon "$daemon_of_card" "old-tg5040-only"
printf 'trimui_inputd\n' >"$T/proc_list" # running, but no MainUI
sh "$switcher" verify >"$T/out3.txt" 2>&1
check_grep "the daemon is restarted" "Input daemon restarted" "$T/out3.txt"
check_grep "the running daemon is stopped first" "pkill trimui_inputd" "$T/pkill.log"
twodaemon "$daemon_of_card" "old-tg5040-only"
: >"$T/pkill.log"
printf 'trimui_inputd\nMainUI\n' >"$T/proc_list"
sh "$switcher" verify >"$T/out4.txt" 2>&1
check_grep "no restart while MainUI runs" "will be used after a reboot" "$T/out4.txt"
check_eq "the running daemon is left alone under MainUI" "" "$(cat "$T/pkill.log")"
sh "$switcher" verify -q >"$T/out5.txt" 2>&1
check_grep_not "quiet mode says nothing about a restart" "reboot" "$T/out5.txt"
sh "$switcher" verify -q >"$T/out5q.txt" 2>&1
check_grep_not "quiet mode says nothing when there is nothing to do" "mismatch" "$T/out5q.txt"

# ------------------------------------------------ 3. device detection fallback
printf '\n== a card without /etc/trimui_device.txt ==\n'
setup
rm -f "$T/etc/trimui_device.txt"
printf 'Hardware : TMS/TG5050 something\n' >"$T/proc/cpuinfo"
twodaemon "$T/sdcard/System/resources/tsps_inputd" "universal-tsp-tsps"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" verify >"$T/out6.txt" 2>&1
check_grep "the SoC is detected as the device" "Input daemon mismatch for tsps" "$T/out6.txt"
check_eq "the daemon for the detected device is installed" "universal-tsp-tsps" "$(marker_of "$daemon_of_card")"

printf '\n== an unknown SoC and no device file ==\n'
setup
rm -f "$T/etc/trimui_device.txt"
printf 'Hardware : something else\n' >"$T/proc/cpuinfo"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" verify >"$T/out7.txt" 2>&1
check_grep "an unknown device keeps the daemon" "Unknown device, keeping the installed input daemon" "$T/out7.txt"
check_eq "nothing is installed for an unknown device" "old-tg5040-only" "$(marker_of "$daemon_of_card")"

# -------------------------------------------------------------- 4. Brick path
printf '\n== the Brick keeps the firmware daemon ==\n'
setup
printf 'brick\n' >"$T/etc/trimui_device.txt"
twodaemon "$T/fw/trimui_inputd" "firmware-brick"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" verify >"$T/out8.txt" 2>&1
check_grep "the Brick mismatch is reported" "Input daemon mismatch for brick" "$T/out8.txt"
check_eq "the firmware daemon is installed on the Brick" "firmware-brick" "$(marker_of "$daemon_of_card")"
twodaemon "$daemon_of_card" "firmware-brick"
sh "$switcher" verify >"$T/out9.txt" 2>&1
check_grep "a matching Brick daemon is OK" "Input daemon OK for brick" "$T/out9.txt"

printf '\n== a Brick without a firmware daemon ==\n'
setup
printf 'brick\n' >"$T/etc/trimui_device.txt"
twodaemon "$daemon_of_card" "something"
sh "$switcher" verify >"$T/out10.txt" 2>&1
check_grep "nothing is installed without a source daemon" "No daemon available for brick" "$T/out10.txt"
check_eq "the installed daemon stays" "something" "$(marker_of "$daemon_of_card")"

# --------------------------------------------------------- 5. polling rate mode
printf '\n== the polling rate mode ==\n'
setup
printf 'tsp\n' >"$T/etc/trimui_device.txt"
twodaemon "$T/sdcard/System/resources/tsp_inputd" "universal-tsp-tsps"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" >"$T/out11.txt" 2>&1
check_eq "the polling rate from crossmix.json is applied" "8000" "$(cat "$T/sdcard/trimui/app/inputd_polling_rate.cfg")"
check_eq "the device's daemon is installed as well" "universal-tsp-tsps" "$(marker_of "$daemon_of_card")"
check_grep "crossmix.json is updated" '"POLLING RATE": "8ms"' "$T/sdcard/System/etc/crossmix.json"
check_grep "the System Tools state is updated" "mainui_state_update POLLING RATE 8ms" "$T/calls.log"
check_grep "MainUI is restarted to pick the rate up" "pkill -KILL MainUI" "$T/pkill.log"

printf '\n== the polling rate mode, sourced from a menu entry ==\n'
# The menu entries 1ms.sh / 8ms.sh / 16ms.sh source the switcher, so the rate
# comes from the name of the script that sourced it.
mkdir -p "$T/menu"
printf '. "%s"\n' "$switcher" >"$T/menu/1ms.sh"
rm -f "$T/sdcard/trimui/app/inputd_polling_rate.cfg"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$T/menu/1ms.sh" >"$T/out12.txt" 2>&1
check_eq "the rate comes from the sourcing script's name" "1000" "$(cat "$T/sdcard/trimui/app/inputd_polling_rate.cfg")"

printf '\n== the polling rate mode, Brick Pro ==\n'
setup
printf 'brickpro\n' >"$T/etc/trimui_device.txt"
twodaemon "$T/sdcard/System/resources/brickpro_inputd" "i2c-brickpro"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" >"$T/out13.txt" 2>&1
check_eq "the Brick Pro gets its I2C daemon" "i2c-brickpro" "$(marker_of "$daemon_of_card")"
check_eq "no polling rate file is written on the Brick Pro" "0" "$(count_lines "$(ls "$T/sdcard/trimui/app" | grep polling_rate)")"
check_grep_not "MainUI is not restarted on the Brick Pro" "MainUI" "$T/pkill.log"

printf '\n== the polling rate mode, Brick ==\n'
setup
printf 'brick\n' >"$T/etc/trimui_device.txt"
twodaemon "$T/fw/trimui_inputd" "firmware-brick"
twodaemon "$daemon_of_card" "old-tg5040-only"
sh "$switcher" >"$T/out14.txt" 2>&1
rc=$?
check_eq "the Brick installs the firmware daemon" "firmware-brick" "$(marker_of "$daemon_of_card")"
check_eq "the Brick polling rate request returns 1" "1" "$rc"
check_eq "no polling rate file on the Brick" "0" "$(count_lines "$(ls "$T/sdcard/trimui/app" | grep polling_rate)")"

printf '\n%s check(s), %s failed\n' "$CHECKS" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
