#!/bin/bash
source /gpfs_scratch/nfie/users/yanliu/forecast/softenv
time python -m memory_profiler /projects/nfie/nfie-floodmap/test/csv2netcdf-hydroprop-fulltable.py /gpfs_scratch/nfie/users/HUC6 /gpfs_scratch/nfie/users/hydroprop/hydroprop-fulltable.nc
