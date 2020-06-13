#!/bin/bash
## huc6tms: create Height Above Nearest Drainage raster TMS Tile Map Service titles
## called by srun in SLURM to get cluster env such as process id
## version: v0.2
## Author: Yan Y. Liu
## Date: 05/13/2020

t1=`date +%s`

# env setup
source /srv/sw/softenv
m=oramd
sdir=/srv/nfie-floodmap/test
source $sdir/handbyhuc.${m}.env

huc=HUC6
#ddir=$HOME/data/HAND/current
ddir=$HOME/data/HAND/20200601
#odir=$HOME/scratch_br/test/huc6tms
odir=/srv/o/huc6tms_20200601
tdir=/dev/shm
todir=$tdir/tms
[ ! -d $odir ] && mkdir -p $odir

colorfile=$sdir/HAND-blues.clr
rastermetatool=$sdir/getRasterInfo.py
#prj="geodetic" 
prj="mercator"

# get list of HUC6 HAND files in zip
#dataarray=(`ls $ddir/*.zip | head -n 4`)
#dataarray=(`ls $ddir/*.zip`)
# border units to be clipped
huctoclip="040900 090300 040101 090203 171100 150301 181002 150801 150802 150503 150502 150803 130302 130301 130401 130402 130800 130900 041503 041505"
huctoclip_hand=""
for huc in huctoclip
do
  huctoclip_hand="$huctoclip_hand $ddir/$huc.zip"
done
dataarray=($huctoclip_hand)

# calc local workload
numtasks=${#dataarray[@]}
#numtasks=2 # debug
numprocs=$SLURM_NPROCS #num of processors
numlast=$((numtasks % numprocs))  # remaining
numlocal=$((numtasks / numprocs)) # num of items to process locally
starti=$((SLURM_PROCID * numlocal + numlast))
if [ $SLURM_PROCID -lt $numlast ]; then # take extra
  starti=$((SLURM_PROCID * (numlocal + 1)))
  let "numlocal+=1"
fi
echo "[$SLURM_PROCID] `date +%s`: starti: $starti numlocal: $numlocal total:$numtasks nnodes=$SLURM_NNODES numprocs=$SLURM_NPROCS onnode=$SLURM_NODEID"

## debug
#sleep $((RANDOM%5))
#exit 0

i=$starti
let "endi=starti+numlocal"
while [ $i -lt $endi ]
do
  [ $i -ge $numtasks ] && continue # debug
  f=${dataarray[$i]}
  n=`basename $f .zip`
  [ -f $odir/${n}.zip ] && let "i+=1" && continue # skip if output exists

  echo "[$SLURM_PROCID] processing HUC6 $n ..."
  # unzip hand
  hand=$n/${n}hand.tif
  colordd=$n/${n}clr.tif
  tmsdir=$todir/$n
  mkdir -p $tmsdir
  cd $tdir
  unzip -q $f $hand
  # crop DEM on conus land border: get a clipping polygon - intersect conus and huc wbd
  # crop DEM on conus land border: crop: gdalwarp  -cutline ~/data/states/conus_us.shp -cl conus_us -of "GTiff" -overwrite -co "BIGTIFF=YES" 090300hand.tif ${n}conus.tif

  # create color relief
  gdaldem color-relief $hand $colorfile $colordd -of GTiff -alpha 
  # create TMS tiles: having -a 0,0,0 causes nodata filled with color
  #$sdir/gdal2tiles_cfim.py -e -z 5-12 -a 0,0,0 -p $prj -s epsg:4326 -r bilinear -w openlayers -u https://cfim.ornl.gov/data/tms/$n -t "HAND Raster - HUC $n (v0.2)" $colordd $tmsdir 
  $sdir/gdal2tiles_cfim.py -e -z 5-12 -p $prj -s epsg:4326 -r bilinear -w openlayers -u https://cfim.ornl.gov/data/tms/$n -t "HAND Raster - HUC $n (v0.2)" $colordd $tmsdir 
  # get extent metadata
  read fsizeDEM colsDEM rowsDEM nodataDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $rastermetatool $hand) && echo "$xmin $ymin $xmax $ymax" > $tmsdir/extent.txt
  # copy and clean up
  cd $todir
  echo "==SIZE== $n `du -smc $n | tail -n 1`"
  zip -q -r $odir/${n}.zip $n
  rm -fr $tdir/$n
  rm -fr $tmsdir

  let "i+=1"
done 

t2=`date +%s`
echo "[$SLURM_PROCID] =STAT= `expr $t2 \- $t1` seconds in total"
