#!/bin/bash
# create catchment mask by HUC boundary, not buffered dd
# Yan Y. Liu <yanliu@illinois.edu>, 01/03/2017

## env
module purge
module load MPICH gdal2.1.2-stack GCC/4.9.2-binutils-2.25
dsnhdplus=/projects/nfie/NFIEGeoNational.gdb
dsepsg="EPSG:4269"
dsnhdepsg="EPSG:4269"
sdir=/projects/nfie/nfie-floodmap/test

## input
hucid=$1
n=$hucid
hucquerypre=`echo $hucid | cut -b 1-8`
wdir=$2
np=20 # for no reason, after module purge, PBS_NP becomes 1
echo "using stage config $stageconf"
[ ! -d $wdir ] && echo "ERROR: work dir does not exist: $wdir" && exit 1
[ ! -f "$wdir/${n}_catch.sqlite" ] && echo "ERROR: catchment shp does not exist: $wdir/${n}_catch.sqlite" && exit 1
[ ! -f "$wdir/${n}hand.tif" ] && echo "ERROR: HAND raster does not exist: $wdir/${n}hand.tif" && exit 1 
tdir=/tmp
[ -d "/scratch/$PBS_JOBID" ] && tdir=/scratch/$PBS_JOBID

## rasterize
t1=`date +%s`
read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}hand.tif) 
echo "read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<\$(python $sdir/getRasterInfoNative.py $wdir/${n}hand.tif) && gdal_rasterize -of GTiff -co \"TILED=YES\" -co \"COMPRESS=LZW\" -co \"BIGTIFF=YES\" -a COMID -l Catchment -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchhuc.tif"
[ ! -f $wdir/${n}catchhuc.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}hand.tif) && gdal_rasterize -of GTiff -co "TILED=YES" -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a COMID -l Catchment -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchhuc.tif
t2=`date +%s`
echo "TIME rasterize_catchment_polygons `expr $t2 \- $t1`"

