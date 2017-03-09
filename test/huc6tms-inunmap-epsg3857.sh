#!/bin/bash
#PBS -N HUC6TMSinunmap
#PBS -e /gpfs_scratch/nfie/gnuparallel/HUC6TMSinunmap.stderr
#PBS -o /gpfs_scratch/nfie/gnuparallel/HUC6TMSinunmap.stdout
#PBS -l nodes=16:ppn=10,walltime=28:00:00
#PBS -M yanliu@ncsa.illinois.edu
#PBS -m be

## huc6tms.sh: create TMS for inundation map rasters
## version: v0.11
## Author: Yan Y. Liu <yanliu.illinois.edu>
## Date: 01/04/2017
numjobs=$PBS_NP
machinefile=$PBS_NODEFILE
tdir=/scratch/$PBS_JOBID # ssd
#tdir=/scratch

module purge
module load parallel gdal2-stack GCC/4.9.2-binutils-2.25

echo "+================================+"
echo "+===Creating HUC6 TMS Tiles =====+"
echo "+================================+"
#timestamplist="20170118_160000 20170118_170000 20170118_180000 20170118_190000 20170118_200000 20170118_210000 20170118_220000 20170118_230000 20170119_000000 20170119_010000 20170119_020000 20170119_030000 20170119_040000 20170119_050000 20170119_060000 20170119_070000"
#timestamplist="20170119_030000 20170119_040000 20170119_050000 20170119_060000 20170119_070000"
#timestamplist="20170119_020000 20170119_030000 20170119_040000 20170119_050000 20170119_060000 20170119_070000 20170119_080000 20170119_090000 20170119_100000 20170119_110000 20170119_120000 20170119_130000 20170119_140000 20170119_150000 20170119_160000"
hucidfile=$1
hucidlist=`head -n 1 $hucidfile`
timestamplist="$2"
init_timestamp="$3"
# create tile map service for all units
#huc=huc6tmstest
huc=HUC6
prj="mercator"
rdir=/gpfs_scratch/nfie/users/inunmap
[ ! -z "$4" ] && rdir="$4"
sdir=$rdir/$huc
jdir=/gpfs_scratch/nfie/gnuparallel
colorfile=/projects/nfie/nfie-floodmap/test/INUNMAP-blues.clr
rastermetatool=/projects/nfie/nfie-floodmap/test/getRasterInfo.py
cmdfile=$jdir/huc6-inunmap-`date +%s`.cmd 
[ -f $cmdfile ] && rm -f $cmdfile

jcount=0
for timestamp in $timestamplist; do

ddir=$rdir/TMS/${huc}-$prj-at-${init_timestamp}-for-$timestamp
[ ! -d $ddir ] && mkdir -p $ddir

# for each unit, use gdaldem to colorize and use gdal2tiles to create TMS
for hucid in $hucidlist; do
    inunmap=$sdir/$hucid/${hucid}inunmap-at-${init_timestamp}-for-${timestamp}.tif
    [ ! -f $inunmap ] && echo "=HUC=skip $hucid INUNMAP N/A, skip. $inunmap" && continue
    tmsdir=$ddir/$hucid
    [ -d $tmsdir/5 ] && echo "=HUC=skip $hucid TMS exists, skip." && continue
    [ ! -d $tmsdir ] && mkdir -p $tmsdir
    colordd=$tdir/HUCDDCOLOR$hucid.$RANDOM.tif
    echo "gdaldem color-relief $inunmap $colorfile $colordd -of GTiff -alpha && gdal2tiles-patched.py -e -z 5-12 -a 0,0,0 -p mercator -s epsg:4326 -r bilinear -w openlayers -t \"INUNMAP Raster - HUC $hucid (v0.11)\" $colordd $tmsdir && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<\$(python $rastermetatool $inunmap) && echo \"\$xmin \$ymin \$xmax \$ymax\" > $tmsdir/extent.txt && rm -f $colordd" >>$cmdfile
    let "jcount+=1"
    
done #hucid

done #timestamplist
[ $jcount -eq 0 ] && echo "Nothing to do, done." && exit 0
echo "GNU Parallel command file has been created: $cmdfile"

export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=huc6tms= `expr $t2 \- $t1` seconds in total"
