#!/bin/bash
qsubdir=/projects/nfie/nfie-floodmap/test/HUC6-inunmap-scripts
[ ! -d $qsubdir ] && mkdir -p $qsubdir && setfacl -m u:gisolve:rwx $qsubdir
logdir=/projects/nfie/nfie-floodmap/test/HUC6-inunmap-logs
[ ! -d $logdir ] && mkdir -p $logdir && setfacl -m u:gisolve:rwx $logdir
sdir=/projects/nfie/nfie-floodmap/test
ddir=/gpfs_scratch/nfie/users/HUC6
odir=/gpfs_scratch/nfie/users/inunmap/HUC6
fcfile=/gpfs_scratch/nfie/users/hydroprop/inun-hq-table-20161208_010000.nc
timestamp=`echo "$fcfile"|awk -F'-' '{print $NF}'|awk -F. '{print $1}'`
for f in `ls /gpfs_scratch/nfie/users/HUC6/*.zip`
do
    hucid=`basename $f .zip`
	[ ! -f $ddir/$hucid/${hucid}hand.tif ] && continue
	[ ! -f $ddir/$hucid/${hucid}catchhuc.tif ] && continue
	[ ! -d $odir/$hucid ] && mkdir -p $odir/$hucid && setfacl -m u:gisolve:rwx $odir/$hucid
	mapfile=$odir/$hucid/${hucid}inunmap-${timestamp}.tif
	if [ -f $mapfile ]; then
		continue
	fi
    qsubfile=$qsubdir/${hucid}-${timestamp}.sh
    echo "#!/bin/bash" > $qsubfile
    echo "#PBS -N INUNMAP$hucid" >> $qsubfile
    echo "#PBS -e $logdir/$hucid-${timestamp}.stderr" >> $qsubfile
    echo "#PBS -o $logdir/$hucid-${timestamp}.stdout" >> $qsubfile
    echo "#PBS -l nodes=1:ppn=20,walltime=6:00:00" >> $qsubfile
    echo "#PBS -M yanliu@ncsa.illinois.edu" >> $qsubfile
    echo "#PBS -m be" >> $qsubfile
    echo "$sdir/forecast-map.sh $hucid $ddir/$hucid $fcfile $mapfile" >> $qsubfile
done
