#!/bin/sh
# Boost the CPU to the device performance profile:
# performance governor, boost minimum -> device maximum frequency.
# Replaces the hardcoded "performance + 1416000" boilerplate so every
# device gets a matching boost (see System/etc/cpu_profiles.sh).

. /mnt/SDCARD/System/etc/cpu_profiles.sh

echo performance >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo "$CPU_FREQ_BOOST_MIN" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
echo "$CPU_FREQ_MAX" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
