#!/bin/sh
# Stand-in for evtest used by tests/stick_diag_test.sh.  On every run it takes
# one answer line from $JUKAMIX_EVTEST_ANSWERS - "<code> <value> [<code> <value>]"
# - and prints it in evtest's format, so the guided direction test can be driven
# without hardware.

answers=${JUKAMIX_EVTEST_ANSWERS:-}
[ -n "$answers" ] || exit 0
[ -f "$answers" ] || exit 0

line=$(head -n 1 "$answers" 2>/dev/null)
if [ "$(wc -l <"$answers" 2>/dev/null | tr -d ' ')" -gt 1 ]; then
    tail -n +2 "$answers" >"$answers.tmp" 2>/dev/null && mv "$answers.tmp" "$answers"
else
    : >"$answers"
fi

set -- $line
while [ $# -ge 2 ]; do
    printf 'Event: time 1.000000, type 3 (EV_ABS), code %s (ABS_X), value %s\n' "$1" "$2"
    shift 2
done
exit 0
