#!/bin/bash
# calc inundation map raster from HAND, comid mask raster, and forecast netcdf
# Yan Y. Liu <yanliu@illinois.edu>, 01/03/2017

## input
hucidfile=$1
hucidlist=`head -n 1 $hucidfile`
nlist="$hucid"
fcdir=$2
fcfilelist=$3
wrootdir=$4
maprootdir=$5
ddir=$maprootdir

echo "+================================+"
echo "+===Creating Forecast Maps  =====+"
echo "+================================+"
#construct machine file
pbs_nodefile=$PBS_NODEFILE
hlist=`sort -u $PBS_NODEFILE`
hnum=`sort -u $PBS_NODEFILE|wc|awk '{print $1}'`
numjobs=$hnum
machinefile=$HOME/tmp/fctable.machinefile.`date +%s`
sort -u $PBS_NODEFILE >$machinefile
echo "GNU PARALLEL: $numjobs jobs on $hnum hosts: $hlist"
jdir=/gpfs_scratch/nfie/gnuparallel
cmdfile=$jdir/forecast-table-`date +%s`.cmd 

module purge
module load parallel MPICH gdal2-stack GCC/4.9.2-binutils-2.25 python/2.7.10 pythonlibs/2.7.10

jcount=0
for hucid in $hucidlist; do

n=$hucid
hucquerypre=`echo $hucid | cut -b 1-8`
wdir=$wrootdir/$hucid
mapdir=$maprootdir/$hucid
[ ! -d $mapdir ] && mkdir -p $mapdir
np=1 # set np=20 after taudem issue on diff np diff result is resolved
[ ! -d $wdir ] && echo "ERROR: work dir does not exist: $wdir" && exit 1
[ ! -f "$wdir/${n}catchhuc.tif" ] && echo "ERROR: catchmen mask raster does not exist: $wdir/${n}catchhuc.tif" && exit 1
[ ! -f "$wdir/${n}hand.tif" ] && echo "ERROR: HAND raster does not exist: $wdir/${n}hand.tif" && exit 1 
[ ! -f "$wdir/${n}waterbodymask.tif" ] && echo "ERROR: waterbody mask raster does not exist: $wdir/${n}waterbodymask.tif" && exit 1 

#for fcfile in `ls $fcdir/inun-hq-table-20170119*.nc`; do
for fcfile in $fcfilelist; do

[ ! -f "$fcdir/$fcfile" ] && echo "ERROR: forecast netcdf does not exist: $fcfile" && exit 1 
init_timestamp=`echo "$fcfile"|awk -F'-' '{print $5}'`
timestamp=`echo "$fcfile"|awk -F'-' '{print $NF}'|awk -F. '{print $1}'`
mapfile=$mapdir/${hucid}inunmap-at-${init_timestamp}-for-${timestamp}.tif
t1=`date +%s`
taudem2=/gpfs_scratch/taudem/TauDEM-CatchHydroGeo
[ -f $mapfile ] && continue
echo "mpirun -np $np $taudem2/inunmap -hand $wdir/${n}hand.tif -catch $wdir/${n}catchhuc.tif -mask $wdir/${n}waterbodymask.tif -forecast $fcdir/$fcfile -mapfile $mapfile" >>$cmdfile
let "jcount+=1"

done # fcfilelist

done # hucidlist

[ $jcount -eq 0 ] && echo "Nothing to do, done." && exit 0

## run gnu parallel
export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=forecast_map= `expr $t2 \- $t1` seconds in total"
