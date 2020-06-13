# conus_clip: clip US conus boundary from WBD.
# if conus shp contains a wbd, return nothing
# if conus shp intersects a wbd, return the intersection as shp
# this tool is used to clip hand rasters that have anomalies on conus land border,
# including:
# 040900 090300 040101 090203 171100 150301 181002 150801 150802 150503 150502 150803 130302 130301 130401 130402 130800 130900 041503 041505
import sys, os, string
from osgeo import gdal
from osgeo import ogr
import numpy as np

def conus_clip(conusShpFile = None, conusLyrName = None, wbdShpFile = None, wbdLyrName = None, of = None):

    # open boundary shp file
    bds = gdal.OpenEx( conusShpFile, gdal.OF_VECTOR | gdal.OF_READONLY)
    if bds is None :
        print ("conus_clip(): ERROR Open failed: " + str(conusShpFile) )
        sys.exit( 1 )
    blyr = bds.GetLayerByName( conusLyrName )
    if blyr is None :
        print ("conus_clip(): ERROR fetch layer: " + str(conusLyrName) )
        sys.exit( 1 )
    blyr.ResetReading()
    bnd = None
    for f in blyr:
        bnd = f.GetGeometryRef().Clone()
        #print(bnd.ExportToWkt())
        break # assume the first feature has the boundary polygon
    bds = None

    # open wbd shape/db file
    ds = gdal.OpenEx( wbdShpFile, gdal.OF_VECTOR | gdal.OF_READONLY)
    if ds is None :
        print ("conus_clip(): ERROR Open failed: " + str(wbdShpFile) )
        sys.exit( 1 )
    lyr = ds.GetLayerByName( wbdLyrName )
    if lyr is None :
        print ("conus_clip(): ERROR fetch layer: " + str(wbdLyrName) )
        sys.exit( 1 )
    lyr.ResetReading()
    num_records = lyr.GetFeatureCount()
    lyr_defn = lyr.GetLayerDefn()
    srs = lyr.GetSpatialRef()
    #print("flowline shp has " + str(num_records) + " lines")
    feature = None
    for f in lyr:
        geom = f.GetGeometryRef()
        feature = f
        break # taking the outmost shp

    newGeom = None
    if not bnd.Contains(geom): # if contained, no need to clip
        if geom.Intersects(bnd): # now clip
            newGeom = geom.Intersection(bnd)
            if not newGeom.IsValid():
                print("WARN intersection seems not a valid geom")
    if newGeom is None:
        return

    geomType = newGeom.GetGeometryType()

    # output flowline shp file
    driverName = "ESRI Shapefile"
    drv = gdal.GetDriverByName( driverName )
    if drv is None:
        print ("conus_clip(): ERROR %s driver not available.\n" % (driverName) )
        sys.exit( 1 )
    ods = drv.Create( of, 0, 0, 0, gdal.GDT_Unknown )
    if ods is None:
        print ("conus_clip(): ERROR Creation of output file failed: "+of)
        sys.exit( 1 )
    oLyrName, ext = os.path.splitext(os.path.basename(of))
    olyr = ods.CreateLayer( oLyrName, srs, geomType)
    if olyr is None:
        print ("conus_clip(): ERROR Layer creation failed: "+ oLyrName)
        sys.exit( 1 )
    # create fields
    for i in range(lyr_defn.GetFieldCount()):
        if (olyr.CreateField(lyr_defn.GetFieldDefn(i)) != 0):
            print ("conus_clip(): ERROR Creating fields in output .")
            sys.exit( 1 )

    newFeature = ogr.Feature(lyr_defn)
    newFeature.SetFrom(feature)
    newFeature.SetGeometry(newGeom)
    if olyr.CreateFeature(newFeature) != 0:
        print ("conus_clip(): ERROR Creating fields in output .")
        sys.exit( 1 )

    ods = None
    ds = None

if __name__ == '__main__':
    conusShpFile = sys.argv[1]
    conusLyrName = sys.argv[2]
    wbdShpFile = sys.argv[3]
    wbdLyrName = sys.argv[4] 
    of = sys.argv[5] # output shp file name

    conus_clip(conusShpFile, conusLyrName, wbdShpFile, wbdLyrName, of)
 
