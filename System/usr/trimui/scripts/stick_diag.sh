#!/bin/sh
# Analog stick diagnostics and repair for TrimUI handhelds (JukaMix OS).
#
# How the sticks actually work on TrimUI hardware
# -----------------------------------------------
# The pad MCUs talk to trimui_inputd over a UART; the daemon applies the
# calibration stored in /mnt/UDISK/joypad.config (left) and joypad_right.config
# (right) and then publishes uinput devices named "TRIMUI Player1..4".  Every
# emulator, MainUI and the firmware's own calibration screen read those devices.
#
# Facts taken from the shipped daemon binary (System/resources/*_inputd):
#   * the daemon is *universal*: it picks TG5040 (Smart Pro) or TG5050
#     (Smart Pro S) behaviour by scanning /proc/cpuinfo, and falls back to
#     TG5040 when the CPU line is missing.  The pad UARTs, pad GPIOs and the
#     pad direction tables differ between the two SoCs.
#   * the OLD build ("Optimized with inotify", the copy in trimui/app/) has no
#     device detection at all and keeps its state in /tmp/trimui_inputd/.
#     Running it on a Smart Pro S breaks the pad completely.
#   * calibration keys: x_min x_max y_min y_max x_zero y_zero z_min z_max
#     deadzone.  The daemon reloads them when /var/trimui_inputd/cal_update is
#     touched.  Direction comes from sign(raw - zero) with per side scales of
#     32640/(zero - min) and 32640/(max - zero) - so a calibration whose
#     min/max no longer bracket zero does NOT mirror an axis, it kills one
#     half of it.  Mirrored input therefore always comes from the pad frame
#     itself, never from the calibration file.
#   * the left stick is published twice: as an analog axis (ABS_X / ABS_Y) and
#     as a d-pad (ABS_HAT0X / ABS_HAT0Y).  Games normally read the analog
#     axis while the firmware's calibration screen only proves the range, so
#     "correct in the calibration app, mirrored in games" points at the axis.
#   * /var/trimui_inputd/ holds the runtime toggles the OS can set:
#     grab, ra_hotkey, rotate_270, swap_ab, sticks_disabled, cal_update.
#
# Usage:
#   stick_diag.sh report            human readable report (default) + log file
#   stick_diag.sh status            one line, for scripts/menus
#   stick_diag.sh sides             which sticks exist here (l, r, lr or empty)
#   stick_diag.sh test [SECONDS]    guided direction test: every stick this
#                                   device has (the Brick has none) + the d-pad
#   stick_diag.sh flip              mirror-workaround state
#   stick_diag.sh flip on [SIDE]    invert a horizontal axis, SIDE is l, r, both
#                                   or lr (default: l = left stick)
#   stick_diag.sh flip reapply      write the recorded workaround back (after an
#                                   update or a settings restore rewrote the cfg)
#   stick_diag.sh flip off          undo the workaround
#   stick_diag.sh reset             back up and remove the calibration files
#   stick_diag.sh ensure            boot time repair (+ daemon sanity check)
#   stick_diag.sh verify            check/reinstall the input daemon, then report
#
# The mirror workaround rewrites RetroArch's controller bindings, which covers
# every emulator running through RetroArch.  Standalone emulators (PPSSPP,
# flycast, Yaba Sanshiro, ...) keep their own mapping tables.
#
# The shipped retroarch.cfg leaves every stick axis at "nul" because RetroArch
# maps the pad on its own, so the workaround writes an explicit binding built
# from the pad's own axis numbering.  Inverting the file value - what an earlier
# version did - would write "nul" back and silently change nothing.
#
# Options: -q quiet (no infoscreen), -y assume yes, -h help.
#
# Unknown devices are handled by asking the pad the daemon published how many
# stick axes it has (see sticks_of), so a new TrimUI model is not mis-detected as
# a two-stick device just because it is not in a table yet.
#
# Testability: SDCARD/UDISK/SYSFS/ETC/PROC/RA config roots can be overridden
# with the JUKAMIX_SDCARD / JUKAMIX_UDISK / JUKAMIX_SYSFS / JUKAMIX_ETC /
# JUKAMIX_PROC / JUKAMIX_RA_CFG environment variables, and JUKAMIX_STICKS can
# pretend the device has a different stick set (l, r or lr).

SDCARD=${JUKAMIX_SDCARD:-/mnt/SDCARD}
UDISK=${JUKAMIX_UDISK:-/mnt/UDISK}
SYSFS=${JUKAMIX_SYSFS:-/sys}
ETC=${JUKAMIX_ETC:-/etc}
PROC=${JUKAMIX_PROC:-/proc}
VAR=${JUKAMIX_VAR:-/var/trimui_inputd}

SCRIPTS_DIR="$SDCARD/System/usr/trimui/scripts"
LOG_DIR="$SDCARD/Apps/SystemTools/Logs"
LOG_FILE="$LOG_DIR/Analog Sticks.log"
LEFT_CAL="$UDISK/joypad.config"
RIGHT_CAL="$UDISK/joypad_right.config"

RA_CFG=${JUKAMIX_RA_CFG:-$SDCARD/RetroArch/retroarch.cfg}
FLIP_STATE="$SDCARD/System/etc/analog_x_flip.cfg"
BACKUP_DIR="$SDCARD/System/backups/joystick"

# RetroArch keys for the analog sticks.  The second value is RetroArch's
# built-in default, used when the key is absent from retroarch.cfg.
RA_KEYS="input_player1_l_x_plus_axis input_player1_l_x_minus_axis input_player1_r_x_plus_axis input_player1_r_x_minus_axis"

# RetroArch numbers a pad's analog axes by position, not by evdev code (with its
# SDL2 joypad driver: ABS_X, ABS_Y, then the remaining axes in code order).
# Every TrimUI pad puts the left stick on ABS_X/ABS_Y, so the workaround binds
# axes 0/1 and 2/3 unless the direction test measured a different code.

QUIET=0
ASSUME_YES=0
WRITTEN=0

# Set by the guided direction test: the evdev code the stick under test really
# reports, and which stick that was.  Used for the binding index.
MEASURED_CODE=""
MEASURED_SIDE=""

# --------------------------------------------------------------------------
# tiny helpers
# --------------------------------------------------------------------------
say() { printf '%s\n' "$*"; }
logline() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf '%s\n' "$*" >>"$LOG_FILE" 2>/dev/null
    [ "$QUIET" -eq 1 ] || say "$*"
}
info_screen() {
    [ "$QUIET" -eq 1 ] && return 0
    [ -x "$SCRIPTS_DIR/infoscreen.sh" ] && "$SCRIPTS_DIR/infoscreen.sh" "$@"
    return 0
}

device_code() {
    if [ -r "$ETC/trimui_device.txt" ]; then
        read -r dev <"$ETC/trimui_device.txt" 2>/dev/null
    fi
    if [ -z "$dev" ]; then
        cpu=$(cat "$PROC/cpuinfo" 2>/dev/null)
        case "$cpu" in
        *TG5050*) dev="tsps" ;;
        *TG5040*) dev="tsp" ;;
        *TG3040*) dev="brick" ;;
        *TG4040*) dev="brickpro" ;;
        *) dev="unknown" ;;
        esac
    fi
    printf '%s' "$dev"
}

soc_of_device() {
    case "$1" in
    tsp) printf 'TG5040' ;;
    tsps) printf 'TG5050' ;;
    brick) printf 'TG3040' ;;
    brickpro) printf 'TG4040' ;;
    *) printf 'unknown' ;;
    esac
}

device_name() {
    case "$1" in
    tsp) printf 'TrimUI Smart Pro' ;;
    tsps) printf 'TrimUI Smart Pro S' ;;
    brick) printf 'TrimUI Brick' ;;
    brickpro) printf 'TrimUI Brick Pro' ;;
    *) printf 'unknown device' ;;
    esac
}

# What the daemon's own device detection reads out of /proc/cpuinfo.  Only the
# universal Smart Pro build acts on TG5040/TG5050; the other builds are compiled
# for their SoC, so the sentence says what is in the file, not what runs.
soc_from_cpuinfo() {
    cpu=$(cat "$PROC/cpuinfo" 2>/dev/null)
    case "$cpu" in
    *TG5050*) printf 'TG5050' ;;
    *TG5040*) printf 'TG5040' ;;
    *TG3040*) printf 'TG3040' ;;
    *TG4040*) printf 'TG4040' ;;
    *) printf 'not readable (the universal daemon would fall back to TG5040)' ;;
    esac
}

