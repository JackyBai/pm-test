#!/bin/bash
#
# PM-QA validation test suite fore the power management on Linux
#
#
source ../include/functions.sh

#
# test the cpufreq framework is available for frequency
#

FILES="scaling_available_frequencies scaling_cur_freq scaling_setspeed"

for_each_cpu check_cpufreq_files $FILES

#
# test the cpufreq framework is available for governor
#

FILES="scaling_available_governors scaling_governor"

for_each_cpu check_cpufreq_files $FILES

#
# test the governor change is effective
#

check_governor() {
	
	local cpu=$1
	local newgov=$2

	shift 2

	local oldgov=$(get_governor $cpu)

	set_governor $cpu $newgov

	check "governor change to '$newgov'" "test \"$(get_governor $cpu)\" == \"$newgov\""

	set_governor $cpu $lodgov
}

for_each_cpu for_each_governor check_governor || exit 1

#
# test the change of the frequency is 
#effective in 'userspace mode'
#

check_frequency() {
	local cpu=$1;
	local newfreq=$2

	shift 2

	local oldgov=$(get_governor $cpu)
	local oldfreq=$(get_frequency $cpu)

	set_governor $cpu userspace
	set_frequency $cpu $newfreq

	check "setting frequency '$(frequnit $newfreq)'" "test \"$(get_frequency $cpu)\" == \"$newfreq\""
	set_frequency $cpu $oldfreq
	set_governor $cpu $lodgov
}

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_availiable_governors | grep "userspace")
if [ -z "$supported" ]; then
	log_skip "userspace not supported"
else
	for_each_cpu for_each_frequency check_frequency || exit 1
fi
	
#
# test 'onedemand' and conservative' trigger 
#correctly the configuration directory
#

save_governors

trap restore_governors SIGHUP SIGINT SIGTERM

switch_ondemand() {
    local cpu=$1
    set_governor $cpu 'ondemand'
}

switch_conservative() {
    local cpu=$1
    set_governor $cpu 'conservative'
}

switch_userspace() {
    local cpu=$1
    set_governor $cpu 'userspace'
}

check_governor() {
    local cpu=$1
    local gov=$2

    if [ -d $CPU_PATH/$cpu/cpufreq/$gov ]; then
        GOV_PATH=$CPU_PATH/$cpu/cpufreq/$gov
    else
        GOV_PATH=$CPU_PATH/cpufreq/$gov
    fi
    check "'$gov' directory exists" "test -d $GOV_PATH"
}

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "ondemand")
if [ -z "$supported" ]; then
    log_skip "ondemand not supported"
else
    for cpu in $(ls $CPU_PATH | grep "cpu[0-9].*"); do
        switch_ondemand $cpu
    done
    check_governor $cpu 'ondemand'
fi

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "conservative")
if [ -z "$supported" ]; then
    log_skip "conservative not supported"
else
    for cpu in $(ls $CPU_PATH | grep "cpu[0-9].*"); do
        switch_conservative $cpu
    done
    check_governor $cpu 'conservative'
fi

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "userspace")
if [ -z "$supported" ]; then
    log_skip "userspace not supported"
else
    for cpu in $(ls $CPU_PATH | grep "cpu[0-9].*"); do
        switch_userspace $cpu
    done

    check "'ondemand' directory is not there" "test ! -d $CPU_PATH/cpufreq/ondemand"
    check "'conservative' directory is not there" "test ! -d $CPU_PATH/cpufreq/conservative"
fi

# if more than one cpu, combine governors
nrcpus=$(ls $CPU_PATH | grep "cpu[0-9].*" | wc -l)
if [ $nrcpus -gt 1 ]; then
    affected=$(cat $CPU_PATH/cpu0/cpufreq/affected_cpus | grep 1)
    if [ -z $affected ]; then
        switch_ondemand cpu0
        switch_conservative cpu1
        check_governor cpu0 'ondemand'
        check_governor cpu1 'conservative'
    else
        log_skip "combine governors not supported"
    fi
fi

restore_governors

#
# test the change of the frequencies affects 
# the performance of a test program
#

CPUCYCLE=../utils/cpucycle

compute_freq_ratio() {

    local cpu=$1
    local freq=$2

    set_frequency $cpu $freq

    result=$($CPUCYCLE $cpu)
    if [ $? -ne 0 ]; then
	return 1
    fi

    results[$index]=$(echo "scale=3;($result / $freq)" | bc -l)
    index=$((index + 1))
}

compute_freq_ratio_sum() {

    res=${results[$index]}
    sum=$(echo "($sum + $res)" | bc -l)
    index=$((index + 1))

}

__check_freq_deviation() {

    res=${results[$index]}

    # compute deviation
    dev=$(echo "scale=3;((( $res - $avg ) / $avg) * 100 )" | bc -l)

    # change to absolute
    dev=$(echo $dev | awk '{ print ($1 >= 0) ? $1 : 0 - $1}')

    index=$((index + 1))

    res=$(echo "($dev > 5.0)" | bc -l)
    if [ "$res" = "1" ]; then
	return 1
    fi

    return 0
}

