#!/bin/bash
qsubdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmenthucbnd-scripts
[ ! -d $qsubdir ] && mkdir -p $qsubdir
logdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmenthucbnd-logs
[ ! -d $logdir ] && mkdir -p $logdir
sdir=/projects/nfie/nfie-floodmap/test
#taudem2=/gpfs_scratch/taudem/TauDEM-CatchHydroGeo/
ddir=/gpfs_scratch/nfie/users/HUC6
for f in `ls /gpfs_scratch/nfie/users/HUC6/*.zip`
do
    hucid=`basename $f .zip`
	if [ ! -f /gpfs_scratch/nfie/users/HUC6/$hucid/${hucid}_catch.sqlite ]; then
		continue
	fi
    qsubfile=$qsubdir/$hucid.sh
    echo "#!/bin/bash" > $qsubfile
    echo "#PBS -N CATCH$hucid" >> $qsubfile
    echo "#PBS -e $logdir/$hucid.stderr" >> $qsubfile
    echo "#PBS -o $logdir/$hucid.stdout" >> $qsubfile
    echo "#PBS -l nodes=1:ppn=20,walltime=6:00:00" >> $qsubfile
    echo "#PBS -M yanliu@ncsa.illinois.edu" >> $qsubfile
    echo "#PBS -m be" >> $qsubfile
    echo "$sdir/catchmentmaskbyhucbnd.sh $hucid $ddir/$hucid" >> $qsubfile
done
