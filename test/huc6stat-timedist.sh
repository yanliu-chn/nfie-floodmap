#!/bin/bash
# collect timing info for all completed jobs
wdir=/gpfs_scratch/nfie/HUC6
ofile=huc6-timedist.csv
echo "#HUC6_ID wbd wbdbuf dem flowline dangle weights pitremove dinf d8 aread8w threshold dinfdistdown hand" >$ofile
efile=huc6-stat-timedist-missing.csv
[ -f $efile ] && rm -f $efile
count=0
#tfile=/tmp/huc6stat-timedist.$RANDOM
tfile=$ofile
min_startt=2460132253
for hucid in `ls $wdir`
do
    logfile=$wdir/$hucid/stdout
    [ ! -f $logfile ] && echo "$hucid">>$efile && continue # incomplete
    l=`grep "=STAT=" $logfile`
    [ -z "$l" ] && echo "$hucid">>$efile && continue # failed job
    statf=/tmp/huc6stat-timedist-$hucid.$RANDOM
    grep "=T" $logfile > $statf
    # if failed before, count timing for prev steps
    prevlog=$wdir/$hucid/stdout1
    if [ -f "$prevlog" ]; then
        grep "=T" $prevlog >> $statf
    fi
    # get measures
    statrow="$hucid"
    for m in wbd wbdbuf dem flowline dangle weights pitremove dinf d8 aread8w threshold dinfdistdown hand
    do
        t=`grep "=T${m}=" $statf | tail -n 1 | awk '{print $2}'`
        statrow="$statrow $t"
    done
    echo "$statrow">>$tfile
    rm -f $statf
    let "count+=1"
done
echo "Done. $count finished jobs. stat in $ofile. jobs to rerun in $efile."
