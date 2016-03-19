/*  
University of Illinois/NCSA Open Source License

find_inlets: A software tool to find the inlet points in the shape file using a reference DEM file

Copyright (c) 2014-2016 CyberInfrastructure and Geospatial Information Laboratory (CIGI), University of Illinois at Urbana-Champaign. All rights reserved.

Developed by: CyberInfrastructure and Geospatial Information Laboratory (CIGI)
University of Illinois at Urbana-Champaign
http://cigi.illinois.edu
 */

#include <cstdlib>
#include <string>
#include <iostream>
#include <vector>
#include <algorithm>

#include <gdal.h>
#include <gdal_priv.h>
#include <ogr_spatialref.h>
#include <float.h>
#include <ogr_core.h>

using namespace std;

struct Point {
    Point(double _x, double _y) : x(_x), y(_y) {
    }

    Point() : x(-1), y(-1) {
    }

    double x;
    double y;
};

struct LineList {
    vector<Point> points;
    Point sPoint;
    Point ePoint;
};

static string shapefile;
static string demfile;
static string danglefile;
static GDALDatasetH hDSDem;
static GDALRasterBandH hBandDem;
static int widthDem, heightDem;
static double nodataDem;
static OGRSpatialReferenceH hSpatialRefRaster;
static float* dataDem;
static double pixelwidthDem;
static double pixelheightDem;
static double xleftedgeDem;
static double ytopedgeDem;

static void findInletPoints();
static void loadDEM();
static float getPointElev(double pointx, double pointy);
static bool inLine(Point A, Point B, Point C);
static double distance(Point A, Point B);

static double err = 0.00000000000000001;

double distance(Point A, Point B) {
    return ((A.x - B.x)*(A.x - B.x)) + ((A.y - B.y)*(A.y - B.y));
}

bool inLine(Point A, Point B, Point C) {
    if (distance(A, C) + distance(B, C) - distance(A, B) < err)
        return true;
    return false;
}

float getPointElev(double pointx, double pointy) {
    int pixellocx = ((double) (pointx - xleftedgeDem) / pixelwidthDem);
    int pixellocy = ((double) (pointy - ytopedgeDem) / pixelheightDem);

    if (pixellocx < 0 || pixellocx >= widthDem || pixellocy < 0 || pixellocy >= heightDem) {
        cerr << "WARNING: Dangle coordinate is out of bound x: " << pixellocx << " y: " << pixellocy << endl;
        return nodataDem;
    }

    float elev = dataDem[pixellocy * widthDem + pixellocx];
    if (elev == nodataDem)
        cerr << "WARNING: Dangle elevation is NODATA x: " << pixellocx << " y: " << pixellocy << endl;

    return elev;
}

static void loadDEM() {
    hDSDem = GDALOpen(demfile.c_str(), GA_ReadOnly);
    if (hDSDem == NULL) {
        cerr << "ERROR: Failed to open the file: " << demfile << endl;
	cerr << "GDAL Msg: " << CPLGetLastErrorMsg() << endl;
        exit(1);
    }

    hBandDem = GDALGetRasterBand(hDSDem, 1);
    widthDem = GDALGetRasterXSize(hDSDem);
    heightDem = GDALGetRasterYSize(hDSDem);
    nodataDem = GDALGetRasterNoDataValue(hBandDem, NULL);

    char *pszProjection;
    double geotransformDem[6];
    pszProjection = (char *) GDALGetProjectionRef(hDSDem);
    hSpatialRefRaster = OSRNewSpatialReference(pszProjection);
    GDALGetGeoTransform(hDSDem, geotransformDem);

    pixelwidthDem = geotransformDem[1];
    pixelheightDem = geotransformDem[5];
    xleftedgeDem = geotransformDem[0];
    ytopedgeDem = geotransformDem[3];

    dataDem = (float *) CPLMalloc(sizeof (float) * widthDem * heightDem);
    if (!dataDem) {
        cerr << "ERROR: Failed to allocate data of size " << sizeof (float) * widthDem * heightDem << endl;
        exit(1);
    }

    GDALRasterIO(hBandDem, GF_Read, 0, 0, widthDem, heightDem, dataDem, widthDem, heightDem,
            GDT_Float32, 0, 0);
}

