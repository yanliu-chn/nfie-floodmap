#!/bin/bash
qsubdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmentmask-scripts
logdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmentmask-logs
sdir=/projects/nfie/nfie-floodmap/test
ddir=/gpfs_scratch/nfie/users/HUC6
for f in `ls /gpfs_scratch/nfie/users/HUC6/*.zip`
do
    hucid=`basename $f .zip`
    qsubfile=$qsubdir/$hucid.sh
    echo "#!/bin/bash" > $qsubfile
    echo "#PBS -N CATCH$hucid" >> $qsubfile
    echo "#PBS -e $logdir/$hucid.stderr" >> $qsubfile
    echo "#PBS -o $logdir/$hucid.stdout" >> $qsubfile
    echo "#PBS -l nodes=1:ppn=20,walltime=1:00:00" >> $qsubfile
    echo "#PBS -M yanliu@ncsa.illinois.edu" >> $qsubfile
    echo "#PBS -m be" >> $qsubfile
    echo "$sdir/catchmentmaskbyhuc.sh $hucid $ddir/$hucid" >> $qsubfile
done
