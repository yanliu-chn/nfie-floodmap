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
if [ ! -f "${n}-wbd.shp" ]; then 
ogr2ogr ${n}-wbdraw.shp $dswbd WBDHU${huclen} -where "HUC${huclen}='${hucid}'" # && \
ogr2ogr -dialect sqlite -sql "select ST_buffer(Geometry, 0) from '${n}-wbdraw'" ${n}-wbd.shp ${n}-wbdraw.shp && \
[ $? -ne 0 ] && echo "ERROR creating watershed boundary shp." && exit 1
fi
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
echo "gdalwarp -cutline ${n}-wbdbuf.shp -cl ${n}-wbdbuf -crop_to_cutline -of \"GTiff\" -overwrite -co \"COMPRESS=LZW\" -co \"BIGTIFF=YES\" $dsdem ${n}z.tif "
Tstart
[ ! -f "${n}z.tif" ] && \
gdalwarp -wm $gdal_cachemax -cutline ${n}-wbdbuf.shp -cl ${n}-wbdbuf -crop_to_cutline -of "GTiff" -overwrite -co "COMPRESS=LZW" -co "BIGTIFF=YES" $dsdem ${n}z.tif \
&& [ $? -ne 0 ] && echo "ERROR clipping study area DEM." && exit 1
ls -l ${n}z.tif
Tcount dem

### burnin process
###########################################
#n=${hucid}_${dem}
#[ ! -f ${n}z.tif ] && mv ${n}.tif ${n}z.tif # original DEM
## b0. generate NHD HR flowline
echo "=3=: create flows_hr shp from NHD HR"
echo "buffering flowlines in neighboring units too in order to avoid possible voids in HAND."
echo "such voids occors in cells whose nearest streams are not in the current wbd."
echo "the fix is: instead of querying flowlines using huc, we also search nearby huc's flowlines"
#echo "=CMD= ogr2ogr ${n}_flows_hr.shp $dsnhdhr NHDFlowline -where \"REACHCODE like '${hucid}%'\""
echo "=3CMD= python $sdir/flowlinesInWBD.py $n REACHCODE $dsnhdhr nhdflowline ${n}-wbdbuf.shp ${n}-wbdbuf ${n}_flows_hr.shp "
Tstart
[ ! -f "${n}_flows_hr.shp" ] && \
#ogr2ogr ${n}_flows_hr.shp $dsnhdhr NHDFlowline -where "REACHCODE like '${hucid}%'" \
python $sdir/flowlinesInWBD.py $n REACHCODE $dsnhdhr nhdflowline ${n}-wbdbuf.shp ${n}-wbdbuf ${n}_flows_hr.shp \
&& [ $? -ne 0 ] && echo "ERROR creating flowline hr shp." && exit 1
Tcount burnflowlinehr

