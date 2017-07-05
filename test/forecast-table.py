## create flood forecast table for all the COMIDs on CONUS
# Yan Y. Liu <yanliu@illinois.edu>
# 10/31/2016
# input 1: the list of hydro property lookup table for each HUC6 code
# input 2: NOAA NWM forecast data, one timestamp
# input 3: NHDPlus MR geodb, for creating georeferenced anomaly shp files
# output: an inundation table for all the COMIDs on CONUS as netcdf and csv

import sys, os, string, time, re, getopt, glob, shutil, math
import osr
import netCDF4
import numpy as np
from osgeo import gdal
from osgeo import ogr
import pandas as pd
import xarray as xr
from datetime import datetime
import csv
#import pytz

# read input NOAA NWM netcdf file
def readForecast(in_nc = None):
    global comids
    global Qs
    global h
    # open netcdf file
    rootgrp = netCDF4.Dataset(in_nc, 'r')
    intype='channel_rt'
    # metadata_dims = ['station'] # for old nwm format b4 05/2017
    metadata_dims = ['feature_id']
    dimsize = len(rootgrp.dimensions[metadata_dims[0]]) # num rows

    global_attrs={att:val for att,val in rootgrp.__dict__.iteritems()}
    timestamp_str=global_attrs['model_output_valid_time']
    timestamp = datetime.strptime(timestamp_str, '%Y-%m-%d_%H:%M:%S') # read
    #timestamp.replace(tzinfo=pytz.UTC) # set timezone 
    t = timestamp.strftime('%Y%m%d_%H%M%S') # reformat timestampe output
    init_timestamp_str=global_attrs['model_initialization_time']
    init_timestamp = datetime.strptime(init_timestamp_str, '%Y-%m-%d_%H:%M:%S') # read
    init_t = init_timestamp.strftime('%Y%m%d_%H%M%S') # reformat timestampe output

    # create attr data for COMID and flowstream attr
    # comids_ref = rootgrp.variables['station_id'] # for old format b4 05/2017
    comids_ref = rootgrp.variables['feature_id']
    Qs_ref = rootgrp.variables['streamflow']
    comids = np.copy(comids_ref) 
    Qs = np.copy(Qs_ref)

    rootgrp.close() # close netcdf file to save memory

    # check for invalid Qfc
    negCount = 0
    for i in range(Qs.size):
        if Qs[i] < 0.0:
            negCount += 1
    print "readForecast(): Warning: read " + str(negCount) + " forecasts with negative value. Will skip these COMIDs."

    # create hash table
    h = dict.fromkeys(comids)
    for i in range(0, dimsize):
        h[comids[i]] = i

    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + " Loaded " + str(len(comids)) + " stations"
    sys.stdout.flush()

    return { 'timestamp': t, 'init_timestamp': init_t}

# interpolate H forecast from the static H and Q table dervied from HAND
# assuming the ascending order to stage heights for a COMID in CSV table
def Hinterpolate(Qfc = 0.0, Hlist = [], Qlist = [], count = 0, comid = 0):
    if Qfc <= 0:
        return -9999.0
    Q1 = None
    Q1i = 0
    Q2 = None
    Q2i = 0
    for i in range(0, count): # find two Qs that can interpolate H forecast
        if Qlist[i] < Qfc: # implicitly Q1 increases
            Q1 = Qlist[i]
            Q1i = i
        if Qlist[i] >= Qfc:
            Q2 = Qlist[i]
            Q2i = i
            break
    # linear interpolation
    if Q1 is None: # Qfc falls below the range of Qs
        return Hlist[0]
    if Q2 is None: # Qfc falls beyond the range of Qs
        Q1 = Qlist[count - 2]
        Q1i = count - 2 # count has to be >=2
        Q2 = Qlist[count - 1]
        Q2i = count - 1
    if Qlist[Q2i] < 0.00000001: # stage table is wrong
        return -9999.0 # can't predict
    if abs(Q2 - Q1) < 0.000001:
        print "WARNING: discharge data flat: count=" + str(count) + " Q1="+str(Q1)+" Q2="+str(Q2) + " Qfc=" + str(Qfc)
        return Hlist[Q2i]
    
    Hfc =  (Qfc - Q1) * (Hlist[Q2i] - Hlist[Q1i]) / (Q2 - Q1) + Hlist[Q1i]
    if Hfc > 25.0: # debug
        print "DEBUG: irregular Hfc: comid=" + str(comid) + " Hfc=" + str(Hfc) + " Qfc=" + str(Qfc) + " Q1=" + str(Q1) + " Q2=" + str(Q2) + " H1=" +str(Hlist[Q1i]) + " H2=" +str(Hlist[Q2i]) + " Q1i=" + str(Q1i) + " Q2i=" + str(Q2i)
    return Hfc

