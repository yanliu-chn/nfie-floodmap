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

timestamp="20161208_010000"

# create tile map service for all units
#huc=huc6tmstest
huc=HUC6
prj="mercator"
rdir=/gpfs_scratch/nfie/users/inunmap
sdir=$rdir/$huc
ddir=$rdir/TMS/${huc}-$prj-$timestamp-1color
jdir=/gpfs_scratch/nfie/gnuparallel


[ ! -d $ddir ] && mkdir -p $ddir
colorfile=/projects/nfie/nfie-floodmap/test/INUNMAP-blues.clr
rastermetatool=/projects/nfie/nfie-floodmap/test/getRasterInfo.py

cmdfile=$jdir/huc6-inunmap-`date +%s`.cmd 
[ -f $cmdfile ] && rm -f $cmdfile
# mor each unit, use gdaldem to colorize and use gdal2tiles to create TMS
for hucid in `ls $sdir`; do
    inunmap=$sdir/$hucid/${hucid}inunmap-${timestamp}.tif
    [ ! -f $inunmap ] && echo "=HUC=skip $hucid INUNMAP N/A, skip." && continue
    tmsdir=$ddir/$hucid
    [ -d $tmsdir/5 ] && echo "=HUC=skip $hucid TMS exists, skip." && continue
    [ ! -d $tmsdir ] && mkdir -p $tmsdir
    colordd=$tdir/HUCDDCOLOR$hucid.$RANDOM.tif
    echo "=HUC=$hucid INUNMAP colorize; TMS; output bbox metainfo"
    echo "gdaldem color-relief $inunmap $colorfile $colordd -of GTiff -alpha && gdal2tiles-patched.py -e -z 5-10 -a 0,0,0 -p mercator -s epsg:4326 -r bilinear -w openlayers -t \"INUNMAP Raster - HUC $hucid (v0.11)\" $colordd $tmsdir && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<\$(python $rastermetatool $inunmap) && echo \"\$xmin \$ymin \$xmax \$ymax\" > $tmsdir/extent.txt && rm -f $colordd" >>$cmdfile
    
done
echo "GNU Parallel command file has been created: $cmdfile"

export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=STAT= `expr $t2 \- $t1` seconds in total"
