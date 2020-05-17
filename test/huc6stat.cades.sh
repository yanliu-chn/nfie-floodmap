#!/bin/bash
# collect timing info for all completed jobs
ddir=$HOME/scratch_br/o/hand/HUC6
wdir=$HOME/scratch_br/log/HUC6
ofile=huc6-timing.cades.csv
echo "#HUC6_ID StartTime CompTime NP" >$ofile
efile=huc6-torerun.cades.csv
[ -f $efile ] && rm -f $efile
count=0
#tfile=/tmp/huc6stat.$RANDOM
tfile=$ofile
min_startt=2460132253
for zipfile in `ls $ddir`
do
    hucid=`basename $zipfile .zip`
    logfile=$wdir/${hucid}.stdout
    [ ! -f $logfile ] && echo "$hucid">>$efile && continue # incomplete
    l=`grep "=STAT=" $logfile`
    [ -z "$l" ] && echo "$hucid">>$efile && continue # failed job
    read p hid startt t np<<<$(echo "$l")
    [ $min_startt -gt $startt ] && min_startt=$startt
    echo "$hucid $startt $t $np">>$tfile
    let "count+=1"
done
echo "Done. $count finished jobs. stat in $ofile. jobs to rerun in $efile."
