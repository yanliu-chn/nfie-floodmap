# ##########################################################
#    FILENAME:   Hydraulic_Property_Calculation.py
#    VERSION:    2.1a
#    SINCE:      2016-08-09
#    AUTHOR:     Xing Zheng - zhengxing@utexas.edu
#    Description:This program is designed for evaluating
#    NHD Flowline Hydraulic Properties from HAND Raster.
#    The input should be (1) Catchment shapefile;
#                        (2) Flowline shapefile;
#                        (3) HAND raster generated
#                            from NHD-HAND.
# ##########################################################

import ogr
import gdal
import osr
import numpy as np
import os
import shutil
import sys
from math import sqrt
import numpy.ma as ma


def Catchment_Rasterization(catchmentshp, handtif, catchmenttif):
    """Rasterize catchment shapefile with the FEATUREID as the raster value
    """
    # Read catchment shapefile
    inDriver = ogr.GetDriverByName("ESRI Shapefile")
    inDataSource = inDriver.Open(catchmentshp, 0)
    inLayer = inDataSource.GetLayer()
    spatialRef = inLayer.GetSpatialRef()
    # Read HAND raster as the template for new rasters
    handfile = gdal.Open(handtif)
    cols = handfile.RasterXSize
    rows = handfile.RasterYSize
    bands = handfile.RasterCount
    geotransform = handfile.GetGeoTransform()
    projInfo = handfile.GetProjection()
    # Create catchment raster
    target_ds = gdal.GetDriverByName('GTiff').Create(
        catchmenttif, cols, rows, 1, gdal.GDT_UInt32)
    target_ds.SetGeoTransform(geotransform)
    target_ds.SetProjection(projInfo)
    NoData_value = 0
    catchmentband = target_ds.GetRasterBand(1)
    catchmentband.SetNoDataValue(NoData_value)
    gdal.RasterizeLayer(target_ds, [1], inLayer,
                        options=["ATTRIBUTE=FEATUREID"])


def Shapefile_Attribute_Reader(catchmentshp, flowlineshp):
    """Find the shared COMID/FEATURE between flowline feature class
    and catchment feature class and read some flowline attributes
    needed to calculate channel hydraulic properties
    """
    # Read catchment shapefile
    driver = ogr.GetDriverByName("ESRI Shapefile")
    dataSource = driver.Open(catchmentshp, 0)
    layer = dataSource.GetLayer()
    # Get catchment FEATUREID list
    catchment_COMID = []
    for catchment in layer:
        catchment_COMID.append(catchment.GetField("FEATUREID"))
    # Get flowline COMID list, reach length, and slope
    flowline_COMID = []
    RiverLength_dic = {}
    Slope_dic = {}
    dataSource = driver.Open(flowlineshp, 0)
    layer = dataSource.GetLayer()
    for flowline in layer:
        flowline_COMID.append(flowline.GetField("COMID"))
        RiverLength_dic[str(flowline.GetField("COMID"))] = flowline.GetField("LENGTHKM")
        Slope_dic[str(flowline.GetField("COMID"))] = flowline.GetField("SLOPE")
    # Find the intersection between catchment FEATUREID set
    # and flowline COMID set
    COMIDlist = list(set(catchment_COMID).intersection(flowline_COMID))

    return COMIDlist, RiverLength_dic, Slope_dic


