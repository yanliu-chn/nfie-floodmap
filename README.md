# nfie-floodmap
National Inundation Mapping, collaboration among CyberGIS, NFIE, and HydroShare. Current code is based on the ROGER supercomputer environment.

So far, we are able to compute the Height Above Nearest Drainage (HAND) grid at 10m resolution for CONUS (conterminous U.S.) from the 10m USGS 3DEP national elevation dataset (NED) and the NHDPlus (National Hydrography Dataset) flowlines. The first run took about 7.5 days to finish (on April 15, 2016). Our goal is to reduce this to within one day through major algorithm enhancements in the two flow direction algorithms (D8 and D$\infty$).

The workflow of the HAND calculation is illustrated as below:
![alt text](http://141.142.170.172/nfiedata/yanliu/HAND-workflow.png)

We only compute the HAND grid for the nation once. Using HAND, we are developing the inundation mapping methodology by coupling various hydro models and NOAA weather information. We are also working on a scalable geospatial data storage, query, and visualization framework in a separate project in order to provide responsive 3D flood mapping visualization by coupling NED 10m (677GB GeoTIFF, 180 billion cells) or DEMs of finer resolution (e.g., those derived from LiDAR) and NHDPlus (2.67 million vectors) and NHD HR (30 million vectors).

If you refer to our work, please cite the following publication(s):
Yan Y Liu, David R Maidment, David G Tarboton, Xing Zheng, Ahmet Yildirim, Nazmus S Sazib and Shaowen Wang. 2016. “A CyberGIS Approach to Generating High-resolution Height Above Nearest Drainage (HAND) Raster for National Flood Mapping”. The Third International Conference on CyberGIS and Geospatial Data Science. July 26–28, 2016, Urbana, Illinois. http://dx.doi.org/10.13140/RG.2.2.24234.41925/1