# Analog sticks per device.  The Smart Pro, the Smart Pro S and the Brick Pro
# have dual analog sticks; the Brick has none (README > Supported devices).
# Any other device (a model this build does not know yet) is not guessed: the
# pad the daemon publishes is asked how many stick axes it has, so a new TrimUI
# model gets the right menu without changing this file.
# sticks_of -> "l", "r", "lr" or ""
sticks_of() {
    # JUKAMIX_STICKS lets the test harness pretend this is a one-stick device.
    if [ -n "$JUKAMIX_STICKS" ]; then
        printf '%s' "$JUKAMIX_STICKS"
        return 0
    fi
    case "$1" in
    brick) printf '' ;;
    tsp | tsps | brickpro) printf 'lr' ;;
    *)
        dir=$(input_sysfs_dir 2>/dev/null)
        if [ -z "$dir" ]; then
            printf 'lr' # no pad published (daemon not running): assume the full set
            return 0
        fi
        # Only a pad that clearly publishes one stick pair is taken as such;
        # anything unreadable is assumed to be the full set, because offering a
        # test for a stick that is not there is harmless while hiding one is not.
        case "$(pad_axis_count "$dir")" in
        2) printf 'l' ;;
        *) printf 'lr' ;;
        esac
        ;;
    esac
}

has_sticks() {
    [ -n "$(sticks_of "$1")" ]
}

has_stick() { # device side
    case "$(sticks_of "$1")" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
    esac
}

sticks_desc() {
    case "$(sticks_of "$1")" in
    lr) printf 'dual analog (left + right)' ;;
    l) printf 'one analog stick (left)' ;;
    r) printf 'one analog stick (right)' ;;
    *) printf 'none' ;;
    esac
}

side_name() {
    case "$1" in
    l) printf 'LEFT' ;;
    r) printf 'RIGHT' ;;
    esac
}

# What the installed daemon actually talks to, read out of the binary: the
# Smart Pro / Smart Pro S builds drive the pad UARTs, the Brick Pro build polls
# the pad over I2C and has no UART strings at all.
daemon_transport() { # daemon path
    b=$1
    [ -f "$b" ] || return 1
    uarts=$(tr -c '[:print:]' '\n' <"$b" 2>/dev/null | grep '^/dev/tty' | sort -u | tr '\n' ' ')
    if [ -n "$uarts" ]; then
        printf 'pad UARTs in this build: %s' "$uarts"
    elif tr -c '[:print:]' '\n' <"$b" 2>/dev/null | grep -q 'joy_i2c_poll'; then
        printf 'pad over I2C (this build has no UART and no device detection)'
    else
        printf 'unknown'
    fi
}

# Directories the daemon watches for its runtime triggers.  The current builds
# use /var/trimui_inputd, the older stock build and the Brick Pro build keep
# cal_update in /tmp/trimui_inputd - write to whichever the binary mentions.
# LOGICAL_* are the on-device paths; VAR/TMPD can be overridden for testing.
LOGICAL_VAR=/var/trimui_inputd
LOGICAL_TMP=/tmp/trimui_inputd
VAR=${JUKAMIX_VAR:-$LOGICAL_VAR}
TMPD=${JUKAMIX_TMP:-$LOGICAL_TMP}

cal_trigger_dirs() { # daemon path -> trigger directories that apply
    b=$1
    [ -f "$b" ] || return 0
    bin_strings=$(tr -c '[:print:]' '\n' <"$b" 2>/dev/null)
    printf '%s\n' "$bin_strings" | grep -q "^$LOGICAL_VAR/cal_update" && printf '%s\n' "$VAR"
    printf '%s\n' "$bin_strings" | grep -q "^$LOGICAL_TMP/cal_update" && printf '%s\n' "$TMPD"
    return 0
}

file_hash() {
    if command -v crc32 >/dev/null 2>&1; then
        crc32 "$1" 2>/dev/null | awk '{print $1}'
    elif command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" 2>/dev/null | awk '{print $1}'
    else
        cksum "$1" 2>/dev/null | awk '{print $1"-"$2}'
    fi
}

# Same parsing the daemon uses: last integer of the last matching line.
cfg_get() {
    [ -f "$1" ] || return 1
    line=$(grep -i -- "$2" "$1" 2>/dev/null | grep -v '^[[:space:]]*#' | tail -n 1)
    [ -n "$line" ] || return 1
    value=$(printf '%s\n' "$line" | grep -o -E -- '-?[0-9]+' | tail -n 1)
    [ -n "$value" ] || return 1
    printf '%s' "$value"
}

cfg_line() {
    [ -f "$1" ] || return 1
    grep -i -- "$2" "$1" 2>/dev/null | grep -v '^[[:space:]]*#' | tail -n 1 | tr -d '\r'
}

# The daemon derives the direction from sign(raw - zero) and only scales each
# side when zero is bracketed by min/max: zero must sit strictly inside
# [min, max] or that half of the axis is dead.
axis_verdict() { # min max zero
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        printf 'INCOMPLETE'
    elif [ "$1" -ge "$2" ]; then
        printf 'BROKEN (min >= max, half axis dead)'
    elif [ "$3" -le "$1" ] || [ "$3" -ge "$2" ]; then
        printf 'BROKEN (zero outside min..max, half axis dead)'
    else
        printf 'OK'
    fi
}

# Each axis is judged on its own, so a file with a broken X still counts as
# BROKEN even when the Y keys were never written (the daemon fills those in).
cal_status() { # file -> OK | MISSING | BROKEN | INCOMPLETE
    f=$1
    [ -f "$f" ] || {
        printf 'MISSING'
        return
    }
    verdicts=""
    for axis in x y; do
        amin=$(cfg_get "$f" "${axis}_min")
        amax=$(cfg_get "$f" "${axis}_max")
        azero=$(cfg_get "$f" "${axis}_zero")
        if [ -z "$amin" ] || [ -z "$amax" ] || [ -z "$azero" ]; then
            verdicts="$verdicts INCOMPLETE"
        else
            verdicts="$verdicts $(axis_verdict "$amin" "$amax" "$azero")"
        fi
    done
    case "$verdicts" in
    *BROKEN*) printf 'BROKEN' ;;
    *INCOMPLETE*) printf 'INCOMPLETE' ;;
    *) printf 'OK' ;;
    esac
}

# Calibration files that matter for this device's sticks: the daemon reads
# joypad.config for the left pad and joypad_right.config for the right one.
cal_files_for() { # device
    case "$(sticks_of "$1")" in
    lr) printf '%s\n%s\n' "$LEFT_CAL" "$RIGHT_CAL" ;;
    l) printf '%s\n' "$LEFT_CAL" ;;
    r) printf '%s\n' "$RIGHT_CAL" ;;
    *) : ;;
    esac
}

# --------------------------------------------------------------------------
# input daemon
# --------------------------------------------------------------------------
daemon_paths() {
    printf '%s\n' "$SDCARD/trimui/app/trimui_inputd" "/usr/trimui/bin/trimui_inputd"
}

daemon_build() {
    p=$1
    [ -f "$p" ] || return 1
    if grep -q -a "UNIVERSAL OPTIMIZED" "$p" 2>/dev/null; then
        printf 'JukaMix universal optimized'
    elif grep -q -a "joy_i2c_poll" "$p" 2>/dev/null; then
        printf 'JukaMix Brick Pro build (I2C pad)'
    elif grep -q -a "Optimized with inotify" "$p" 2>/dev/null; then
        printf 'old CrossMix build (single SoC)'
    elif grep -q -a "TRIMUI Input Daemon" "$p" 2>/dev/null; then
        printf 'TrimUI stock'
    else
        printf 'unrecognised'
    fi
}