def Hydraulic_Property_Calculation(catchmenttif, handtif,
                                   COMIDlist, RiverLength_dic,
                                   Slope_dic, Hmax, dh, roughness):
    """Calculate NHD reach-average hydraulic properties from HAND raster
    """
    # Read HAND raster
    handfile = gdal.Open(handtif)
    cols = handfile.RasterXSize
    rows = handfile.RasterYSize
    handband = handfile.GetRasterBand(1)
    handarray = handband.ReadAsArray()
    # Read Catchment raster
    catchmentraster = gdal.Open(catchmenttif)
    catchmentband = catchmentraster.GetRasterBand(1)
    comidarray = catchmentband.ReadAsArray()
    # Create Output folder
    outputFolder = os.path.join(os.getcwd(), "HydraulicProperty")
    if not os.path.exists(outputFolder):
        os.mkdir(outputFolder)
    volumeFolder = os.path.join(outputFolder, "Volume")
    if not os.path.exists(volumeFolder):
        os.mkdir(volumeFolder)
    topwidthFolder = os.path.join(outputFolder, "TopWidth")
    if not os.path.exists(topwidthFolder):
        os.mkdir(topwidthFolder)
    wetareaFolder = os.path.join(outputFolder, "WetArea")
    if not os.path.exists(wetareaFolder):
        os.mkdir(wetareaFolder)
    wetperimeterFolder = os.path.join(outputFolder, "WettedPerimeter")
    if not os.path.exists(wetperimeterFolder):
        os.mkdir(wetperimeterFolder)
    surfaceareaFolder = os.path.join(outputFolder, "SurfaceArea")
    if not os.path.exists(surfaceareaFolder):
        os.mkdir(surfaceareaFolder)
    bedareaFolder = os.path.join(outputFolder, "BedArea")
    if not os.path.exists(bedareaFolder):
        os.mkdir(bedareaFolder)
    hydraulicradiusFolder = os.path.join(outputFolder, "HydraulicRadius")
    if not os.path.exists(hydraulicradiusFolder):
        os.mkdir(hydraulicradiusFolder)
    ratingcurveFolder = os.path.join(outputFolder, "RatingCurve")
    if not os.path.exists(ratingcurveFolder):
        os.mkdir(ratingcurveFolder)
    summaryFolder = os.path.join(outputFolder, "Summary")
    if not os.path.exists(summaryFolder):
        os.mkdir(summaryFolder)
    # Create incremental stage height
    Depth = np.arange(0, Hmax, dh)
    DDepth = np.diff(Depth)
    for comid in COMIDlist:
        # Mask HAND raster with COMID
        singlecatchmentarray = ma.masked_where(comidarray != comid, handarray)
        singlecatchmentarray = singlecatchmentarray.compressed()
        nodata = -9999
        # Delete all nan cells
        singlecatchmentarray = ma.masked_where(singlecatchmentarray <=
                                               nodata, singlecatchmentarray)
        singlecatchmentarray = singlecatchmentarray.compressed()
        Volumelist = []
        SAlist = []
        for H in np.arange(0, Hmax, dh):
            # Subtract stage height from hand raster
            dts_value = singlecatchmentarray-H
            # Find dts<0
            dts_less_height = dts_value <= 0
            # Count number of cell has negative value
            count_cell = dts_less_height.sum()
            cell_height = dts_value[dts_less_height]*(-1)
            # Calculate flood volume for stage height H in Catchment comid
            volume_in = 10*10*cell_height
            Volume = volume_in.sum()
            # Calculate water surface area
            SurfaceArea = count_cell*10*10
            Volumelist.append(Volume)
            SAlist.append(SurfaceArea)
        Volumearray = np.asarray(Volumelist)
        SAarray = np.asarray(SAlist)
        # Calculate wet area
        WAarray = Volumearray/RiverLength_dic[str(comid)]/1000
        # Calculate channel top width
        TWarray = SAarray/RiverLength_dic[str(comid)]/1000
        # Calculate channel wetted perimeter and bed area
        WPlist = []
        BAlist = []
        WetPerimeter = 0
        BedArea = 0
        for i in range(len(TWarray)):
            if i == 0:
                WetPerimeter = TWarray[i]
                WPlist.append(WetPerimeter)
            else:
                WetPerimeter += 2*sqrt(DDepth[i-1]*DDepth[i-1] +
                                       ((TWarray[i]-TWarray[i-1])/2)**2)
                WPlist.append(WetPerimeter)
            BedArea = WetPerimeter*RiverLength_dic[str(comid)]*1000
            BAlist.append(BedArea)
        WParray = np.asarray(WPlist)
        BAarray = np.asarray(BAlist)
        # Calculate channel hydraulic radius and discharege
        # from Manning's Equation
        HRlist = []
        Qlist = []
        HRlist.append(0)
        for i in range(1, len(WAarray)):
            HydraulicRadius = WAarray[i]/WParray[i]
            HRlist.append(HydraulicRadius)
        Qlist.append(0)
        for i in range(1, len(WAarray)):
            if Slope_dic[str(comid)] >= 0:
                Discharge = WAarray[i]*(HRlist[i]**(2.0/3))*sqrt(
                    Slope_dic[str(comid)])/roughness
                Qlist.append(Discharge)
            else:
                Qlist.append(0)
        HRarray = np.asarray(HRlist)
        Qarray = np.asarray(Qlist)
        # Write outputs
        Volumelocation = os.path.join(volumeFolder, str(comid) + '.csv')
        np.savetxt(Volumelocation, np.column_stack((Depth, Volumearray)),
                   delimiter=',', header="Depth(m),Volume(m^3)", comments='')
        SAlocation = os.path.join(surfaceareaFolder, str(comid)+".csv")
        np.savetxt(SAlocation, np.column_stack((Depth, SAarray)),
                   delimiter=',', header="Depth(m),SurfaceArea(m^2)",
                   comments='')
        TWlocation = os.path.join(topwidthFolder, str(comid) + '.csv')
        np.savetxt(TWlocation, np.column_stack((Depth, TWarray)),
                   delimiter=',', header="Depth(m),TopWidth(m)", comments='')
        WAlocation = os.path.join(wetareaFolder, str(comid)+".csv")
        np.savetxt(WAlocation, np.column_stack((Depth, WAarray)),
                   delimiter=',', header="Depth(m),WetArea(m^2)", comments='')
        WPlocation = os.path.join(wetperimeterFolder, str(comid)+".csv")
        np.savetxt(WPlocation, np.column_stack((Depth, WParray)),
                   delimiter=',', header="Depth(m),WettedPerimeter(m)",
                   comments='')
        BAlocation = os.path.join(bedareaFolder, str(comid)+".csv")
        np.savetxt(BAlocation, np.column_stack((Depth, BAarray)),
                   delimiter=',', header="Depth(m),BedArea(m^2)",
                   comments='')
        HRlocation = os.path.join(hydraulicradiusFolder, str(comid)+".csv")
        np.savetxt(HRlocation, np.column_stack((Depth, HRarray)),
                   delimiter=',', header="Depth(m),HydraulicRadius(m)",
                   comments='')
        HQlocation = os.path.join(ratingcurveFolder, str(comid)+".csv")
        np.savetxt(HQlocation, np.column_stack((Depth, Qarray)), delimiter=',',
                   header="Depth(m),Discharge(m^3/s)", comments='')
        Sumlocation = os.path.join(summaryFolder, str(comid)+".csv")
        np.savetxt(Sumlocation, np.column_stack((Depth,
                                                 TWarray, WAarray, WParray,
                                                 SAarray, BAarray, HRarray,
                                                 Qarray)), delimiter=',',
                   header="Depth(m),TopWidth(m),WetArea(m^2),"
                   "WettedPerimeter(m),SurfaceArea(m^2),BedArea(m^2),"
                   "HydraulicRadius(m),Discharge(m^3/s)", comments='')


def main():

    catchmentshp = str(sys.argv[2])
    flowlineshp = str(sys.argv[4])
    handtif = str(sys.argv[6])
    catchmenttif = catchmentshp[:-4]+".tif"
    Hmax = 25
    dh = 0.3048
    roughness = 0.05
    Catchment_Rasterization(catchmentshp, handtif, catchmenttif)
    COMIDlist, RiverLength_dic, Slope_dic = Shapefile_Attribute_Reader(catchmentshp, flowlineshp)
    Hydraulic_Property_Calculation(catchmenttif,
                                   handtif, COMIDlist, RiverLength_dic,
                                   Slope_dic, Hmax, dh, roughness)


if __name__ == "__main__":
    main()
