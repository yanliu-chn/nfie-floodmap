#!/bin/bash
# create Waterbody layer 0-1 mask from nhdplus mr based on HUC code
# to be used to mask inundation maps so that only rivers are predicted.
# Yan Y. Liu <yanliu@illinois.edu>, 01/05/2017

## env
module purge
module load MPICH gdal2.1.2-stack GCC/4.9.2-binutils-2.25
dsnhdplus=/gpfs_scratch/usgs/nhd/NFIEGeoNational.gdb
dsepsg="EPSG:4269"
dsnhdepsg="EPSG:4269"
sdir=/projects/nfie/nfie-floodmap/test

hucid=$1
n=$1
wdir=$2

## rasterize by querying NHDPlus Waterbody layer directly
t1=`date +%s`
# TODO: change to Byte when TauDEM supports BYTE_TYPE
[ ! -f $wdir/${n}waterbodymask.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}hand.tif) && gdal_rasterize -of GTiff -co "TILED=YES" -co "COMPRESS=LZW" -co "BIGTIFF=YES" -burn 1 -l Waterbody -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int16 -a_nodata 0 $dsnhdplus $wdir/${n}waterbodymask.tif
t2=`date +%s`
echo "TIME rasterize_waterbody_polygons `expr $t2 \- $t1`"


