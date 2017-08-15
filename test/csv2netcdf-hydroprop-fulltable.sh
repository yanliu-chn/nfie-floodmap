#!/bin/bash
source /gpfs_scratch/nfie/users/yanliu/forecast/softenv
ofile=/gpfs_scratch/nfie/users/hydroprop/hydroprop-fulltable.nc
t=`date +%s`
[ -f $ofile ] && mv $ofile `dirname $ofile`/`basename $ofile .nc`.$t.nc
time python -m memory_profiler /projects/nfie/nfie-floodmap/test/csv2netcdf-hydroprop-fulltable.py /gpfs_scratch/nfie/users/HUC6 $ofile
