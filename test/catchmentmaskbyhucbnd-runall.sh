#!/bin/bash
# run all on in a single job

sdir=/projects/nfie/nfie-floodmap/test/HUC6-catchmenthucbnd-scripts
ldir=/projects/nfie/nfie-floodmap/test/HUC6-catchmenthucbnd-logs
for s in `ls $sdir`
do
    n=`basename $s .sh`
    echo "/bin/bash $sdir/$s 1>$ldir/$n.stdout 2>$ldir/$n.stderr"
    /bin/bash $sdir/$s 1>$ldir/$n.stdout 2>$ldir/$n.stderr
done
