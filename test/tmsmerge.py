# tmsmerge.py: merge TMS tile images using ImageMagick
# Yan Y. Liu <yanliu@illinois.edu>, 02/07/2017
# 20200515: upgraded to python 3

import sys
import os
import time
import getopt
import glob
import shutil
import re
import subprocess

# build a dictionary to index tiles, each tile may have multiple tile images
# from separate directories
def indexTiles(rdir=None, zoomLevel=10, imgFormat='png'):
    wildcard = rdir + '/*/' + str(zoomLevel) + '/*/*.' + imgFormat
    flist = glob.glob(wildcard)
    print("STAT.Zoom" + str(zoomLevel) + " : " + str(len(flist)) + " tile images")
    matchPattern = '^.+/([0-9]+)/([0-9]+)\.'+imgFormat+'$'
    myre = re.compile(matchPattern)
    h = {}
    for f in flist:
        mo = myre.match(f)
        if not mo :
            continue
        xy = mo.group(1, 2) # 0 is the full string
        key = str(xy[0]) + '.' + str(xy[1])
        if key not in h:
            h[key] = [ f ]
        else:
            h[key].append(f)
    return {
        'num_files': len(flist),
        'h': h
    }

if __name__ == '__main__':
    ridir = sys.argv[1] # TMS root dir
    rodir = sys.argv[2] # TMS output root dir
    zoomStart = int(sys.argv[3]) # starting zoom level, inclusive
    zoomEnd = int(sys.argv[4]) # ending zoom level, inclusive
    imgFormat = 'png'
    stat=[0,0,0,0,0]
    for zoom in range(zoomStart, zoomEnd + 1):
        r = indexTiles(ridir, zoom, imgFormat) # build hash
        num_srctiles = r['num_files']
        h = r['h']
        num_cp = 0
        num_merge = 0
        num_err = 0
        rzodir = rodir + '/' + str(zoom)
        if not os.path.isdir(rzodir):
            os.mkdir(rzodir)
        for k, flist in h.items():
            xy = k.split('.')
            x = xy[0]
            y = xy[1]
            odir = rzodir + '/' + x
            if not os.path.isdir(odir):
                os.mkdir(odir)
            if os.path.exists(odir + '/' + y + '.' + imgFormat):
                continue # by pass
            if (len(flist) == 1): # copy
                cmd = ['cp', flist[0], odir+'/']
                print('CMD: ' + ' '.join(cmd))
                succ = subprocess.call(cmd, stderr=subprocess.STDOUT, shell=False)
                if succ != 0:
                    num_err += 1
                else:
                    num_cp += 1
            else : # use convert to merge tile images
                cmd = ['convert', flist[0], flist[1]]
                for i in range(2, len(flist)):
                    cmd.append('-composite')
                    cmd.append(flist[i])
                cmd.append('-composite')
                cmd.append(odir + '/' + y + '.' + imgFormat)
                print('CMD: ' + ' '.join(cmd))
                succ = subprocess.call(cmd, stderr=subprocess.STDOUT, shell=False)
                if succ != 0:
                    num_err += 1
                else:
                    num_merge += 1
        print("STAT-Zoom" + str(zoom) + " summary: " + str(num_srctiles) + " srctiles " +  str(len(h)) + " dsttiles " + str(num_cp) + " copied " + str(num_merge) + " merged " + str(num_err) + " failed")
        sys.stdout.flush()
        stat[0] += num_srctiles
        stat[1] += len(h)
        stat[2] += num_cp
        stat[3] += num_merge
        stat[4] += num_err
    print("STAT-Total " + str(stat[0]) + " srctiles " + str(stat[1]) + " dsttiles " + str(stat[2]) + " copied " + str(stat[3]) + " merged " + str(stat[4]) + " failed "  )
