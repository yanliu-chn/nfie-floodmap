#!/bin/bash
# collect timing info for all completed jobs
ddir=$HOME/scratch_br/o/hand/HUC6
wdir=$HOME/scratch_br/log/HUC6
ofile=huc6-timedist.cades.csv
echo "#HUC6_ID wbd wbdbuf dem flowline dangle weights pitremove dinf d8 aread8w threshold dinfdistdown hand catchcomid catchraster catchrasterhuc catchhydrogeo hydratable waterbody ocopy" >$ofile
efile=huc6-stat-timedist-missing.cades.csv
[ -f $efile ] && rm -f $efile
count=0
#tfile=/tmp/huc6stat-timedist.$RANDOM
tfile=$ofile
min_startt=2460132253
for zipfile in `ls $ddir`
do
    hucid=`basename $zipfile .zip`
    logfile=$wdir/${hucid}.stdout
    [ ! -f $logfile ] && echo "$hucid">>$efile && continue # incomplete
    l=`grep "=STAT=" $logfile`
    [ -z "$l" ] && echo "$hucid">>$efile && continue # failed job
    statf=/dev/shm/cfim/huc6stat-timedist-$hucid.$RANDOM
    grep "=T" $logfile > $statf
    # get measures
    statrow="$hucid"
    for m in wbd wbdbuf dem flowline dangle weights pitremove dinf d8 aread8w threshold dinfdistdown hand catchcomid catchraster catchrasterhuc catchhydrogeo hydratable waterbody ocopy
    do
        t=`grep "=T${m}=" $statf | tail -n 1 | awk '{print $2}'`
        statrow="$statrow $t"
    done
    echo "$statrow">>$tfile
    rm -f $statf
    let "count+=1"
done
echo "Done. $count finished jobs. stat in $ofile. jobs to rerun in $efile."
