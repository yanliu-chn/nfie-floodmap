#!/bin/bash
#SBATCH -J handtms
#SBATCH -A birthright
##SBATCH -p gpu
#SBATCH -p high_mem_cd
#SBATCH -N 1
#SBATCH -n 32
#SBATCH -c 1
#SBATCH -t 12:00:00
#SBATCH --mem=128g
#SBATCH -o /home/yxl/scratch_br/log/%x.stdout
#SBATCH -e /home/yxl/scratch_br/log/%x.stderr
#SBATCH --mail-type BEGIN,FAIL,END,TIME_LIMIT
#SBATCH --mail-user yxl@ornl.gov

## mimic slurm, but on oramd, we run it w/o job scheduler
#srun $HOME/nfie-floodmap/test/huc6tms.cades.sh

m=oramd

cmd=/srv/nfie-floodmap/test/huc6tms.${m}.sh
log=/srv/log/handtms

np=32
t1=`date +%s`
for i in `seq 0 $((np-1))`
do
  SLURM_PROCID=$i SLURM_NPROCS=$np SLURM_NODEID=localhost SLURM_NNODES=1 $cmd >$log.$i.log 2>&1 & 
done
wait
t2=`date +%s`
echo "==STAT== TOTAL TIME `expr $t2 \- $t1` seconds"
