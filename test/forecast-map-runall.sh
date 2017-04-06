#!/bin/bash
# run all on in a single job
# Yan Y. Liu <yanliu@illinois.edu>, 01/03/2017

sdir=/projects/nfie/nfie-floodmap/test/HUC6-inunmap-scripts
ldir=/projects/nfie/nfie-floodmap/test/HUC6-inunmap-logs
for s in `ls $sdir`
do
    n=`basename $s .sh`
    echo "/bin/bash $sdir/$s 1>$ldir/$n.stdout 2>$ldir/$n.stderr"
    /bin/bash $sdir/$s 1>$ldir/$n.stdout 2>$ldir/$n.stderr
done
