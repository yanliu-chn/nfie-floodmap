#!/bin/bash
# create tile map service for all units
huc=HUC6
#huc=huc6tmstest
sdir=/gpfs_scratch/nfie/$huc
ddir=/gpfs_scratch/nfie/TMS/$huc
[ ! -d $ddir ] && mkdir -p $ddir
colorfile=/projects/nfie/nfie-floodmap/test/HAND-blues.clr
rastermetatool=/projects/nfie/nfie-floodmap/test/getRasterInfo.py
 
# for each unit, use gdaldem to colorize and use gdal2tiles to create TMS
for hucid in `ls $sdir`; do
    hand=$sdir/$hucid/${hucid}dd.tif
    [ ! -f $hand ] && echo "=HUC=skip $hucid HAND N/A, skip." && continue
    tmsdir=$ddir/$hucid
    [ -d $tmsdir ] && echo "=HUC=skip $hucid TMS exists, skip." && continue
    [ ! -d $tmsdir ] && mkdir -p $tmsdir
    t1=`date +%s`
    colordd=/tmp/HUCDDCOLOR$hucid.tif
    echo "=HUC=$hucid HAND colorize"
    echo "=CMD= gdaldem color-relief $hand $colorfile $colordd -of GTiff -alpha"
    gdaldem color-relief $hand $colorfile $colordd -of GTiff -alpha
    echo "=HUC=$hucid TMS"
    echo "gdal2tiles.py -e -z 5-10 -a 0,0,0 -p geodetic -s epsg:4326 -r near -w openlayers -t \"Height above Stream (HAND) Raster - HUC6 $hucid (v0.01dev)\" $colordd $tmsdir"
    gdal2tiles.py -e -z 5-10 -a 0,0,0 -p geodetic -s epsg:4326 -r near -w openlayers -t "Height above Stream (HAND) Raster - HUC6 $hucid (v0.01dev)" $colordd $tmsdir
    echo "=HUC=$hucid bounding box"
    read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $rastermetatool $hand)
    echo "$xmin $ymin $xmax $ymax" > $tmsdir/extent.txt
    t2=`date +%s`
    echo "=STAT= $hucid `expr $t2 \- $t1`"
    rm -f $colordd
done
