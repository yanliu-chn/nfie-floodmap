#!/bin/bash
# get catchment shp from nhdplus mr based on HUC code
# Yan Y. Liu <yanliu@illinois.edu>, 10/30/2016

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
[ ! -d $wdir ] && echo "ERROR: work dir does not exist: $wdir" && exit 1
[ ! -f "$wdir/${n}-flows.shp" ] && echo "ERROR: Flowline shp does not exist: $wdir/${n}-flows.shp" && exit 1
[ ! -f "$wdir/${n}hand.tif" ] && echo "ERROR: HAND raster does not exist: $wdir/${n}hand.tif" && exit 1
tdir=/tmp
[ -d "/scratch/$PBS_JOBID" ] && tdir=/scratch/$PBS_JOBID

cd $tdir
echo "ogr2ogr -t_srs $dsnhdepsg $tdir/flows.shp $wdir/${n}-flows.shp"
ogr2ogr -t_srs $dsnhdepsg $tdir/${n}flows.shp $wdir/${n}-flows.shp
## query catchment polygons
lname="'${n}flows.shp'.${n}flows"
l1=${n}flows
l2=Catchment
t1=`date +%s`
# ogr2ogr way: TOO SLOW. it works, though
# [ ! -f $wdir/${n}_catch.sqlite ] && ogr2ogr -t_srs $dsepsg -f SQLite -overwrite -sql "SELECT $l1.COMID AS COMID, $l1.REACHCODE AS REACHID, $l2.Shape_Length AS ShpLen, $l2.Shape_Area AS ShpArea, $l2.AreaSqKM as AreaSqKM from $l2 INNER JOIN $lname ON $l2.FEATUREID=$l1.COMID " $wdir/${n}_catch.sqlite $dsnhdplus

# specialized INNER JOIN using fast python hash on COMID in flowline layer
echo "python $sdir/catchShapeByHUC.py $n $tdir/${n}flows.shp $l1 COMID $dsnhdplus $l2 $wdir"
[ ! -f $wdir/${n}_catch.sqlite ] && python $sdir/catchShapeByHUC.py $n $tdir/${n}flows.shp $l1 COMID $dsnhdplus $l2 $wdir
t2=`date +%s`
echo "TIME query_catchment_polygons `expr $t2 \- $t1`"

## rasterize
t1=`date +%s`
echo "read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}hand.tif) && gdal_rasterize -of GTiff -co \"COMPRESS=LZW\" -co \"BIGTIFF=YES\" -a COMID -l $l2 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchmask.tif"
[ ! -f $wdir/${n}catchmask.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}hand.tif) && gdal_rasterize -of GTiff -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a COMID -l $l2 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchmask.tif
t2=`date +%s`
echo "TIME rasterize_catchment_polygons `expr $t2 \- $t1`"