# Which SoCs a build can serve: only the universal build detects the device at
# runtime, every other build is compiled for one SoC.
daemon_device_support() {
    p=$1
    [ -f "$p" ] || return 1
    bin=$(tr -c '[:print:]' '\n' <"$p" 2>/dev/null)
    if printf '%s\n' "$bin" | grep -q 'joy_i2c_poll'; then
        printf 'TG4040 Brick Pro only (I2C pad)'
    elif printf '%s\n' "$bin" | grep -q '^TG5040' && printf '%s\n' "$bin" | grep -q '^TG5050'; then
        printf 'TG5040 + TG5050 (runtime detection)'
    elif printf '%s\n' "$bin" | grep -q '^TG5050'; then
        printf 'TG5050 only'
    elif printf '%s\n' "$bin" | grep -q '^/dev/ttyAS'; then
        printf 'single SoC, TG5050 family (ttyAS pads), no detection'
    elif printf '%s\n' "$bin" | grep -q '^/dev/ttyS3'; then
        printf 'single SoC, TG5040 family (ttyS pads), no detection'
    elif printf '%s\n' "$bin" | grep -q '^/dev/tty'; then
        printf 'single SoC with pad UARTs, no detection strings'
    else
        printf 'single SoC, no detection and no UART strings'
    fi
}

# Does this build pick the SoC at runtime (the universal one) or is it compiled
# for a single device?  Same strings daemon_device_support() prints.
daemon_detects_runtime() { # daemon path
    bin=$(tr -c '[:print:]' '\n' <"$1" 2>/dev/null)
    printf '%s\n' "$bin" | grep -q '^TG5040' && printf '%s\n' "$bin" | grep -q '^TG5050'
}

installed_inputd() {
    for p in $(daemon_paths); do
        if [ -f "$p" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

# Path of the daemon process that is actually feeding the pad right now.
running_daemon() {
    command -v pgrep >/dev/null 2>&1 || return 1
    for pid in $(pgrep trimui_inputd 2>/dev/null); do
        exe=$(readlink "$PROC/$pid/exe" 2>/dev/null)
        [ -n "$exe" ] || exe=$(tr '\0' ' ' <"$PROC/$pid/cmdline" 2>/dev/null)
        case "$exe" in
        *trimui/app/*) printf 'pid %s = card copy (%s)' "$pid" "$exe" ;;
        */usr/trimui/bin/*) printf 'pid %s = FIRMWARE copy (%s)' "$pid" "$exe" ;;
        *) printf 'pid %s = %s' "$pid" "$exe" ;;
        esac
        return 0
    done
    return 1
}

inputd_report() {
    dev=$1
    expected="$SDCARD/System/resources/${dev}_inputd"
    say "-- Input daemon (reads the pads, feeds every emulator) --"
    for p in $(daemon_paths); do
        [ -f "$p" ] || continue
        say "$p"
        say "    build    : $(daemon_build "$p")"
        say "    hash     : $(file_hash "$p")"
        say "    device   : $(daemon_device_support "$p")"
        say "    pad      : $(daemon_transport "$p")"
        trg=$(cal_trigger_dirs "$p" | tr '\n' ' ')
        say "    triggers : ${trg:-none in this build - reboot after recalibrating}"
        # Quote free pattern: a quoted glob would be literal and a pattern with
        # a space is a syntax error, so ask the build directly.
        if daemon_detects_runtime "$p"; then
            case "$dev" in
            tsps) say "               this SoC uses the /dev/ttyAS5 + /dev/ttyAS7 pad pair" ;;
            tsp) say "               this SoC uses the /dev/ttyS4 + /dev/ttyS3 pad pair" ;;
            esac
        fi
    done

    # Which copy is actually running decides everything: the card copy is the
    # one JukaMix installs and can repair, the firmware copy is the fallback.
    running=$(running_daemon)
    if [ -n "$running" ]; then
        say "running  : $running"
    else
        say "running  : none (pgrep trimui_inputd found nothing)"
    fi

    if [ -f "$expected" ]; then
        ins=$(installed_inputd)
        if [ -z "$ins" ]; then
            say "expected for $dev : $expected (not installed - run 'inputd_switcher.sh verify')"
        elif [ "$(file_hash "$ins")" = "$(file_hash "$expected")" ]; then
            say "expected for $dev : matches the installed daemon"
        else
            say "expected for $dev : $(basename "$expected") - MISMATCH, run 'inputd_switcher.sh verify'"
        fi
    else
        case "$dev" in
        brick) say "expected for $dev : the firmware's own daemon (no sticks on Brick)" ;;
        *) say "expected for $dev : none shipped, the installed one is kept" ;;
        esac
    fi
    for d in "$VAR" "$TMPD"; do
        [ -d "$d" ] || continue
        say "runtime toggles in $d:"
        ls "$d" 2>/dev/null | sed 's/^/    /'
    done
    [ -d "$VAR" ] || [ -d "$TMPD" ] || say "no runtime toggle directory yet"
    say ""
}

# --------------------------------------------------------------------------
# mirror workaround (RetroArch)
# --------------------------------------------------------------------------
# Games read the analog axis; when the pad frame reports the horizontal
# direction the other way round, everything behind RetroArch shows a mirrored
# stick.  RetroArch lets us invert that per axis without touching the daemon.
flip_state() {
    [ -f "$FLIP_STATE" ] || {
        printf 'off'
        return 0
    }
    read -r s <"$FLIP_STATE" 2>/dev/null
    printf '%s' "${s:-off}"
}

ra_axis_get() { # key
    [ -f "$RA_CFG" ] || return 1
    line=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$RA_CFG" 2>/dev/null | tail -n 1)
    [ -n "$line" ] || return 1
    printf '%s' "$line" | sed 's/^[^=]*=[[:space:]]*//; s/^"//; s/"[[:space:]]*$//' | tr -d '\r'
}

ra_axis_set() { # key value
    if [ -f "$RA_CFG" ]; then
        "$SCRIPTS_DIR/set_ra_cfg.sh" "$RA_CFG" "$1" "$2" >/dev/null 2>&1
    else
        mkdir -p "$(dirname "$RA_CFG")" 2>/dev/null
        printf '%s = "%s"\n' "$1" "$2" >>"$RA_CFG"
    fi
}

ra_axis_remove() { # key
    [ -f "$RA_CFG" ] || return 0
    sed -i "/^[[:space:]]*$1[[:space:]]*=/d" "$RA_CFG" 2>/dev/null
}

flip_keys() { # l | r | both
    case "$1" in
    l) printf '%s\n' input_player1_l_x_plus_axis input_player1_l_x_minus_axis ;;
    r) printf '%s\n' input_player1_r_x_plus_axis input_player1_r_x_minus_axis ;;
    *) for k in $RA_KEYS; do printf '%s\n' "$k"; done ;;
    esac
}

key_side() { # key -> l | r
    case "$1" in
    *input_player1_l_*) printf 'l' ;;
    *) printf 'r' ;;
    esac
}

axis_key_parts() { # key -> "<stick> <direction>"
    case "$1" in
    input_player1_l_x_plus_axis) printf 'l plus' ;;
    input_player1_l_x_minus_axis) printf 'l minus' ;;
    input_player1_r_x_plus_axis) printf 'r plus' ;;
    input_player1_r_x_minus_axis) printf 'r minus' ;;
    *) return 1 ;;
    esac
}

# Every analog axis the published pad advertises, as evdev codes, in the order
# its driver enumerates them.  abs_codes() turns the kernel's hex bitmap (64 bit
# words, lowest word first) into a sorted list - busybox awk is all we can count
# on here, so the bits are extracted by hand.
abs_codes() { # hex bitmap words on stdin
    awk '
        BEGIN { for (i = 0; i < 16; i++) hex[substr("0123456789abcdef", i + 1, 1)] = i }
        {
            for (w = 1; w <= NF; w++) {
                h = tolower($w)
                n = length(h)
                for (i = 1; i <= n; i++) {
                    d = hex[substr(h, i, 1)]
                    if (d == "") continue
                    base = (n - i) * 4
                    # digit value 1<<b sits at bit base+b
                    for (b = 0; b < 4; b++)
                        if (int(d / (2 ^ b)) % 2) print (w - 1) * 64 + base + b
                }
            }
        }' | sort -n | tr '\n' ' ' | sed 's/ *$//'
}

# The sysfs directory of the TRIMUI Player1 device.  That is where the axis
# capabilities live (/dev/input/eventN itself has no subdirectories).
input_sysfs_dir() {
    for e in "$SYSFS"/class/input/event*; do
        [ -f "$e/device/name" ] || continue
        [ "$(cat "$e/device/name" 2>/dev/null)" = "TRIMUI Player1" ] || continue
        printf '%s' "$e"
        return 0
    done
    return 1
}

