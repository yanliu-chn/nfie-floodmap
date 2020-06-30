#!/bin/bash

q="high_mem_cd"

jdir=$HOME/scratch_br/j/HUC6-scripts
jbdir=$HOME/scratch_br/j/burnin/HUC6-scripts
odir=$HOME/scratch_br/o/hand/HUC6
obdir=$HOME/scratch_br/o/burnin/HUC6
huclist=./huc6_conus.csv
count=0
cutpoint=120902
#cutpoint=0
while read conushuc
do
  [ $conushuc -lt $cutpoint ] && continue
  #echo "now is $conushuc" && exit 0 # debug
  #[ -f $jdir/huc${conushuc}.sh ] && [ ! -f $odir/${conushuc}.zip ] && echo "sbatch $jdir/huc${conushuc}.sh" && sbatch $jdir/huc${conushuc}.sh && sleep 1 && let "count+=1"
  skipBurnin=1
  [ -f $jbdir/huc${conushuc}.sh ] && [ ! -f $obdir/${conushuc}.zip ] && skipBurnin=0 && jbid=`sbatch $jbdir/huc${conushuc}.sh | awk '{print $NF}'`
  sleep 1
  inQ=`squeue -p $q | grep "$jbid high_mem" | wc -l | awk '{print $NF}'`
  [ $skipBurnin -eq 0 ] && [ $inQ -ne 1 ] && echo "ERROR job submission failed on $conushuc" && exit 1 # failed
  if [ $skipBurnin -eq 0 ]; then # job dependency
    cmd="sbatch -d afterok:$jbid $jdir/huc${conushuc}.sh"
  else
    cmd="sbatch $jdir/huc${conushuc}.sh"
  fi
  [ -f $jdir/huc${conushuc}.sh ] && [ ! -f $odir/${conushuc}.zip ] && echo "sbatch $jdir/huc${conushuc}.sh" && jid=`$cmd | awk '{print $NF}'` && let "count+=1"
  echo "huc $conushuc jhand $jid <-- jburnin $jbid"
  jbid="" 
  jid="" 
  sleep 1
done<$huclist
echo "submitted $count job pairs"
