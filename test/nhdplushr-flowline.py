# This utility is an efficient way to do inner join of two layers 
# in NHDPlus HR to get flowline shapefile for a HUC unit
# Yan Y. Liu <yanliu@illinois.edu>
# 11/30/2016
# Input: HUC code
# Input: NHDPlus HR filegdb path
# Output: flowline shapefile
# Dependency: GDAL 2.1+ with python library support
import sys, os, string
from osgeo import gdal
from osgeo import ogr
import numpy as np

# function: filter NHDPlusFlowlineVAA layer using NHDPlusBurnLineEvent features and output FromNode and ToNode data. Output shapefile
def queryByHash(NHDDBPath = None, NHDCatchLayerName = None, flowIDField = None,  Hucid = None, odir = None, olyrName = None, flowHash = None):
    global keys
    global geoms
    global reachcodes
    global fromnodes
    global tonodes
    global srs
    global geomType
    if flowHash is None or len(flowHash) <= 0:
        print "queryByHash(): ERROR Flowline HASH is empty. \n"
        sys.exit( 1 )
    if not os.path.isdir(odir):
        print "queryByHash(): ERROR output dir not exists: " + str(odir) + "\n"
        sys.exit( 1 )
    of = odir + "/" + olyrName + ".shp"
    if os.path.exists(of):
        print "queryByHash(): ERROR output file already exists: " + str(of) + ". Remove and run this program again if you want to re-create. " + "\n"
        sys.exit( 1 )
    
    # open NHDPlus DB
    ds = gdal.OpenEx( NHDDBPath, gdal.OF_VECTOR | gdal.OF_READONLY)
    if ds is None :
        print "queryByHash(): ERROR Open failed: " + str(NHDDBPath) + "\n"
        sys.exit( 1 )
    lyr = ds.GetLayerByName( NHDCatchLayerName )
    if lyr is None :
        print "queryByHash(): ERROR fetch layer: " + str(NHDCatchLayerName) + "\n"
        sys.exit( 1 )
    lyr.ResetReading()
    num_records = lyr.GetFeatureCount()
    lyr_defn = lyr.GetLayerDefn()
    print "queryByHash(): Opening " + NHDCatchLayerName + " layer. num_records: " + str(num_records) + "\n"   

    fi_comid = lyr_defn.GetFieldIndex(flowIDField)
    fdef_comid = lyr_defn.GetFieldDefn(fi_comid)
    fi_fromnode = lyr_defn.GetFieldIndex('FromNode')
    fdef_fromnode = lyr_defn.GetFieldDefn(fi_fromnode)
    fi_tonode = lyr_defn.GetFieldIndex('ToNode')
    fdef_tonode = lyr_defn.GetFieldDefn(fi_tonode)

    # create output 
    driverName = "ESRI Shapefile"
    #driverName = "SQLite"
    drv = gdal.GetDriverByName( driverName )
    if drv is None:
        print "queryByHash(): ERROR %s driver not available.\n" % driverName
        sys.exit( 1 )
    ods = drv.Create( of, 0, 0, 0, gdal.GDT_Unknown )
    if ods is None:
        print "queryByHash(): ERROR Creation of output file failed: "+of+ "\n"
        sys.exit( 1 )
    olyr = ods.CreateLayer(olyrName, srs, geomType)
    if olyr is None:
        print "queryByHash(): ERROR Layer creation failed: "+olyrName+ "\n"
        sys.exit( 1 )
    # create fields
    ofdef_comid = ogr.FieldDefn( flowIDField, ogr.OFTInteger64)
    ofdef_reachcode = ogr.FieldDefn( "ReachCode", ogr.OFTString)
    ofdef_fromnode = ogr.FieldDefn( "FromNode", ogr.OFTInteger64)
    ofdef_tonode = ogr.FieldDefn( "ToNode", ogr.OFTInteger64)
    if olyr.CreateField ( ofdef_comid ) != 0 or olyr.CreateField ( ofdef_reachcode ) != 0 or olyr.CreateField ( ofdef_fromnode ) != 0 or olyr.CreateField ( ofdef_tonode ) != 0:
        print "queryByHash(): ERROR Creating fields in output .\n"
        sys.exit( 1 )
    # get integer index to speed up the loops
    olyr_defn = olyr.GetLayerDefn()
    ofi_comid = olyr_defn.GetFieldIndex(flowIDField )
    ofi_reachcode = olyr_defn.GetFieldIndex('ReachCode')
    ofi_fromnode = olyr_defn.GetFieldIndex('FromNode')
    ofi_tonode = olyr_defn.GetFieldIndex('ToNode')
    # filter and keep only the records with FEATUREID=COMID
    i = 0
    count = 0
    #comid_index_list = np.zeros(len(flowHash), dtype='int32')
    print "0%"
    for f in lyr: # for each row. in NHDPlus MR, it's 2.67m
        comid = f.GetFieldAsInteger64(fi_comid)
        if comid in flowHash: # computationally expensive if hash size is big
            fromnode = f.GetFieldAsInteger64(fi_fromnode) 
            tonode = f.GetFieldAsInteger64(fi_tonode) 
            if fromnode <= 0 or tonode <= 0:
                continue
            # create feature
            fc = ogr.Feature( olyr_defn )
            fc.SetField(ofi_comid, comid)
            comid_index = flowHash[comid]
            fc.SetField(ofi_reachcode, reachcodes[comid_index])
            fc.SetField(ofi_fromnode, fromnode)
            fc.SetField(ofi_tonode, tonode)
            # create geom field
            fc.SetGeometry( geoms[comid_index] ) # this method makes a copy of geom
            if olyr.CreateFeature( fc ) != 0:
                print "queryByHash(): ERROR Creating new feature in output for COMID=" + str(comid) + " .\n"
                sys.exit( 1 )
            fc.Destroy()
            #comid_index_list[count] = comid_index
            count += 1
        i += 1
        if (i % (num_records / 10 + 1) == 0):
            print "-->" + str((i * 100)/num_records) + "%"

    print "FLOWLINEJOIN " + str(count) + " features with FromNode-ToNode matched with " + str(len(flowHash)) + " lines in " + str(Hucid) + "\n"
    print "\nDone\n"

    ds = None
    ods = None
   

