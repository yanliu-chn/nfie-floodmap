# ##########################################################
#    FILENAME:   Hydraulic_Property_Calculation.py
#    VERSION:    2.1b
#    SINCE:      2016-08-09
#    AUTHOR:     Xing Zheng - zhengxing@utexas.edu
#    Description:This program is designed for evaluating
#    NHD Flowline Hydraulic Properties from HAND Raster.
#    The input should be (1) Catchment shapefile;
#                        (2) Flowline shapefile;
#                        (3) HAND raster generated
#                            from NHD-HAND.
# ##########################################################

import sys
from osgeo import gdal, ogr
import os
import numpy as np
import numpy.ma as ma
from math import sqrt
import shutil


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


def HANDClipper(catchmentshp, flowlineshp, handtif,
                COMIDlist, RiverLength_dic, Slope_dic,
                Hmax, dh, roughness):
    """Create HAND Raster for every catchment in the study area
    """
    # Set output path
    outputFolder = os.path.join(os.getcwd(), "HydraulicProperty")
    catchmentFolder = os.path.join(os.getcwd(), "Catchment")
    # Clean up existing folders and files
    if os.path.exists(catchmentFolder):
        shutil.rmtree(catchmentFolder)
    if os.path.exists(outputFolder):
        shutil.rmtree(outputFolder)
    # Create output folder
    if not os.path.exists(catchmentFolder):
        os.mkdir(catchmentFolder)
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
    # Read catchment shapefile
    inDriver = ogr.GetDriverByName("ESRI Shapefile")
    inDataSource = inDriver.Open(catchmentshp, 0)
    inLayer = inDataSource.GetLayer()
    spatialRef = inLayer.GetSpatialRef()
    for i in range(0, inLayer.GetFeatureCount()):
        # Get an input catchment feature
        inFeature = inLayer.GetFeature(i)
        COMID = inFeature.GetField('FeatureID')
        if COMID in COMIDlist:
            # Set individual catchment shapefile path
            outShapefile = os.path.join(catchmentFolder, str(COMID)+".shp")
            outDriver = ogr.GetDriverByName("ESRI Shapefile")
            # Remove output shapefile if it already exists
            if os.path.exists(outShapefile):
                outDriver.DeleteDataSource(outShapefile)
            # Create the output shapefile
            outDataSource = outDriver.CreateDataSource(outShapefile)
            outLayer = outDataSource.CreateLayer(str(COMID), spatialRef,
                                                 geom_type=ogr.wkbPolygon)
            # Add input layer fields to the output Layer
            inLayerDefn = inLayer.GetLayerDefn()
            for k in range(0, inLayerDefn.GetFieldCount()):
                fieldDefn = inLayerDefn.GetFieldDefn(k)
                outLayer.CreateField(fieldDefn)
            # Get the output layer's feature definition
            outLayerDefn = outLayer.GetLayerDefn()
            outFeature = ogr.Feature(outLayerDefn)
            # Add field values from input layer
            for m in range(0, outLayerDefn.GetFieldCount()):
                outFeature.SetField(outLayerDefn.GetFieldDefn(m).GetNameRef(),
                                    inFeature.GetField(m))
            # Get polygon geometry
            geom = inFeature.GetGeometryRef()
            outFeature.SetGeometry(geom)
            # Add new feature to output Layer
            outLayer.CreateFeature(outFeature)
            # Close output file
            outDataSource.Destroy()
            # Read single catchment shapefile
            infile = outShapefile
            inSource = inDriver.Open(infile, 0)
            inlayer = inSource.GetLayer()
            extent = inlayer.GetExtent()
            dtsdir = handtif
            dts_out_file = os.path.join(catchmentFolder,
                                        str(COMID) + "hand.tif")
            if os.path.exists(dts_out_file):
                os.remove(dts_out_file)
            # Clip HAND raster with single catchment polygon boundary
            command_dd = "gdalwarp -te " + str(extent[0]) + " " + \
                         str(extent[2]) + " " + str(extent[1]) + " " + \
                         str(extent[3]) + " -dstnodata -32768 -cutline " + \
                         outShapefile + " -cl " + str(COMID) + " " + dtsdir + \
                         " " + dts_out_file
            os.system(command_dd)
            if os.path.exists(dts_out_file):
                # Hydraulic property calculation
                volumefolder = os.path.join(outputFolder, "Volume")
                volume_write = open(volumefolder+"/"+str(COMID)+".csv",
                                    'a')
                volume_write.write("StageHeight(m),Volume(m^3)\n")
                volume_write.close()
                # Calculate flood volume and water surface area
                Return = Volume_SA_Calculation(COMID, dts_out_file,
                                               dh, Hmax)
                Volume = np.asarray(Return[0])
                SAlist = np.asarray(Return[1])
                for H in np.arange(0, Hmax, dh):
                    volume_write = open(volumefolder+"/"+str(COMID)+".csv",
                                        'a')
                    volume_write.write(str(H)+","+str(Volume[int(H/dh)])+"\n")
                    volume_write.close()
                Depth, Volume = np.loadtxt(volumeFolder + "/" +
                                           str(COMID) + ".csv",
                                           delimiter=',', skiprows=1,
                                           usecols=(0, 1, ), unpack=True)
                # Calculate channel top width, wet area,
                # wetted perimeter, and bed area
                if np.any(Volume):
                    RiverLength = RiverLength_dic[str(COMID)]
                    Return_Result = TW_WA_WP_BA_Calculation(Depth, RiverLength,
                                                            Volume, SAlist, dh)
                    TWlist = np.asarray(Return_Result[0])
                    WAlist = np.asarray(Return_Result[1])
                    WPlist = np.asarray(Return_Result[2])
                    BAlist = np.asarray(Return_Result[3])
                    TWlocation = os.path.join(topwidthFolder,
                                              str(COMID) + '.csv')
                    np.savetxt(TWlocation, np.column_stack((Depth, TWlist)),
                               delimiter=',',
                               header="Depth(m),TopWidth(m)",
                               comments='')
                    WAlocation = os.path.join(wetareaFolder,
                                              str(COMID)+".csv")
                    np.savetxt(WAlocation, np.column_stack((Depth, WAlist)),
                               delimiter=',',
                               header="Depth(m),WetArea(m^2)",
                               comments='')
                    WPlocation = os.path.join(wetperimeterFolder,
                                              str(COMID)+".csv")
                    np.savetxt(WPlocation, np.column_stack((Depth, WPlist)),
                               delimiter=',',
                               header="Depth(m),WettedPerimeter(m)",
                               comments='')
                    SAlocation = os.path.join(surfaceareaFolder,
                                              str(COMID)+".csv")
                    np.savetxt(SAlocation, np.column_stack((Depth, SAlist)),
                               delimiter=',',
                               header="Depth(m),SurfaceArea(m^2)",
                               comments='')
                    BAlocation = os.path.join(bedareaFolder,
                                              str(COMIDlist[i])+".csv")
                    np.savetxt(BAlocation, np.column_stack((Depth, BAlist)),
                               delimiter=',', header="Depth(m),BedArea(m^2)",
                               comments='')
                    # Calculate hydraulic radius and discharge
                    Slope = Slope_dic[str(COMID)]
                    Return_Result = HR_Q_Calculation(WAlist, WPlist,
                                                     Slope, roughness)
                    HRlist = Return_Result[0]
                    Qlist = Return_Result[1]
                    HRlocation = os.path.join(hydraulicradiusFolder,
                                              str(COMID)+".csv")
                    np.savetxt(HRlocation, np.column_stack((Depth, HRlist)),
                               delimiter=',',
                               header="Depth(m),HydraulicRadius(m)",
                               comments='')
                    HQlocation = os.path.join(ratingcurveFolder,
                                              str(COMID)+".csv")
                    np.savetxt(HQlocation, np.column_stack((Depth, Qlist)),
                               delimiter=',',
                               header="Depth(m),Discharge(m^3/s)",
                               comments='')
                    Sumlocation = os.path.join(summaryFolder,
                                               str(COMID)+".csv")
                    np.savetxt(Sumlocation, np.column_stack((Depth, TWlist,
                                                             WAlist, WPlist,
                                                             SAlist, BAlist,
                                                             HRlist, Qlist)),
                               delimiter=',', header="Depth(m),TopWidth(m),"
                               "WetArea(m^2),WettedPerimeter(m),"
                               "SurfaceArea(m^2),BedArea(m^2),"
                               "HydraulicRadius(m),Discharge(m^3/s)",
                               comments='')


