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
stageconf=$3
np=20 # for no reason, after module purge, PBS_NP becomes 1
[ -z "$stageconf" ] && stageconf=$sdir/stage.txt
[ ! -f $stageconf ] && echo "ERROR: stage config not exist $stageconf" && exit 1
echo "using stage config $stageconf"
[ ! -d $wdir ] && echo "ERROR: work dir does not exist: $wdir" && exit 1
[ ! -f "$wdir/${n}-flows.shp" ] && echo "ERROR: Flowline shp does not exist: $wdir/${n}-flows.shp" && exit 1
[ ! -f "$wdir/${n}dd.tif" ] && echo "ERROR: HAND raster does not exist: $wdir/${n}dd.tif" && exit 1 # use dd.tif to have same dim with slp.tif for hydroprop calc
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
echo "read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}dd.tif) && gdal_rasterize -of GTiff -co \"TILED=YES\" -co \"COMPRESS=LZW\" -co \"BIGTIFF=YES\" -a COMID -l $l2 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchmask.tif"
[ ! -f $wdir/${n}catchmask.tif ] && read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfoNative.py $wdir/${n}dd.tif) && gdal_rasterize -of GTiff -co "TILED=YES" -co "COMPRESS=LZW" -co "BIGTIFF=YES" -a COMID -l $l2 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax -ot Int32 -a_nodata 0 $wdir/${n}_catch.sqlite $wdir/${n}catchmask.tif
t2=`date +%s`
echo "TIME rasterize_catchment_polygons `expr $t2 \- $t1`"

## hydro property calculation
t1=`date +%s`
taudem2=/gpfs_scratch/taudem/TauDEM-CatchHydroGeo
module purge
module load MPICH gdal2-stack GCC/4.9.2-binutils-2.25 python/2.7.10 pythonlibs/2.7.10
echo "mpirun -np $np $taudem2/catchhydrogeo -hand $wdir/${n}dd.tif -catch $wdir/${n}catchmask.tif -catchlist $wdir/${n}_comid.txt -slp $wdir/${n}slp.tif -h $stageconf -table $wdir/hydroprop-basetable-${n}.csv"
[ ! -f $wdir/hydroprop-basetable-${n}.csv ] && mpirun -np $np $taudem2/catchhydrogeo -hand $wdir/${n}dd.tif -catch $wdir/${n}catchmask.tif -catchlist $wdir/${n}_comid.txt -slp $wdir/${n}slp.tif -h $stageconf -table $wdir/hydroprop-basetable-${n}.csv
## addon hydro properties 
echo "python $sdir/hydraulic_property_postprocess.py $wdir/hydroprop-basetable-${n}.csv 0.05 $wdir/hydroprop-fulltable-${n}.csv"
[ ! -f $wdir/hydroprop-fulltable-${n}.csv ] && python $sdir/hydraulic_property_postprocess.py $wdir/hydroprop-basetable-${n}.csv 0.05 $wdir/hydroprop-fulltable-${n}.csv
t2=`date +%s`
echo "TIME hydroprop `expr $t2 \- $t1`"


