#!/bin/bash
source /gpfs_scratch/nfie/users/yanliu/forecast/softenv
time python /projects/nfie/nfie-floodmap/test/forecast-table.py /gpfs_scratch/nfie/users/HUC6 /gpfs_scratch/nfie/users/yanliu/forecast/nwm.t00z.short_range.channel_rt.f001.conus.nc /gpfs_scratch/nfie/users/hydroprop
