#!/bin/sh
# This will only run the quickhit tests.

i=0;
t=2;
d=5;
r=0;
while [ "$i" -lt 50 ];
do
	if [ "$t" -lt 4 ]; then
		/unit_tests/rtcwakeup.out -d rtc0 -m mem -s $t;
	else
		/unit_tests/rtcwakeup.out -d rtc0 -m standby -s $t;
	fi
	i=`expr $i + 1`;
	r=`date +%s`;
	t=`expr $r % 5 + 2`;
	d=`expr $r % 4 + 1`;
	sleep $d;
	echo "==============================="
	echo  suspend $i times, suspend $t s
	echo "==============================="
done

