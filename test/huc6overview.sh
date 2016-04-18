#!/bin/bash
#PBS -N HUC6overview
#PBS -e /gpfs_scratch/nfie/overview/HUC6/stderr
#PBS -o /gpfs_scratch/nfie/overview/HUC6/stdout
#PBS -l nodes=cg-gpu11:ppn=20,walltime=6:00:00
#PBS -M yanliu@ncsa.illinois.edu
#PBS -m be

# create tile map service for all units
#huc=huc6tmstest
huc=HUC6
sdir=/gpfs_scratch/nfie/$huc
ddir=/gpfs_scratch/nfie/overview/$huc
[ ! -d $ddir ] && mkdir -p $ddir
rm -f $ddir/job*.log
 
# for each unit, use gdaldem to colorize and use gdal2tiles to create TMS
t0=`date +%s`
listf=$ddir/ov.list
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
    of=$ddir/${hucid}ov.tif
    [ -f $of ] && echo "=HUC=skip $hucid OVERVIEW exists, skip." && continue
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
    /projects/nfie/nfie-floodmap/test/huc6overview-single.sh $jobfile.$i $sdir $ddir $listf $ddir/job$i.log &
    pidlist="$pidlist $!"
done
echo "Waiting jobs $pidlist..."
wait $pidlist
echo "=HUC= creating overview VRT"
ovvrt=$ddir/ov.vrt
[ -f $ovvrt ] && rm -f $ovvrt
gdalbuildvrt -input_file_list $listf $ovvrt
echo "=HUC= creating overview GTiff "
ovf=$ddir/ov.tif
[ -f $ovf ] && rm -f $ovf
gdal_translate $ovvrt $ovf
tt=`date +%s`
echo "=HUC= DONE `expr $tt \- $t0` seconds"