static void findInletPoints() {
    GDALDatasetH hDSFlow;
    OGRLayerH hLayerFlow;
    
    hDSFlow = GDALOpenEx(shapefile.c_str(), GDAL_OF_VECTOR, NULL, NULL, NULL);
    if (hDSFlow == NULL) {
        cerr << "ERROR: Failed to open the file: " << shapefile << endl;
	cerr << "GDAL Msg: " << CPLGetLastErrorMsg() << endl;
        exit(1);
    }
    
    loadDEM();

    OGRSpatialReferenceH hSpatialRefFlowLines = OSRNewSpatialReference(GDALGetProjectionRef(hDSFlow));
    OGRCoordinateTransformationH spatialTransform = OCTNewCoordinateTransformation(hSpatialRefFlowLines, hSpatialRefRaster);

    hLayerFlow = GDALDatasetGetLayer(hDSFlow, 0);

    if (hLayerFlow == NULL) {
        cerr << "ERROR: Failed to open layer of the shapefile: " << shapefile << endl;
	cerr << "GDAL Msg: " << CPLGetLastErrorMsg() << endl;
        exit(1);
    }

    vector<LineList> lineStrings;

    OGR_L_ResetReading(hLayerFlow);
    
    OGRFeatureH hFeature;
    while ((hFeature = OGR_L_GetNextFeature(hLayerFlow)) != NULL) {
        OGRGeometryH hGeometry;
        hGeometry = OGR_F_GetGeometryRef(hFeature);

        LineList lString;
        if (hGeometry != NULL) {
            OGRwkbGeometryType gType = wkbFlatten(OGR_G_GetGeometryType(hGeometry));
            if (gType == wkbLineString) {
                int pointCount = OGR_G_GetPointCount(hGeometry);
                double* xBuffer = (double*) malloc(sizeof (double) * pointCount);
                double* yBuffer = (double*) malloc(sizeof (double) * pointCount);
                int pc = OGR_G_GetPoints(hGeometry, xBuffer, sizeof (double), yBuffer, sizeof (double), NULL, 0);
                lString.sPoint = Point(xBuffer[0], yBuffer[0]);
                lString.ePoint = Point(xBuffer[pc - 1], yBuffer[pc - 1]);

                for (int i = 0; i < pc; ++i)
                    lString.points.push_back(Point(xBuffer[i], yBuffer[i]));

                free(xBuffer);
                free(yBuffer);
            }
        }
        lineStrings.push_back(lString);
        OGR_F_Destroy(hFeature);
    }
    GDALClose(hDSFlow);

    const char *pszDriverName = "ESRI Shapefile";
    GDALDriver *poDriver;
    poDriver = (GDALDriver*) GDALGetDriverByName(pszDriverName);
    if (poDriver == NULL) {
        cerr << "ERROR: " << pszDriverName << " driver is not available" << endl;
        exit(1);
    }

    GDALDatasetH poDS;

    poDS = GDALCreate(poDriver, danglefile.c_str(), 0, 0, 0, GDT_Unknown, NULL);
    if (poDS == NULL) {
        cerr << "ERROR: Failed to create file: " << danglefile << endl;
        exit(1);
    }

    OGRLayerH hLayerOut;
    hLayerOut = GDALDatasetCreateLayer(poDS, "Dangles", hSpatialRefRaster, wkbPoint, NULL);
    if (hLayerOut == NULL) {
        cerr << "ERROR: Failed to create Dangles layer in file: " << danglefile << endl;
        exit(1);
    }

    OGRFieldDefnH hFieldDefn;
    hFieldDefn = OGR_Fld_Create("Elevation", OFTReal);
    if (OGR_L_CreateField(hLayerOut, hFieldDefn, TRUE) != OGRERR_NONE) {
        cerr << "ERROR: Failed to create Elevation field in file: " << danglefile << endl;
        exit(1);
    }
    OGR_Fld_Destroy(hFieldDefn);

    int i, j, k;

    GIntBig outletpoint = -1;
    float minelev = FLT_MAX;
    double outletpointx, outletpointy;
    float elev;
    for (i = 0; i < lineStrings.size(); ++i) {
        LineList lstring = lineStrings[i];

        bool isSInLine = false;
        bool isEInLine = false;

        for (j = 0; j < lineStrings.size(); ++j) {
            if (i == j)
                continue;

            LineList lstring2 = lineStrings[j];

            for (k = 0; k < lstring2.points.size() - 1; ++k) {
                Point a = lstring2.points[k];
                Point b = lstring2.points[k + 1];
                Point sc = lstring.sPoint;
                Point ec = lstring.ePoint;

                if (inLine(a, b, sc))
                    isSInLine = true;

                if (inLine(a, b, ec))
                    isEInLine = true;
            }
        }

        if (!isSInLine) {
            OGRFeatureH hFeature;
            hFeature = OGR_F_Create(OGR_L_GetLayerDefn(hLayerOut));

            OGRGeometryH hPt;
            hPt = OGR_G_CreateGeometry(wkbPoint);
            OGR_G_SetPoint_2D(hPt, 0, lstring.sPoint.x, lstring.sPoint.y);
            OGR_F_SetGeometry(hFeature, hPt);
            if (spatialTransform)
                OGR_G_Transform(hPt, spatialTransform);
            OGR_G_GetPoint(hPt, 0, &outletpointx, &outletpointy, NULL);
            elev = getPointElev(outletpointx, outletpointy);
            OGR_G_DestroyGeometry(hPt);

            OGR_F_SetFieldDouble(hFeature, OGR_F_GetFieldIndex(hFeature, "Elevation"), elev);

            if (OGR_L_CreateFeature(hLayerOut, hFeature) != OGRERR_NONE) {
                cerr << "ERROR: Failed to create feature in file: " << danglefile << endl;
                exit(1);
            }

            if (elev != nodataDem && elev < minelev) {
                outletpoint = OGR_F_GetFID(hFeature);
                minelev = elev;
            }

            OGR_F_Destroy(hFeature);
        }

        if (!isEInLine) {
            OGRFeatureH hFeature;
            hFeature = OGR_F_Create(OGR_L_GetLayerDefn(hLayerOut));

            OGRGeometryH hPt;
            hPt = OGR_G_CreateGeometry(wkbPoint);
            OGR_G_SetPoint_2D(hPt, 0, lstring.ePoint.x, lstring.ePoint.y);
            OGR_F_SetGeometry(hFeature, hPt);
            if (spatialTransform)
                OGR_G_Transform(hPt, spatialTransform);
            OGR_G_GetPoint(hPt, 0, &outletpointx, &outletpointy, NULL);
            elev = getPointElev(outletpointx, outletpointy);
            OGR_G_DestroyGeometry(hPt);

            OGR_F_SetFieldDouble(hFeature, OGR_F_GetFieldIndex(hFeature, "Elevation"), elev);

            if (OGR_L_CreateFeature(hLayerOut, hFeature) != OGRERR_NONE) {
                cerr << "ERROR: Failed to create feature in file: " << danglefile << endl;
                exit(1);
            }

            if (elev != nodataDem && elev < minelev) {
                outletpoint = OGR_F_GetFID(hFeature);
                minelev = elev;
            }

            OGR_F_Destroy(hFeature);
        }
    }

    if (outletpoint != -1)
        OGR_L_DeleteFeature(hLayerOut, outletpoint);

    GDALClose(poDS);
    
    free(dataDem);
}

void usage() {
    cout << "INFO: Finds the dangle points on the flow file (-flow)" << endl;
    cout << "INFO: Outlet point is removed using dem file (-dem)" << endl;
    cout << "INFO: Writes the result inlets into shape file (-inletsout)" << endl;
    cout << "USAGE: find_dangles -flow [shape file of flow lines] -dem [reference dem file] -inletsout [output shape file] (default: inlets.shp)" << endl;
}

/*
 * 
 */
int main(int argc, char** argv) {
    GDALAllRegister();
    
    shapefile = "";
    demfile = "";
    danglefile = "";
    
    for (int i = 1; i < argc; ++i) {
        if (string(argv[i]) == "-flow") {
	    if (i + 1 < argc)
	        shapefile = string(argv[++i]);
        } else if (string(argv[i]) == "-dem") {
 	    if (i + 1 < argc)
                demfile = string(argv[++i]);
        } else if (string(argv[i]) == "-inletsout") {
           if (i + 1 < argc) 
  	       danglefile = string(argv[++i]);
        }
    }
    
    if (danglefile == "") {
        danglefile = "inlets.shp";
    }
    
    if (shapefile == "" || demfile == "") {
        usage();
        exit(1);
    }

    findInletPoints();
    return 0;
}


