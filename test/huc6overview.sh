#!/bin/bash
#PBS -N HUC6overview
#PBS -e /gpfs_scratch/nfie/overview/HUC6/stderr
#PBS -o /gpfs_scratch/nfie/overview/HUC6/stdout
#PBS -l nodes=10:ppn=10,walltime=6:00:00
#PBS -M yanliu@ncsa.illinois.edu
#PBS -m be

## huc6overview: create an overview for Height Above Nearest Drainage raster
## version: v0.11
## Author: Yan Y. Liu <yanliu.illinois.edu>
## Date: 05/27/2016
module purge
module load parallel gdal2-stack GCC/4.9.2-binutils-2.25
rastermetatool=/projects/nfie/nfie-floodmap/test/getRasterInfo.py

# create tile map service for all units
huc=huc6tmstest
#huc=HUC6
sdir=/gpfs_scratch/nfie/$huc
ddir=/gpfs_scratch/nfie/overview/$huc
jdir=/gpfs_scratch/nfie/gnuparallel
tdir=/scratch/$PBS_JOBID # ssd
[ ! -d $ddir ] && mkdir -p $ddir

cmdfile=$jdir/huc6overview-`date +%s`.cmd 
[ -f $cmdfile ] && rm -f $cmdfile
res=0.01098632812500 # zoom level 6
for hucid in `ls $sdir`; do
    hand=$sdir/$hucid/${hucid}hand.tif
    [ ! -f $hand ] && echo "=HUC=skip $hucid HAND N/A, skip." && continue
    of=$ddir/${hucid}ov.tif
    [ -f $of ] && echo "=HUC=skip $hucid OVERVIEW exists, skip." && continue
    echo "=HUC=$hucid overview" >>$logf
    echo "read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<\$(python $rastermetatool $hand) &&   gdalwarp -t_srs EPSG:4326 -tr $res $res -te \$xmin \$ymin \$xmax \$ymax -of GTiff -r cubic $hand $of" >>$cmdfile
done
echo "GNU Parallel command file has been created: $cmdfile"

numjobs=$PBS_NP
machinefile=$PBS_NODEFILE
export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=STAT= GNU Parallel took `expr $t2 \- $t1` seconds"

echo "=HUC= creating overview VRT"
listf=$ddir/ov.list
for hucid in `ls $sdir`; do
    of=$ddir/${hucid}ov.tif
    [ ! -f $of ] && echo "=HUC= NO $hucid OVERVIEW, skip." && continue
    echo "$of" >>$listf
done
ovvrt=$ddir/ov.vrt
[ -f $ovvrt ] && rm -f $ovvrt
gdalbuildvrt -input_file_list $listf $ovvrt
echo "=HUC= creating overview GTiff "
ovf=$ddir/ov.tif
[ -f $ovf ] && rm -f $ovf
gdal_translate $ovvrt $ovf
tt=`date +%s`
echo "=HUC= VRT overview took `expr $tt \- $t2` seconds. "
echo "DONE."

