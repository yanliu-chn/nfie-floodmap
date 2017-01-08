#!/bin/bash
rdir=/gpfs_scratch/nfie/users/inunmap/TMS
#idir=$rdir/HUC6-mercator-20161208_010000
#idir=$rdir/HUC6-mercator-20161208_010000-3color
idir=$rdir/HUC6-mercator-20161208_010000-1color
#odir=$rdir/CONUS-mercator-20161208_010000
#odir=$rdir/CONUS-mercator-20161208_010000-3color
odir=$rdir/CONUS-mercator-20161208_010000-1color
[ ! -d $odir ] && mkdir -p $odir
time python /projects/nfie/nfie-floodmap/test/tmsmerge.py $idir $odir  5 10 >/gpfs_scratch/nfie/users/yanliu/forecast/test/viz/inunmapviz-conus-singlelayer-tilemerge.log 2>&1
