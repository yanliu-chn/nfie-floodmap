# ##########################################################
#    FILENAME:   Hydraulic_Property_Calculation.py
#    VERSION:    1.0
#    SINCE:      2016-04-09
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


def HANDClipper(inShapefile, flowlineShapefile, HANDRaster,
                Hstart, dh, HRange, roughness):
    """Create HAND Raster for every catchment in the study area
    """
# Read catchment dataset
    inDriver = ogr.GetDriverByName("ESRI Shapefile")
    inDataSource = inDriver.Open(inShapefile, 0)
    inLayer = inDataSource.GetLayer()
    spatialRef = inLayer.GetSpatialRef()
# Read flowline attributes
    flowlineDataSource = inDriver.Open(flowlineShapefile, 0)
    flowlineLayer = flowlineDataSource.GetLayer()
    RiverLengthDic = {}
    SlopeDic = {}
    for i in range(0, flowlineLayer.GetFeatureCount()):
        inFeature = flowlineLayer.GetFeature(i)
        COMID = inFeature.GetField('COMID')
        RiverLengthDic[str(COMID)] = inFeature.GetField('LENGTHKM')
        SlopeDic[str(COMID)] = inFeature.GetField('SLOPE')
# Set output path
    outputFolder = os.path.join(os.getcwd(), "HydraulicProperty")
    catchmentFolder = os.path.join(os.getcwd(), "Catchment")
# Clean up Existing Folders and Files
    if os.path.exists(catchmentFolder):
        shutil.rmtree(catchmentFolder)
    if os.path.exists(outputFolder):
        shutil.rmtree(outputFolder)
    if os.path.exists(os.getcwd()+"/CatchmentMissed.txt"):
        os.remove(os.getcwd()+"/CatchmentMissed.txt")
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
    hydraulicradiusFolder = os.path.join(outputFolder, "HydraulicRadius")
    if not os.path.exists(hydraulicradiusFolder):
        os.mkdir(hydraulicradiusFolder)
    ratingcurveFolder = os.path.join(outputFolder, "RatingCurve")
    if not os.path.exists(ratingcurveFolder):
        os.mkdir(ratingcurveFolder)
    summaryFolder = os.path.join(outputFolder, "Summary")
    if not os.path.exists(summaryFolder):
        os.mkdir(summaryFolder)
    for i in range(0, inLayer.GetFeatureCount()):
        # Get the input Feature
        inFeature = inLayer.GetFeature(i)
        COMID = inFeature.GetField('FeatureID')
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
        # Add input Layer Fields to the output Layer
        inLayerDefn = inLayer.GetLayerDefn()
        for k in range(0, inLayerDefn.GetFieldCount()):
            fieldDefn = inLayerDefn.GetFieldDefn(k)
            outLayer.CreateField(fieldDefn)
            # Get the output Layer's Feature Definition
        outLayerDefn = outLayer.GetLayerDefn()
        outFeature = ogr.Feature(outLayerDefn)
        # Add field values from input Layer
        for m in range(0, outLayerDefn.GetFieldCount()):
            outFeature.SetField(outLayerDefn.GetFieldDefn(m).GetNameRef(),
                                inFeature.GetField(m))
        # Get geometry
        geom = inFeature.GetGeometryRef()
        outFeature.SetGeometry(geom)
        # Add new feature to output Layer
        outLayer.CreateFeature(outFeature)
        # Close output file
        outDataSource.Destroy()
        # Clip HAND raster by catchment
        infile = outShapefile
        inSource = inDriver.Open(infile, 0)
        inlayer = inSource.GetLayer()
        extent = inlayer.GetExtent()
        dtsdir = HANDRaster
        dts_out_file = os.path.join(catchmentFolder, str(COMID) + "dd.tif")
        if os.path.exists(dts_out_file):
            os.remove(dts_out_file)
        command_dd = "gdalwarp -te " + str(extent[0]) + " " + \
                     str(extent[2]) + " " + str(extent[1]) + " " + \
                     str(extent[3]) + " -dstnodata -32768 -cutline " + \
                     outShapefile + " -cl " + str(COMID) + " " + dtsdir + \
                     " " + dts_out_file
        os.system(command_dd)
        # Hydraulic property calculation
        if os.path.exists(dts_out_file):
            # Calculate flood volume at different stage height
            Volume_Calculation(outputFolder, COMID,
                               dts_out_file, Hstart, dh, HRange)
            Depth, Volume = np.loadtxt(volumeFolder + "/" +
                                       str(COMID) + ".csv",
                                       delimiter=',', skiprows=0,
                                       usecols=(0, 1, ), unpack=True)
            # Calculate hydraulic properties
            if type(Volume) is not np.float64:
                Top_Width_Calculation(outputFolder, COMID, RiverLengthDic, dh)
                WA_WP_HR_Q_Calculation(outputFolder, COMID, SlopeDic,
                                       dh, roughness)
            else:
                missed_catchment = open(os.getcwd() +
                                        "/CatchmentMissed.txt", 'a')
                missed_catchment.write(str(COMID) + "\n")
                missed_catchment.close()
        else:
            missed_catchment = open(os.getcwd() + "/CatchmentMissed.txt", 'a')
            missed_catchment.write(str(COMID) + "\n")
            missed_catchment.close()
