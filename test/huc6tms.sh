#!/bin/bash
#PBS -N HUC6TMS
#PBS -e /gpfs_scratch/nfie/gnuparallel/HUC6TMS-2.stderr
#PBS -o /gpfs_scratch/nfie/gnuparallel/HUC6TMS-2.stdout
#PBS -l nodes=1:ppn=1,walltime=8:00:00
#PBS -M yanliu@ncsa.illinois.edu
#PBS -m be

## huc6tms.sh: create TMS for Height Above Nearest Drainage raster
## version: v0.11
## Author: Yan Y. Liu <yanliu.illinois.edu>
## Date: 05/27/2016
module purge
module load parallel gdal2-stack GCC/4.9.2-binutils-2.25
#module load parallel gdal-stack

# create tile map service for all units
#huc=huc6tmstest
huc=HUC6
sdir=/gpfs_scratch/nfie/$huc
ddir=/gpfs_scratch/nfie/TMS/$huc
jdir=/gpfs_scratch/nfie/gnuparallel
tdir=/scratch/$PBS_JOBID # ssd

[ ! -d $ddir ] && mkdir -p $ddir
colorfile=/projects/nfie/nfie-floodmap/test/HAND-blues.clr
rastermetatool=/projects/nfie/nfie-floodmap/test/getRasterInfo.py

cmdfile=$jdir/huc6-`date +%s`.cmd 
[ -f $cmdfile ] && rm -f $cmdfile
# mor each unit, use gdaldem to colorize and use gdal2tiles to create TMS
for hucid in `ls $sdir`; do
    hand=$sdir/$hucid/${hucid}hand.tif
    [ ! -f $hand ] && echo "=HUC=skip $hucid HAND N/A, skip." && continue
    tmsdir=$ddir/$hucid
    [ -d $tmsdir ] && echo "=HUC=skip $hucid TMS exists, skip." && continue
    [ ! -d $tmsdir ] && mkdir -p $tmsdir
    colordd=$tdir/HUCDDCOLOR$hucid.$RANDOM.tif
    echo "=HUC=$hucid HAND colorize; TMS; output bbox metainfo"
    echo "gdaldem color-relief $hand $colorfile $colordd -of GTiff -alpha && gdal2tiles-patched.py -e -z 5-10 -a 0,0,0 -p geodetic -s epsg:4326 -r bilinear -w openlayers -t \"HAND Raster - HUC $hucid (v0.11)\" $colordd $tmsdir && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<\$(python $rastermetatool $hand) && echo \"\$xmin \$ymin \$xmax \$ymax\" > $tmsdir/extent.txt && rm -f $colordd" >>$cmdfile
    
done
echo "GNU Parallel command file has been created: $cmdfile"

numjobs=$PBS_NP
machinefile=$PBS_NODEFILE
export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=STAT= `expr $t2 \- $t1` seconds in total"
