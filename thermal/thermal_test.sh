#!/bin/bash

###

source ../include/functions.sh
source ../include/thermal_functions.sh

check_cooling_device_type() {
    local all_zones=$(ls $THERMAL_PATH | grep "cooling_device['$MAX_CDEV']")
    echo "Cooling Device list:"
    for i in $all_zones; do
	local type=$(cat $THERMAL_PATH/$i/type)
	echo "-    $type"
    done
}

check_thermal_zone_type() {
    local all_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    echo "Thermal Zone list:"
    for i in $all_zones; do
	local type=$(cat $THERMAL_PATH/$i/type)
	echo "-    $type"
    done
}

for_each_thermal_zone check_thermal_zone_type
for_each_thermal_zone check_cooling_device_type

###

ATTRIBUTES="mode temp type uevent"

check_thermal_zone_attributes() {

    local dirpath=$THERMAL_PATH/$1
    local zone_name=$1
    shift 1
    for i in $ATTRIBUTES; do
	check_file $i $dirpath || return 1
    done

    check_valid_temp "temp" $zone_name || return 1
}

check_thermal_zone_mode() {

    local dirpath=$THERMAL_PATH/$1
    local zone_name=$1
    shift 1
    local prev_mode=$(cat $dirpath/mode)
    echo -n enabled > $dirpath/mode
    local cur_mode=$(cat $dirpath/mode)
    check "$zone_name cur_mode=$cur_mode"\
			 "test $cur_mode = enabled" || return 1
    echo -n disabled > $dirpath/mode
    local cur_mode=$(cat $dirpath/mode)
    check "$zone_name cur_mode=$cur_mode"\
			"test $cur_mode = disabled" || return 1

    echo $prev_mode > $dirpath/mode
}

check_thermal_zone_trip_level() {

    local all_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    for i in $all_zones; do
	for_each_trip_point_of_zone $i "validate_trip_level" || return 1
    done
}

check_thermal_zone_bindings() {

    local all_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    for i in $all_zones; do
	for_each_binding_of_zone $i "validate_trip_bindings" || return 1
    done
}

for_each_thermal_zone check_thermal_zone_attributes

for_each_thermal_zone check_thermal_zone_mode

check_thermal_zone_trip_level

check_thermal_zone_bindings

###

CDEV_ATTRIBUTES="cur_state max_state type uevent"

check_cooling_device_attributes() {

    local dirpath=$THERMAL_PATH/$1
    local cdev_name=$1
    shift 1

    for i in $CDEV_ATTRIBUTES; do
	check_file $i $dirpath || return 1
    done

}

check_cooling_device_states() {
    local dirpath=$THERMAL_PATH/$1
    local cdev_name=$1
    shift 1
    local max_state=$(cat $dirpath/max_state)
    local prev_state_val=$(cat $dirpath/cur_state)
    local count=0
    local cur_state_val=0
    while (test $count -le $max_state); do
	echo $count > $dirpath/cur_state
	cur_state_val=$(cat $dirpath/cur_state)
	check "$cdev_name cur_state=$count"\
				"test $cur_state_val -eq $count" || return 1
	count=$((count+1))
    done
    echo $prev_state_val > $dirpath/cur_state
}

for_each_cooling_device check_cooling_device_attributes

for_each_cooling_device check_cooling_device_states

###

CPU_HEAT_BIN=../utils/heat_cpu
cpu_pid=0

heater_kill1() {
    if [ $cpu_pid -ne 0 ]; then
	kill -9 $cpu_pid
    fi
    kill_glmark2
}

check_temperature_change() {
    local dirpath=$THERMAL_PATH/$1
    local zone_name=$1
    shift 1

    local init_temp=$(cat $dirpath/temp)
    $CPU_HEAT_BIN &
    cpu_pid=$(ps | grep heat_cpu| awk '{print $1}')
    test -z $cpu_pid && cpu_pid=0
    check "start cpu heat binary" "test $cpu_pid -ne 0"
    test $cpu_pid -eq 0 && return

    start_glmark2

    sleep 5
    local final_temp=$(cat $dirpath/temp)
    heater_kill1
    check "temperature variation with load" "test $final_temp -gt $init_temp"
}

trap "heater_kill; sigtrap" SIGHUP SIGINT SIGTERM

for_each_thermal_zone check_temperature_change

####

HEAT_CPU_MODERATE=../utils/heat_cpu
pid=0

heater_kill2() {
    if [ $pid -ne 0 ]; then
	kill -9 $pid
    fi
}

verify_cooling_device_temp_change() {
    local dirpath=$THERMAL_PATH/$1
    local cdev_name=$1
    shift 1
    local tzonepath=$THERMAL_PATH/thermal_zone0
    test -d $tzonepath
    if [ $? -ne 0 ] ; then
	echo "No thermal zone present"
	return 1;
    fi
    local max_state=$(cat $dirpath/max_state)
    local prev_state_val=$(cat $dirpath/cur_state)
    local prev_mode_val=$(cat $tzonepath/mode)
    echo -n disabled > $tzonepath/mode

    local count=1
    local cur_state_val=0
    local init_temp=0
    local final_temp=0
    local cool_temp=0
    ./$HEAT_CPU_MODERATE moderate &
    pid=$!
    test $pid -eq 0 && return

    while (test $count -le $max_state); do
	echo 0 > $dirpath/cur_state
	sleep 5
	init_temp=$(cat $tzonepath/temp)

	echo $count > $dirpath/cur_state
	sleep 5
	final_temp=$(cat $tzonepath/temp)
	cool_temp=$(($init_temp - $final_temp))
	check "$cdev_name:state=$count effective cool=$cool_temp "\
					"test $cool_temp -ge 0"
	count=$((count+1))
    done
    heater_kill2
    echo $prev_mode_val > $tzonepath/mode
    echo $prev_state_val > $dirpath/cur_state
}

trap "heater_kill; sigtrap" SIGHUP SIGINT SIGTERM

for_each_cooling_device verify_cooling_device_temp_change

#####

verify_cpufreq_cooling_device_action() {
    local dirpath=$THERMAL_PATH/$1
    local cdev_name=$1
    shift 1

    local cpufreq_cdev=$(cat $dirpath/type)
    cat $dirpath/type | grep cpufreq
    if [ $? -ne 0  ] ; then
	return 0
    fi

    local max_state=$(cat $dirpath/max_state)
    local prev_state_val=$(cat $dirpath/cur_state)
    disable_all_thermal_zones

    local count=1
    local before_scale_max=0
    local after_scale_max=0
    local change=0

    while (test $count -le $max_state); do
	echo 0 > $dirpath/cur_state
	sleep 1

	store_scaling_maxfreq
	before_scale_max=$scale_freq

	echo $count > $dirpath/cur_state
	sleep 1

	store_scaling_maxfreq
	after_scale_max=$scale_freq

	check_scaling_freq $before_scale_max $after_scale_max
	change=$?

	check "cdev=$cdev_name state=$count" "test $change -ne 0"

	count=$((count+1))
    done
    enable_all_thermal_zones
    echo $prev_state_val > $dirpath/cur_state
}
for_each_cooling_device verify_cpufreq_cooling_device_action


trap "heater_kill; sigtrap" SIGHUP SIGINT SIGTERM

for_each_thermal_zone check_trip_point_change

## Show the results for all thermal tests

test_status_show
