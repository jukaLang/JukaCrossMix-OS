#!/bin/sh
# Off-device checks for stick_diag.sh (JukaMix OS).  Everything runs against a
# simulated device tree: the tool can be redirected with the JUKAMIX_* variables
# and the guided test is driven by tests/stub_evtest.sh.
#
#   sh tests/stick_diag_test.sh
#
# Exit status 0 = all checks passed, 1 = at least one failed.

REPO=$(cd "$(dirname "$0")/.." && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$REPO/System/usr/trimui/scripts/stick_diag.sh"
SET_RA="$REPO/System/usr/trimui/scripts/set_ra_cfg.sh"
SHIPPED_CFG="$REPO/RetroArch/retroarch.cfg"

T=${TMPDIR:-/tmp}/stick_diag_test
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

# ---------------------------------------------------------------- device tree
setup() { # device cpuinfo sticks [axis-bitmap]
    dev=$1
    cpu=$2
    sticks=$3
    bitmap=$4
    JUKAMIX_STICKS=$sticks
    export JUKAMIX_STICKS

    rm -rf "$T"
    mkdir -p "$T/sdcard/System/usr/trimui/scripts" \
        "$T/sdcard/System/etc" "$T/sdcard/System/backups" \
        "$T/sdcard/Apps/SystemTools/Logs" "$T/sdcard/RetroArch" \
        "$T/udisk" "$T/etc" "$T/proc" "$T/var" "$T/tmp/trimui_inputd" \
        "$T/sys/class/input/event2/device/capabilities"

    printf '%s\n' "$dev" >"$T/etc/trimui_device.txt"
    printf '%s\n' "$cpu" >"$T/proc/cpuinfo"
    printf 'Target platform\n' >"$T/etc/version"
    printf 'Linux version 4.9\n' >"$T/proc/version"

    # The shipped config leaves the stick axes unbound ("nul").
    printf 'input_player1_l_x_plus_axis = "nul"\ninput_player1_l_x_minus_axis = "nul"\n' >"$T/sdcard/RetroArch/retroarch.cfg"
    printf 'input_player1_r_x_plus_axis = "nul"\ninput_player1_r_x_minus_axis = "nul"\n' >>"$T/sdcard/RetroArch/retroarch.cfg"
    printf 'input_joypad_driver = "sdl2"\n' >>"$T/sdcard/RetroArch/retroarch.cfg"

    printf 'TRIMUI Player1\n' >"$T/sys/class/input/event2/device/name"
    [ -n "$bitmap" ] && printf '%s\n' "$bitmap" >"$T/sys/class/input/event2/device/capabilities/abs"

    cp "$SET_RA" "$T/sdcard/System/usr/trimui/scripts/set_ra_cfg.sh"
    chmod +x "$T/sdcard/System/usr/trimui/scripts/set_ra_cfg.sh"
    cp "$HERE/stub_evtest.sh" "$T/sdcard/System/usr/trimui/scripts/evtest"
    chmod +x "$T/sdcard/System/usr/trimui/scripts/evtest"

    STATE="$T/sdcard/System/etc/analog_x_flip.cfg"
    LOG="$T/sdcard/Apps/SystemTools/Logs/Analog Sticks.log"
}

stick() { # args...
    JUKAMIX_SDCARD="$T/sdcard" JUKAMIX_UDISK="$T/udisk" JUKAMIX_SYSFS="$T/sys" \
        JUKAMIX_ETC="$T/etc" JUKAMIX_PROC="$T/proc" JUKAMIX_VAR="$T/var" \
        JUKAMIX_TMP="$T/tmp/trimui_inputd" \
        JUKAMIX_RA_CFG="$T/sdcard/RetroArch/retroarch.cfg" \
        sh "$SCRIPT" "$@"
}

cfgv() { # key
    sed -n "s/^$1 *= *\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$T/sdcard/RetroArch/retroarch.cfg" | tail -n 1
}

statev() { # key
    grep "^$1=" "$STATE" 2>/dev/null | cut -d= -f2-
}

# --------------------------------------------------------------- 1. stock cfg
printf '\n== stock config (the axes are "nul") with a four axis pad ==\n'
setup tsp "TG5040" lr "0000000000030027"
cp "$T/sdcard/RetroArch/retroarch.cfg" "$T/cfg.orig"

stick -q flip on l >"$T/flip1.txt" 2>&1
check_eq "flip on l binds an explicit inverted axis (l_x_plus)" "-0" "$(cfgv input_player1_l_x_plus_axis)"
check_eq "flip on l binds an explicit inverted axis (l_x_minus)" "+0" "$(cfgv input_player1_l_x_minus_axis)"
check_eq "flip on l leaves the right stick alone" "nul" "$(cfgv input_player1_r_x_plus_axis)"
check_eq "the state file records what was written" "-0" "$(statev applied_input_player1_l_x_plus_axis)"
check_eq "the state file records the original for undo" "nul" "$(statev input_player1_l_x_plus_axis)"
check_grep "the log says what changed" "input_player1_l_x_plus_axis : not set, RetroArch maps it as +0 -> -0" "$LOG"

stick -q flip >"$T/flip.txt" 2>&1
check_grep "flip status shows the workaround on" "horizontal-axis workaround: on" "$T/flip.txt"
check_grep "flip status shows the joypad driver" "joypad driver          : sdl2" "$T/flip.txt"

stick -q flip on l >"$T/flip2.txt" 2>&1
check_eq "flip on l twice does not invert twice" "-0" "$(cfgv input_player1_l_x_plus_axis)"
check_grep "flip on l twice says nothing changed" "already in place" "$T/flip2.txt"

stick -q flip on r >"$T/flip3.txt" 2>&1
check_eq "flip on r afterwards binds the right stick" "-2" "$(cfgv input_player1_r_x_plus_axis)"
check_eq "flip on r afterwards binds the right stick (minus)" "+2" "$(cfgv input_player1_r_x_minus_axis)"
check_eq "flip on r keeps the left stick inverted" "-0" "$(cfgv input_player1_l_x_plus_axis)"
check_eq "the recorded sides merge" "lr" "$(statev sides)"
check_eq "the right stick original is recorded too" "nul" "$(statev input_player1_r_x_plus_axis)"

stick -q flip off >/dev/null 2>&1
if cmp -s "$T/cfg.orig" "$T/sdcard/RetroArch/retroarch.cfg"; then
    pass "flip off restores the shipped config byte for byte"
else
    fail "flip off restores the shipped config byte for byte"
    diff "$T/cfg.orig" "$T/sdcard/RetroArch/retroarch.cfg" | head -5
fi
[ -f "$STATE" ] && fail "flip off removes the state file" || pass "flip off removes the state file"

# --------------------------------------------------- 2. heal after an OS update
printf '\n== an OS update / settings restore rewrites retroarch.cfg ==\n'
setup tsps "TG5050" lr "00000000003f0027"
stick -q flip on both >/dev/null 2>&1
cp "$T/sdcard/RetroArch/retroarch.cfg" "$T/cfg.flipped"
: >"$LOG"
printf 'input_player1_l_x_plus_axis = "nul"\ninput_player1_l_x_minus_axis = "nul"\n' >"$T/sdcard/RetroArch/retroarch.cfg"
printf 'input_player1_r_x_plus_axis = "nul"\ninput_player1_r_x_minus_axis = "nul"\n' >>"$T/sdcard/RetroArch/retroarch.cfg"
printf 'input_joypad_driver = "sdl2"\n' >>"$T/sdcard/RetroArch/retroarch.cfg"

stick -q ensure >/dev/null 2>&1
check_eq "ensure heals l_x_plus after the config was reset" "-0" "$(cfgv input_player1_l_x_plus_axis)"
check_eq "ensure heals r_x_minus after the config was reset" "+2" "$(cfgv input_player1_r_x_minus_axis)"
if cmp -s "$T/cfg.flipped" "$T/sdcard/RetroArch/retroarch.cfg"; then
    pass "the healed config matches the workaround state again"
else
    fail "the healed config matches the workaround state again"
    diff "$T/cfg.flipped" "$T/sdcard/RetroArch/retroarch.cfg" | head -5
fi
check_grep "the log says the workaround was restored" "workaround restored" "$LOG"

printf '\n== a binding the user changed by hand is left alone ==\n'
stick -q flip on both >/dev/null 2>&1
sed -i '/^input_player1_l_x_plus_axis = /d' "$T/sdcard/RetroArch/retroarch.cfg"
printf 'input_player1_l_x_plus_axis = "+3"\n' >>"$T/sdcard/RetroArch/retroarch.cfg"
: >"$LOG"
stick -q ensure >/dev/null 2>&1
check_eq "a hand made binding survives the boot heal" "+3" "$(cfgv input_player1_l_x_plus_axis)"
check_grep "the boot heal logs why it left it" "use 'flip reapply' to force" "$LOG"
stick -q flip reapply >"$T/reapply.txt" 2>&1
check_eq "flip reapply forces the recorded binding back" "-0" "$(cfgv input_player1_l_x_plus_axis)"
check_grep "flip reapply says what it did" "bindings restored" "$T/reapply.txt"

printf '\n== status reports drift ==\n'
sed -i '/^input_player1_r_x_plus_axis = /d' "$T/sdcard/RetroArch/retroarch.cfg"
printf 'input_player1_r_x_plus_axis = "nul"\n' >>"$T/sdcard/RetroArch/retroarch.cfg"
stick -q status >"$T/status.txt" 2>&1
rc=$?
check_grep "status flags the dropped workaround" "needs re-apply" "$T/status.txt"
check_eq "status exits 2 when action is needed" "2" "$rc"

# --------------------------------------------------------------- 3. one stick
printf '\n== a device with a single stick ==\n'
setup tsp "TG5040" r "0000000000030027"
printf 'x_min 600\nx_max 800\nx_zero 700\ny_min 600\ny_max 800\ny_zero 700\ndeadzone 20\n' >"$T/udisk/joypad_right.config"
printf 'x_min 600\nx_max 3500\nx_zero 2048\n' >"$T/udisk/joypad.config" # broken, but not this device's stick
stick -q status >"$T/status1.txt" 2>&1
rc=$?
check_eq "single stick status is OK" "OK (right: OK)" "$(cat "$T/status1.txt")"
check_eq "single stick status exits 0" "0" "$rc"
stick -q flip on l >"$T/single.txt" 2>&1
check_eq "flip on l is refused when the device has no left stick" "nul" "$(cfgv input_player1_l_x_plus_axis)"
check_grep "the refusal names the missing stick" "no LEFT stick" "$T/single.txt"
stick -q flip on r >/dev/null 2>&1
check_eq "flip on r works on a right-only device" "-2" "$(cfgv input_player1_r_x_plus_axis)"
stick -q flip off >/dev/null 2>&1

printf 'x_min 3500\nx_max 600\nx_zero 2000\n' >"$T/udisk/joypad_right.config"
stick -q status >"$T/status2.txt" 2>&1
rc=$?
check_grep "single stick status flags a broken calibration" "ACTION (right: BROKEN)" "$T/status2.txt"
check_eq "broken calibration makes status exit 2" "2" "$rc"
stick -q report >"$T/report1.txt" 2>&1
check_grep "report only lists this device's calibration file" "joypad_right.config" "$T/report1.txt"
grep -q "joypad.config" "$T/report1.txt" && fail "report must not list the other stick's calibration" || pass "report must not list the other stick's calibration"

# --------------------------------------------------------- 4. Axis numbering
printf '\n== the pad decides which code the stick reports ==\n'
setup tsp "TG5040" lr "000000000000003f"
printf '0 -30000\n0 30000\n1 -30000\n1 30000\n' >"$T/answers"
printf '4 30000\n4 -30000\n5 -30000\n5 30000\n16 -1\n16 1\n' >>"$T/answers"
export JUKAMIX_EVTEST_ANSWERS="$T/answers"
stick -q -y test 1 >"$T/test1.txt" 2>&1
check_grep "the test names the mirrored stick" "mirrored horizontal axis on: r" "$T/test1.txt"
check_eq "the measured code drives the binding (r_x_plus)" "-4" "$(cfgv input_player1_r_x_plus_axis)"
check_eq "the measured code drives the binding (r_x_minus)" "+4" "$(cfgv input_player1_r_x_minus_axis)"
check_eq "the correct left stick keeps its binding" "nul" "$(cfgv input_player1_l_x_plus_axis)"
check_grep "the log explains where the index came from" "index of the code the test measured: 4" "$LOG"
check_eq "the workaround records the measured stick" "r" "$(statev sides)"

printf '\n== without a measurement the standard layout is used ==\n'
setup tsp "TG5040" lr "000000000000003f"
stick -q flip on r >/dev/null 2>&1
check_eq "blind flip on r uses axis 2" "-2" "$(cfgv input_player1_r_x_plus_axis)"
stick -q report >"$T/report2.txt" 2>&1
check_grep "report shows the evdev codes the pad publishes" "0 1 2 3 4 5" "$T/report2.txt"
check_grep "report warns that the numbering is an assumption" "that is an" "$T/report2.txt"

setup tsp "TG5040" lr "0000000000030027"
stick -q report >"$T/report3.txt" 2>&1
check_grep "a four axis pad is reported as the usual layout" "(the usual four axis TrimUI pad)" "$T/report3.txt"
grep -q "that is an" "$T/report3.txt" && fail "a four axis pad must not warn about the numbering" || pass "a four axis pad must not warn about the numbering"

setup tsp "TG5040" lr ""
stick -q report >"$T/report4.txt" 2>&1
check_grep "an unreadable bitmap is reported" "unreadable" "$T/report4.txt"

printf '\n== a mirrored left stick ==\n'
setup tsp "TG5040" lr "000000000000003f"
printf '0 30000\n0 -30000\n1 -30000\n1 30000\n' >"$T/answers"
printf '4 -30000\n4 30000\n5 -30000\n5 30000\n16 -1\n16 1\n' >>"$T/answers"
stick -q -y test 1 >"$T/test2.txt" 2>&1
check_grep "the left stick is named as mirrored" "mirrored horizontal axis on: l" "$T/test2.txt"
check_eq "the left stick binds axis 0" "-0" "$(cfgv input_player1_l_x_plus_axis)"
check_eq "the correct right stick is left alone" "nul" "$(cfgv input_player1_r_x_plus_axis)"

printf '\n== a stick whose half axis is dead is not offered a flip ==\n'
setup tsp "TG5040" lr "000000000000003f"
printf '0 -30000\n0\n1 -30000\n1 30000\n' >"$T/answers"
printf '4 -30000\n4 30000\n5 -30000\n5 30000\n16 -1\n16 1\n' >>"$T/answers"
stick -q -y test 1 >"$T/test3.txt" 2>&1
check_grep "an unreadable half is reported as inconclusive" "did not report both horizontal directions" "$T/test3.txt"
check_eq "no binding is written for a dead half axis" "nul" "$(cfgv input_player1_l_x_plus_axis)"
grep -q -i "mirrored horizontal axis" "$T/test3.txt" && fail "a dead half must not be called mirrored" || pass "a dead half must not be called mirrored"

# ------------------------------------------------------------- 5. Brick path
printf '\n== the Brick has no sticks ==\n'
setup brick "TG3040" "" ""
stick -q status >"$T/status3.txt" 2>&1
rc=$?
check_grep "brick status is N/A" "N/A (no analog sticks on brick)" "$T/status3.txt"
check_eq "brick status exits 0" "0" "$rc"
stick -q sides >"$T/sides.txt" 2>&1
check_eq "brick reports no sticks" "" "$(cat "$T/sides.txt")"
stick -q flip on l >"$T/brickflip.txt" 2>&1
check_eq "flip is refused on the Brick" "nul" "$(cfgv input_player1_l_x_plus_axis)"
check_eq "no state file is written on the Brick" "" "$(statev sides)"
check_grep "the refusal is explained" "no analog sticks" "$T/brickflip.txt"
stick -q report >"$T/report5.txt" 2>&1
check_grep "the brick report explains there is nothing to check" "no analog sticks" "$T/report5.txt"

printf '\n== boot checks run for every device, sticks or not ==\n'
setup brick "TG3040" "" ""
# A stub switcher records how the boot check asks for the daemon to be verified.
{
    printf '#!/bin/sh\n'
    printf 'echo "switcher $*" >>"%s"\n' "$T/switcher.calls"
    printf 'exit 0\n'
} >"$T/sdcard/System/usr/trimui/scripts/inputd_switcher.sh"
chmod +x "$T/sdcard/System/usr/trimui/scripts/inputd_switcher.sh"
stick -q ensure >"$T/ensure_brick.txt" 2>&1
check_eq "the boot check still runs on the Brick" "switcher verify -q" "$(cat "$T/switcher.calls" 2>/dev/null)"
check_eq "the boot check stays silent" "" "$(cat "$T/ensure_brick.txt")"

printf '\n== a device with no calibration file ==\n'
setup tsp "TG5040" lr "0000000000030027"
stick -q status >"$T/status5.txt" 2>&1
rc=$?
check_eq "an uncalibrated stick is not an action item" "OK (left: not calibrated, right: not calibrated)" "$(cat "$T/status5.txt")"
check_eq "an uncalibrated device exits 0" "0" "$rc"

printf '\n== a device this build does not know yet ==\n'
# No JUKAMIX_STICKS: the stick set has to come from the pad itself.  'smart' is
# deliberately not in the table of the tool.
setup smart "TG3030" "" "0000000000000003" # ABS_X + ABS_Y
check_eq "a two axis pad is seen as a left stick only" "l" "$(stick -q sides)"
printf 'x_min 560\nx_max 3600\nx_zero 2048\ny_min 560\ny_max 3600\ny_zero 2048\n' >"$T/udisk/joypad.config"
stick -q status >"$T/status4.txt" 2>&1
check_eq "status covers only the left stick there" "OK (left: OK)" "$(cat "$T/status4.txt")"

setup smart "TG3030" "" "000000000000003f" # four stick axes
check_eq "a four axis pad is seen as two sticks" "lr" "$(stick -q sides)"

setup smart "TG3030" "" "0000000000000000" # capabilities unreadable
check_eq "an unreadable pad is assumed to have both sticks" "lr" "$(stick -q sides)"
rm -rf "$T/sys/class/input/event2"
check_eq "a missing pad is assumed to have both sticks" "lr" "$(stick -q sides)"

printf '\n== the shipped retroarch.cfg itself ==\n'
if [ -f "$SHIPPED_CFG" ]; then
    check_grep "the shipped retroarch.cfg leaves the axes unbound" 'input_player1_l_x_plus_axis = "nul"' "$SHIPPED_CFG"

    # Round trip on the real file (about 1600 lines, the axes "nul").  The SD
    # card gets the repository's LF version; a Windows checkout has CRLF and its
    # sed rewrites files in text mode, so normalise before comparing.
    setup tsp "TG5040" lr "0000000000030027"
    tr -d '\r' <"$SHIPPED_CFG" >"$T/sdcard/RetroArch/retroarch.cfg"
    cp "$T/sdcard/RetroArch/retroarch.cfg" "$T/cfg.real"
    stick -q flip on both >/dev/null 2>&1
    check_eq "the real config gets an explicit left binding" "-0" "$(cfgv input_player1_l_x_plus_axis)"
    check_eq "the real config gets an explicit right binding" "-2" "$(cfgv input_player1_r_x_plus_axis)"
    check_eq "the rest of the real config is untouched" "sdl2" "$(cfgv input_joypad_driver)"
    stick -q flip off >/dev/null 2>&1
    check_eq "the left binding is back to unbound" "nul" "$(cfgv input_player1_l_x_plus_axis)"
    check_eq "the left binding is back to unbound (minus)" "nul" "$(cfgv input_player1_l_x_minus_axis)"
    check_eq "the right binding is back to unbound" "nul" "$(cfgv input_player1_r_x_plus_axis)"
    check_eq "the right binding is back to unbound (minus)" "nul" "$(cfgv input_player1_r_x_minus_axis)"
    if cmp -s "$T/cfg.real" "$T/sdcard/RetroArch/retroarch.cfg"; then
        pass "the real config is restored byte for byte"
    elif [ "$(tr -d '\r' <"$T/cfg.real" | md5sum)" = "$(tr -d '\r' <"$T/sdcard/RetroArch/retroarch.cfg" | md5sum)" ]; then
        # This host's sed rewrites the file in text mode and drops the CRs of a
        # CRLF config; busybox sed on the device preserves them.
        printf 'note - only the line endings differ after the round trip (host sed, not busybox sed)\n'
        pass "the real config keeps every other byte"
    else
        fail "the real config is restored"
        diff "$T/cfg.real" "$T/sdcard/RetroArch/retroarch.cfg" | head -6
    fi
else
    fail "the shipped retroarch.cfg was not found"
fi

printf '\n%s check(s), %s failed\n' "$CHECKS" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
