#/bin/bash
#
# Power Management Test Case.
#

hotplug_allow_cpu0=0
VAR="*.sh"
DIR="cpufreq thermal cpuidle suspend"

for dir in $DIR
do
	cd $dir
	for cmd in $VAR
	do
		echo
		echo -e "\033[;32m####Test for $dir#####\033[0m"
		echo "$cmd:"
		echo "###"
		./$cmd 2> log
	done
	cd ../	
done
