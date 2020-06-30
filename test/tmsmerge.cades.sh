#!/bin/bash
#SBATCH -J tmsmerge
#SBATCH -A birthright
##SBATCH -p gpu
#SBATCH -p high_mem_cd
#SBATCH -N 1 
#SBATCH -n 4
#SBATCH -c 1
#SBATCH -t 24:00:00
#SBATCH --mem=128g
#SBATCH -o /home/yxl/scratch_br/log/%x.stdout
#SBATCH -e /home/yxl/scratch_br/log/%x.stderr
#SBATCH --mail-type BEGIN,FAIL,END,TIME_LIMIT
#SBATCH --mail-user yxl@ornl.gov

# calling tmsmerge.py to merge huc6 TMS tiles to CONUS
# Author: Yan Liu <yanliu@ornl.gov>

t1=`date +%s`

# env
source $HOME/sw/softenv

sdir=$HOME/nfie-floodmap/test
tmssrc=$HOME/scratch_br/test/huc6tms
tmsdst=$HOME/data/HANDTMS/v0.2
mkdir -p $tmsdst
tdir=/dev/shm
tmpsrc=$tdir/tmssrc
mkdir -p $tmpsrc
tmpdst=$tdir/conus
mkdir -p $tmpdst

log=$HOME/scratch_br/log/handtmsmerge.log

# unzip HUC6 TMS zips
cd $tmpsrc
for f in `ls $tmssrc/*.zip`
do
  unzip -q $f
done

# tmsmerge.py
python $sdir/tmsmerge.py $tmpsrc $tmpdst 5 12 >$log

# transfer to persistent storage
cd $tmpdst
tar cf $tdir/conus.tar *
cd $tmsdst
tar xf $tdir/conus.tar

# cleanup
rm -fr $tmpsrc
rm -fr $tmpdst
rm -f $tdir/conus.tar

t2=`date +%s`
echo "processing log: $log"
echo "=TIME= `expr $t2 \- $t1` seconds total processing time"