# function: build hash for flowline keys (NHDPlusID) from NHDPlusBurnLineEvent 
def buildFlowlineHash(flowShpFile = None, lyrName = None, keyFieldName = None, flowHucid = None):
    global keys
    global geoms
    global reachcodes
    global fromnodes
    global tonodes
    global srs
    global geomType
    # open shape file
    ds = gdal.OpenEx( flowShpFile, gdal.OF_VECTOR | gdal.OF_READONLY)
    if ds is None :
        print "buildFlowlineHash(): ERROR Open failed: " + str(flowShpFile) + "\n"
        sys.exit( 1 )
    lyr = ds.GetLayerByName( lyrName )
    if lyr is None :
        print "buildFlowlineHash(): ERROR fetch layer: " + str(lyrName) + "\n"
        sys.exit( 1 )
    lyr.ResetReading()
    num_records = lyr.GetFeatureCount()
    lyr_defn = lyr.GetLayerDefn()

    srs = lyr.GetSpatialRef().Clone()
    geomType = lyr.GetGeomType()
    geomTypeStr = ""
    if geomType == ogr.wkbPolygon:
        geomTypeStr = "Polygon"
    if geomType == ogr.wkbMultiPolygon:
        geomTypeStr = "MultiPolygon"
    if geomType == ogr.wkbMultiLineString:
        geomTypeStr = "MultiLineString"

    fi_comid = lyr_defn.GetFieldIndex(keyFieldName)
    fi_reachcode = lyr_defn.GetFieldIndex('ReachCode')
    if fi_comid < 0 or fi_reachcode < 0 :
        print "buildFlowlineHash(): ERROR no key/slope field: " + str(keyFieldName) + "\n"
        sys.exit( 1 )

    # scan for keys. dunno size after match; so use dyna list
    #keys = np.zeros(num_records, dtype='int64')
    keys = []
    geoms = [] # geom feature list
    #reachcodes = ["" for x in range(num_records)]
    reachcodes = []
    i = 0
    for f in lyr:
        reachcode = f.GetFieldAsString(fi_reachcode)
        if reachcode.find(flowHucid) == 0: # match the begging substring
            keys.append (f.GetFieldAsInteger64(fi_comid))
            reachcodes.append (reachcode)
            geoms.append(f.GetGeometryRef().Clone() )
        i+=1

    ds = None   # close input layer 

    count=len(keys)
    print "FLOWLINE_FILTER " + str(len(keys)) + " lines extracted for HUC " + str(flowHucid) + " from " + str(num_records) + " lines in " + lyrName +"\n"
    # build hash
    #flowHash = frozenset(keys) # hash as frozenset
    flowHash = dict.fromkeys(keys) # hash as pre-sized dictionary
    for j in range(0, count):
        flowHash[keys[j]] = j

    # now we know the max size for fromnode and tonodes
    fromnodes = np.zeros(count, dtype='int64')
    tonodes = np.zeros(count, dtype='int64')

    # return
    return flowHash

# global vars
keys=None
geoms=None
reachcodes=None
fromnodes=None
tonodes=None
srs=None
geomType=None

# usage: 
# module purge
# module load gdal2.1.2-stack
# python /projects/nfie/nfie-floodmap/test/nhdplushr-flowline.py 120902 /gpfs_scratch/usgs/nhd/nhdplus-hr/data/HRNHDPlus1209.gdb NHDPlusID . 120902-flows
if __name__ == '__main__':
    flowHucid = sys.argv[1] # HUC id
    NHDDBPath = sys.argv[2] # NHDPlus DB (filegdb) path
    flowIDField = sys.argv[3] # COMID or NHDPlusID
    lineLayerName = 'NHDPlusBurnLineEvent' # NHDPlus HR (filegdb) 
    nodeLayerName = 'NHDPlusFlowlineVAA' # NHDPlus HR (filegdb) 
    outputdir = sys.argv[4] # output dir
    olyrName = sys.argv[5] # output dir

    # build hash for COMID
    flowHash = buildFlowlineHash(NHDDBPath, lineLayerName, flowIDField, flowHucid)
    print sys.argv[0] + ": Built hash with " + str(len(flowHash)) + " COMIDs\n"

    # filter Catchment layer and output
    queryByHash(NHDDBPath, nodeLayerName, flowIDField, flowHucid, outputdir,olyrName,  flowHash)



