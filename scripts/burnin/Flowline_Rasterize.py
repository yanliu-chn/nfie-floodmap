# ##########################################################
#    FILENAME:   FlowlineRasterize.py
#    VERSION:    1.0
#    SINCE:      2016-05-02
#    AUTHOR:     Xing Zheng - zhengxing@utexas.edu
#    Description:This program is designed for converting
#    NHD flowline features to a source raster that is
#    used in HAND
#    The input should be (1) NHD flowline shapefile;
#                        (2) HAND src file with inlets.
# ##########################################################

import sys
from osgeo import gdal, ogr
import numpy as np
import shutil


def FlowlineRasterize(flowlineshp,srctif,flowlinetif):
    """Rasterize NHD waterbody features
    """
# Read waterbody dataset
    inDriver = ogr.GetDriverByName("ESRI Shapefile")
    FlowlineDataSource = inDriver.Open(flowlineshp, 0)
    FlowlineLayer = FlowlineDataSource.GetLayer()
# Read inlet source file
    srcfile = gdal.Open(srctif)
    cols = srcfile.RasterXSize
    rows = srcfile.RasterYSize
    bands = srcfile.RasterCount
    geotransform = srcfile.GetGeoTransform()
    projInfo = srcfile.GetProjection()
# Create waterbody source file
    target_ds = gdal.GetDriverByName('GTiff').Create(flowlinetif, cols, rows, 1, gdal.GDT_Byte)
    target_ds.SetGeoTransform(geotransform)
    target_ds.SetProjection(projInfo)
##    NoData_value = 0
    band = target_ds.GetRasterBand(1)  
##    band.SetNoDataValue(NoData_value)
    gdal.RasterizeLayer(target_ds, [1], FlowlineLayer, burn_values=[1])

def main():
    flowlineshp = str(sys.argv[2])
    DEMtif = str(sys.argv[4])
    flowlinetif = str(sys.argv[6])
    FlowlineRasterize(flowlineshp,DEMtif,flowlinetif)

    
if __name__ == "__main__":
    main()