def updateH(comid = 0, fccount = 0, count = 0, numHeights = 83, h = None, Qs = None, Hlist = None, Qlist = None, comidlist = None, Hfclist = None, Qfclist = None):
    if count != numHeights:
        print "Warning: COMID " + str(comid) + " has <" + str(numHeights) + " rows on hydroprop table"
    j = h[comid]
    Qfc = Qs[j]
    if Qfc > 0.0:
        Hfc = Hinterpolate(Qfc, Hlist, Qlist, count, comid)
        if Hfc > 0.0:
            comidlist[fccount] = comid
            Hfclist[fccount] = Hfc
            Qfclist[fccount] = Qfc
            return 1
    return 0

def forecastH (init_timestr = None, timestr = None, tablelist = None, numHeights = 83, huclist = None, odir = None, nhddbpath = None):
    global comids
    global Qs
    global h
    global comidlist 
    global Qfclist
    global Hfclist
    global fccount

    comidlist = np.zeros(len(comids), dtype='int64')
    Hfclist = np.zeros(len(comids), dtype='float64')
    Qfclist = np.zeros(len(comids), dtype='float64')
    fccount = 0
    missings = 0 # in hydro table but not in station hash
    nulls = 0 # null values that are not interpolated
    catchcount = 0 # count of catchments in hydro table
    for i in range(0, len(tablelist)): # scan each HUC's hydro prop table
        hpfile = tablelist[i]
        hpdata = None
        colcatchid = None # memory to store CatchId column
        colH = None # memory to store Stage column
        colQ = None # memory to store Discharge (m3s-1)/Discharge column
        filetype = hpfile.split('.')[-1]
        print hpfile + "   +++++++   " + filetype
        if filetype == 'csv':
            hpdata = pd.read_csv(hpfile)
            colcatchid = np.copy(hpdata['CatchId'])
            colH = np.copy(hpdata['Stage'])
            colQ = np.copy(hpdata['Discharge (m3s-1)'])
        elif filetype == 'nc':
            hpdata = netCDF4.Dataset(hpfile, 'r')
            colcatchid = np.copy(hpdata.variables['CatchId'])
            colH = np.copy(hpdata.variables['Stage'])
            colQ = np.copy(hpdata.variables['Discharge'])
        #TODO: error handling on unsupported file formats
        catchcount += (colcatchid.size / numHeights )
        print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + hpfile + " : " + str(colcatchid.size) + " rows "
        sys.stdout.flush()
        comid = None
        count = 0
        Hlist = np.zeros(numHeights, dtype = 'float64')
        Qlist = np.zeros(numHeights, dtype = 'float64')
        #for index, row in csvdata.iterrows(): # loop each row of the table
        for i in range(colcatchid.size):
            catchid = int(colcatchid[i]) # get comid
            if not catchid in h: # hydro table doesn't have info for this comid
                missings += 1
                continue
            if comid is None: # first iteration in the loop
                comid = catchid
            if comid != catchid : # time to interpolate
                updated = updateH(comid, fccount, count, numHeights, h, Qs, Hlist, Qlist, comidlist, Hfclist, Qfclist)
                if updated == 1:
                    fccount += 1
                else:
                    nulls += 1
                count = 0
                comid = catchid
                Hlist.fill(0)
                Qlist.fill(0)
            Hlist[count] = colH[i]
            Qlist[count] = colQ[i]
            count += 1
        # update the last comid
        if comid > 0:
            updated = updateH(comid, fccount, count, numHeights, h, Qs, Hlist, Qlist, comidlist, Hfclist, Qfclist)
            if updated == 1:
                fccount += 1
            else:
                nulls += 1
    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "Read " + str(len(comids)) + " stations from NWM, " + str(catchcount) + " catchments from hydro table. " + str(missings / numHeights) + " comids in hydro table but not in NWM. " + str(nulls) + " comids null and skipped. " + str(fccount) + " forecasts generated."
    sys.stdout.flush()

    # save forecast output
    saveForecast(init_timestr, timestr, odir) 

    # save anomaly shp files
    if not nhddbpath is None and os.path.isdir(nhddbpath):
        anomalyMethod='linearrate'
