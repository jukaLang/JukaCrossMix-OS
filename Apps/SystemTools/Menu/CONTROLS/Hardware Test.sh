#!/bin/sh

pkill -f hwt

if [ "$#" -gt 0 ]; then
  ./hwt "$@"
else
  progdir=$(dirname "$0")
  cd "$progdir" || exit 1
  ./hwt
fi