# How many stick axes (ABS_X..ABS_BRAKE, codes 0..10) the pad advertises.  Hats
# (codes 16..19) are not axes for RetroArch's SDL2 driver, so they do not count
# and do not shift the numbering.
pad_axis_count() { # sysfs directory
    codes=$(abs_codes <"$1/device/capabilities/abs" 2>/dev/null)
    n=0
    for c in $codes; do
        [ "$c" -le 10 ] && n=$((n + 1))
    done
    printf '%s' "$n"
}

# Position of one evdev code in the axis numbering RetroArch uses.  The guided
# test reports which code a stick moves, so a pad that numbers its right stick
# differently still gets a binding that hits the right axis.
pad_axis_index_of_code() { # evdev code
    node=$(input_sysfs_dir 2>/dev/null) || return 1
    codes=$(abs_codes <"$node/device/capabilities/abs" 2>/dev/null)
    [ -n "$codes" ] || return 1
    pos=0
    for c in $codes; do
        [ "$c" -le 10 ] || continue
        if [ "$c" = "$1" ]; then
            printf '%s' "$pos"
            return 0
        fi
        pos=$((pos + 1))
    done
    return 1
}

# RetroArch leaves an axis unbound with "nul" - that is what the shipped
# retroarch.cfg does, and inverting "nul" would produce "nul" again.
ra_axis_bound() { # value
    case "$1" in
    "" | nul | none | NULL) return 1 ;;
    *) return 0 ;;
    esac
}

# Index a binding should use: the code the direction test measured for this
# stick when MEASURED_CODE/MEASURED_SIDE are set, else the standard layout - the
# left stick on axes 0/1 and the right stick on 2/3, which is what every TrimUI
# pad publishes in the order its driver reports them.
default_for() { # key -> "+<index>" | "-<index>"
    parts=$(axis_key_parts "$1") || return 1
    kside=${parts%% *}
    ksign=${parts##* }
    idx=""
    if [ -n "$MEASURED_CODE" ] && [ "$MEASURED_SIDE" = "$kside" ]; then
        idx=$(pad_axis_index_of_code "$MEASURED_CODE" 2>/dev/null)
    fi
    if [ -z "$idx" ]; then
        case "$kside" in
        l) idx=0 ;;
        r) idx=2 ;;
        *) return 1 ;;
        esac
    fi
    # Note: a format string starting with '-' is taken for an option by busybox
    # printf, so the sign is a separate argument.
    case "$ksign" in
    plus) printf '%s' "+$idx" ;;
    minus) printf '%s' "-$idx" ;;
    esac
}

ra_axis_current() { # key -> the axis binding that is currently in force
    v=$(ra_axis_get "$1")
    if ra_axis_bound "$v"; then
        printf '%s' "$v"
    else
        default_for "$1"
    fi
}

ra_driver() {
    v=$(ra_axis_get input_joypad_driver)
    printf '%s' "${v:-sdl2}"
}

ra_driver_note() {
    case "$(ra_driver)" in
    sdl2) printf 'axis numbers are SDL positions' ;;
    udev | linuxraw) printf 'axis numbers come from evdev: check the numbering below' ;;
    *) printf 'unknown joypad driver: the binding below may need adjusting' ;;
    esac
}

# What the daemon publishes and how RetroArch numbers it - the numbers the
# workaround has to bind.
pad_axis_report() {
    node=$(input_sysfs_dir 2>/dev/null) || {
        say "pad      : no TRIMUI Player1 device found (is trimui_inputd running?)"
        return 0
    }
    codes=$(abs_codes <"$node/device/capabilities/abs" 2>/dev/null)
    say "pad axes : ${codes:-unreadable} (evdev codes published by the daemon)"
    n=$(pad_axis_count "$node")
    say "RA axes  : RetroArch numbers them by position, not by code: left stick x=0"
    if [ "$n" = "4" ]; then
        say "           y=1, right stick x=2 y=3 (the usual four axis TrimUI pad)"
    else
        say "           y=1, right stick x=2 y=3 - with $n stick axes published that is an"
        say "           assumption: the direction test pins the code the stick reports"
    fi
}

invert_axis_value() { # +0 -> -0, -2 -> +2
    case "$1" in
    +*) printf '%s' "-${1#+}" ;;
    -*) printf '%s' "+${1#-}" ;;
    *) printf '%s' "$1" ;;
    esac
}

flip_sides() { # sides recorded when the workaround was enabled
    s=$(grep '^sides=' "$FLIP_STATE" 2>/dev/null | cut -d= -f2)
    printf '%s' "${s:-both}"
}

flip_summary() {
    if [ "$(flip_state)" = "on" ]; then
        printf 'workaround on (%s)' "$(flip_sides)"
    else
        printf 'workaround off'
    fi
}

# Does the config still hold what we wrote?  A no tells the user the workaround
# is silently inactive (a restored or reset retroarch.cfg looks like that).
flip_drifted() {
    [ "$(flip_state)" = "on" ] || return 1
    for k in $(flip_keys both); do
        case "$(flip_sides)" in *"$(key_side "$k")"*) ;; *) continue ;; esac
        want=$(grep "^applied_$k=" "$FLIP_STATE" 2>/dev/null | cut -d= -f2-)
        [ -n "$want" ] || continue
        [ "$(ra_axis_get "$k")" = "$want" ] || return 0
    done
    return 1
}

cmd_flip_status() {
    state=$(flip_state)
    say "horizontal-axis workaround: $state"
    say "retroarch.cfg          : $RA_CFG"
    say "joypad driver          : $(ra_driver) ($(ra_driver_note))"
    if [ "$state" = "on" ]; then
        say "sticks                 : $(flip_sides)"
        if [ -f "$FLIP_STATE" ]; then
            for k in $(flip_keys both); do
                case "$(flip_sides)" in *"$(key_side "$k")"*) ;; *) continue ;; esac
                orig=$(grep "^$k=" "$FLIP_STATE" 2>/dev/null | cut -d= -f2-)
                want=$(grep "^applied_$k=" "$FLIP_STATE" 2>/dev/null | cut -d= -f2-)
                now=$(ra_axis_get "$k")
                say "    $k = ${now:-unset} (was ${orig:-unset}, workaround writes ${want:-?})"
            done
        fi
        if flip_drifted; then
            say "state                  : the config no longer holds the workaround"
            say "                         run 'stick_diag.sh flip reapply' (or flip it again from"
            say "                         System Tools > CONTROLS) to put it back"
        fi
    else
        say "games read the pad exactly as the daemon publishes it"
    fi
    return 0
}

# Remember the bindings we are about to replace, so 'flip off' restores the
# user's own values (or removes the keys we had to invent).
record_flip_state() { # sides (l|r|both)
    {
        printf 'on\n'
        printf 'sides=%s\n' "${1:-both}"
        if [ -f "$RA_CFG" ]; then
            printf 'cfg_was_present=yes\n'
        else
            printf 'cfg_was_present=no\n'
        fi
        for k in $(flip_keys both); do
            if v=$(ra_axis_get "$k"); then
                printf '%s=%s\n' "$k" "$v"
            else
                printf '%s=ABSENT\n' "$k"
            fi
        done
    } >"$FLIP_STATE"
}

record_original() { # key - fill in an original we have not seen yet
    [ -f "$FLIP_STATE" ] || return 0
    grep -q "^$1=" "$FLIP_STATE" 2>/dev/null && return 0
    if v=$(ra_axis_get "$1"); then
        printf '%s=%s\n' "$1" "$v" >>"$FLIP_STATE"
    else
        printf '%s=ABSENT\n' "$1" >>"$FLIP_STATE"
    fi
}

record_applied() { # key value - what the workaround wrote, for healing later
    [ -f "$FLIP_STATE" ] || return 0
    if grep -q "^applied_$1=" "$FLIP_STATE" 2>/dev/null; then
        sed -i "s|^applied_$1=.*|applied_$1=$2|" "$FLIP_STATE" 2>/dev/null
    else
        printf 'applied_%s=%s\n' "$1" "$2" >>"$FLIP_STATE"
    fi
}

