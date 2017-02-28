#!/bin/bash
rdir=/gpfs_scratch/nfie/users/inunmap/TMS

echo "+================================+"
echo "+===Merging HUC6 TMS Tiles  =====+"
echo "+================================+"
#construct machine file
pbs_nodefile=$PBS_NODEFILE
hlist=`sort -u $PBS_NODEFILE`
hnum=`sort -u $PBS_NODEFILE|wc|awk '{print $1}'`
jnum=`wc $PBS_NODEFILE|awk '{print $1}'`
numjobs=$jnum
machinefile=$PBS_NODEFILE
echo "GNU PARALLEL: $numjobs jobs on $hnum hosts: $hlist"
jdir=/gpfs_scratch/nfie/gnuparallel
ddir=$jdir
cmdfile=$jdir/tms-tilemerge-`date +%s`.cmd 
jcount=0

#timestamplist="20170118_160000 20170118_170000 20170118_180000 20170118_190000 20170118_200000 20170118_210000 20170118_220000 20170118_230000 20170119_000000 20170119_010000 20170119_020000"
#timestamplist="20170119_030000 20170119_040000 20170119_050000 20170119_060000 20170119_070000"
#timestamplist="20170119_020000 20170119_030000 20170119_040000 20170119_050000 20170119_060000 20170119_070000 20170119_080000 20170119_090000 20170119_100000 20170119_110000 20170119_120000 20170119_130000 20170119_140000 20170119_150000 20170119_160000"
timestamplist="$1"
init_timestamp="$2"

module purge
module load parallel gdal2-stack

tcount=0
# calc mercator outmost bbox
minx=100000000 
miny=100000000 
maxx=-100000000
maxy=-100000000
bboxdone=0

for timestamp in $timestamplist
do

idir=$rdir/HUC6-mercator-at-${init_timestamp}-for-${timestamp}
if [ $bboxdone -eq 0 ]; then
	for d in `ls $idir`; do
		extfile=$idir/$d/extent.txt
		[ ! -f $extfile ] && continue
		read llx lly urx ury<<<$(head -n 1 $extfile)
		read x1 y1 z<<<$(echo "$llx $lly"|gdaltransform -s_srs epsg:4326 -t_srs epsg:3857)
		read x2 y2 z<<<$(echo "$urx $ury"|gdaltransform -s_srs epsg:4326 -t_srs epsg:3857)
#echo "$d $x1 $y1 $x2 $y2"
		[ `echo "$x1 < $minx" | bc -l` -gt 0 ] && minx="$x1"
		[ `echo "$y1 < $miny" | bc -l` -gt 0 ] && miny="$y1"
		[ `echo "$x2 > $maxx" | bc -l` -gt 0 ] && maxx="$x2"
		[ `echo "$y2 > $maxy" | bc -l` -gt 0 ] && maxy="$y2"
	done
	bboxdone=1
fi
odir=$rdir/CONUS-mercator-at-${init_timestamp}-for-${timestamp}
[ ! -d $odir ] && mkdir -p $odir
[ -d $odir/5 ] && echo "Merged dir $odir exists, skipping ..." && continue
echo "python /projects/nfie/nfie-floodmap/test/tmsmerge.py $idir $odir  5 12 "
#time python /projects/nfie/nfie-floodmap/test/tmsmerge.py $idir $odir  5 12 >/gpfs_scratch/nfie/users/yanliu/forecast/test/viz/inunmapviz-conus-singlelayer-tilemerge-$timestamp.log 2>&1
echo "python /projects/nfie/nfie-floodmap/test/tmsmerge.py $idir $odir  5 12 ">>$cmdfile
let "tcount+=1"
let "jcount+=1"
done
echo "$tcount timestamps identified for tilemerge"

[ $jcount -eq 0 ] && echo "Nothing to do, done." && exit 0

## run gnu parallel
export PARALLEL="--env PATH --env LD_LIBRARY_PATH --env PYTHONPATH"
t1=`date +%s`
echo "parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile"
parallel --env PATH --env LD_LIBRARY_PATH --env PYTHONPATH --jobs $numjobs --sshloginfile $machinefile --joblog $jdir/`basename $cmdfile`.log --workdir $ddir <$cmdfile
t2=`date +%s`
echo "=tms-tilemerge= `expr $t2 \- $t1` seconds in total"

# create viz config json
vizconfigdir=/gpfs_scratch/nfie/users/yanliu/viz
vizjson=inunmap_${init_timestamp}.json
url="http://nfie.roger.ncsa.illinois.edu/nfiedata/maps/maps.html#source=..%2Fyanliu%2Fviz%2F${vizjson}&extent=${minx}_${miny}_${maxx}_${maxy}"
vf=$vizconfigdir/$vizjson
echo "{">$vf
echo "  \"layers\": [">>$vf
for t in $timestamplist; do
	echo "    {">>$vf
	echo "      \"id\": \"${t}\",">>$vf
	echo "      \"title\": \"${t}UTC\",">>$vf
	echo "      \"zIndex\": 1,">>$vf
	echo "      \"visible\": false,">>$vf
	echo "      \"opacity\": 1,">>$vf
	echo "      \"extent\": [$minx, $miny, $maxx, $maxy],">>$vf
	echo "      \"source\": {">>$vf
	echo "        \"type\": \"XYZ\",">>$vf
	echo "        \"options\": {">>$vf
	echo "          \"url\": \"http:\/\/nfie.roger.ncsa.illinois.edu\/nfiedata\/inunmap/TMS\/CONUS-mercator-at-${init_timestamp}-for-${t}\/{z}\/{x}\/{-y}.png\",">>$vf
	echo "          \"projection\": \"EPSG:3857\",">>$vf
	echo "          \"minZoom\": 5,">>$vf
	echo "          \"maxZoom\": 12">>$vf
	echo "        }">>$vf
	echo "      }">>$vf
	echo "    },">>$vf
done
echo "    {">>$vf
echo "      \"id\": \"osm\",">>$vf
echo "      \"title\": \"OpenStreetMap\",">>$vf
echo "      \"zIndex\": 0,">>$vf
echo "      \"visible\": true,">>$vf
echo "      \"opacity\": 1,">>$vf
echo "      \"source\": {">>$vf
echo "        \"type\": \"OSM\",">>$vf
echo "        \"options\": {}">>$vf
echo "      }">>$vf
echo "    }">>$vf
echo "  ],">>$vf
echo "  \"extent\": [$minx, $miny, $maxx, $maxy],">>$vf
echo "  \"projection\": \"EPSG:3857\"">>$vf
echo "}">>$vf

echo "TMS Visualization URL: $url"
