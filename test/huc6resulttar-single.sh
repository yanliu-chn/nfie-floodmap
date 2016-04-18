#!/bin/bash
jobf=$1
sdir=$2
ddir=$3
logf=$4

cdir=`pwd`
cd $sdir
while read hucid
do
    t1=`date +%s`
    zip -r $ddir/$hucid.zip $hucid >>$logf 2>&1
    rcode=$?
    t2=`date +%s`
    if [ $rcode -ne 0 ]; then
     echo "=FAILED= $hucid $of" >>$logf
    else 
        echo "=STAT= $hucid `expr $t2 \- $t1`" >>$logf
    fi
done<$jobf
cd $cdir
exit 0
