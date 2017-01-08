#!/bin/bash
qsubdir=/projects/nfie/nfie-floodmap/test/HUC6-waterbody-scripts
[ ! -d $qsubdir ] && mkdir -p $qsubdir && setfacl -m u:gisolve:rwx $qsubdir
logdir=/projects/nfie/nfie-floodmap/test/HUC6-waterbody-logs
[ ! -d $logdir ] && mkdir -p $logdir && setfacl -m u:gisolve:rwx $logdir
sdir=/projects/nfie/nfie-floodmap/test
ddir=/gpfs_scratch/nfie/users/HUC6
c=0
for f in `ls /gpfs_scratch/nfie/users/HUC6/*.zip`
do
    hucid=`basename $f .zip`
	[ ! -f $ddir/$hucid/${hucid}catchmask.tif ] && continue
    qsubfile=$qsubdir/${hucid}.sh
    echo "#!/bin/bash" > $qsubfile
    echo "#PBS -N waterbody$hucid" >> $qsubfile
    echo "#PBS -e $logdir/$hucid.stderr" >> $qsubfile
    echo "#PBS -o $logdir/$hucid.stdout" >> $qsubfile
    echo "#PBS -l nodes=1:ppn=20,walltime=24:00:00" >> $qsubfile
    echo "#PBS -M yanliu@ncsa.illinois.edu" >> $qsubfile
    echo "#PBS -m be" >> $qsubfile
    echo "$sdir/waterbodymaskbyhuc.sh $hucid $ddir/$hucid" >> $qsubfile
	let "c+=1"
done
echo "$c job submission scripts created in $qsubdir"
