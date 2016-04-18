#!/bin/bash
# submit huc6 HAND jobs
listfile="./list.HUC6" # list of huc6 IDs
rwdir=/gpfs_scratch/nfie/HUC6 # root working dir
scriptdir="./HUC6-scripts"
mkdir -p $scriptdir
while read hucid
do
    jname="HUC$hucid"
    wdir=$rwdir/$hucid
    mkdir -p $wdir
    np=3
    walltime="6:00:00" # 6 hours at most
    sed -e "s|__N__|$jname|g" \
        -e "s|__RWDIR__|$rwdir|g" \
        -e "s|__NP__|$np|g" \
        -e "s|__T__|$walltime|g" \
        -e "s|__HUCID__|$hucid|g" \
        ./_handbyhuc.sh > $scriptdir/huc$hucid.sh
done<$listfile
