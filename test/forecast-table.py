import sys
import os
import time
import getopt
import glob
import shutil
import re
import osr
import netCDF4
import numpy as np
import pandas as pd
import xarray as xr
from datetime import datetime
import csv
#import pytz

## create flood forecast table for all the COMIDs on CONUS
# input 1: the list of hydro property lookup table for each HUC6 code
# input 2: NOAA NWM forecast data, one timestamp
# output: an inundation table for all the COMIDs on CONUS as netcdf and csv

# read input NOAA NWM netcdf file
def readForecast(in_nc = None):
    global comids
    global Qs
    global h
    # open netcdf file
    rootgrp = netCDF4.Dataset(in_nc, 'r')
    intype='channel_rt'
    metadata_dims = ['station']
    dimsize = len(rootgrp.dimensions[metadata_dims[0]]) # num rows

    global_attrs={att:val for att,val in rootgrp.__dict__.iteritems()}
    timestamp_str=global_attrs['model_output_valid_time']
    timestamp = datetime.strptime(timestamp_str, '%Y-%m-%d_%H:%M:%S') # read
    #timestamp.replace(tzinfo=pytz.UTC) # set timezone 
    t = timestamp.strftime('%Y%m%d_%H%M%S') # reformat timestampe output

    # create attr data for COMID and flowstream attr
    comids_ref = rootgrp.variables['station_id']
    Qs_ref = rootgrp.variables['streamflow']
    comids = np.copy(comids_ref) 
    Qs = np.copy(Qs_ref)

    rootgrp.close() # close netcdf file to save memory

    # create hash table
    h = dict.fromkeys(comids)
    for i in range(0, dimsize):
        h[comids[i]] = i

    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + " Loaded " + str(len(comids)) + " stations"
    sys.stdout.flush()

    return t

# interpolate H forecast from the static H and Q table dervied from HAND
# assuming the ascending order to stage heights for a COMID in CSV table
def Hinterpolate(Qfc = 0.0, Hlist = [], Qlist = [], count = 0):
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
        Q1 = Qlist[0]
        Q1i = 0
        Q2 = Qlist[count - 1]
        Q2i = count - 1
    if Q2 == Q1:
        print "WARNING: discharge data flat: count=" + str(count) + " Q1="+str(Q1)+" Q2="+str(Q2)
        return Hlist[Q1i]
    return (Qfc - Q1) * (Hlist[Q2i] - Hlist[Q1i]) / (Q2 - Q1) + Hlist[Q1i]


def forecastH (timestr = None, tablelist = None, numHeights = 83, huclist = None, odir = None):
    global comids
    global Qs
    global h

    comidlist = np.zeros(len(comids), dtype='int64')
    Hfclist = np.zeros(len(comids), dtype='float64')
    Qfclist = np.zeros(len(comids), dtype='float64')
    fccount = 0
    missings = 0 # in hydro table but not in station hash
    catchcount = 0 # count of catchments in hydro table
    for i in range(0, len(tablelist)): # scan each HUC's hydro prop table
        csvfile = tablelist[i]
        csvdata = pd.read_csv(csvfile)
        catchcount += (csvdata.size / numHeights )
        print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + csvfile + " : " + str(csvdata.size/14) + " rows "
        sys.stdout.flush()
        comid = None
        count = 0
        Hlist = np.zeros(numHeights, dtype = 'float64')
        Qlist = np.zeros(numHeights, dtype = 'float64')
        for index, row in csvdata.iterrows(): # loop each row of the table
            catchid = int(row['CatchId']) # get comid
            if not catchid in h: # hydro table doesn't have info for this comid
                missings += 1
                continue
            if comid is None:
                comid = catchid
            if comid != catchid : # time to interpolate
                j = h[comid]
                Qfc = Qs[j]
                Hfc = Hinterpolate(Qfc, Hlist, Qlist, count)
                comidlist[fccount] = comid
                Hfclist[fccount] = Hfc
                Qfclist[fccount] = Qfc
                fccount += 1
                count = 0
                comid = catchid
            Hlist[count] = row['Stage']
            Qlist[count] = row['Discharge (m3s-1)']
            count += 1
    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "Read " + str(len(comids)) + " stations from NWM, " + str(catchcount) + " catchments from hydro table. " + str(missings) + " comids in hydro table but not in NWM. " + " generated " + str(fccount) + " forecasts"
    sys.stdout.flush()
    # save to netcdf
    xds = xr.Dataset({
        'COMID': (['index'], comidlist[:fccount]),
        'Time': (['index'], [timestr for i in range(fccount)]),
        'H': (['index'], Hfclist[:fccount]),
        'Q': (['index'], Qfclist[:fccount])
    })
    xds.attrs = {
        'Subject': 'Inundation table derived from HAND and NOAA NWM for CONUS',
        'Description': 'Inundation lookup table for all the COMIDs in CONUS through the aggregation of HUC6-level hydro property tables and NOAA NWM forecast netcdf on channel_rt'
    }
    xds['COMID'].attrs = { 'units': 'index', 'long_name': 'Catchment ID (COMID)'}
    xds['H'].attrs = { 'units': 'm', 'long_name': 'Inundation height forecast'}
    xds['Q'].attrs = { 'units': 'm3s-1', 'long_name': 'Inundation discharge forecast'}
    ofilename = 'inun-hq-table-' + timestr
    ofilenetcdf = odir + '/' + ofilename + '.nc'
    ofilecsv = odir + '/' + ofilename + '.csv'
    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "Writing netcdf output " + ofilenetcdf 
    sys.stdout.flush()
    xds.to_netcdf(ofilenetcdf)
    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "Writing csv output " + ofilecsv
    sys.stdout.flush()
    with open(ofilecsv, 'wb') as ofcsv:
        ow = csv.writer(ofcsv, delimiter = ',')
        ow.writerow(['COMID', 'Time', 'H', 'Q']) # header
        for i in range(fccount):
            ow.writerow([comidlist[i], timestr, Hfclist[i], Qfclist[i]])

    print datetime.now().strftime("%Y-%m-%d %H:%M:%S : ") + "DONE"
    sys.stdout.flush()
        
# global variables
comids = None # COMID list
Qs = None # Q forecast list (discharge)
h = None # hash table for Q forecast lookup, indexed by COMID (station id)

# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/HUC6 /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t00z.short_range.channel_rt.f001.conus.nc /gpfs_scratch/nfie/users/hydroprop
# python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/yanliu/forecast/test /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t00z.short_range.channel_rt.f001.conus.nc /gpfs_scratch/nfie/users/yanliu/forecast/test
if __name__ == '__main__':
    tabledir = sys.argv[1] # HUC6 HAND root dir
    fcfile = sys.argv[2] # NOAA NWM forecast netcdf path
    odir = sys.argv[3] # output netcdf path, directory must exist

    timestr = readForecast(fcfile) # read forecast, set up hash table

    # read dir list
    wildcard = os.path.join(tabledir, '*')
    dlist = glob.glob(wildcard)
    huclist = []
    tablelist = []
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
    print str(count) + " hydro property tables will be read."
    sys.stdout.flush()

    forecastH(timestr, tablelist, 83, huclist, odir)



