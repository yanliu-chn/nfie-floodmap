#!/bin/bash
#SBATCH -J handtms
#SBATCH -A birthright
##SBATCH -p gpu
#SBATCH -p high_mem_cd
#SBATCH -N 2
#SBATCH -n 20
#SBATCH -c 1
#SBATCH -t 12:00:00
#SBATCH --mem=128g
#SBATCH -o /home/yxl/scratch_br/log/%x.stdout
#SBATCH -e /home/yxl/scratch_br/log/%x.stderr
#SBATCH --mail-type BEGIN,FAIL,END,TIME_LIMIT
#SBATCH --mail-user yxl@ornl.gov

srun $HOME/nfie-floodmap/test/huc6tms.cades.sh
