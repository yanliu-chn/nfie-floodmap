#!/bin/bash
wdir=/gpfs_scratch/nfie/HUC6
count=0
failed=0
for d in `ls -d $wdir/*`
do
    if [ -f $d/stdout ]; then
        s=`grep "=STAT=" $d/stdout`
        if [ -z "$s" ]; then
            echo "FAILED: `basename $d`"
            let "failed+=1"
        else
            echo "$s"
        fi
        let "count+=1"
    else
        echo "$d has not output"
    fi
done
echo 
echo "$count finished. $failed failed. `expr $count \- $failed` done."

