#!/bin/bash
umask 002

# calc inundation forecast for one single NWM short-range forecast

srdir=/gpfs_scratch/nfie/users/yanliu/forecast/houston20170118
sdir=/projects/nfie/nfie-floodmap/test
##url ex: http://nomads.ncep.noaa.gov/pub/data/nccf/com/nwm/prod/nwm.20170118/short_range/nwm.t23z.short_range.channel_rt.f001.conus.nc.gz
##url example: http://thredds.hydroshare.org/thredds/fileServer/nwm/nomads/nwm.20170120/short_range/nwm.t14z.short_range.channel_rt.f015.conus.nc.gz
day=$1 # ex: 20170118
fcgen_tag=$2 # ex: t23z
[ -z "$day" ] && echo "Usage: specify day in YYYYMMDD format" && exit 1
[ -z "$fcgen_tag" ] && echo "Usage: specify forecast generation tag, eg., t23z" && exit 1

range="short_range"
fctype="channel_rt"
fcdir=/projects/nfie/nwm-forecast/$day
#[ ! -d $fcdir ] && fcdir=/scratch/$PBS_JOBID
[ ! -d $fcdir ] && mkdir -p $fcdir

module purge
module load parallel gdal2-stack

## download data
echo "+================================+"
echo "+===Downloading NWM Forecast=====+"
echo "+================================+"
[ ! -d $fcdir ]  && mkdir -p $fcdir/
fcfilelist=""
for fchour in f001 f002 f003 f004 f005 f006 f007 f008 f009 f010 f011 f012 f013 f014 f015; do
	fcfile=nwm.${fcgen_tag}.${range}.${fctype}.${fchour}.conus.nc
	if [ ! -f $fcdir/$fcfile ]; then
#		wget --no-verbose http://nomads.ncep.noaa.gov/pub/data/nccf/com/nwm/prod/nwm.${day}/${range}/${fcfile}.gz -O $fcdir/${fcfile}.gz
		wget --no-verbose http://thredds.hydroshare.org/thredds/fileServer/nwm/nomads/nwm.${day}/${range}/${fcfile}.gz -O $fcdir/${fcfile}.gz
		gunzip $fcdir/${fcfile}.gz
	fi
	fcfilelist="$fcfilelist $fcfile"
done

timestamplist=""
for fcfile in $fcfilelist; do
	init_timestamp=`ncdump -h $fcdir/$fcfile |grep model_initialization_time |awk -F'"' '{print $2}'|sed -e "s/\-//g" -e "s/://g"`
	timestamp=`ncdump -h $fcdir/$fcfile |grep model_output_valid_time|awk -F'"' '{print $2}'|sed -e "s/\-//g" -e "s/://g"`
	timestamplist="$timestamplist $timestamp"
	echo "fcfile: $fcfile $init_timestamp $timestamp"
done

## calc worst scenario anomaly map
. `dirname $0`/../softenv
fcworst="worstscenario.$day.${fcgen_tag}.$range.$fctype.conus.nc"
[ ! -f $fcdir/$fcworst ] && python $sdir/forecast-nwm-worst.py $fcdir "$fcfilelist" $fcdir/$fcworst
fcfilelist="$fcfilelist $fcworst"
## calc forecast table
$srdir/forecast-table.sh $fcdir "$fcfilelist" "$day"

## create inun maps for specified HUC6 units
hucidlist="120401 120402 120903 120904 120701 121001 121004" # houston
#hucidlist="180701 180702 180703 181001 181002" # san diego
#hucidlist="010100 010200 010300 010400 010500 010600 010700 010801 010802 010900 011000 020200 020301 020302 020401 020402 020403 020501 020502 020503 020600 020700 020801 020802 030101 030102 030201 030202 030203 030300 030401 030402 030501 030502 030601 030602 030701 030702 030801 030802 030901 030902 031001 031002 031101 031102 031200 031300 031401 031402 031403 031501 031502 031601 031602 031700 031800 040101 040102 040103 040201 040202 040301 040302 040400 040500 040601 040700 040801 040802 040900 041000 041100 041201 041300 041401 041402 041501 041503 041504 041505 050100 050200 050301 050302 050400 050500 050600 050701 050702 050800 050901 050902 051001 051002 051100 051201 051202 051301 051302 051401 051402 060101 060102 060200 060300 060400 070101 070102 070200 070300 070400 070500 070600 070700 070801 070802 070900 071000 071100 071200 071300 071401 071402 080101 080102 080201 080202 080203 080204 080301 080302 080401 080402 080403 080500 080601 080602 080701 080702 080703 080801 080802 080901 080902 080903 090100 090201 090202 090203 090300 090400 100200 100301 100302 100401 100402 100500 100600 100700 100800 100901 100902 101000 101101 101102 101201 101202 101301 101302 101303 101401 101402 101500 101600 101701 101702 101800 101900 102001 102002 102100 102200 102300 102400 102500 102600 102701 102702 102801 102802 102901 102902 103001 103002 110100 110200 110300 110400 110500 110600 110701 110702 110800 110901 110902 111001 111002 111003 111101 111102 111201 111202 111203 111301 111302 111303 111401 111402 111403 120100 120200 120301 120302 120401 120402 120500 120601 120602 120701 120702 120800 120901 120902 120903 120904 121001 121002 121003 121004 121101 121102 130100 130201 130202 130301 130302 130401 130402 130403 130500 130600 130700 130800 130900 140100 140200 140300 140401 140402 140500 140600 140700 140801 140802 150100 150200 150301 150302 150400 150501 150502 150503 150601 150602 150701 150702 150801 150802 150803 160101 160102 160201 160202 160203 160300 160401 160402 160501 160502 160503 160600 170101 170102 170103 170200 170300 170401 170402 170501 170502 170601 170602 170603 170701 170702 170703 170800 170900 171001 171002 171003 171100 171200 180101 180102 180200 180201 180300 180400 180500 180600 180701 180702 180703 180800 180901 180902 181001 181002" # CONUS
[ ! -z "$3" ] && hucidlist="$3"

hucidfile=/tmp/hucidfile.$RANDOM
echo "$hucidlist" > $hucidfile
fctabledir=/gpfs_scratch/nfie/users/hydroprop/$day
fctablefilelist="$fcworst"
#for f in `ls $fctabledir/inun-hq-table-at-${init_timestamp}-for-*.nc`; do
#	fctablefilelist="$fctablefilelist `basename $f`"
#done
ddir=/gpfs_scratch/nfie/users/HUC6
maprootdir=/gpfs_scratch/nfie/users/inunmap/HUC6
$srdir/forecast-map-batch.sh $hucidfile $fctabledir "$fctablefilelist" $ddir $maprootdir

## create TMS tiles for specified HUC6 units
$srdir/huc6tms-inunmap-epsg3857.sh $hucidfile "$timestamplist" $init_timestamp

## merge tiles
$srdir/tmsmerge-inunmaptest.sh "$timestamplist" $init_timestamp

## display output info
