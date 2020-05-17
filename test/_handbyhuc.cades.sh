#!/bin/bash
#SBATCH -J __N__
#SBATCH -A birthright
##SBATCH -p gpu
#SBATCH -p high_mem_cd
#SBATCH -N __NN__
#SBATCH -n __NP__ 
#SBATCH -c 1
#SBATCH -t __T__
#SBATCH --mem=128g
#SBATCH -o __LOGDIR__/__HUCID__.stdout
#SBATCH -e __LOGDIR__/__HUCID__.stderr
##SBATCH -o /lustre/or-hydra/cades-birthright/yxl/log/%x.out
#SBATCH --mail-type BEGIN,FAIL,END,TIME_LIMIT
#SBATCH --mail-user yxl@ornl.gov

## handbyhuc.sh: create Height Above Nearest Drainage raster by HUC code.
## version: v0.12
## Author: Yan Y. Liu
## Date: 02/25/2020
## This is a script to demonstrate all the steps needed to create HAND.

# env setup
source $HOME/sw/softenv
m=cades
sdir=$HOME/nfie-floodmap/test
source $sdir/handbyhuc.${m}.env

# config
hucid='120402'
n='gbay'
hucid='12090205'
n='travis'
hucid='__HUCID__'
n='__HUCID__'
[ ! -z "$1" ] && hucid="$1"
huclen=${#hucid}
[ ! -z "$2" ] && n="$2"
np="$3"
[ -z "$np" ] && np=$SLURM_NTASKS && [ -z "$np" ] && np=32

T00=`date +%s` 
echo "[`date`] Running HAND workflow for HUC$hucid($n) using $np cores..."
rwdir=$HOME/scratch/test # root working dir
[ ! -z "$SLURM_NTASKS" ] && rwdir=__RWDIR__
ldir=$rwdir
[ ! -z "$SLURM_NTASKS" ] && ldir=__LDIR__
[ ! -d "$ldir" ] && ldir=$rwdir
wdir=$ldir/${n}
cdir=`pwd`
mkdir -p $wdir
cd $wdir

# memory optimization for gdal operations
gdal_cachemax=$((32*2**30))  # 32GB TODO: make sure it is satisfied

echo "======== wdir=$wdir ========="
[ ! -z "$SLURM_NTASKS" ] && df | grep __LDIR__

echo "=1=: create watershed boundary shp from WBD"
echo -e "\tThis step queries WBD to get the boundary shp of study watershed."
echo "=1= ogr2ogr ${n}-wbd.shp $dswbd WBDHU${huclen} -where \"HUC${huclen}='${hucid}'\" "
echo "using buffer size 0 to create wbd.shp to avoid the Ring Self-intersection error in some units"
Tstart
[ ! -f "${n}-wbd.shp" ] && \
ogr2ogr ${n}-wbdraw.shp $dswbd WBDHU${huclen} -where "HUC${huclen}='${hucid}'" \
&& ogr2ogr -dialect sqlite -sql "select ST_buffer(Geometry, 0) from '${n}-wbdraw'" ${n}-wbd.shp ${n}-wbdraw.shp \
&& [ $? -ne 0 ] && echo "ERROR creating watershed boundary shp." && exit 1
Tcount wbd

echo "=1.1=: buffer boundary shp to avoid edge contamination effect"
echo "ogr2ogr -dialect sqlite -sql \"select ST_buffer(Geometry, $bufferdist) from '${n}-wbd'\" ${n}-wbdbuf.shp ${n}-wbd.shp "
Tstart
[ ! -f "${n}-wbdbuf.shp" ] && \
ogr2ogr -dialect sqlite -sql "select ST_buffer(Geometry, $bufferdist) from '${n}-wbd'" ${n}-wbdbuf.shp ${n}-wbd.shp  \
&& [ $? -ne 0 ] && echo "ERROR buffering boundary shp." && exit 1
Tcount wbdbuf

echo "=2=: create DEM from NED 10m"
echo -e "\tThis step clips the DEM of the study watershed from the NED 10m VRT."
echo -e "\tThe output is hucid.tif of the original projection (geo)."
echo "gdalwarp -cutline ${n}-wbdbuf.shp -cl ${n}-wbdbuf -crop_to_cutline -of \"GTiff\" -overwrite -co \"COMPRESS=LZW\" -co \"BIGTIFF=YES\" $dsdem ${n}.tif "
Tstart
[ ! -f "${n}.tif" ] && \
gdalwarp -wm $gdal_cachemax -cutline ${n}-wbdbuf.shp -cl ${n}-wbdbuf -crop_to_cutline -of "GTiff" -overwrite -co "COMPRESS=LZW" -co "BIGTIFF=YES" $dsdem ${n}.tif \
&& [ $? -ne 0 ] && echo "ERROR clipping study area DEM." && exit 1
ls -l ${n}.tif
Tcount dem

echo "=3=: create flowline shp from NHDPlus"
echo "buffering flowlines in neighboring units too in order to avoid possible voids in HAND."
echo "such voids occors in cells whose nearest streams are not in the current wbd."
echo "the fix is: instead of querying flowlines using huc, we also search nearby huc's flowlines"
#echo "=3CMD= ogr2ogr ${n}-flows.shp $dsnhdplus NHDFlowline_Network -where \"REACHCODE like '${hucid}%'\""
echo "=3CMD= python $sdir/flowlinesInWBD.py $n REACHCODE $dsnhdplus NHDFlowline_Network ${n}-wbdbuf.shp ${n}-wbdbuf ${n}-flows.shp" 
Tstart
[ ! -f "${n}-flows.shp" ] && \
#ogr2ogr ${n}-flows.shp $dsnhdplus NHDFlowline_Network -where "REACHCODE like '${hucid}%'" \
python $sdir/flowlinesInWBD.py $n REACHCODE $dsnhdplus NHDFlowline_Network ${n}-wbdbuf.shp ${n}-wbdbuf ${n}-flows.shp \
&& [ $? -ne 0 ] && echo "ERROR creating flowline shp." && exit 1
Tcount flowline

echo "=4=: find inlets from flowline shp"
find_inlets=$sdir/../src/find_inlets/build/find_inlets_mr
#find_inlets=/projects/nfie/hand/inlet-finder/build/find_inlets
echo "=4CMD= $find_inlets -flow ${n}-flows.shp -dangle ${n}-inlets0.shp "
Tstart
[ ! -f "${n}-inlets0.shp" ] && \
$find_inlets -flow ${n}-flows.shp -dangle ${n}-inlets0.shp \
&& [ $? -ne 0 ] && echo "ERROR creating inlet shp." && exit 1
Tcount dangle

echo "=5=: rasterize inlet points"
Tstart
[ ! -f "${n}-weights.tif" ] && \
ogr2ogr -t_srs $dsepsg ${n}-inlets.shp ${n}-inlets0.shp && \
read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfo.py ${n}.tif) && \
echo "=5CMD= gdal_rasterize  -ot Int16 -of GTiff -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${n}-inlets.shp ${n}-weights.tif" && \
gdal_rasterize  -ot Int16 -of GTiff -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${n}-inlets.shp ${n}-weights.tif \
&& [ $? -ne 0 ] && echo "ERROR rasterizing inlet shp to weight grid." && exit 1
Tcount weights

