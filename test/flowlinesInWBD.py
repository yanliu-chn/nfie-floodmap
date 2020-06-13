# flowlinesInWBD: fetch all the flowlines in or intersecting the input boundary
# polygon (WBD). This is an improvement over original ogr query based on 
# reach code's HUC prefix. 
import sys, os, string
from osgeo import gdal
from osgeo import ogr
import numpy as np

def flowlinesInWBD(hucid = None, keyFieldName = None, shpFile = None, lyrName = None, wbdShpFile = None, wbdLayer = None, of = None):

    # open boundary shp file
    bds = gdal.OpenEx( wbdShpFile, gdal.OF_VECTOR | gdal.OF_READONLY)
    if bds is None :
        print ("flowlinesInWBD(): ERROR Open failed: " + str(wbdShpFile) )
        sys.exit( 1 )
    blyr = bds.GetLayerByName( wbdLyrName )
    if blyr is None :
        print ("flowlinesInWBD(): ERROR fetch layer: " + str(wbdLyrName) )
        sys.exit( 1 )
    blyr.ResetReading()
    bnd = None
    bndbbox = None
    bbb = None
    for f in blyr:
        bnd = f.GetGeometryRef().Clone()
        bbb = bnd.GetEnvelope() # minX, maxX, minY, maxY
        bndbbox = ogr.CreateGeometryFromWkt("POLYGON ((%f %f, %f %f, %f %f, %f %f, %f %f))" % ( \
                  bbb[0], bbb[2], \
                  bbb[0], bbb[3], \
                  bbb[1], bbb[3], \
                  bbb[1], bbb[0], \
                  bbb[0], bbb[2]))
        #print("fetched boundary geometry:")
        #print(bnd.ExportToWkt())
        break # assume the first feature has the boundary polygon
    bds = None

    # open flowline shape/db file
    ds = gdal.OpenEx( shpFile, gdal.OF_VECTOR | gdal.OF_READONLY)
    if ds is None :
        print ("flowlinesInWBD(): ERROR Open failed: " + str(shpFile) )
        sys.exit( 1 )
    lyr = ds.GetLayerByName( lyrName )
    if lyr is None :
        print ("flowlinesInWBD(): ERROR fetch layer: " + str(lyrName) )
        sys.exit( 1 )
    lyr.ResetReading()
    num_records = lyr.GetFeatureCount()
    lyr_defn = lyr.GetLayerDefn()
    srs = lyr.GetSpatialRef()
    geomType = lyr.GetGeomType()
    print("flowline shp has " + str(num_records) + " lines")

    o = [] # hold filtered features

    count_codematch = 0
    count_geommatch = 0
    #count = 0
    fi_comid = lyr_defn.GetFieldIndex(keyFieldName)
    for f in lyr:
        key = f.GetFieldAsString(fi_comid)
        #print("key: " + key)
        if key.startswith(hucid):
            o.append(f)
            count_codematch += 1
        else:
            geom = f.GetGeometryRef()
            #print(geom.ExportToWkt())
            # bb in bbb? 
            bb = geom.GetEnvelope() # minX, maxX, minY, maxY
            fineCheck = False
            for x in range(0, 2): # any point is in bnd bbox means further check
                for y in range(2, 4):
                    if bb[x] > bbb[0] and bb[x] < bbb[1] and bb[y] > bbb[2] and bb[y] < bbb[3]:
                        fineCheck = True
                        break
                if fineCheck:
                    break
            if fineCheck:
                if bndbbox.Contains(geom) or geom.Intersects(bndbbox):
                    if bnd.Contains(geom) or geom.Intersects(bnd):
                        o.append(f)
                        count_geommatch += 1
            #geom.Destroy()
        #count += 1
        #if count % 100000 == 0:
        #    print("progress --> %d %d %d" % (count, count_codematch, count_geommatch))
    bndbbox.Destroy()
    print("selected " + str(len(o)) + " features, " + str(count_codematch) + " code matched, " + str(count_geommatch) + " geom matched")

    # output flowline shp file
    driverName = "ESRI Shapefile"
    drv = gdal.GetDriverByName( driverName )
    if drv is None:
        print ("flowlinesInWBD(): ERROR %s driver not available.\n" % (driverName) )
        sys.exit( 1 )
    ods = drv.Create( of, 0, 0, 0, gdal.GDT_Unknown )
    if ods is None:
        print ("flowlinesInWBD(): ERROR Creation of output file failed: "+of)
        sys.exit( 1 )
    oLyrName, ext = os.path.splitext(os.path.basename(of))
    olyr = ods.CreateLayer( oLyrName, srs, geomType)
    if olyr is None:
        print ("flowlinesInWBD(): ERROR Layer creation failed: "+ oLyrName)
        sys.exit( 1 )
    # create fields
    for i in range(lyr_defn.GetFieldCount()):
        if (olyr.CreateField(lyr_defn.GetFieldDefn(i)) != 0):
            print ("flowlinesInWBD(): ERROR Creating fields in output .")
            sys.exit( 1 )

    for f in o:
        if olyr.CreateFeature(f) != 0:
            print ("flowlinesInWBD(): ERROR Creating fields in output .")
            sys.exit( 1 )

    ods = None
    ds = None

if __name__ == '__main__':
    hucid = sys.argv[1] # HUC id
    keyFieldName = sys.argv[2] # HUC id keyFieldName, 'REACHCODE'
    shpFile = sys.argv[3] # flowline shp path for the HUC   
    lyrName = sys.argv[4] # layer name   
    wbdShpFile = sys.argv[5] # wbd bounaary shp path for the HUC   
    wbdLyrName = sys.argv[6] # wbd layer name   
    of = sys.argv[7] # output shp file name

    flowlinesInWBD(hucid, keyFieldName, shpFile, lyrName, wbdShpFile, wbdLyrName, of)
 
