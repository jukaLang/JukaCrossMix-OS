#!/bin/ash

governor="$1"
min_id="$2"
max_id="$3"
active_cores="$4"

id_to_freq() {
	case $1 in
	0) echo 408000 ;;
	1) echo 600000 ;;
	2) echo 816000 ;;
	3) echo 1008000 ;;
	4) echo 1200000 ;;
	5) echo 1416000 ;;
	6) echo 1608000 ;;
	7) echo 1800000 ;;
	8) echo 2000000 ;;
	esac
}

freq_to_id() {
	case $1 in
	408000) echo 0 ;;
	600000) echo 1 ;;
	816000) echo 2 ;;
	1008000) echo 3 ;;
	1200000) echo 4 ;;
	1416000) echo 5 ;;
	1608000) echo 6 ;;
	1800000) echo 7 ;;
	2000000) echo 8 ;;
	esac
}

# display current CPU settings and usage examples
show_info() {
	read current_governor </sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	read current_min_freq </sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
	read current_max_freq </sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq

	min_id=$(freq_to_id "$current_min_freq")
	max_id=$(freq_to_id "$current_max_freq")
	[ -z "$min_id" ] && min_id="?"
	[ -z "$max_id" ] && max_id="?"

	num_cores=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
	active_count=$(grep -h ^1$ /sys/devices/system/cpu/cpu*/online 2>/dev/null | wc -l)


	cat <<-EOF
		========================================================================
		Usage examples:
		---------------
		  cpufreq.sh performance 3 7    # Set governor to 'performance', only max freq will be applied to 1800000 kHz
		  cpufreq.sh ondemand 1 5       # Set governor to 'ondemand', min freq to 600000 kHz, max freq to 1416000 kHz
		  cpufreq.sh ondemand 1 5 2     # Set governor to 'ondemand', min freq to 600000 kHz, max freq to 1416000 kHz, 2 cores enabled
		  cpufreq.sh powersave 0 2      # Set governor to 'powersave', min freq to 408000 kHz, max freq to 816000 kHz
		========================================================================
		Current CPU settings:
		---------------------
		  Governor: $current_governor
		  Min Frequency: $min_id = ${current_min_freq} kHz
		  Max Frequency: $max_id = ${current_max_freq} kHz
		  Active Cores: $active_count / $num_cores
		========================================================================
	EOF
}

# without arguments, display current cpu settings and examples
if [ -z "$governor" ]; then
	show_info
	exit 0
fi

# Device-aware frequency clamping: never request a step the device cannot
# reach (e.g. 2000 MHz on stock A133P kernels), so "max" tools actually work
# on every device. See System/etc/cpu_profiles.sh.
. /mnt/SDCARD/System/etc/cpu_profiles.sh 2>/dev/null || CPU_FREQ_MAX=1800000

case "$CPU_FREQ_MAX" in
1800000) CPU_MAX_ID=7 ;;
1608000) CPU_MAX_ID=6 ;;
1416000) CPU_MAX_ID=5 ;;
1200000) CPU_MAX_ID=4 ;;
1008000) CPU_MAX_ID=3 ;;
816000)  CPU_MAX_ID=2 ;;
*)       CPU_MAX_ID=7 ;;
esac

if [ -n "$min_id" ] && [ -n "$max_id" ]; then
	[ "$min_id" -gt "$CPU_MAX_ID" ] && min_id=$CPU_MAX_ID
	[ "$max_id" -gt "$CPU_MAX_ID" ] && max_id=$CPU_MAX_ID
	[ "$min_id" -gt "$max_id" ] && min_id=$max_id
fi

# Validate frequency settings
if [ "$governor" != "interactive" ] && [ "$governor" != "ondemand" ] && [ "$governor" != "performance" ] && [ "$governor" != "powersave" ] && [ "$governor" != "conservative" ] && [ "$governor" != "schedutil" ]; then
	echo "cpufreq.sh: Invalid governor."
	exit 1
elif [ $min_id -lt 0 ] || [ $min_id -gt 8 ]; then
	echo "cpufreq.sh: Invalid min frequency ID."
	exit 1
elif [ $max_id -lt $min_id ] || [ $max_id -gt 8 ]; then
	echo "cpufreq.sh: Invalid max frequency ID."
	exit 1
fi

# Validate core count if provided
if [ -n "$active_cores" ]; then
	total_cores=$(ls -d /sys/devices/system/cpu/cpu[0-3]* 2>/dev/null | wc -l)
	if [ "$active_cores" -lt 1 ] || [ "$active_cores" -gt "$total_cores" ]; then
		echo "cpufreq.sh: Invalid active core count."
		exit 1
	fi
fi

min_freq=$(id_to_freq $min_id)
max_freq=$(id_to_freq $max_id)

echo "Setting CPU frequency to $governor, $min_freq - $max_freq kHz."

# Apply frequency settings
echo $governor >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
if [ $min_freq -gt "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)" ]; then
	echo $max_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
	echo $min_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
else
	echo $min_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
	echo $max_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
fi

# Tune the scaling governor for gaming workloads. The kernel defaults are
# jittery: ondemand down-throttles the moment load dips, so after a menu
# pause a game can stay stuck at a low frequency. These best-effort writes
# make the governor ramp up fast and hold high frequencies longer. Kernels
# that do not expose a tunable simply ignore the write.
if [ "$governor" = "ondemand" ]; then
	TUNE_DIR=/sys/devices/system/cpu/cpufreq/ondemand
	[ -d "$TUNE_DIR" ] && {
		echo 90  >"$TUNE_DIR/up_threshold"         2>/dev/null
		echo 10  >"$TUNE_DIR/sampling_down_factor" 2>/dev/null
		echo 10000 >"$TUNE_DIR/sampling_rate"      2>/dev/null
		echo 0   >"$TUNE_DIR/ignore_nice_load"     2>/dev/null
	}
fi
if [ "$governor" = "conservative" ]; then
	TUNE_DIR=/sys/devices/system/cpu/cpufreq/conservative
	[ -d "$TUNE_DIR" ] && {
		echo 80  >"$TUNE_DIR/up_threshold"           2>/dev/null
		echo 30  >"$TUNE_DIR/down_threshold"         2>/dev/null
		echo 5   >"$TUNE_DIR/freq_step"              2>/dev/null
	}
fi
if [ "$governor" = "interactive" ]; then
	TUNE_DIR=/sys/devices/system/cpu/cpufreq/interactive
	[ -d "$TUNE_DIR" ] && {
		echo 90     >"$TUNE_DIR/go_hispeed_load" 2>/dev/null
		echo 20000  >"$TUNE_DIR/min_sample_time" 2>/dev/null
		echo 10000  >"$TUNE_DIR/timer_rate"      2>/dev/null
	}
fi

# Optionally set number of active CPU cores
if [ -n "$active_cores" ]; then
	i=0
	for cpu_path in /sys/devices/system/cpu/cpu[0-3]*; do
		cpu_id=$(basename $cpu_path | sed 's/cpu//')
		if [ "$i" -lt "$active_cores" ]; then
			echo 1 > "$cpu_path/online" 2>/dev/null
		else
			echo 0 > "$cpu_path/online" 2>/dev/null
		fi
		i=$((i + 1))
	done
	echo "Activated $active_cores CPU core(s)."
fi