# Invert the binding in force for one stick (never the recorded one: inverting
# an already inverted binding would undo the fix).
flip_apply_side() { # side
    for k in $(flip_keys "$1"); do
        record_original "$k"
        raw=$(ra_axis_get "$k")
        cur=$(ra_axis_current "$k")
        if [ -z "$cur" ]; then
            logline "  $k : no axis binding readable - skipped"
            continue
        fi
        new=$(invert_axis_value "$cur")
        ra_axis_set "$k" "$new"
        record_applied "$k" "$new"
        note=""
        if [ -n "$MEASURED_CODE" ] && [ "$(key_side "$k")" = "$MEASURED_SIDE" ]; then
            note=" (index of the code the test measured: $MEASURED_CODE)"
        fi
        if ra_axis_bound "$raw"; then
            logline "  $k : $raw -> $new$note"
        else
            # The shipped config leaves the axis unbound, so name the mapping
            # RetroArch lets the pad expose on its own as well.
            logline "  $k : not set, RetroArch maps it as $cur -> $new$note"
        fi
        WRITTEN=$((WRITTEN + 1))
    done
}

# Put the recorded bindings back.  Without 'force' a value the user changed by
# hand is left alone; unset values and values that still match the recorded
# original are what a restored, reset or updated config looks like.
flip_restore_side() { # side [force]
    for k in $(flip_keys "$1"); do
        want=$(grep "^applied_$k=" "$FLIP_STATE" 2>/dev/null | cut -d= -f2-)
        [ -n "$want" ] || continue
        cur=$(ra_axis_get "$k")
        [ "$cur" = "$want" ] && continue
        if [ -z "$2" ] && [ -n "$cur" ]; then
            orig=$(grep "^$k=" "$FLIP_STATE" 2>/dev/null | cut -d= -f2-)
            if [ "$cur" != "$orig" ]; then
                logline "  $k is $cur (was $orig): keeping it, use 'flip reapply' to force"
                continue
            fi
        fi
        ra_axis_set "$k" "$want"
        logline "  $k : ${cur:-unset} -> $want (workaround restored)"
        WRITTEN=$((WRITTEN + 1))
    done
}

cmd_flip_on() { # [l|r|both|lr]
    side=${1:-l}
    case "$side" in
    lr) side="both" ;;
    l | r | both) ;;
    *)
        say "Unknown stick '$side' (use l, r, both or lr)."
        return 1
        ;;
    esac

    dev=$(device_code)
    if ! has_sticks "$dev"; then
        say "This device has no analog sticks - there is nothing to invert."
        return 0
    fi

    for s in l r; do
        case "$side" in
        l) [ "$s" = "l" ] || continue ;;
        r) [ "$s" = "r" ] || continue ;;
        esac
        has_stick "$dev" "$s" || {
            say "This device has no $(side_name "$s") stick - nothing to invert for it."
            return 0
        }
    done

    mkdir -p "$SDCARD/System/etc" "$BACKUP_DIR" 2>/dev/null

    new_sides="$side"
    case "$side" in
    both) new_sides="lr" ;;
    esac

    old_sides=""
    if [ "$(flip_state)" = "on" ]; then
        old_sides=$(flip_sides)
    else
        rm -f "$FLIP_STATE" 2>/dev/null
        record_flip_state "$new_sides"
    fi

    WRITTEN=0
    for s in l r; do
        case "$new_sides" in *"$s"*) ;; *) continue ;; esac
        case "$old_sides" in
        *"$s"*)
            # Already inverted once: re-apply the recorded values instead of
            # inverting them a second time.
            flip_restore_side "$s" force
            ;;
        *) flip_apply_side "$s" ;;
        esac
    done

    sides=$(sides_merge "$old_sides" "$new_sides")
    sed -i "s|^sides=.*|sides=$sides|" "$FLIP_STATE" 2>/dev/null
    sync
    logline "Horizontal-axis workaround enabled for RetroArch: sticks $sides ($WRITTEN change(s))."
    if [ "$WRITTEN" -eq 0 ]; then
        say "Nothing to change - the workaround is already in place for those sticks."
        return 0
    fi
    say "Start a game through RetroArch; if the direction is now correct, keep it."
    info_screen -m "Horizontal axis inverted for RetroArch.\nRevert any time from System Tools > CONTROLS." -t 3
    return 0
}

# Explicit way to put the workaround back after something rewrote the config.
cmd_flip_reapply() {
    if [ "$(flip_state)" != "on" ]; then
        say "The workaround is not enabled - nothing to re-apply."
        return 0
    fi
    WRITTEN=0
    for s in l r; do
        case "$(flip_sides)" in *"$s"*) flip_restore_side "$s" force ;; esac
    done
    sync
    if [ "$WRITTEN" -gt 0 ]; then
        logline "Horizontal-axis workaround re-applied ($(flip_sides), $WRITTEN change(s))."
        say "RetroArch bindings restored from the workaround record."
    else
        say "The RetroArch bindings already hold the workaround."
    fi
    return 0
}

# Boot time: repair the workaround when an OS update, a settings restore or a
# config reset dropped it, but leave deliberate user changes alone.
cmd_flip_heal() {
    [ "$(flip_state)" = "on" ] || return 0
    WRITTEN=0
    for s in l r; do
        case "$(flip_sides)" in *"$s"*) flip_restore_side "$s" ;; esac
    done
    [ "$WRITTEN" -gt 0 ] && sync
    return 0
}

sides_merge() { # "l" "r" -> l, r or lr
    out=""
    case "$1$2" in *l*) out="l" ;; esac
    case "$1$2" in *r*) out="${out}r" ;; esac
    printf '%s' "$out"
}

cmd_flip_off() {
    if [ "$(flip_state)" != "on" ] || [ ! -f "$FLIP_STATE" ]; then
        rm -f "$FLIP_STATE" 2>/dev/null
        say "Nothing to undo - the workaround is not enabled."
        return 0
    fi

    cfg_was_present=$(grep '^cfg_was_present=' "$FLIP_STATE" 2>/dev/null | cut -d= -f2)

    for k in $(flip_keys both); do
        orig=$(grep "^$k=" "$FLIP_STATE" 2>/dev/null | cut -d= -f2-)
        case "$orig" in
        "" ) continue ;;
        ABSENT)
            ra_axis_remove "$k"
            logline "  $k : removed (it did not exist before)"
            ;;
        *)
            ra_axis_set "$k" "$orig"
            logline "  $k : restored to $orig"
            ;;
        esac
    done

    # If we had to create retroarch.cfg just for the workaround, drop it again.
    if [ "$cfg_was_present" = "no" ] && [ -f "$RA_CFG" ]; then
        remaining=$(grep -c -v '^[[:space:]]*$' "$RA_CFG" 2>/dev/null)
        if [ "$remaining" -le 4 ]; then
            rm -f "$RA_CFG"
            logline "  removed $RA_CFG (created for the workaround)"
        fi
    fi

    rm -f "$FLIP_STATE" 2>/dev/null
    sync
    logline "Horizontal-axis workaround disabled."
    info_screen -m "Horizontal axis restored (RetroArch)." -t 3
    return 0
}

# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------
do_report() {
    dev=$(device_code)
    soc=$(soc_of_device "$dev")
    say ""
    say "=========== JukaMix OS - analog sticks report ==========="
    say "date     : $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    say "device   : $dev ($(device_name "$dev")) / $soc"
    say "cpuinfo  : $(soc_from_cpuinfo)"
    [ -r "$ETC/version" ] && say "firmware : $(cat "$ETC/version" 2>/dev/null)"
    [ -r "$PROC/version" ] && say "kernel   : $(cat "$PROC/version" 2>/dev/null)"
    say "sticks   : $(sticks_desc "$dev")"
    if has_sticks "$dev"; then
        say "mirror   : $(flip_summary)"
    fi
    say ""
    inputd_report "$dev"

    if has_sticks "$dev"; then
        say "-- Calibration (read live by the daemon) --"
    else
        say "-- Calibration --"
        say "This device has no analog sticks, so there is no stick calibration, no pad"
        say "direction and no mirror workaround to check. The daemon report above still"
        say "tells you whether the pad/button layer is the build for this device."
    fi
    for f in $(cal_files_for "$dev"); do
        st=$(cal_status "$f")
        if [ ! -f "$f" ]; then
            say "$f"
            say "    state    : $st (daemon uses its built-in defaults: 560/2048/3600)"
            say "               calibrate on the device: Settings > System > Calibrate Joystick"
            continue
        fi
        say "$f  ($(wc -c <"$f" 2>/dev/null | tr -d ' ') bytes)"
        say "    raw      : $(cfg_line "$f" x_min) | $(cfg_line "$f" x_max) | $(cfg_line "$f" x_zero)"
        xmin=$(cfg_get "$f" x_min)
        xmax=$(cfg_get "$f" x_max)
        xzero=$(cfg_get "$f" x_zero)
        ymin=$(cfg_get "$f" y_min)
        ymax=$(cfg_get "$f" y_max)
        yzero=$(cfg_get "$f" y_zero)
        say "    parsed   : x min=$xmin zero=$xzero max=$xmax | y min=$ymin zero=$yzero max=$ymax"
        say "    deadzone : $(cfg_line "$f" deadzone | sed 's/^[^:=]*[:=][[:space:]]*//')"
        say "    X axis   : $(axis_verdict "$xmin" "$xmax" "$xzero")"
        say "    Y axis   : $(axis_verdict "$ymin" "$ymax" "$yzero")"
        say "    state    : $st"
    done
    say ""

    say "-- Uinput devices published by the daemon --"
    found=0
    for e in "$SYSFS"/class/input/event*; do
        [ -f "$e/device/name" ] || continue
        name=$(cat "$e/device/name" 2>/dev/null)
        case "$name" in
        TRIMUI*) say "/dev/input/$(basename "$e") : $name"; found=1 ;;
        esac
    done
    [ "$found" -eq 0 ] && say "none found - is trimui_inputd running? (pgrep trimui_inputd)"
    say ""

    if has_sticks "$dev"; then
        say "-- RetroArch (where the workaround binds) --"
        pad_axis_report
        say ""

        say "-- Horizontal mirror workaround --"
        cmd_flip_status
        say ""

        say "-- What to do --"
        l_state=$(cal_status "$LEFT_CAL")
        r_state=$(cal_status "$RIGHT_CAL")
        case "$l_state$r_state" in
        *BROKEN* | *INCOMPLETE*)
            say "A calibration file is inconsistent. Run 'stick_diag.sh reset' (System Tools >"
            say "CONTROLS > Analog Sticks) and recalibrate, then reboot."
            ;;
        *MISSING*)
            say "No calibration found: the daemon uses its built-in defaults. Calibrate on"
            say "the device (Settings > System > Calibrate Joystick)."
            ;;
        *)
            say "Calibration looks sane. If games show a mirrored horizontal axis while the"
            say "stick and the calibration screen are fine, run 'stick_diag.sh test': it"
            say "checks every stick of this device and names the one that is mirrored."
            ;;
        esac
        say ""
    fi

    say "-- Verdict --"
    cmd_status 2>/dev/null || true
    say "Log: $LOG_FILE"
    say "========================================================"
    say ""
}

cmd_report() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    {
        printf '\n\n##### %s #####\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
        do_report
    } | tee -a "$LOG_FILE" 2>/dev/null
}

cmd_sides() {
    # "l", "r", "lr" or nothing - lets the menus offer only what exists here
    printf '%s\n' "$(sticks_of "$(device_code)")"
}

# Make sure the daemon on the card is the one this device needs, then show the
# pad stack.  A daemon built for another SoC makes the pad report wrong buttons
# and directions - the usual damage after moving a card between devices.
cmd_verify() {
    if [ -x "$SCRIPTS_DIR/inputd_switcher.sh" ]; then
        logline "Checking the input daemon for $(device_code)"
        "$SCRIPTS_DIR/inputd_switcher.sh" verify
    else
        say "inputd_switcher.sh not found - cannot check the input daemon."
    fi
    cmd_report
}

cal_file_of() { # side -> calibration file the daemon reads for it
    case "$1" in
    l) printf '%s' "$LEFT_CAL" ;;
    r) printf '%s' "$RIGHT_CAL" ;;
    esac
}

# One line for menus and logs.  Exits 2 when a stick needs attention (broken
# calibration or a workaround that is no longer in the config).
cmd_status() {
    dev=$(device_code)
    sticks=$(sticks_of "$dev")
    if [ -z "$sticks" ]; then
        printf 'N/A (no analog sticks on %s)\n' "$dev"
        return 0
    fi
    desc=""
    problem=0
    for side in l r; do
        has_stick "$dev" "$side" || continue
        st=$(cal_status "$(cal_file_of "$side")")
        [ "$st" = "MISSING" ] && st="not calibrated"
        case "$side" in
        l) desc="${desc:+$desc, }left: $st" ;;
        r) desc="${desc:+$desc, }right: $st" ;;
        esac
        # Only a broken file is an action item: a file the daemon cannot use
        # kills half an axis, while a merely incomplete one falls back to the
        # daemon's per key defaults.
        [ "$st" = "BROKEN" ] && problem=1
    done
    mirror=""
    if [ "$(flip_state)" = "on" ]; then
        mirror=", mirror fix on ($(flip_sides))"
        if flip_drifted; then
            mirror="$mirror - needs re-apply"
            problem=1
        fi
    fi
    if [ "$problem" -eq 0 ]; then
        printf 'OK (%s)%s\n' "$desc" "$mirror"
        return 0
    fi
    printf 'ACTION (%s)%s\n' "$desc" "$mirror"
    return 2
}

# --------------------------------------------------------------------------
# guided direction test
# --------------------------------------------------------------------------
input_event_node() {
    for e in "$SYSFS"/class/input/event*; do
        [ -f "$e/device/name" ] || continue
        [ "$(cat "$e/device/name" 2>/dev/null)" = "TRIMUI Player1" ] || continue
        printf '/dev/input/%s' "$(basename "$e")"
        return 0
    done
    return 1
}

EVTEST=""

# Largest magnitude value per requested ABS code while the user holds the
# stick: one "<code> <value>" line per code that moved, lowest code first.
sample_codes() { # "code ..." seconds
    codes=$1
    secs=$2
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$EVTEST" "$DEV" 2>/dev/null
    else
        "$EVTEST" "$DEV" 2>/dev/null &
        pid=$!
        sleep "$secs"
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    fi | awk -v want="$codes" '
        # evtest prints: type 3 (EV_ABS), code 0 (ABS_X), value 1800
        # some builds drop the axis name, leaving a comma on the code field
        BEGIN { n = split(want, c, " ") }
        /EV_ABS/ {
            code = $8
            sub(/,$/, "", code)
            keep = 0
            for (i = 1; i <= n; i++) if (code == c[i]) keep = 1
            if (!keep) next
            v = $NF + 0
            m = v < 0 ? -v : v
            if (m > best[code]) { best[code] = m; val[code] = v }
        }
        END { for (i = 1; i <= n; i++) if (c[i] in val) print c[i], val[c[i]] }
    '
}

sample_one() { # code seconds -> value, empty when nothing moved
    sample_codes "$1" "$2" | awk '{print $2; exit}'
}

# The code with the largest magnitude in a sample - the stick's own axis moves
# furthest, so it wins over noise on the other axes.
strongest_code() { # sample lines
    printf '%s\n' "$1" | awk '
        NF >= 2 { v = $2 + 0; m = v < 0 ? -v : v; if (m > best) { best = m; c = $1 } }
        END { print c }'
}

value_of_code() { # code sample lines
    printf '%s\n' "$2" | awk -v c="$1" '$1 == c { print $2; exit }'
}

# ABS codes to sample per stick.  The left stick is ABS_X/ABS_Y on every TrimUI
# pad; how the right stick is numbered differs between models (Z/RZ, RX/RY,
# RY/RZ), so every candidate is sampled and whichever code moves becomes the
# axis under test - the pad decides, not a hardcoded guess.
stick_h_codes() {
    case "$1" in
    l) printf '0' ;;
    *) printf '2 3 4 5' ;;
    esac
}

stick_v_codes() {
    case "$1" in
    l) printf '1' ;;
    *) printf '2 3 4 5' ;;
    esac
}

sign_ok() { # value neg|pos
    [ -z "$1" ] && return 1
    if [ "$2" = "neg" ]; then
        [ "$1" -lt 0 ]
    else
        [ "$1" -gt 0 ]
    fi
}

verdict_line() { # label value expected_sign description
    if [ -z "$2" ]; then
        printf '  %-16s : no movement seen while you held it\n' "$1"
        return 1
    fi
    sign_ok "$2" "$3" && ok=yes || ok=no
    printf '  %-16s : %-7s %s\n' "$1" "$2" "$4"
    [ "$ok" = "yes" ]
}

