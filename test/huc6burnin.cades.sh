#!/bin/bash
# submit huc6 HAND jobs
listfile="huc6_conus.csv" # list of huc6 IDs
rwdir=/lustre/or-hydra/cades-birthright/yxl/o/burnin/HUC6 # root working dir
ldir=/dev/shm # local mem fs, half of physical mem 
scriptdir="/lustre/or-hydra/cades-birthright/yxl/j/burnin/HUC6-scripts"
logdir="/lustre/or-hydra/cades-birthright/yxl/log/burnin/HUC6"
comprofile="./huc6-timing.csv"
m=cades
nn=1 # to use local ssd or /dev/shm, we can only use 1 node for now
mkdir -p $scriptdir
mkdir -p $logdir
mkdir -p $rwdir
while read hucid
do
    jname="bi$hucid"
    #wdir=$rwdir/$hucid
    #mkdir -p $rwdir/$hucid
    # set nnodes and walltime from previous profile 
    read hid startT walltime np<<<$(grep -e "^$hucid " $comprofile)
    [[ -z "$np" || $np -eq 0 ]] && np=20
    [[ -z "$walltime" || $walltime -lt 3600 ]] && walltime=3600 # set min hr
    #[[ -z "$np" || $np -lt 1 ]] && np=60 # 3 nodes default
    let "np/=20"
    #let "walltime=$walltime * $np / 3600 + 10"
    let "walltime=$walltime * $np / 3600 + 15"
    [ $walltime -gt 336 ] && walltime=336 # set max walltime
    # real np
    np=32
    walltime="$walltime:00:00"
    sed -e "s|__N__|$jname|g" \
        -e "s|__RWDIR__|$rwdir|g" \
        -e "s|__LDIR__|$ldir|g" \
        -e "s|__NP__|$np|g" \
        -e "s|__NN__|$nn|g" \
        -e "s|__T__|$walltime|g" \
        -e "s|__HUCID__|$hucid|g" \
        -e "s|__LOGDIR__|$logdir|g" \
        ./_handbyhuc-burnin.${m}.sh >$scriptdir/huc$hucid.sh

    unset walltime
done<$listfile