#        anomalyMethod='lograte'
        createAnomalyMap(anomalyMethod, anomalyThreshold = 2.5, filterThreshold = 3.703703, NHDDBPath = nhddbpath, NHDLayerName = 'Flowline', odir=odir)

def saveForecast(init_timestr = None, timestr = None, odir = None):
    global comidlist 
    global Qfclist
    global Hfclist
    global fccount
    # save to netcdf
    xds = xr.Dataset({
        'COMID': (['index'], comidlist[:fccount]),
#        'Time': (['index'], [timestr for i in range(fccount)]),
        'H': (['index'], Hfclist[:fccount]),
        'Q': (['index'], Qfclist[:fccount])
    })
    xds.attrs = {
        'Subject': 'Inundation table derived from HAND and NOAA NWM for CONUS',
        'Initialization_Timestamp': init_timestr,
        'Timestamp': timestr,
        'Description': 'Inundation lookup table for all the COMIDs in CONUS through the aggregation of HUC6-level hydro property tables and NOAA NWM forecast netcdf on channel_rt'
    }
    xds['COMID'].attrs = { 'units': 'index', 'long_name': 'Catchment ID (COMID)'}
    xds['H'].attrs = { 'units': 'm', 'long_name': 'Inundation height forecast'}
    xds['Q'].attrs = { 'units': 'm3s-1', 'long_name': 'Inundation discharge forecast'}
    ofilename = 'inun-hq-table-at-' + init_timestr + '-for-' +  timestr
    ofilenetcdf = odir + '/' + ofilename + '.nc'
    ofilecsv = odir + '/' + ofilename + '.csv'
    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "Writing netcdf output " + ofilenetcdf 
    sys.stdout.flush()
    xds.to_netcdf(ofilenetcdf)
    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "Writing csv output " + ofilecsv
    sys.stdout.flush()
    with open(ofilecsv, 'wb') as ofcsv:
        ow = csv.writer(ofcsv, delimiter = ',')
#        ow.writerow(['COMID', 'Time', 'H', 'Q']) # header
        ow.writerow(['COMID', 'H', 'Q']) # header
        for i in range(fccount):
#            ow.writerow([comidlist[i], timestr, Hfclist[i], Qfclist[i]])
            ow.writerow([comidlist[i], Hfclist[i], Qfclist[i]])

    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "DONE"
    sys.stdout.flush()