#module purge
#module load MPICH gdal-stack

echo "=6=: taudem pitremove"
echo "=6CMD= mpirun -np $np $taudem/pitremove -z ${n}.tif -fel ${n}fel.tif"
Tstart
[ ! -f "${n}fel.tif" ] && \
mpirun -np $np $taudem/pitremove -z ${n}.tif -fel ${n}fel.tif \
&& [ $? -ne 0 ] && echo "ERROR creating pitremove DEM." && exit 1
Tcount pitremove 

echo "=7=: taudem dinf"
#echo "=7CMD= mpirun -np $np $taudem/dinfflowdir -fel ${n}fel.tif -ang ${n}ang.tif -slp ${n}slp.tif "
echo "=7CMD= mpirun -np $np $taudemdinf -fel ${n}fel.tif -ang ${n}ang.tif -slp ${n}slp.tif "
Tstart
[ ! -f "${n}ang.tif" ] && \
#mpirun -np $np $taudem/dinfflowdir -fel ${n}fel.tif -ang ${n}ang.tif -slp ${n}slp.tif \
mpirun -np $np $taudemdinf -fel ${n}fel.tif -ang ${n}ang.tif -slp ${n}slp.tif \
&& [ $? -ne 0 ] && echo "ERROR creating dinf raster." && exit 1
Tcount dinf

