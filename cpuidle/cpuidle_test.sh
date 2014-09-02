#!/bin/bash

###

source ../include/functions.sh

STATES="desc latency name power time usage"
FILES="current_driver current_governor_ro"

check_cpuidle_state_files(){

	local dirpath=$CPU_PATH/$1/cpuidle
	shift 1

	for i in $(ls -d $dirpath/state*); do
		for j in $STATES; do
			check_file $j $i || return 1
		done
	done

	return 0
}

check_cpuidle_files() {
	local dirpath=$CPU_PATH/cpuidle

	for i in $FILES; do
		check_file $i $CPU_PATH/cpuidle || return 1
	done

	return 0
}

check_cpuidle_files

for_each_cpu check_cpuidle_state_files

####

CPUIDLE_KILLER=./cpuidle_killer

check "cpuidle program runs successfully (120 secs)" "./$CPUIDLE_KILLER"

###

CPUIDLE_KILLER=./cpuidle_killer

if [ $(id -u) -ne 0 ]; then
    log_skip "run as non-root"
    exit 0
fi

restore_cpus() {
    for_each_cpu set_online
}

check_cpuidle_kill() {

    if [ "$1" = "cpu0" ]; then
	log_skip "skipping cpu0"
	return 0
    fi

    set_offline $1
    check "cpuidle program runs successfully (120 secs)" "./$CPUIDLE_KILLER"
}

trap "restore_cpus; sigtrap" SIGHUP SIGINT SIGTERM

for_each_cpu check_cpuidle_kill
restore_cpus

### Show the results for all the cpuidle tests
test_status_show
