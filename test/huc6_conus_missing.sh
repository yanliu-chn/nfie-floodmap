#!/bin/bash

jdir=$HOME/scratch_br/j/HUC6-scripts
odir=$HOME/scratch_br/o/hand/HUC6
huclist=./huc6_conus.csv
count=0
while read conushuc
do
  #[ -f $jdir/huc${conushuc}.sh ] && [ ! -f $odir/${conushuc}.zip ] && echo "missing ${conushuc}" && sbatch $jdir/huc${conushuc}.sh && let "count+=1"
  [ -f $jdir/huc${conushuc}.sh ] && [ ! -f $odir/${conushuc}.zip ] && echo "missing ${conushuc}" && let "count+=1"
done<$huclist
echo "missing and resubmitted $count jobs"
