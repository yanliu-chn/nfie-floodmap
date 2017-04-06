#!/bin/bash
# clean up oneforecast data.
# Yan Y. Liu <yanliu@illinois.edu>
# 02/07/2017
if [ $# -ne 6 ]; then
	echo -e "## clean fcnc\tfcmap\ttmshuc\ttmsconus"
	echo -e "day time 1|0\t1|0\t1|0\t1|0"
	exit 1
fi
day=$1
t=$2
rdir=/gpfs_scratch/nfie/users
rdir_fc=$rdir/hydroprop/$day
rdir_inunmap=$rdir/inunmap/HUC6
rdir_tmshuc=$rdir/inunmap/TMS

init_timestamp="${day}_$t"

## clean forecast tables
if [ $3 -eq 1 ]; then
	echo "******* clean forecast tables ******"
	echo "Pattern: $rdir_fc/inun-hq-table-at-${day}_${t}*"
	for f in `ls $rdir_fc/inun-hq-table-at-${day}_${t}*`
	do
		rm -f $f && echo "rm -f $f"
	done
fi
## clean forecast maps
if [ $4 -eq 1 ]; then
	echo "******* clean forecast maps ******"
	echo "Pattern: $rdir_inunmap/{HUCID}/{HUCID}inunmap-at-${day}_${t}*.tif"
	for d in `ls $rdir_inunmap`
	do
		[ ! -d $rdir_inunmap/$d ] && continue
		echo "[dir] $d :"
		for f in `ls $rdir_inunmap/$d/${d}inunmap-at-${day}_${t}*.tif`
		do
			rm -f $f && echo "rm -f $f"
		done
	done
fi
## clean huc TMS tiles
if [ $5 -eq 1 ]; then
	echo "******* clean huc TMS tiles ******"
	echo "Pattern: $rdir_tmshuc/HUC6-mercator-at-${day}_${t}*"
	rm -fr $rdir_tmshuc/HUC6-mercator-at-${day}_${t}* && echo "rm -fr $rdir_tmshuc/HUC6-mercator-at-${day}_${t}*"
fi
## clean conus TMS tiles
if [ $6 -eq 1 ]; then
	echo "******* clean conus TMS tiles ******"
	echo "Pattern: $rdir_tmshuc/CONUS-mercator-at-${day}_${t}*"
	rm -fr $rdir_tmshuc/CONUS-mercator-at-${day}_${t}* && echo "rm -fr $rdir_tmshuc/CONUS-mercator-at-${day}_${t}*"
fi