# Close DataSources
    inDataSource.Destroy()
    flowlineDataSource.Destroy()


def Volume_Calculation(outputFolder, COMID, dts_out_file, Hstart, dh, HRange):

    dts_ds = gdal.Open(dts_out_file)
    band_dts = dts_ds.GetRasterBand(1)
    nodata_dts = band_dts.GetNoDataValue()
    array_dts = band_dts.ReadAsArray()
    arraydts = ma.masked_where(array_dts == nodata_dts, array_dts)
    volumefolder = os.path.join(outputFolder, "Volume")
    volume_write = open(volumefolder+"/"+str(COMID)+".csv", 'a')
    volume_write.write("0,0\n")
    volume_write.close()
    for H in range(Hstart, HRange, dh):
        # subtract height from distance raster
        dts_value = arraydts-H*0.3048
        # find dts<0
        dts_less_height = dts_value < 0
        # count number of cell has less than zero
        count_cell = dts_less_height.sum()
        cell_height = dts_value[dts_less_height]*(-1)
        # volume
        volume_in = 10*10*cell_height
        volume = volume_in.sum()
        if type(volume) is not np.float32:
            continue
        volume_write = open(volumefolder+"/"+str(COMID)+".csv", 'a')
        volume_write.write(str(H*0.3048)+","+str(volume)+"\n")
        volume_write.close()


def Top_Width_Calculation(outputFolder, COMID, RiverLengthDic, dh):
    dh = dh*0.3048
    volumeFolder = os.path.join(outputFolder, "Volume")
    topwidthFolder = os.path.join(outputFolder, "TopWidth")
    Depth, Volume = np.loadtxt(volumeFolder+"/"+str(COMID)+".csv",
                               delimiter=',', skiprows=0,
                               usecols=(0, 1,), unpack=True)
    Riverlength = RiverLengthDic[str(COMID)]*1000
    Volume = Volume - Volume[0]
    DVolume = np.diff(Volume)
    DDepth = np.diff(Depth)
    TotalArea = Volume/Riverlength
    WAlist = list(TotalArea)
    DArea = DVolume/Riverlength
    dArea = np.diff(DArea)
    TWlist = []
    TemTW = []
    for i in range(DArea.size):
        TopWidth = DArea[i]/dh/(DDepth[i]/dh)
        TemTW.append(TopWidth)
    TWlist.append(TemTW[0])
    for i in range(len(TemTW)-1):
        TWlist.append((TemTW[i]+TemTW[i+1])/2)
    TWlist.append(TemTW[-1])
    TWlocation = os.path.join(topwidthFolder, str(COMID) + '.csv')
    np.savetxt(TWlocation, np.column_stack((Depth, TWlist)), delimiter=',',
               header="Depth,TopWidth", comments='')


