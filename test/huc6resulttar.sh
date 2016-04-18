#!/bin/bash
#PBS -N HUC6overview
#PBS -e /projects/demserve/nfie/HAND/HUC6/zip.stderr
#PBS -o /projects/demserve/nfie/HAND/HUC6/zip.stdout
#PBS -l nodes=cg-gpu11:ppn=20,walltime=24:00:00
#PBS -M yanliu@ncsa.illinois.edu
#PBS -m be

# create tile map service for all units
#huc=huc6tmstest
huc=HUC6
sdir=/gpfs_scratch/nfie/$huc
ddir=/projects/demserve/nfie/HAND/$huc
[ ! -d $ddir ] && mkdir -p $ddir
rm -f $ddir/job*.log
 
# for each unit, zip it
t0=`date +%s`
np=20
count=0
jobfile=$ddir/job
# create jobs
for i in `seq 0 $((np-1))`
do
    [ -f $jobfile.$i ] && rm -f $jobfile.$i
done
huclist=""
for hucid in `ls $sdir`; do
    hand=$sdir/$hucid/${hucid}dd.tif
    [ ! -f $hand ] && echo "=HUC=skip $hucid HAND N/A, skip." && continue
    of=$ddir/${hucid}.zip
    [ -f $of ] && echo "=HUC=skip $hucid HAND ZIP exists, skip." && continue
    p=`expr $count \% $np`
    echo "$hucid" >> $jobfile.$p
    huclist="$huclist $hucid"
    let "count+=1"
done
echo "Processing $count jobs..."
echo "$huclist"
pidlist=""
for i in `seq 0 $((np-1))`
do
    [ ! -f $jobfile.$i ] && continue
    /projects/nfie/nfie-floodmap/test/huc6resulttar-single.sh $jobfile.$i $sdir $ddir /tmp/job$i.log &
    pidlist="$pidlist $!"
done
echo "Waiting jobs $pidlist..."
wait $pidlist
tt=`date +%s`
echo "=HUC= DONE `expr $tt \- $t0` seconds"