echo "=8=: taudem d8"
#echo "=8CMD= mpirun -np $np $taudem/d8flowdir -fel ${n}fel.tif -p ${n}p.tif -sd8 ${n}sd8.tif "
echo "=8CMD= mpirun -np $np $taudemd8 -fel ${n}fel.tif -p ${n}p.tif -sd8 ${n}sd8.tif "
Tstart
[ ! -f "${n}p.tif" ] && \
#mpirun -np $np $taudem/d8flowdir -fel ${n}fel.tif -p ${n}p.tif -sd8 ${n}sd8.tif \
mpirun -np $np $taudemd8 -fel ${n}fel.tif -p ${n}p.tif -sd8 ${n}sd8.tif \
&& [ $? -ne 0 ] && echo "ERROR creating d8 raster." && exit 1
Tcount d8

echo "=9=: taudem aread8 with weights"
echo "=9CMD= mpirun -np $np $taudem/aread8 -p ${n}p.tif -ad8 ${n}ssa.tif -wg ${n}-weights.tif -nc"
Tstart
[ ! -f "${n}ssa.tif" ] && \
mpirun -np $np $taudem/aread8 -p ${n}p.tif -ad8 ${n}ssa.tif -wg ${n}-weights.tif -nc \
&& [ $? -ne 0 ] && echo "ERROR creating aread8 raster with weights." && exit 1
Tcount aread8w

echo "=10=: taudem threshold"
echo "=10CMD= mpirun -np $np $taudem/threshold -ssa ${n}ssa.tif -src ${n}src.tif -thresh 1 "
Tstart
[ ! -f "${n}src.tif" ] && \
mpirun -np $np $taudem/threshold -ssa ${n}ssa.tif -src ${n}src.tif -thresh 1 \
&& [ $? -ne 0 ] && echo "ERROR creating streamgrid using threshold." && exit 1
Tcount threshold

echo "=11=: taudem dinfdistdown"
echo "=11CMD= mpirun -np $np $taudem/dinfdistdown -fel ${n}fel.tif -ang ${n}ang.tif -src ${n}src.tif -dd ${n}dd.tif -m ave v"
Tstart
[ ! -f "${n}dd.tif" ] && \
mpirun -np $np $taudem/dinfdistdown -fel ${n}fel.tif -ang ${n}ang.tif -src ${n}src.tif -dd ${n}dd.tif -m ave v \
&& [ $? -ne 0 ] && echo "ERROR creating HAND raster." && exit 1
Tcount dinfdistdown

echo "=12=: clip DistDown raster to original WBD size"
echo "gdalwarp does a bad job in clipping, which results in huge output raster."
echo "so we create an uncompressed tmp hand; then move it to the right size."
echo "gdalwarp -cutline ${n}-wbd.shp -cl ${n}-wbd -crop_to_cutline -of "GTiff" -overwrite -co "COMPRESS=LZW" -co "BIGTIFF=YES" ${n}dd.tif ${n}hand.tif "
Tstart
[ ! -f "${n}hand.tif" ] && \
gdalwarp -wm $gdal_cachemax -cutline ${n}-wbd.shp -cl ${n}-wbd -crop_to_cutline -of "GTiff" -overwrite -co "BIGTIFF=YES" ${n}dd.tif ${n}handtmp.tif \
&& gdal_translate --config GDAL_CACHEMAX $gdal_cachemax -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" ${n}handtmp.tif ${n}hand.tif \
&& rm -f ${n}handtmp.tif \
&& [ $? -ne 0 ] && echo "ERROR clipping DistDown raster to original WBD boundary" && exit 1
Tcount hand


echo "=13=: create catchment and comid files"
echo "for a HUC ID, fetch catchment polygons as sqlite and comids in it as csv txt."
Tstart
tdir=./_tmp.$RANDOM
mkdir -p $tdir
echo "ogr2ogr -t_srs $dsnhdepsg $tdir/${n}flows.shp ${n}-flows.shp"
ogr2ogr -t_srs $dsnhdepsg $tdir/${n}flows.shp ${n}-flows.shp
## query catchment polygons
lname="'${n}flows.shp'.${n}flows"
l1=${n}flows
l2=Catchment
# ogr2ogr way: TOO SLOW. it works, though
# [ ! -f $wdir/${n}_catch.sqlite ] && ogr2ogr -t_srs $dsepsg -f SQLite -overwrite -sql "SELECT $l1.COMID AS COMID, $l1.REACHCODE AS REACHID, $l2.Shape_Length AS ShpLen, $l2.Shape_Area AS ShpArea, $l2.AreaSqKM as AreaSqKM from $l2 INNER JOIN $lname ON $l2.FEATUREID=$l1.COMID " $wdir/${n}_catch.sqlite $dsnhdplus