# One guided stick: ask for the four directions and judge the signs.
# Sets TG_HC (the axis code that answered), TG_HL/TG_HR/TG_VU/TG_VD (values),
# TG_SEEN (1 when anything moved) and TG_MIRROR (1 when the horizontal axis is
# reported the other way round).
stick_test() { # side seconds
    side=$1
    step=$2
    name=$(side_name "$side")
    hc=$(stick_h_codes "$side")
    vc=$(stick_v_codes "$side")

    info_screen -m "Analog stick test\nHold the $name stick fully LEFT" -t "$step"
    hl_list=$(sample_codes "$hc" "$step")
    info_screen -m "Now hold the $name stick fully RIGHT" -t "$step"
    hr_list=$(sample_codes "$hc" "$step")
    info_screen -m "Now hold the $name stick fully UP" -t "$step"
    vu_list=$(sample_codes "$vc" "$step")
    info_screen -m "Now hold the $name stick fully DOWN" -t "$step"
    vd_list=$(sample_codes "$vc" "$step")

    # The horizontal axis is the code that answered while pushing left or right,
    # the vertical one is the code that answered while pushing up or down.
    TG_HC=$(strongest_code "$hl_list")
    [ -n "$TG_HC" ] || TG_HC=$(strongest_code "$hr_list")
    [ -n "$TG_HC" ] || TG_HC=$(printf '%s' "$hc" | awk '{print $1}')
    TG_HL=$(value_of_code "$TG_HC" "$hl_list")
    TG_HR=$(value_of_code "$TG_HC" "$hr_list")
    TG_VC=$(strongest_code "$vu_list")
    [ -n "$TG_VC" ] || TG_VC=$(strongest_code "$vd_list")
    TG_VU=$(value_of_code "$TG_VC" "$vu_list")
    TG_VD=$(value_of_code "$TG_VC" "$vd_list")

    say "-- $name stick, horizontal axis $TG_HC, vertical axis ${TG_VC:-?} --"
    h_ok=1
    verdict_line "hold LEFT" "$TG_HL" neg "(code $TG_HC expected negative)" || h_ok=0
    verdict_line "hold RIGHT" "$TG_HR" pos "(code $TG_HC expected positive)" || h_ok=0
    verdict_line "hold UP" "$TG_VU" neg "(code ${TG_VC:-?} expected negative)" || true
    verdict_line "hold DOWN" "$TG_VD" pos "(code ${TG_VC:-?} expected positive)" || true
    say ""

    TG_SEEN=0
    { [ -n "$TG_HL" ] || [ -n "$TG_HR" ]; } && TG_SEEN=1
    TG_MIRROR=0
    if [ "$h_ok" -eq 0 ] && [ "$TG_SEEN" -eq 1 ]; then
        # Both halves wrong, or the only half that could be read is wrong.
        [ -n "$TG_HL" ] && [ -n "$TG_HR" ] && [ "$TG_HL" -gt 0 ] && [ "$TG_HR" -lt 0 ] && TG_MIRROR=1
        [ -z "$TG_HR" ] && [ -n "$TG_HL" ] && [ "$TG_HL" -gt 0 ] && TG_MIRROR=1
        [ -z "$TG_HL" ] && [ -n "$TG_HR" ] && [ "$TG_HR" -lt 0 ] && TG_MIRROR=1
    fi
    TG_OK=0
    [ "$h_ok" -eq 1 ] && TG_OK=1
    return 0
}

cmd_test() { # [seconds-per-step]
    step=${1:-3}
    dev=$(device_code)
    sticks=$(sticks_of "$dev")
    if [ -z "$sticks" ]; then
        say "This device ($(device_name "$dev")) has no analog sticks - nothing to test."
        logline "Direction test skipped: no analog sticks on $dev"
        return 0
    fi
    DEV=$(input_event_node) || {
        say "No 'TRIMUI Player1' input device found - is trimui_inputd running?"
        return 1
    }
    EVTEST="$SCRIPTS_DIR/evtest"
    [ -x "$EVTEST" ] || EVTEST=$(command -v evtest 2>/dev/null)
    if [ -z "$EVTEST" ]; then
        say "evtest not found, cannot run the direction test."
        return 1
    fi

    say ""
    say "Guided direction test on $DEV - $(device_name "$dev"), $(sticks_desc "$dev"),"
    say "${step}s per step. Hold the stick fully in the direction it asks for."
    say ""

    mirrored_sides=""
    odd_sides=""
    seen_any=0
    measured_l=""
    measured_r=""
    for side in l r; do
        has_stick "$dev" "$side" || continue
        stick_test "$side" "$step"
        [ "$TG_SEEN" -eq 1 ] && seen_any=1
        case "$side" in
        l) measured_l=$TG_HC ;;
        r) measured_r=$TG_HC ;;
        esac
        if [ "$TG_MIRROR" -eq 1 ]; then
            mirrored_sides="$mirrored_sides$side"
            logline "Direction test: $(side_name "$side") stick horizontal MIRRORED (axis $TG_HC left=$TG_HL right=$TG_HR)"
        elif [ "$TG_OK" -eq 1 ]; then
            logline "Direction test: $(side_name "$side") stick horizontal correct (axis $TG_HC left=$TG_HL right=$TG_HR)"
        elif [ "$TG_SEEN" -eq 1 ]; then
            odd_sides="$odd_sides$side"
            logline "Direction test: $(side_name "$side") stick reported only one horizontal direction (axis $TG_HC left=$TG_HL right=$TG_HR)"
        fi
    done

    # The d-pad bits come from the left pad frame on every TrimUI device.
    hat_seen=0
    hat_ok=1
    if has_stick "$dev" l; then
        info_screen -m "Now press and hold the D-PAD LEFT" -t "$step"
        h_left=$(sample_one 16 "$step")
        info_screen -m "Now press and hold the D-PAD RIGHT" -t "$step"
        h_right=$(sample_one 16 "$step")
        say "-- D-pad (ABS_HAT0X = code 16) --"
        verdict_line "d-pad LEFT" "$h_left" neg "(HAT0X expected -1)" || true
        verdict_line "d-pad RIGHT" "$h_right" pos "(HAT0X expected +1)" || true
        say ""
        { [ -n "$h_left" ] || [ -n "$h_right" ]; } && hat_seen=1
        sign_ok "$h_left" neg || hat_ok=0
        sign_ok "$h_right" pos || hat_ok=0
        if [ "$hat_seen" -eq 1 ] && [ "$hat_ok" -eq 0 ]; then
            logline "Direction test: d-pad HAT0X mirrored (left=$h_left right=$h_right)"
        fi
    fi

    if [ -n "$mirrored_sides" ]; then
        say ">>> VERDICT: mirrored horizontal axis on: $mirrored_sides"
        say "    The pad frame reports left/right the other way round for that stick, so"
        say "    every game behind the daemon sees it reversed - while the firmware"
        say "    calibration screen, which only proves the range, still looks fine."
        if [ "$ASSUME_YES" -ne 1 ]; then
            answer=""
            if [ -x "$SCRIPTS_DIR/shellect.sh" ]; then
                answer=$(printf 'No\nYes\n' | "$SCRIPTS_DIR/shellect.sh" \
                    -t "Invert the horizontal axis for RetroArch games?" \
                    -b "Reversible - System Tools > CONTROLS > Analog sticks > Undo mirror fix." 2>/dev/null)
            fi
            case "$answer" in
            Yes*)
                # Apply per stick with the code it really reports, so pads that
                # number their right stick differently still bind the right axis.
                for s in l r; do
                    case "$mirrored_sides" in *"$s"*) ;; *) continue ;; esac
                    MEASURED_SIDE=$s
                    case "$s" in
                    l) MEASURED_CODE=$measured_l ;;
                    r) MEASURED_CODE=$measured_r ;;
                    esac
                    cmd_flip_on "$s"
                done
                MEASURED_CODE=""
                MEASURED_SIDE=""
                ;;
            *) say "    Enable it any time: stick_diag.sh flip on $mirrored_sides" ;;
            esac
        else
            for s in l r; do
                case "$mirrored_sides" in *"$s"*) ;; *) continue ;; esac
                MEASURED_SIDE=$s
                case "$s" in
                l) MEASURED_CODE=$measured_l ;;
                r) MEASURED_CODE=$measured_r ;;
                esac
                cmd_flip_on "$s"
            done
            MEASURED_CODE=""
            MEASURED_SIDE=""
        fi
    elif [ -n "$odd_sides" ]; then
        say ">>> VERDICT: the $odd_sides stick did not report both horizontal directions."
        say "    Either it was not pushed all the way, or one half of that axis is dead:"
        say "    the daemon disables a half whose calibration no longer brackets the centre."
        say "    Run 'stick_diag.sh reset' (System Tools > CONTROLS) and recalibrate - and if"
        say "    the same half stays silent the pad hardware is the problem."
    elif [ "$seen_any" -eq 1 ]; then
        say ">>> VERDICT: every analog axis follows its stick correctly."
        if [ "$hat_seen" -eq 1 ] && [ "$hat_ok" -eq 0 ]; then
            say "    But the D-PAD left/right events are mirrored: that comes from the pad"
            say "    direction table inside trimui_inputd. Reinstall the daemon for this"
            say "    device (System Tools > CONTROLS, or 'inputd_switcher.sh verify') and"
            say "    keep this log for a bug report."
        else
            say "    If games are still mirrored, the flip happens inside that emulator's"
            say "    own mapping (not in the OS). See README 'Analog sticks'."
        fi
    else
        say ">>> VERDICT: not enough movement was captured - try again and hold the"
        say "    stick fully in each direction until the screen changes."
        logline "Direction test: inconclusive (no movement on any axis)"
    fi
    say ""
    say "Logged to $LOG_FILE"
    return 0
}

