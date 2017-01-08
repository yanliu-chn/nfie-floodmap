#!/bin/bash
# calc inundation map raster from HAND, comid mask raster, and forecast netcdf
# Yan Y. Liu <yanliu@illinois.edu>, 01/03/2017

## input
hucid=$1
n=$hucid
hucquerypre=`echo $hucid | cut -b 1-8`
wdir=$2
fcfile=$3
timestamp=`echo "$fcfile"|awk -F'-' '{print $NF}'|awk -F. '{print $1}'`
mapfile=$4
np=1 # set np=20 after taudem issue on diff np diff result is resolved
[ ! -d $wdir ] && echo "ERROR: work dir does not exist: $wdir" && exit 1
[ ! -f "$wdir/${n}catchhuc.tif" ] && echo "ERROR: catchmen mask raster does not exist: $wdir/${n}catchhuc.tif" && exit 1
[ ! -f "$wdir/${n}hand.tif" ] && echo "ERROR: HAND raster does not exist: $wdir/${n}hand.tif" && exit 1 
[ ! -f "$wdir/${n}waterbodymask.tif" ] && echo "ERROR: waterbody mask raster does not exist: $wdir/${n}waterbodymask.tif" && exit 1 
[ ! -f "$fcfile" ] && echo "ERROR: forecast netcdf does not exist: $fcfile" && exit 1 

t1=`date +%s`
taudem2=/gpfs_scratch/taudem/TauDEM-CatchHydroGeo
module purge
module load MPICH gdal2-stack GCC/4.9.2-binutils-2.25 python/2.7.10 pythonlibs/2.7.10
echo "mpirun -np $np $taudem2/inunmap -hand $wdir/${n}hand.tif -catch $wdir/${n}catchhuc.tif -mask $wdir/${n}waterbodymask.tif -forecast $fcfile -mapfile $mapfile"
[ ! -f $mapfile ] && mpirun -np $np $taudem2/inunmap -hand $wdir/${n}hand.tif -catch $wdir/${n}catchhuc.tif -mask $wdir/${n}waterbodymask.tif -forecast $fcfile -mapfile $mapfile

