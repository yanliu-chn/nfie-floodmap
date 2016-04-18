#!/bin/bash
# create tile map service for one subset of units
rastermetatool=/projects/nfie/nfie-floodmap/test/getRasterInfo.py
 
jobf=$1
sdir=$2
ddir=$3
listf=$4
logf=$5

while read hucid
do
    t1=`date +%s`
    hand=$sdir/$hucid/${hucid}dd.tif
    [ ! -f $hand ] && echo "=HUC=skip $hucid HAND N/A, skip.">>$logf && continue
    of=$ddir/${hucid}ov.tif
    [ -f $of ] && echo "=HUC=skip $hucid OVERVIEW exists, skip." >>$logf && continue
    echo "=HUC=$hucid overview" >>$logf
    read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $rastermetatool $hand)
    res=0.01098632812500 # zoom level 6
    #gdalwarp -t_srs EPSG:4326 -tr $res $res -te $xmin $ymin $xmax $ymax -of GTiff -co TILED=YES -co BLOCKXSIZE=256 -co BLOCKYSIZE=256 -r bilinear $hand $of
    gdalwarp -t_srs EPSG:4326 -tr $res $res -te $xmin $ymin $xmax $ymax -of GTiff -r cubic $hand $of >>$logf 2>&1
    rcode=$?
    t2=`date +%s`
    if [ $rcode -ne 0 ]; then
     echo "=FAILED= $hucid $of" >>$logf
    else 
        echo "$of" >>$listf
        echo "=STAT= $hucid `expr $t2 \- $t1`" >>$logf
    fi
done<$jobf
exit 0
