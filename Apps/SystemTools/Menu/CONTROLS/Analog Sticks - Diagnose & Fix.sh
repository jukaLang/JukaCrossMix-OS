#!/bin/sh
# System Tools > CONTROLS > Analog Sticks - Diagnose & Fix
#
# Shows what the pad stack looks like on this unit (device type, installed input
# daemon and what it talks to, calibration files, published input devices, the
# axis numbering and the mirror-workaround state) and offers the actions that
# help:
#   * guided direction test - checks every analog stick this device has against
#     the direction the daemon reports on TRIMUI Player1, so it can name the
#     layer that mirrors (pad frame vs emulator mapping) and bind the right axis
#   * horizontal mirror fix - reversible RetroArch binding swap for the units
#     whose pad frame reports left/right the other way round
#   * re-apply / undo the fix - an OS update or a settings restore rewrites
#     retroarch.cfg and can drop it, so both directions are one tap away
#   * reinstall the input daemon - a daemon built for another device makes the
#     whole pad report wrong buttons and directions
#   * calibration reset - archive the calibration files and recalibrate
#
# The Brick has no analog sticks: the menu then only shows the report and the
# input daemon check.

PATH="/mnt/SDCARD/System/bin:/mnt/SDCARD/System/usr/trimui/scripts:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/System/lib:/usr/trimui/lib:$LD_LIBRARY_PATH"

STICK="/mnt/SDCARD/System/usr/trimui/scripts/stick_diag.sh"
SHELLECT="/mnt/SDCARD/System/usr/trimui/scripts/shellect.sh"
REPORT="/tmp/stick_report.txt"

if [ ! -x "$STICK" ]; then
    infoscreen.sh -m "stick_diag.sh not found." -c red -t 2
    exit 1
fi

# Everything the tool prints goes to a file the on-screen viewer can show.
show_report() { # title file
    if [ -x /mnt/SDCARD/System/bin/text_viewer ]; then
        /mnt/SDCARD/System/bin/text_viewer -t "$1" -s "cat \"$2\""
    else
        cat "$2"
        printf '\nPress A to continue...'
        read -r -n 1 -s -t 20 dummy
    fi
}

"$STICK" -q report >"$REPORT" 2>&1
state=$("$STICK" -q status | tr -d '\r')
flip=$("$STICK" -q flip 2>/dev/null | head -n 1 | sed 's/.*: //')
sides=$("$STICK" -q sides 2>/dev/null | tr -d '\r')

show_report "Analog sticks - $state" "$REPORT"

if [ -z "$sides" ]; then
    # No analog sticks on this device (Brick): nothing to test, flip or reset.
    # The input daemon can still be the wrong one for this device, so offer that.
    if [ -x "$SHELLECT" ]; then
        choice=$(printf 'Nothing\nReinstall the input daemon for this device\n' |
            "$SHELLECT" -t "Analog sticks: no sticks on this device" -b "The report above shows which daemon is installed.")
        case "$choice" in
        *"Reinstall"*)
            "$STICK" -q verify >"$REPORT" 2>&1
            show_report "Input daemon" "$REPORT"
            ;;
        *) echo "Nothing to do." ;;
        esac
    else
        infoscreen.sh -m "This device has no analog sticks." -t 3
    fi
    exit 0
fi

if [ ! -x "$SHELLECT" ]; then
    echo "shellect.sh not found, nothing to do."
    exit 1
fi

choice=$(printf 'Nothing\n1. Direction test\n2. Enable mirror fix (games)\n3. Re-apply mirror fix (after an update)\n4. Undo mirror fix\n5. Reinstall input daemon for this device\n6. Clear calibration (recalibrate)\n' |
    "$SHELLECT" -t "Analog sticks: $state | mirror fix: $flip" -b "The direction test shows which layer mirrors the stick.")

case "$choice" in
*"Direction test")
    # 3 seconds per step: the user has to follow the on-screen prompts.
    "$STICK" test 3
    ;;
*"Enable mirror fix")
    # Inverting a stick that is already correct breaks it, so ask which one.
    options="Left stick (recommended)\n"
    [ "$sides" = "lr" ] && options="Both sticks\nRight stick\nLeft stick (recommended)\n"
    case "$sides" in
    r) options="Right stick\n" ;;
    esac
    side=$(printf '%b' "$options" |
        "$SHELLECT" -t "Which stick moves the wrong way?" -b "Say both only when both sticks are mirrored.")
    case "$side" in
    *Both*) "$STICK" flip on both ;;
    *Right*) "$STICK" flip on r ;;
    *) "$STICK" flip on l ;;
    esac
    ;;
*"Re-apply mirror fix")
    "$STICK" flip reapply
    ;;
*"Undo mirror fix")
    "$STICK" flip off
    ;;
*"Reinstall input daemon")
    "$STICK" -q verify >"$REPORT" 2>&1
    show_report "Input daemon" "$REPORT"
    ;;
*"Clear calibration")
    "$STICK" reset
    ;;
*)
    echo "Nothing to do."
    ;;
esac

exit 0