def Volume_SA_Calculation(COMID, HANDRaster, dh, Hmax):
    """Calculate flood volume and water surface area
    """
    # Read HAND raster
    dts_ds = gdal.Open(HANDRaster)
    band_dts = dts_ds.GetRasterBand(1)
    nodata_dts = band_dts.GetNoDataValue()
    array_dts = band_dts.ReadAsArray()
    arraydts = ma.masked_where(array_dts == nodata_dts, array_dts)
    Volumelist = []
    SAlist = []
    for H in np.arange(0, Hmax, dh):
        # Subtract stage height from hand raster
        dts_value = arraydts-H
        # Find dts<0
        dts_less_height = dts_value <= 0
        # Count number of cell has negative value
        count_cell = dts_less_height.sum()
        cell_height = dts_value[dts_less_height]*(-1)
        # Calculate flood volume for stage height H
        volume_in = 10*10*cell_height
        volume = volume_in.sum()
        # Calculate water surface area for stage height H
        SurfaceArea = count_cell*10*10
        if type(volume) is not np.float32:
            Volumelist.append(0.0)
            SAlist.append(0.0)
        else:
            Volumelist.append(volume)
            SAlist.append(SurfaceArea)
    ReturnResult = [Volumelist, SAlist]
    return ReturnResult


