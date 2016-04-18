#!/bin/bash
# collect timing info for all completed jobs
wdir=/gpfs_scratch/nfie/HUC6
ofile=huc6-timing.csv
echo "#HUC6_ID StartTime CompTime NP" >$ofile
efile=huc6-torerun.csv
[ -f $efile ] && rm -f $efile
count=0
tfile=/tmp/huc6stat.$RANDOM
min_startt=2460132253
for hucid in `ls $wdir`
do
    logfile=$wdir/$hucid/stdout
    [ ! -f $logfile ] && echo "$hucid">>$efile && continue # incomplete
    l=`grep "=STAT=" $logfile`
    [ -z "$l" ] && echo "$hucid">>$efile && continue # failed job
    read p hid startt t np<<<$(echo "$l")
    [ $min_startt -gt $startt ] && min_startt=$startt
    # if failed before, count timing for prev steps
    prevlog=$wdir/$hucid/stdout1
    if [ -f "$prevlog" ]; then
        for tt in `grep "=T" $prevlog | awk '{print $2}'`; do 
            [ ! -z "$tt" ] && let "t+=$tt"
        done
    fi
    echo "$hucid $startt $t $np">>$tfile
    let "count+=1"
done
while read l
do
    read hucid startt t np<<<$(echo "$l")
    let "startt-=$min_startt"
    echo "$hucid $startt $t $np">>$ofile
done<$tfile
echo "Done. $count finished jobs. stat in $ofile. jobs to rerun in $efile."
