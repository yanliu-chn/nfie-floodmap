# nfie-floodmap
The NFIE (National Flood Interoperability Experiment) continental flood inundation mapping (CFIM) framework is a computational framework for the new Height Above Nearest Drainage (HAND)-based inundation mapping methodology. The development is a collaboration among NSF projects (CyberGIS, NFIE, HydroShare, XSEDE (ECSS)), research institutions (UT Austin, Utah State U., UIUC), government agencies (USGS and NOAA NWS), and industry (Esri). The computation was originally done on the ROGER cluster at NCSA, now at TACC using Stampede 2, Wrangler, and JetStream.

So far, we are able to compute the Height Above Nearest Drainage (HAND) grid at 10m resolution for CONUS (conterminous U.S.) from the 10m USGS 3DEP national elevation dataset (NED) and NHDPlus (National Hydrography Dataset Plus) medium and high resolution datasets. For now, we are able to compute HAND at 10m resolution for 331 HUC6 units in CONUS within 1.5 days; hydraulic property table in 2.5 hours (covering 2.7 million river reaches in NHDPlus MR); inundation table in 10 minutes, and inundation maps in 30 minutes. We employ TauDEM, a high-performance hydrologic information analysis software, with major algorithm enhancements in the two flow direction algorithms (D8 and D$\infty$).

The workflow of the HAND calculation is illustrated as below:
![alt text](https://web.corral.tacc.utexas.edu/nfiedata/docs/hand-workflow.png)

The workflow of the construction of hydraulic property table and inundation maps is illustrated as below:
![alt text](https://web.corral.tacc.utexas.edu/nfiedata/docs/inunmap-workflow.png) 

We only compute the HAND grid for the nation once. Using HAND, we are developing the inundation mapping methodology by coupling various hydro models and NOAA weather information. We are also working on a scalable geospatial data storage, query, and visualization framework in a separate project in order to provide responsive 3D flood mapping visualization by coupling NED 10m (677GB GeoTIFF, 180 billion cells) or DEMs of finer resolution (e.g., those derived from LiDAR) and NHDPlus (2.67 million vectors) and NHD HR (30 million vectors).

## Data
We currently host all the [HAND and inundation map data](https://web.corral.tacc.utexas.edu/nfiedata/) at TACC's Corral storage system. Please download what you need there.

## Publications
### Presentations
[A CyberGIS Integration and Computation Framework for High-Resolution Continental-Scale Flood Inundation Mapping](https://web.corral.tacc.utexas.edu/nfiedata/docs/NFIE-CFIM-JAWRA-YanLiu-20170619.pdf), presentation associated with the JAWRA journal paper.

### Papers
If you refer to our work, please cite the following publication(s):

Liu, Yan Y., David R. Maidment, David G. Tarboton, Xing Zheng, and Shaowen Wang. 2018. A CyberGIS Integration and Computation Framework for High-Resolution Continental-Scale Flood Inundation Mapping. *Journal of the American Water Resources Association (JAWRA)*. Accepted.

Liu, Yan Y., David R. Maidment, David G. Tarboton, Xing Zheng, Ahmet Yildirim, Nazmus S. Sazib and Shaowen Wang. 2016. A CyberGIS Approach to Generating High-resolution Height Above Nearest Drainage (HAND) Raster for National Flood Mapping. *The Third International Conference on CyberGIS and Geospatial Data Science*. July 26–28, 2016, Urbana, Illinois. http://dx.doi.org/10.13140/RG.2.2.24234.41925/1