def TW_WA_WP_BA_Calculation(Depth, RiverLength, Volume, SAlist, dh):
    """Calculate channel top width, wet area, wetted perimeter, and
    bed area
    """
    Volume = Volume - Volume[0]
    DVolume = np.diff(Volume)
    DDepth = np.diff(Depth)
    TotalArea = Volume/RiverLength/1000
    TWlist = SAlist/RiverLength/1000
    WAlist = list(TotalArea)
    TWlist = list(TWlist)
    WPlist = []
    BAlist = []
    WetPerimeter = 0
    BedArea = 0
    for i in range(len(TWlist)):
        if i == 0:
            WetPerimeter = TWlist[i]
            WPlist.append(WetPerimeter)
        else:
            WetPerimeter += 2*sqrt(DDepth[i-1]*DDepth[i-1] +
                                   ((TWlist[i]-TWlist[i-1])/2)**2)
            WPlist.append(WetPerimeter)
        BedArea = WetPerimeter*RiverLength
        BAlist.append(BedArea)
    ReturnResult = [TWlist, WAlist, WPlist, BAlist]

    return ReturnResult


def HR_Q_Calculation(WAlist, WPlist, Slope, roughness):
    """ Calculate hydraulic radius and discharge
    """
    HRlist = []
    Qlist = []
    HRlist.append(0)
    for i in range(1, len(WAlist)):
        HydraulicRadius = WAlist[i]/WPlist[i]
        HRlist.append(HydraulicRadius)
    Qlist.append(0)
    for i in range(1, len(WAlist)):
        if Slope >= 0:
            Discharge = WAlist[i]*(HRlist[i]**(2.0/3))*sqrt(Slope)/roughness
            Qlist.append(Discharge)
        else:
            Qlist.append(0)
    ReturnResult = [HRlist, Qlist]

    return ReturnResult


def main():
    catchmentshp = str(sys.argv[2])
    flowlineshp = str(sys.argv[4])
    handtif = str(sys.argv[6])
    Hmax = 25
    dh = 0.3048
    roughness = 0.05
    COMIDlist, RiverLength_dic, Slope_dic = Shapefile_Attribute_Reader(catchmentshp, flowlineshp)
    HANDClipper(catchmentshp, flowlineshp, handtif,
                COMIDlist, RiverLength_dic, Slope_dic,
                Hmax, dh, roughness)


if __name__ == "__main__":
    main()