# --------------------------------------------------------------------------
# repair / reset
# --------------------------------------------------------------------------
quarantine() { # file
    f=$1
    [ -f "$f" ] || return 0
    stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null)
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    cp -f "$f" "$BACKUP_DIR/$(basename "$f").$stamp.bak" 2>/dev/null
    cp -f "$f" "$f.bak-$stamp" 2>/dev/null
    rm -f "$f"
    sync
    logline "  quarantined $f (backup: System/backups/joystick/$(basename "$f").$stamp.bak)"
}

poke_daemon() {
    # The daemon re-reads the calibration files through inotify and also polls a
    # cal_update trigger, so create it briefly to force a reload.  The trigger
    # directory differs per build (see cal_trigger_dirs), so every directory the
    # installed binary mentions gets one.
    b=$(installed_inputd 2>/dev/null)
    dirs=""
    [ -n "$b" ] && dirs=$(cal_trigger_dirs "$b")
    if [ -z "$dirs" ]; then
        # Builds without a cal_update trigger (the old stock daemon) keep their
        # runtime files in the same directories, so try every one of them.
        dirs="$VAR"
        if [ -n "$b" ] && tr -c '[:print:]' '\n' <"$b" 2>/dev/null | grep -q "^$LOGICAL_TMP"; then
            dirs="$dirs $TMPD"
        fi
    fi
    for d in $dirs; do
        mkdir -p "$d" 2>/dev/null
        : >"$d/cal_update" 2>/dev/null
    done
    sleep 1
    for d in $dirs; do
        rm -f "$d/cal_update" 2>/dev/null
    done
}

cmd_reset() {
    dev=$(device_code)
    if ! has_sticks "$dev"; then
        say "This device has no analog sticks."
        return 0
    fi
    if [ "$ASSUME_YES" -ne 1 ]; then
        answer=""
        if [ -x "$SCRIPTS_DIR/shellect.sh" ]; then
            answer=$(printf 'No\nYes\n' | "$SCRIPTS_DIR/shellect.sh" \
                -t "Clear the analog stick calibration?" \
                -b "Then recalibrate in Settings > System > Calibrate Joystick." 2>/dev/null)
        fi
        case "$answer" in
        Yes*) : ;;
        *)
            say "Cancelled."
            return 0
            ;;
        esac
    fi
    logline "Clearing analog stick calibration for $dev"
    quarantine "$LEFT_CAL"
    quarantine "$RIGHT_CAL"
    poke_daemon
    sync
    b=$(installed_inputd 2>/dev/null)
    if [ -n "$b" ] && [ -z "$(cal_trigger_dirs "$b")" ]; then
        logline "This daemon build has no cal_update trigger - reboot after recalibrating."
    fi
    logline "Done. Recalibrate the sticks (Settings > System > Calibrate Joystick)."
    info_screen -m "Analog stick calibration cleared.\nRecalibrate in Settings > System > Calibrate Joystick,\nthen reboot." -t 4
    return 0
}

# Boot time: only touch files that are demonstrably unusable, never a working
# calibration, and make sure the installed daemon matches this device.
#
# A BROKEN file (min/max no longer bracketing zero) makes the daemon publish
# only one half of that axis, so the daemon's built-in defaults are strictly
# better - the file is backed up before it is moved away.  A file that merely
# misses keys is left alone: the daemon fills in its per-key defaults.
cmd_ensure() {
    changed=0
    dev=$(device_code)

    # The daemon check runs for every device, sticks or not: a build for another
    # SoC makes the whole pad misbehave, buttons included - and the Brick, which
    # has no sticks, is exactly the device that gets one left on the card.
    if [ -x "$SCRIPTS_DIR/inputd_switcher.sh" ]; then
        "$SCRIPTS_DIR/inputd_switcher.sh" verify -q 2>/dev/null
    fi

    has_sticks "$dev" || return 0

    for f in $(cal_files_for "$dev"); do
        [ -f "$f" ] || continue
        st=$(cal_status "$f")
        case "$st" in
        BROKEN)
            quarantine "$f"
            changed=1
            continue
            ;;
        INCOMPLETE)
            [ -s "$f" ] && continue # daemon uses defaults per missing key
            quarantine "$f"
            changed=1
            ;;
        esac
    done
    if [ "$changed" -eq 1 ]; then
        logline "Analog stick calibration repaired at boot - recalibrate both sticks"
        poke_daemon
    fi

    # OS updates and settings restores rewrite RetroArch's config and quietly
    # drop the mirror workaround, so put the recorded bindings back.
    cmd_flip_heal
    return 0
}

# --------------------------------------------------------------------------
usage() {
    cat <<'EOF'
Analog stick diagnostics and repair for TrimUI handhelds (JukaMix OS).

  stick_diag.sh [options] COMMAND [ARG]

Commands
  report              what the pad stack looks like on this unit (default),
                      written to Apps/SystemTools/Logs/Analog Sticks.log as well
  verify              reinstall the input daemon when it does not match this
                      device, then report the result
  status              one line summary; exit code 2 when a stick needs action
  sides               which sticks this device has: l, r, lr or nothing
  test [SECONDS]      guided direction test of every stick it has + the d-pad
  flip                mirror-workaround state, bindings and config drift
  flip on [SIDE]      invert the horizontal axis for RetroArch games
                      SIDE is l (default), r, both or lr
  flip reapply        write the recorded workaround back into retroarch.cfg
  flip off            undo the workaround and restore the original bindings
  reset               archive the calibration files, then recalibrate
  ensure              boot repair: calibration, input daemon and workaround

Options
  -q, --quiet         no on-screen messages, only logs and reports
  -y, --yes           assume yes for the questions the tool asks
  -h, --help          this text

Devices: TrimUI Smart Pro (tsp), Smart Pro S (tsps), Brick (brick, no sticks),
Brick Pro (brickpro).  The tool adapts the daemon, the calibration files, the
sticks it tests and the RetroArch axis bindings to the current device; for a
model it does not know it takes the stick count from the published pad.
EOF
    return 0
}

main() {
    cmd="report"
    arg=""
    step=3
    while [ $# -gt 0 ]; do
        case "$1" in
        -q | --quiet) QUIET=1 ;;
        -y | --yes) ASSUME_YES=1 ;;
        report | status | sides | test | flip | reset | ensure | verify) cmd="$1" ;;
        on | off | reapply | l | r | both | lr) arg="$1" ;;
        [0-9]*) step="$1" ;;
        -h | --help) usage ; return 0 ;;
        help) cmd="help" ;;
        *)
            say "Unknown option: $1 (try --help)"
            return 1
            ;;
        esac
        shift
    done
    case "$cmd" in
    report) cmd_report ;;
    status) cmd_status ;;
    sides) cmd_sides ;;
    test) cmd_test "$step" ;;
    flip)
        case "$arg" in
        on) cmd_flip_on l ;;
        off) cmd_flip_off ;;
        reapply) cmd_flip_reapply ;;
        l | r | both | lr) cmd_flip_on "$arg" ;;
        *) cmd_flip_status ;;
        esac
        ;;
    reset) cmd_reset ;;
    ensure) cmd_ensure ;;
    verify) cmd_verify ;;
    help) usage ;;
    esac
}

main "$@"