## b1. rasterize flowline
Tstart
[ ! -f ${n}srfv.tif ] && \
read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py ${n}z.tif) && \
echo "gdal_rasterize -ot Int16 -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a_nodata 0 -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${hucid}_flows_hr.shp ${n}srfv.tif" && \
#gdal_rasterize -ot Int16 -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a_nodata 0 -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${hucid}_flows_hr.shp ${n}srfv.tif && \
gdal_rasterize -ot Int16 -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -init 0 -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${hucid}_flows_hr.shp ${n}srfv.tif && \
[ $? -ne 0 ] && echo "ERROR burnin: rasterizing HR flowline shp. " && exit 1
Tcount burnlineraster
## b2. Burn srfv into z using raster calculator  zb = z-100 * srfv
Tstart
[ ! -f ${n}bz.tif ] && \
echo "gdal_calc.py -A ${n}z.tif -B ${n}srfv.tif --outfile=${n}bz.tif --calc='A-100*B'" && \
#gdal_calc.py -A ${n}z.tif -B ${n}srfv.tif --outfile=${n}bz.tif --calc="A-100*B" --co="COMPRESS=LZW" --co="BIGTIFF=YES" --co="TILED=YES" --NoDataValue="$nodataDEM"  && \
gdal_calc.py --quiet -A ${n}z.tif -B ${n}srfv.tif --outfile=${n}bz.tif --calc="A-100*B"  --co="BIGTIFF=YES" --NoDataValue="$nodataDEM"  && \
[ $? -ne 0 ] && echo "ERROR burnin: burn dem -100 using gdal_calc.py" && exit 1
Tcount burncut100
## b3. pitremove
Tstart
[ ! -f ${n}bfel.tif ] && \
echo "mpirun -np $np $taudem/pitremove -z ${n}bz.tif -fel ${n}bfel.tif" && \
## TODO: change np=$np after np>1 works correctly in flowdircond
mpirun -np 1 $taudem/pitremove -z ${n}bz.tif -fel ${n}bfel.tif && \
#mpirun -np $np $taudem/pitremove -z ${n}bz.tif -fel ${n}bfel.tif && \
[ $? -ne 0 ] && echo "ERROR burnin: pitremove " && exit 1
Tcount burnpitfill
## b4. d8 to create p raster
Tstart
[ ! -f ${n}bp.tif ] && \
echo "mpirun -np $np $taudemd8 -fel ${n}bfel.tif -p ${n}bp.tif -sd8 ${n}bsd8.tif" && \
## TODO: change np=$np after np>1 works correctly in flowdircond
#mpirun -np $np $taudemd8 -fel ${n}bfel.tif -p ${n}bp.tif -sd8 ${n}bsd8.tif && \
mpirun -np 1 $taudemd8 -fel ${n}bfel.tif -p ${n}bp.tif -sd8 ${n}bsd8.tif && \
[ $? -ne 0 ] && echo "ERROR burnin: d8" && exit 1
Tcount burnd8
## b5. Mask D8 flow directions to only have flow directions on streams
Tstart
[ ! -f ${n}bmp.tif ] && \
echo "gdal_calc.py -A ${n}bp.tif -B ${n}srfv.tif --outfile=${n}bmp.tif --calc='A*B'" && \
#gdal_calc.py -A ${n}bp.tif -B ${n}srfv.tif --outfile=${n}bmp.tif --calc="A*B" --co="COMPRESS=LZW" --co="BIGTIFF=YES" --co="TILED=YES" --NoDataValue="0" 
gdal_calc.py --quiet -A ${n}bp.tif -B ${n}srfv.tif --outfile=${n}bmp.tif --calc="A*B"  --co="BIGTIFF=YES" --NoDataValue="0" 
[ $? -ne 0 ] && echo "ERROR burnin: mask d8 direction" && exit 1
Tcount burnmask
## b6. Apply new TauDEM flow direction conditioning tool "Flowdircond"
Tstart
[ ! -f ${n}.tif ] && \
echo "mpirun -np $np $taudem/flowdircond -z ${n}z.tif -p ${n}bmp.tif -zfdc ${n}.tif" && \
## TODO: change np=$np after np>1 works correctly in flowdircond
#mpirun -np $np $taudem/flowdircond -z ${n}z.tif -p ${n}bmp.tif -zfdc ${n}.tif && \
mpirun -np 1 $taudem/flowdircond -z ${n}z.tif -p ${n}bmp.tif -zfdc ${n}bi.tif && \
[ $? -ne 0 ] && echo "ERROR burnin: flowdircond " && exit 1
###########################################
Tcount burnflowdircond

echo "=19=: copy/archive output from node-local dir to shared file system"
Tstart
#tar cfz $rwdir/${n}.tar.gz $n
zip --quiet -r ../${n}.zip *
cp ../${n}.zip $rwdir/
Tcount ocopy

T01=`date +%s`
echo "=STAT= $hucid $T00 `expr $T01 \- $T00` $np" 
cd $cdir
echo "[`date`] Finished."
