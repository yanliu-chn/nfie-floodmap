#!/bin/bash
qsubdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmentmask-scripts
logdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmentmask-logs
sdir=/projects/nfie/nfie-floodmap/test
#taudem2=/gpfs_scratch/taudem/TauDEM-CatchHydroGeo/
ddir=/gpfs_scratch/nfie/users/HUC6
for f in `ls /gpfs_scratch/nfie/users/HUC6/*.zip`
do
    hucid=`basename $f .zip`
    qsubfile=$qsubdir/$hucid.sh
    echo "#!/bin/bash" > $qsubfile
    echo "#PBS -N CATCH$hucid" >> $qsubfile
    echo "#PBS -e $logdir/$hucid.stderr" >> $qsubfile
    echo "#PBS -o $logdir/$hucid.stdout" >> $qsubfile
    echo "#PBS -l nodes=1:ppn=20,walltime=12:00:00" >> $qsubfile
    echo "#PBS -M yanliu@ncsa.illinois.edu" >> $qsubfile
    echo "#PBS -m be" >> $qsubfile
    echo "$sdir/catchmentmaskbyhuc.sh $hucid $ddir/$hucid" >> $qsubfile
#    echo "t1=\`date +%s\`" >> $qsubfile
#    echo "module purge" >> $qsubfile
#    echo "module load MPICH gdal2-stack GCC/4.9.2-binutils-2.25 python/2.7.10 pythonlibs/2.7.10" >> $qsubfile
#
#    echo "mpirun -np \$PBS_NP $taudem2/catchhydrogeo -hand $ddir/${hucid}/${hucid}dd.tif -catch $ddir/${hucid}/${hucid}catchmask.tif -catchlist $ddir/${hucid}/${hucid}_comid.txt -slp $ddir/${hucid}/${hucid}slp.tif -h $sdir/stage.txt -table $ddir/${hucid}/hydropropotable-${hucid}-\${PBS_NP}.txt" >> $qsubfile
#    echo "t2=\`date +%s\`" >> $qsubfile
#    echo "ttaudem=\`expr \$t2 \\- \$t1\`" >> $qsubfile
#    echo "echo \"TIME taudem_catchhydrogeo \$ttaudem\"" >> $qsubfile
done
