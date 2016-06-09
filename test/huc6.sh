#!/bin/bash
# submit huc6 HAND jobs
listfile="./list.HUC6" # list of huc6 IDs
rwdir=/gpfs_scratch/nfie/HUC6 # root working dir
scriptdir="./HUC6-scripts"
comprofile="./huc6-timing.csv"
mkdir -p $scriptdir
while read hucid
do
    jname="HUC$hucid"
    wdir=$rwdir/$hucid
    mkdir -p $wdir
    # set nnodes and walltime from previous profile 
    read hid startT walltime np<<<$(grep -e "^$hucid " $comprofile)
    [[ -z "$walltime" || $walltime -lt 3600 ]] && walltime=10800 # 3h default
    [[ -z "$np" || $np -lt 1 ]] && np=60 # 3 nodes default
    let "np/=20"
    let "walltime=$walltime / 3600 + 1"
    walltime="$walltime:00:00"
    sed -e "s|__N__|$jname|g" \
        -e "s|__RWDIR__|$rwdir|g" \
        -e "s|__NP__|$np|g" \
        -e "s|__T__|$walltime|g" \
        -e "s|__HUCID__|$hucid|g" \
        ./_handbyhuc.sh > $scriptdir/huc$hucid.sh
done<$listfile
