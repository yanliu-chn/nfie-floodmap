#!/bin/bash

fcdir=$1
[ -z $fcdir ] && fcdir=/projects/nfie/houston_20170118
fcfilelist="$2"
day="$3"

#nhddbpath=/gpfs_scratch/usgs/nhd/NFIEGeoNational.gdb #TODO: uncomment if to get anomaly shapes

echo "+================================+"
echo "+===Computing Forecast Table=====+"
echo "+================================+"
#construct machine file
pbs_nodefile=$PBS_NODEFILE
hlist=`sort -u $PBS_NODEFILE`
hnum=`sort -u $PBS_NODEFILE|wc|awk '{print $1}'`
numjobs=15
repeatnum=`expr $numjobs \/ $hnum`
machinefile=/tmp/fctable.machinefile.`date +%s`
[ -f $machinefile ] && rm -f $machinefile
for i in `seq $repeatnum`; do
	for h in $hlist; do
		echo $h >>$machinefile
	done
done
echo "GNU PARALLEL: $numjobs jobs on $hnum hosts"
cat $machinefile
jdir=/gpfs_scratch/nfie/gnuparallel
cmdfile=$jdir/forecast-table-`date +%s`.cmd 

module purge
module load parallel python/2.7.10 gdal2-stack pythonlibs/2.7.10

sdir=/projects/nfie/nfie-floodmap/test
ddir=/gpfs_scratch/nfie/users/hydroprop
odir=$ddir/$day
[ ! -d $odir ] && mkdir -p $odir
jcount=0
for fcfile in $fcfilelist; do
	init_timestamp=`ncdump -h $fcdir/$fcfile |grep model_initialization_time |awk -F'"' '{print $2}'|sed -e "s/\-//g" -e "s/://g"`
	timestamp=`ncdump -h $fcdir/$fcfile |grep model_output_valid_time|awk -F'"' '{print $2}'|sed -e "s/\-//g" -e "s/://g"`
	fctablename="inun-hq-table-at-${init_timestamp}-for-${timestamp}"
	# override if exists
	#[ -f "${fctablename}.nc" ] && rm -f $fcdir/${fctablename}.nc
	#[ -f "${fctablename}.csv" ] && rm -f $fcdir/${fctablename}.csv
	# skip if exists
	[ -f "$odir/${fctablename}.nc" ] && continue
	#TODO: uncomment to calc for the nation
	#echo "python $sdir/forecast-table.py $ddir/hydroprop-fulltable.nc $fcdir/$fcfile $odir $nhddbpath " >>$cmdfile
	echo "python $sdir/forecast-table.py /gpfs_scratch/nfie/users/yanliu/forecast/test $fcdir/$fcfile $odir $nhddbpath " >>$cmdfile
	echo "Adding ${fctablename}.nc ... " 
	let "jcount+=1"
done
[ $jcount -eq 0 ] && exit 0

## run gnu parallel
export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=forecast_table= `expr $t2 \- $t1` seconds in total"
