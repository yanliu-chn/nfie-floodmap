# aggregate HUC6 unit level hydraulic property table files (netcdf) to CONUS
# Yan Y. Liu <yanliu@illinois.edu>
# 10/31/2016

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

# convert hydro property full table CSVs to a single netcdf
# for all HUC6 units

@profile
def merge2netcdf(ddir = None, of = None):
    # create output array
    od = None
#    attrs = {}
    # read dir list
    wildcard = os.path.join(ddir, '*')
    dlist = glob.glob(wildcard)
    count = 0
    for d in dlist:
        if not os.path.isdir(d):
            continue
        hucid = os.path.basename(d)
        csvfile = d+'/'+'hydroprop-fulltable-'+hucid+'.csv'
        if not os.path.isfile(csvfile):
            continue
        count +=1

        # read CSV content
        csv = pd.read_csv(csvfile, index_col=['CatchId', 'Stage']) # 2D index
        if od is None:
            od = csv
        else:
            od = od.append(csv)
#        attrs[hucid] = {
#            'HUC': hucid,
#            'count': csv.size
#        }
        print csvfile + " : " + str(csv.size) + " rows " + str(od.memory_usage(index=True, deep=False).sum()) + " B"
        sys.stdout.flush()
    print str(count) + " HUC units read into memory"
    print str(od.size) + " cells have been concatenated, each row has 14 cells"
    # output as netcdf
    xds = xr.Dataset.from_dataframe(od)
    xds.attrs = {
        'Subject': 'Hydro properties derived from HAND and NHDPlus MR for CONUS',
        'Description': 'Hydro property lookup table for all the COMIDs in CONUS through the aggregation of HUC6-level hydro property tables'
    }
    # rename variables
    xds = xds.rename({
        'Number of Cells': 'NumCells',
        'SurfaceArea (m2)': 'SurfaceArea',
        'BedArea (m2)': 'BedArea',
        'Volume (m3)': 'Volume',
        'TopWidth (m)': 'TopWidth',
        'WettedPerimeter (m)': 'WettedPerimeter',
        'WetArea (m2)': 'WetArea',
        'HydraulicRadius (m)': 'HydraulicRadius',
        'Discharge (m3s-1)': 'Discharge'
    })
    xds['CatchId'].attrs = { 'units': 'index', 'long_name': 'Catchment ID (COMID)'}
    xds['Stage'].attrs = { 'units': 'm', 'long_name': 'Stage height, the H value'}
    xds['NumCells'].attrs = { 'units': 'integer', 'long_name': 'Number of cells in catchment'}
    xds['SurfaceArea'].attrs = { 'units': 'm2', 'long_name': 'Surface Area'}
    xds['BedArea'].attrs = { 'units': 'm2', 'long_name': 'Bed Area'}
    xds['Volume'].attrs = { 'units': 'm3', 'long_name': 'Volume'}
    xds['SLOPE'].attrs = { 'units': 'degree', 'long_name': 'Slope of the river line segment'}
    xds['LENGTHKM'].attrs = { 'units': 'km', 'long_name': 'Length of the river line segment'}
    xds['AREASQKM'].attrs = { 'units': 'km2', 'long_name': 'Area of the reach catchment'}
    xds['Roughness'].attrs = { 'units': 'Manning param', 'long_name': 'Roughness, manning param v=0.05'}
    xds['TopWidth'].attrs = { 'units': 'm', 'long_name': 'Top Width'}
    xds['WettedPerimeter'].attrs = { 'units': 'm', 'long_name': 'Wetted Perimeter'}
    xds['WetArea'].attrs = { 'units': 'm2', 'long_name': 'Wet Area'}
    xds['HydraulicRadius'].attrs = { 'units': 'm', 'long_name': 'Hydraulic Radius'}
    xds['Discharge'].attrs = { 'units': 'm3s-1', 'long_name': 'Discharge, the Q value'}

#    for hucid in attrs:
#        xds[hucid].attrs = attrs[hucid]
    xds.to_netcdf(of)

## usage: python -m memory_profiler /projects/nfie/nfie-floodmap/test/csv2netcdf-hydroprop-fulltable.py /gpfs_scratch/nfie/users/yanliu/forecast/test /gpfs_scratch/nfie/users/yanliu/forecast/test/t.nc
## usage: time python -m memory_profiler /projects/nfie/nfie-floodmap/test/csv2netcdf-hydroprop-fulltable.py /gpfs_scratch/nfie/users/HUC6 /gpfs_scratch/nfie/users/hydroprop/hydroprop-fulltable.nc

if __name__ == '__main__':
    ddir = sys.argv[1] # HUC6 HAND root dir
    of = sys.argv[2] # output netcdf path
    merge2netcdf(ddir, of)