def WA_WP_HR_Q_Calculation(outputFolder, COMID, SlopeDic, dh, roughness):
    topwidthFolder = os.path.join(outputFolder, "TopWidth")
    wetareaFolder = os.path.join(outputFolder, "WetArea")
    wetperimeterFolder = os.path.join(outputFolder, "WettedPerimeter")
    hydraulicradiusFolder = os.path.join(outputFolder, "HydraulicRadius")
    ratingcurveFolder = os.path.join(outputFolder, "RatingCurve")
    summaryFolder = os.path.join(outputFolder, "Summary")
    dh = dh*0.3048
    if os.path.exists(os.path.join(topwidthFolder, str(COMID)+".csv")):
        Depth, TWlist = np.loadtxt(os.path.join(topwidthFolder,
                                                str(COMID)+".csv"),
                                   delimiter=',', skiprows=1,
                                   usecols=(0, 1), unpack=True)
    DDepth = np.diff(Depth)
    WAlist = []
    WPlist = []
    HRlist = []
    Qlist = []
    WetArea = 0
    WetPerimeter = 0
    Slope = SlopeDic[str(COMID)]
    for i in range(len(TWlist)):
        if i == 0:
            WetArea = 0
            WAlist.append(WetArea)
        else:
            WetArea += (DDepth[i-1]/dh)*dh*(TWlist[i]+TWlist[i-1])/2
            WAlist.append(WetArea)
    for i in range(len(TWlist)):
        if i == 0:
            WetPerimeter = TWlist[i]
            WPlist.append(WetPerimeter)
        else:
            WetPerimeter += 2*sqrt((DDepth[i-1]/dh)*dh*(DDepth[i-1]/dh)*dh +
                                   ((TWlist[i]-TWlist[i-1])/2)**2)
            WPlist.append(WetPerimeter)
    HRlist.append(0)
    for i in range(1, len(TWlist)):
        HydraulicRadius = WAlist[i]/WPlist[i]
        HRlist.append(HydraulicRadius)
    Qlist.append(0)
    for i in range(1, len(TWlist)):
        if Slope >= 0:
            Discharge = WAlist[i]*(HRlist[i]**(2.0/3))*sqrt(Slope)/roughness
            Qlist.append(Discharge)
        else:
            Qlist.append(0)
    WAlocation = os.path.join(wetareaFolder, str(COMID)+".csv")
    np.savetxt(WAlocation, np.column_stack((Depth, WAlist)), delimiter=',',
               header="Depth,WetArea", comments='')
    WPlocation = os.path.join(wetperimeterFolder, str(COMID)+".csv")
    np.savetxt(WPlocation, np.column_stack((Depth, WPlist)), delimiter=',',
               header="Depth,WettedPerimeter", comments='')
    HRlocation = os.path.join(hydraulicradiusFolder, str(COMID)+".csv")
    np.savetxt(HRlocation, np.column_stack((Depth, HRlist)), delimiter=',',
               header="Depth,HydraulicRadius", comments='')
    HQlocation = os.path.join(ratingcurveFolder, str(COMID)+".csv")
    np.savetxt(HQlocation, np.column_stack((Depth, Qlist)), delimiter=',',
               header="Depth,Discharge", comments='')
    Sumlocation = os.path.join(summaryFolder, str(COMID)+".csv")
    np.savetxt(Sumlocation, np.column_stack((Depth,
                                             TWlist, WAlist, WPlist,
                                             HRlist, Qlist)), delimiter=',',
               header="Depth(m),TopWidth(m),WetArea(m^2),WettedPerimeter(m),"
               "HydraulicRadius(m),Discharge(M^3/s)", comments='')


def main():
    inShapefile = str(sys.argv[2])
    flowlineShapefile = str(sys.argv[4])
    HANDRaster = str(sys.argv[6])
    Hstart = 1
    dh = 1
    HRange = 50
    roughness = 0.05
    HANDClipper(inShapefile, flowlineShapefile,
                HANDRaster, Hstart, dh, HRange, roughness)


if __name__ == "__main__":
    main()
