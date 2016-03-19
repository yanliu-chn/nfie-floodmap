module load gdal2-stack
module load GCC/5.1.0-binutils-2.25
mkdir build
cd build
cmake .. -DGDAL_INCLUDE_DIR=/sw/geosoft/gdal-2.0.1-fgdb/include
make
