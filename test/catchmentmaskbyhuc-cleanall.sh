#!/bin/bash
# Clean up hydraulic property table files in all HUC6 units
# Yan Y. Liu <yanliu@illinois.edu>, 10/30/2016
rdir=/gpfs_scratch/nfie/users/HUC6
for f in `ls $rdir/*.zip`
do
    hucid=`basename $f .zip`
    wdir=$rdir/$hucid
### all
    #for f in ${hucid}catchmask.tif ${hucid}_catch.sqlite ${hucid}_comid.txt hydroprop-basetable-${hucid}.csv hydroprop-fulltable-${hucid}.csv hydropropotable-${hucid}-60.txt; do
### hydro tables only
    for f in hydroprop-basetable-${hucid}.csv hydroprop-fulltable-${hucid}.csv
    do
        [ -f $wdir/$f ] && rm $wdir/$f && echo "deleted: $wdir/$f"
    done
done