def createAnomalyMap(anomalyMethod='linearrate', anomalyThreshold = 2.5, filterThreshold = 3.703703, NHDDBPath = None, NHDLayerName = None, odir=None):
    global comidlist 
    global Qfclist
    global Hfclist
    global fccount
    global h # reuse h; reset first
    # create comid hash for forecast output
    h = None
    h = dict.fromkeys(comidlist)
    for i in range(0, fccount):
        h[comidlist[i]] = i

    # open NHDPlus MR to scan each flowline only once
    ds = gdal.OpenEx( NHDDBPath, gdal.OF_VECTOR | gdal.OF_READONLY)
    if ds is None :
        print "createAnomalyMap(): ERROR Open failed: " + str(NHDDBPath) + "\n"
        sys.exit( 1 )
    lyr = ds.GetLayerByName( NHDLayerName )
    if lyr is None :
        print "createAnomalyMap(): ERROR fetch layer: " + str(NHDLayerName) + "\n"
        sys.exit( 1 )
    lyr.ResetReading()
    num_records = lyr.GetFeatureCount()
    lyr_defn = lyr.GetLayerDefn()
    srs = lyr.GetSpatialRef()
    geomType = lyr.GetGeomType()
    # get index of attributes to be extracted
    fi_comid = lyr_defn.GetFieldIndex('COMID')
    fdef_comid = lyr_defn.GetFieldDefn(fi_comid)
    fi_huc = lyr_defn.GetFieldIndex('REACHCODE')
    fdef_huc = lyr_defn.GetFieldDefn(fi_huc)
    fi_meanflow = lyr_defn.GetFieldIndex('Q0001E')
    fdef_meanflow = lyr_defn.GetFieldDefn(fi_meanflow)

    # create output shp 
    driverName = "ESRI Shapefile"
    ofilename = 'anomalymap-at-' + init_timestr + '-for-' +  timestr
    of = odir + '/' + ofilename + '.shp'
    drv = gdal.GetDriverByName( driverName )
    if drv is None:
        print "createAnomalyMap(): ERROR %s driver not available.\n" % driverName
        sys.exit( 1 )
    ods = drv.Create( of, 0, 0, 0, gdal.GDT_Unknown )
    if ods is None:
        print "createAnomalyMap(): ERROR Creation of output file failed: "+of+ "\n"
        sys.exit( 1 )
    olyr = ods.CreateLayer('anomalymap', srs, geomType)
    if olyr is None:
        print "createAnomalyMap(): ERROR Layer creation failed: anomalymap "+ "\n"
        sys.exit( 1 )
    # create fields
    ofdef_comid = ogr.FieldDefn( "COMID", ogr.OFTInteger)
    ofdef_H = ogr.FieldDefn( "H", ogr.OFTReal)
    ofdef_Q = ogr.FieldDefn( "Q", ogr.OFTReal)
    ofdef_rating = ogr.FieldDefn( "RATING", ogr.OFTReal)
    if olyr.CreateField ( ofdef_comid ) != 0 or olyr.CreateField ( fdef_huc ) != 0 or olyr.CreateField ( ofdef_Q ) != 0 or olyr.CreateField ( fdef_meanflow ) != 0 or olyr.CreateField ( ofdef_rating ) != 0 or olyr.CreateField ( ofdef_H ) != 0 :
        print "createAnomalyMap(): ERROR Creating fields in output .\n"
        sys.exit( 1 )
    # get integer index to speed up the loops
    olyr_defn = olyr.GetLayerDefn()
    ofi_comid = olyr_defn.GetFieldIndex('COMID')
    ofi_huc = olyr_defn.GetFieldIndex('REACHCODE')
    ofi_Q = olyr_defn.GetFieldIndex('Q')
    ofi_meanflow = olyr_defn.GetFieldIndex('Q0001E')
    ofi_rating = olyr_defn.GetFieldIndex('RATING')
    ofi_H = olyr_defn.GetFieldIndex('H')

    count = 0 
    for f in lyr: # for each row. in NHDPlus MR, it's 2.67m
        comid = f.GetFieldAsInteger(fi_comid)
        if not comid in h: # comid has no forecast record
            continue
        i = h[comid] # index of this comid in Qfclist and Hfclist
        Qfc = Qfclist[i]
        meanflow = f.GetFieldAsDouble(fi_meanflow) 
        rate = calcAnomalyRate(Qfc, meanflow, anomalyMethod, anomalyThreshold, filterThreshold)
        if rate < 0.00000001: # filter by rate diff
            continue
        # it is an anomaly, get it
        Hfc = Hfclist[i]
        huc = f.GetFieldAsString(fi_huc)
        # create feature and write to output
        fc = ogr.Feature( olyr_defn )
        fc.SetField(ofi_comid, comid)
        fc.SetField(ofi_huc, huc)
        fc.SetField(ofi_Q, Qfc)
        fc.SetField(ofi_meanflow, meanflow)
        fc.SetField(ofi_rating, rate)
        fc.SetField(ofi_H, Hfc);
        # create geom field
        geom = f.GetGeometryRef()
        fc.SetGeometry( geom ) # this method makes a copy of geom
        if olyr.CreateFeature( fc ) != 0:
            print "createAnomalyMap(): ERROR Creating new feature in output for COMID=" + str(comid) + " .\n"
            sys.exit( 1 )
        fc.Destroy()
        count += 1
    ds = None
    ods = None 

    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : createAnomalyMap ") + " generated " + str(count) + " anomalies from " + str(fccount) + " forecast reaches"
        
def calcAnomalyRate(Q = 0.0, meanflow = 0.00000001, anomalyMethod='linearrate', anomalyThreshold = 2.5, filterThreshold = 3.703703):
    #filterThreshold = 100.0 / 27 # 100cfs; 100/27 cms
    f2m = 3.28084 * 3.28084 * 3.28084
    meanflow = meanflow / f2m
    if (Q - meanflow  < filterThreshold): # absolute change is too small
        return 0
    if anomalyMethod == 'linearrate': # Q / Qmean > 2.5
        return Q - meanflow * anomalyThreshold
    else: # lograte: Q > Qmean^2.5
        #return Q - meanflow * meanflow * math.sqrt(meanflow) 
        return Q - math.pow(meanflow, anomalyThreshold)