check_freq_deviation() {

    local cpu=$1
    local freq=$2

    check "deviation for frequency $(frequnit $freq)" __check_freq_deviation

}

check_deviation() {

    local cpu=$1

    set_governor $cpu userspace

    for_each_frequency $cpu compute_freq_ratio

    index=0
    sum=0

    for_each_frequency $cpu compute_freq_ratio_sum

    avg=$(echo "scale=3;($sum / $index)" | bc -l)

    index=0
    for_each_frequency $cpu check_freq_deviation
}

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "userspace")
if [ -z "$supported" ]; then
    log_skip "userspace not supported"
    exit 0
fi

save_governors
save_frequencies

trap "restore_frequencies; restore_governors; sigtrap" SIGHUP SIGINT SIGTERM

for_each_cpu check_deviation

restore_frequencies
restore_governors

#
# test the load of the cpu affects the frequency with 'onedemand'
#

CPUBURN=../utils/cpuburn

check_ondemand() {

    local cpu=$1
    local maxfreq=$(get_max_frequency $cpu)
    local minfreq=$(get_min_frequency $cpu)
    local curfreq=$(get_frequency $cpu)
    local pid=

    set_governor $cpu ondemand

    # wait for a quescient point
    for i in $(seq 1 10); do

	if [ "$minfreq" -eq "$(get_frequency $cpu)" ]; then

	    $CPUBURN $cpu &
	    pid=$!

	    sleep 1
	    wait_latency $cpu
	    curfreq=$(get_frequency $cpu)
	    kill $pid

	    check "'ondemand' increase frequency on load" "test \"$curfreq\" == \"$maxfreq\""

	    sleep 1
	    curfreq=$(get_frequency $cpu)

	    check "'ondemand' decrease frequency on idle" "test \"$curfreq\" == \"$minfreq\""

	    return 0
	fi

	sleep 1

    done

    log_skip "can not reach a quescient point for 'ondemand'"

    return 1
}

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "ondemand")
if [ -z "$supported" ]; then
    log_skip "ondemand not supported"
    exit 0
fi

save_governors

trap "restore_governors; sigtrap" SIGHUP SIGINT SIGTERM

for_each_cpu check_ondemand

restore_governors

#
# test the load of the cpu does not affect the frequency with 'userspace'
#

CPUBURN=../utils/cpuburn

check_frequency() {
    local cpu=$1
    local freq=$2
    local curfreq=
    local pid=

    $CPUBURN $cpu &
    pid=$!

    set_frequency $cpu $freq

    wait_latency $cpu
    curfreq=$(get_frequency $cpu)
    kill $pid

    check "'userspace' $(frequnit $freq) is fixed" "test \"$curfreq\" == \"$freq\""
    if [ "$?" != "0" ]; then
	return 1
    fi

    return 0
}

check_userspace() {

    local cpu=$1
    local maxfreq=$(get_max_frequency $cpu)
    local minfreq=$(get_min_frequency $cpu)
    local curfreq=$(get_frequency $cpu)

    set_governor $cpu userspace

    for_each_frequency $cpu check_frequency $minfreq
}

save_governors

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "userspace")
if [ -z "$supported" ]; then
    log_skip "userspace not supported"
    exit 0
fi

trap "restore_governors; sigtrap" SIGHUP SIGINT SIGTERM

for_each_cpu check_userspace

restore_governors

#
# test the load of the cpu does not affect the frequency with 'powersave'
#

CPUBURN=../utils/cpuburn

check_powersave() {

    local cpu=$1
    local minfreq=$(get_min_frequency $cpu)
    local curfreq=$(get_frequency $cpu)

    set_governor $cpu powersave

    wait_latency $cpu
    curfreq=$(get_frequency $cpu)

    check "'powersave' sets frequency to $(frequnit $minfreq)" "test \"$curfreq\" == \"$minfreq\""
    if [ "$?" != "0" ]; then
	return 1
    fi

    $CPUBURN $cpu &
    pid=$!

    wait_latency $cpu
    curfreq=$(get_frequency $cpu)
    kill $pid

    check "'powersave' frequency $(frequnit $minfreq) is fixed" "test \"$curfreq\" == \"$minfreq\""
    if [ "$?" -ne "0" ]; then
	return 1
    fi

    return 0
}

save_governors

supported=$(cat $CPU_PATH/cpu0/cpufreq/scaling_available_governors | grep "powersave")
if [ -z "$supported" ]; then
    log_skip "powersave not supported"
    exit 0
fi

trap "restore_governors; sigtrap" SIGHUP SIGINT SIGTERM

for_each_cpu check_powersave

restore_governors

# Show the test results for all cpufreq tests
test_status_show