# specialized INNER JOIN using fast python hash on COMID in flowline layer
echo "python $sdir/catchShapeByHUC.py $n $tdir/${n}flows.shp $l1 COMID $dsnhdplus $l2 ."
[ ! -f ${n}_catch.sqlite ] && python $sdir/catchShapeByHUC.py $n $tdir/${n}flows.shp $l1 COMID $dsnhdplus $l2 .
Tcount catchcomid

echo "=14=: rasterize catchment - buffered"
echo "for a HUC ID, convert catchment polygons in sqlite to raster of the same extent as dd.tif w/ buffer"
echo "skipping -co TILED=YES option bc it causes 'ERROR 2: gdalrasterize.cpp: 957: Multiplication overflow' error"
Tstart
echo "read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}dd.tif) && gdal_rasterize -of GTiff -co \"TILED=YES\" -co \"COMPRESS=LZW\" -co \"BIGTIFF=YES\" -a COMID -l $l2 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchmask.tif"
[ ! -f ${n}catchmask.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py ${n}dd.tif) && gdal_rasterize -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a COMID -l $l2 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 ${n}_catch.sqlite ${n}catchmask.tif
Tcount catchraster

echo "=15=: rasterize catchment - on huc boundary"
echo "for a HUC ID, convert catchment polygons in sqlite to raster of the same extent as hand.tif w/o buffer"
echo "skipping -co TILED=YES option bc it causes 'ERROR 2: gdalrasterize.cpp: 957: Multiplication overflow' error"
Tstart
[ ! -f ${n}catchhuc.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py ${n}hand.tif) && gdal_rasterize -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a COMID -l Catchment -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 ${n}_catch.sqlite ${n}catchhuc.tif
Tcount catchrasterhuc

echo "=16=: hydro property calculation"
echo "calculate base hydraulic property table"
echo "np=1 gives correct results"
#TODO: test varying np numerical difference. if minor, use $np
Tstart
stageconf=$sdir/stage.txt
[ ! -f $stageconf ] && echo "ERROR: stage config not exist $stageconf" && exit 1
echo "mpirun -np $np $taudem_catchhydrogeo/catchhydrogeo -hand $wdir/${n}dd.tif -catch $wdir/${n}catchmask.tif -catchlist $wdir/${n}_comid.txt -slp $wdir/${n}slp.tif -h $stageconf -table $wdir/hydroprop-basetable-${n}.csv"
[ ! -f hydroprop-basetable-${n}.csv ] && mpirun -np 1 $taudem_catchhydrogeo/catchhydrogeo -hand ${n}dd.tif -catch ${n}catchmask.tif -catchlist ${n}_comid.txt -slp ${n}slp.tif -h $stageconf -table hydroprop-basetable-${n}.csv
Tcount catchhydrogeo

echo "=17=: addon hydro properties "
echo "calculate base hydraulic property table"
Tstart
echo "python $sdir/hydraulic_property_postprocess.py $wdir/hydroprop-basetable-${n}.csv 0.05 $wdir/hydroprop-fulltable-${n}.csv"
[ ! -f hydroprop-fulltable-${n}.csv ] && python $sdir/hydraulic_property_postprocess.py hydroprop-basetable-${n}.csv 0.05 hydrogeo-fulltable-${n}.csv
Tcount hydratable

echo "=18=: extract waterbody in huc"
echo "skipping -co TILED=YES option bc it causes 'ERROR 2: gdalrasterize.cpp: 957: Multiplication overflow' error"
Tstart
[ ! -f ${n}waterbodymask.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py ${n}hand.tif) && gdal_rasterize -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -burn 1 -l NHDWaterbody -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int16 -a_nodata 0 $dsnhdplus ${n}waterbodymask.tif
Tcount waterbody

## cleanup
[ -d "$tdir" ] && rm -fr $tdir

echo "=19=: copy/archive output from node-local dir to shared file system"
Tstart
cd ..
#tar cfz $rwdir/${n}.tar.gz $n
zip --quiet -r ${n}.zip ${n}
cp ${n}.zip $rwdir/
Tcount ocopy

T01=`date +%s`
echo "=STAT= $hucid $T00 `expr $T01 \- $T00` $np" 
cd $cdir
echo "[`date`] Finished."