# global variables
comids = None # COMID list from NWM forecast table
Qs = None # Q forecast list (discharge) from NWM
h = None # hash table for Q forecast lookup, indexed by COMID (station id)
comidlist = None # COMID list, intersection of NWM forecast and hydroprop
Qfclist = None # Q forecast
Hfclist = None # H forecast
fccount = 0 # length of the above three arrays

## software environment:
## . /gpfs_scratch/nfie/users/yanliu/forecast/softenv
# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/hydroprop/hydroprop-fulltable.nc /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t00z.short_range.channel_rt.f001.conus.nc /gpfs_scratch/nfie/users/hydroprop
# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/HUC6 /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t00z.short_range.channel_rt.f001.conus.nc /gpfs_scratch/nfie/users/hydroprop
## forecast table test:
# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/yanliu/forecast/test /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t00z.short_range.channel_rt.f001.conus.nc /gpfs_scratch/nfie/users/yanliu/forecast/test
## anomaly map shp test:
# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/yanliu/forecast/test /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t10z.short_range.channel_rt.f010.conus.nc /gpfs_scratch/nfie/users/yanliu/forecast/test/anomaly /gpfs_scratch/usgs/nhd/NFIEGeoNational.gdb
## worst-scenario anomaly test:
# python /projects/nfie/nfie-floodmap/test/forecast-nwm-worst.py /projects/nfie/houston_20170119 "nwm.t10z.short_range.channel_rt.f001.conus.nc nwm.t10z.short_range.channel_rt.f002.conus.nc nwm.t10z.short_range.channel_rt.f003.conus.nc nwm.t10z.short_range.channel_rt.f004.conus.nc nwm.t10z.short_range.channel_rt.f005.conus.nc nwm.t10z.short_range.channel_rt.f006.conus.nc nwm.t10z.short_range.channel_rt.f007.conus.nc nwm.t10z.short_range.channel_rt.f008.conus.nc nwm.t10z.short_range.channel_rt.f009.conus.nc nwm.t10z.short_range.channel_rt.f010.conus.nc nwm.t10z.short_range.channel_rt.f011.conus.nc nwm.t10z.short_range.channel_rt.f012.conus.nc nwm.t10z.short_range.channel_rt.f013.conus.nc nwm.t10z.short_range.channel_rt.f014.conus.nc nwm.t10z.short_range.channel_rt.f015.conus.nc" ./20170119.nwm.t10z.short_range.channel_rt.worstscenario.conus.nc
# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/yanliu/forecast/test ./20170119.nwm.t10z.short_range.channel_rt.worstscenario.conus.nc  /gpfs_scratch/nfie/users/yanliu/forecast/test/anomaly/worstscenario /gpfs_scratch/usgs/nhd/NFIEGeoNational.gdb
if __name__ == '__main__':
    hpinput = sys.argv[1] # hydro property file root dir
    fcfile = sys.argv[2] # NOAA NWM forecast netcdf path
    odir = sys.argv[3] # output netcdf path, directory must exist
    nhddbpath = ''
    if len(sys.argv) > 4:
        nhddbpath = sys.argv[4] # nhdplus mr filegdb path

    tobj = readForecast(fcfile) # read forecast, set up hash table
    timestr = tobj['timestamp']
    init_timestr = tobj['init_timestamp']

    huclist = []
    tablelist = []
    if os.path.isdir(hpinput):
        tabledir = hpinput
        # read dir list
        wildcard = os.path.join(tabledir, '*')
        dlist = glob.glob(wildcard)
        count = 0
        for d in dlist:
            if not os.path.isdir(d):
                continue
            hucid = os.path.basename(d)
            csvfile = d+'/'+'hydroprop-fulltable-'+hucid+'.csv'
            if not os.path.isfile(csvfile):
                continue
            tablelist += [ csvfile ]
            huclist += [ hucid ]
            count +=1
    else: # single netcdf file
        tablelist += [hpinput]
        count = 1
    print str(count) + " hydro property tables will be read."
    sys.stdout.flush()

    forecastH(init_timestr, timestr, tablelist, 83, huclist, odir, nhddbpath)



