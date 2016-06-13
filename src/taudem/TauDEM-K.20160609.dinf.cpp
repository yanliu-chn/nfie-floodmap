/*  TauDEM DinfFlowDir function to compute flow direction based on dinf flow model.

  David G Tarboton, Dan Watson, Jeremy Neff
  Utah State University
  May 23, 2010

*/

/*  Copyright (C) 2010  David Tarboton, Utah State University

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
version 2, 1991 as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A copy of the full GNU General Public License is included in file
gpl.html. This is also available at:
http://www.gnu.org/copyleft/gpl.html
or from:
The Free Software Foundation, Inc., 59 Temple Place - Suite 330,
Boston, MA  02111-1307, USA.

If you wish to use or incorporate this program (or parts of it) into
other software that does not meet the GNU General Public License
conditions contact the author to request permission.

David G. Tarboton
Utah State University
8200 Old Main Hill
Logan, UT 84322-8200
USA
http://www.engineering.usu.edu/dtarb/
email:  dtarb@usu.edu
*/

//  This software is distributed from http://hydrology.usu.edu/taudem/

#include <algorithm>
#include <cinttypes>
#include <set>
#include <vector>
#include <math.h>

#include <mpi.h>

#include "d8.h"
#include "linearpart.h"
#include "commonLib.h"
#include "tiffIO.h"
#include "Node.h"

#include "mpitimer.h"

using namespace std;

template<typename T> long resolveFlats(T& elev, SparsePartition<int>& inc, linearpart<float>& flowDir, std::vector<std::vector<node>>& islands, linearpart<float>& orelevDir);
template<typename T> long resolveFlats_parallel(T& elevDEM, SparsePartition<int>& inc, linearpart<float>& flowDir, std::vector<std::vector<node>>& islands, linearpart<float>& orelevDir);

template<typename T> void flowTowardsLower(T& elev, linearpart<float>& flowDir, std::vector<std::vector<node>>& islands, SparsePartition<int>& inc);
template<typename T> void flowFromHigher(T& elevDEM, linearpart<float>& flowDir, std::vector<std::vector<node>>& islands, SparsePartition<int>& inc);
template<typename T> int markPits(T& elevDEM, linearpart<float>& flowDir, std::vector<std::vector<node>>& islands, SparsePartition<int>& inc);

size_t propagateIncrements(linearpart<float>& flowDir, SparsePartition<int>& inc, std::vector<node>& queue);
size_t propagateBorderIncrements(linearpart<float>& flowDir, SparsePartition<int>& inc);

double **fact;

long setPosDirDinf(linearpart<float>& elevDEM, linearpart<float>& flowDir, linearpart<float>& slope, int useflowfile);

//Checks if cells cross
int dontCross(int k, int i, int j, linearpart<float>& flowDir)
{
    long in1, jn1, in2, jn2;
    int n1, c1, n2, c2;

    switch(k) {
    case 2:
        n1=1;
        c1=4;
        n2=3;
        c2=8;
        break;
    case 4:
        n1=3;
        c1=6;
        n2=5;
        c2=2;
        break;
    case 6:
        n1=7;
        c1=4;
        n2=5;
        c2=8;
        break;
    case 8:
        n1=1;
        c1=6;
        n2=7;
        c2=2;
        break;
    default:
        return 0;
    }

    in1=i+d1[n1];
    jn1=j+d2[n1];
    in2=i+d1[n2];
    jn2=j+d2[n2];

    if (flowDir.getData(in1,jn1) == c1 || flowDir.getData(in2,jn2) == c2)
    {
        return 1;
    }

    return 0;
}

//Open files, Initialize grid memory, makes function calls to set flowDir, slope, and resolvflats, writes files
int setdir(char* demfile, char* pointfile, char *slopefile, char *flowfile, int useflowfile)
{
    MPI_Init(NULL,NULL);

    int rank,size;
    MPI_Comm_rank(MCW,&rank);
    MPI_Comm_size(MCW,&size);

    if (rank==0) {
        printf("DinfFlowDir version %s\n",TDVERSION);
        fflush(stdout);
    }

    MPITimer t;

    double begint = MPI_Wtime();

    t.start("Total");
    t.start("Header read");

    //Read DEM from file
    tiffIO dem(demfile, FLOAT_TYPE);

    long totalX = dem.getTotalX();
    long totalY = dem.getTotalY();
    double dx = dem.getdxA();
    double dy = dem.getdyA();

    linearpart<float> elevDEM(totalX, totalY, dx, dy, MPI_FLOAT, *(float*) dem.getNodata());

    int xstart, ystart;
    int nx = elevDEM.getnx();
    int ny = elevDEM.getny();
    elevDEM.localToGlobal(0, 0, xstart, ystart);
    elevDEM.savedxdyc(dem);

    t.end("Header read");

    double headert = MPI_Wtime();

    if (rank==0) {
        float timeestimate=(2.8e-9*pow((double)(totalX*totalY),1.55)/pow((double) size,0.65))/60+1;  // Time estimate in minutes
        //fprintf(stderr,"%d %d %d\n",totalX,totalY,size);
        fprintf(stderr,"This run may take on the order of %.0f minutes to complete.\n",timeestimate);
        fprintf(stderr,"This estimate is very approximate. \nRun time is highly uncertain as it depends on the complexity of the input data \nand speed and memory of the computer. This estimate is based on our testing on \na dual quad core Dell Xeon E5405 2.0GHz PC with 16GB RAM.\n");
        fflush(stderr);
    }

    uint64_t bytes_to_read = (uint64_t) nx * ny * sizeof(float);
    if (rank == 0) { 
        fprintf(stderr, "Reading input data (%s)... ", humanReadableSize(bytes_to_read).c_str());
    }

    t.start("Data read");

    dem.read(xstart, ystart, ny, nx, elevDEM.getGridPointer());
    elevDEM.share();
    double data_read_time = t.end("Data read");
   
    if (rank == 0) {
        fprintf(stderr, "done (%s/s).\n", humanReadableSize(bytes_to_read / data_read_time).c_str());
    }

    //Creates empty partition to store new flow direction
    float flowDirNodata = MISSINGFLOAT;

    linearpart<float> flowDir(totalX, totalY, dx, dy, MPI_FLOAT, flowDirNodata);

    if (rank == 0) fprintf(stderr, "Calculating flow directions... ");
    t.start("Calculate flow directions");
    uint64_t numFlat;
    {
        t.start("Calculate flow directions");
        float slopeNodata = -1.0f;
        linearpart<float> slope(totalX, totalY, dx, dy, MPI_FLOAT, slopeNodata);

        numFlat = setPosDirDinf(elevDEM, flowDir, slope, useflowfile);
        t.end("Calculate flow directions");

        t.start("Write slope");
        tiffIO slopeIO(slopefile, FLOAT_TYPE, &slopeNodata, dem);
        slopeIO.write(xstart, ystart, ny, nx, slope.getGridPointer());
        t.end("Write slope");
    }

    flowDir.share();

    uint64_t totalNumFlat = 0;
    MPI_Allreduce(&numFlat, &totalNumFlat, 1, MPI_UINT64_T, MPI_SUM, MCW);
   
    if (rank == 0) {
        fprintf(stderr, "done. %" PRIu64 " flats to resolve.\n", totalNumFlat);
        fflush(stderr);
    }

    t.start("Resolve flats");

    if (totalNumFlat > 0) {
        std::vector<node> flats;

        t.start("Add flats");

        // FIXME: Should do this during slope calculation
        for (int j=0; j<ny; j++) {
            for (int i=0; i<nx; i++) {
                if (flowDir.getData(i, j) == -1) {
                    flats.push_back(node(i, j));
                }
            }
        }

        t.end("Add flats");

        if (rank == 0) {
            fprintf(stderr, "Finding flat islands...\n");
        }

        double flatFindStart = MPI_Wtime();
        int numIslands = 0;

        std::vector<std::vector<node>> islands;
        std::set<int> bordering_island_labels;

        t.start("Find islands");
        {
            SparsePartition<int> island_marker(nx, ny, 0);
            std::vector<node> q;

            for(node flat : flats)
            {
                if (island_marker.getData(flat.x, flat.y) != 0) {
                    continue;
                }

                q.push_back(flat);

                int label = ++numIslands;
                islands.push_back(std::vector<node>());

                while(!q.empty()) {
                    node flat = q.back();
                    q.pop_back();

                    if (island_marker.getData(flat.x, flat.y) != 0) {
                        continue;
                    }

                    island_marker.setData(flat.x, flat.y, label);
                    islands[label - 1].push_back(flat);

                    for (int k=1; k<=8; k++) {
                        //if neighbor is in flat
                        int in = flat.x + d1[k];
                        int jn = flat.y + d2[k];

                        if ((jn == -1 || jn == ny) && flowDir.hasAccess(in, jn)) {
                            if (flowDir.getData(in, jn) == -1) 
                            {
                                bordering_island_labels.insert(label);
                            }
                        }

                        if (!flowDir.isInPartition(in, jn))
                            continue;

                        if (flowDir.getData(in, jn) == -1)
                            q.push_back(node(in, jn));
                    }
                }
            }
        }
        t.end("Find islands");

        std::vector<std::vector<node>> borderingIslands;
        uint64_t localSharedFlats = 0, sharedFlats = 0;

        for (auto& label : bordering_island_labels) {
            std::vector<node> island = std::move(islands[label - 1]);

            localSharedFlats += island.size(); 
            borderingIslands.push_back(island);
        }

        t.start("Resolve shared flats");
        MPI_Allreduce(&localSharedFlats, &sharedFlats, 1, MPI_UINT64_T, MPI_SUM, MCW);

        if (rank == 0 && size > 1) {
            fprintf(stderr, "Processing partial flats\n");
            printf("PRL: %llu flats shared across processors (%llu local -> %.2f%% shared)\n", sharedFlats, totalNumFlat - sharedFlats, 100. * sharedFlats / totalNumFlat);
        }

        if (sharedFlats > 0) {
            SparsePartition<int> inc(nx, ny, 0);
            size_t lastNumFlat = resolveFlats_parallel(elevDEM, inc, flowDir, borderingIslands, elevDEM);

            if (rank==0) {
                fprintf(stderr, "PRL: Iteration complete. Number of flats remaining: %zu\n", lastNumFlat);
                fflush(stderr);
            }

            // Repeatedly call resolve flats until there is no change across all processors
            while (lastNumFlat > 0) {
                SparsePartition<int> newInc(nx, ny, 0);

                lastNumFlat = resolveFlats_parallel(inc, newInc, flowDir, borderingIslands, elevDEM);
                inc = std::move(newInc);

                if (rank==0) {
                    fprintf(stderr, "PRL: Iteration complete. Number of flats remaining: %zu\n", lastNumFlat);
                    fflush(stderr);
                }
            }
        }
        t.end("Resolve shared flats");

        //printf("rank %d: Done, %d islands. Took %.2f seconds\n", rank, numIslands, MPI_Wtime() - flatFindStart);
        //printf("rank %d: %lu bordering islands with %d flats\n", rank, bordering_islands.size(), localSharedFlats);

        t.start("Resolve local flats");
        if (!islands.empty()) {
            SparsePartition<int> inc(nx, ny, 0);
            size_t lastNumFlat = resolveFlats(elevDEM, inc, flowDir, islands, elevDEM);

            if (rank==0) {
                fprintf(stderr, "Iteration complete. Number of flats remaining: %zu\n\n", lastNumFlat);
                fflush(stderr);
            }

            // Repeatedly call resolve flats until there is no change
            while (lastNumFlat > 0)
            {
                SparsePartition<int> newInc(nx, ny, 0);

                lastNumFlat = resolveFlats(inc, newInc, flowDir, islands, elevDEM);
                inc = std::move(newInc);

                if (rank==0) {
                    fprintf(stderr, "Iteration complete. Number of flats remaining: %zu\n\n", lastNumFlat);
                    fflush(stderr);
                }
            } 
        }
        t.end("Resolve local flats");
    }

    t.end("Resolve flats");

    t.start("Write directions");
    tiffIO pointIO(pointfile, FLOAT_TYPE, &flowDirNodata, dem);
    pointIO.write(xstart, ystart, ny, nx, flowDir.getGridPointer());
    t.end("Write directions");

    t.end("Total");
    t.stop();
    //t.save("timing_info");

    MPI_Finalize();
    return 0;
}

void VSLOPE(float E0, float E1, float E2,
        float D1, float D2, float DD,
        float *S, float *A) {
    //SUBROUTINE TO RETURN THE SLOPE AND ANGLE ASSOCIATED WITH A DEM PANEL 
    float S1, S2, AD;
    if (D1 != 0)
        S1 = (E0 - E1) / D1;
    if (D2 != 0)
        S2 = (E1 - E2) / D2;

    if (S2 == 0 && S1 == 0) *A = 0;
    else
        *A = (float) atan2(S2, S1);
    AD = (float) atan2(D2, D1);
    if (*A < 0.) {
        *A = 0.;
        *S = S1;
    } else if (*A > AD) {
        *A = AD;
        *S = (E0 - E2) / DD;
    } else
        *S = (float) sqrt(S1 * S1 + S2 * S2);
}
// Sets only flowDir only where there is a positive slope
// Returns number of cells which are flat

void SET2(int I, int J, float *DXX, float DD, linearpart<float>& elevDEM, linearpart<float>& flowDir, linearpart<float>& slope) {
    double dxA = elevDEM.getdxA();
    double dyA = elevDEM.getdyA();
    float SK[9];
    float ANGLE[9];
    float SMAX;
    float tempFloat;
    int K;
    int KD;

    int ID1[] = {0, 1, 2, 2, 1, 1, 2, 2, 1};
    int ID2[] = {0, 2, 1, 1, 2, 2, 1, 1, 2};
    int I1[] = {0, 0, -1, -1, 0, 0, 1, 1, 0};
    int I2[] = {0, -1, -1, -1, -1, 1, 1, 1, 1};
    int J1[] = {0, 1, 0, 0, -1, -1, 0, 0, 1};
    int J2[] = {0, 1, 1, -1, -1, -1, -1, 1, 1};
    float ANGC[] = {0, 0., 1., 1., 2., 2., 3., 3., 4.};
    float ANGF[] = {0, 1., -1., 1., -1., 1., -1., 1., -1.};


    for (K = 1; K <= 8; K++) {
        VSLOPE(
                elevDEM.getData(J, I, tempFloat), //felevg.d[J][I],
                elevDEM.getData(J + J1[K], I + I1[K], tempFloat), //[felevg.d[J+J1[K]][I+I1[K]],
                elevDEM.getData(J + J2[K], I + I2[K], tempFloat), //felevg.d[J+J2[K]][I+I2[K]],
                DXX[ID1[K]],
                DXX[ID2[K]],
                DD,
                &SK[K],
                &ANGLE[K]
                );
    }
    tempFloat = -1;
    SMAX = 0.;
    KD = 0;
    flowDir.setData(J, I, tempFloat); //USE -1 TO INDICATE DIRECTION NOT YET SET 
    for (K = 1; K <= 8; K++) {
        if (SK[K] > SMAX) {
            SMAX = SK[K];
            KD = K;
        }
    }

    if (KD > 0) {
        tempFloat = (float) (ANGC[KD]*(PI / 2) + ANGF[KD] * ANGLE[KD]);
        flowDir.setData(J, I, tempFloat); //set to angle
    }
    slope.setData(J, I, SMAX);
}

template<typename T> 
void SET2(int I, int J, float *DXX, float DD, T& elevDEM, SparsePartition<int>& elev2, linearpart<float>& flowDir) {
    float SK[9];
    float ANGLE[9];
    float SMAX = 0.0;
    float tempFloat;
    int tempShort, tempShort1, tempShort2;
    int K;
    int KD = 0;

    int ID1[] = {0, 1, 2, 2, 1, 1, 2, 2, 1};
    int ID2[] = {0, 2, 1, 1, 2, 2, 1, 1, 2};
    int I1[] = {0, 0, -1, -1, 0, 0, 1, 1, 0};
    int I2[] = {0, -1, -1, -1, -1, 1, 1, 1, 1};
    int J1[] = {0, 1, 0, 0, -1, -1, 0, 0, 1};
    int J2[] = {0, 1, 1, -1, -1, -1, -1, 1, 1};
    float ANGC[] = {0, 0., 1., 1., 2., 2., 3., 3., 4.};
    float ANGF[] = {0, 1., -1., 1., -1., 1., -1., 1., -1.};
    bool diagOutFound = false;  

    for (K = 1; K <= 8; K++) {
        tempShort1 = elev2.getData(J + J1[K], I + I1[K]);
        tempShort2 = elev2.getData(J + J2[K], I + I2[K]);
        
        if (tempShort1 <= 0 && tempShort2 <= 0) { //Both E1 and E2 are outside the flat get slope and angle
            float a = elevDEM.getData(J, I);
            float b = elevDEM.getData(J + J1[K], I + I1[K]);
            float c = elevDEM.getData(J + J2[K], I + I2[K]);
            VSLOPE(
                    a, //E0
                    b, //E1
                    c, //E2
                    DXX[ID1[K]], //dx or dy depending on ID1
                    DXX[ID2[K]], //dx or dy depending on ID2
                    DD, //Hypotenuse
                    &SK[K], //Slope Returned
                    &ANGLE[K]//Angle Returned
                    );
            if (SK[K] >= 0.0) //  Found an outlet
            {
                if (b > a) // Outlet found had better be a diagonal, because it is not an edge
                {
                    if (!diagOutFound) {
                        diagOutFound = true;
                        KD = K;
                    }
                } else { //  Here it is an adjacent outlet
                    KD = K;
                    break;
                }
            }

        } else if (tempShort1 <= 0 && tempShort2 > 0) {//E1 is outside of the flat and E2 is inside the flat. Use DEM elevations. tempShort2/E2 is in the artificial grid
            float a = elevDEM.getData(J, I);
            float b = elevDEM.getData(J + J1[K], I + I1[K]);

            if (a >= b) {
                ANGLE[K] = 0.0;
                SK[K] = 0.0;
                KD = K;
                break;
            }
            int a1 = elev2.getData(J, I);
            int c1 = elev2.getData(J + J2[K], I + I2[K]);
            int b1 = max(a1, c1);
            VSLOPE(
                    (float) a1, //felevg.d[J][I],
                    (float) b1, //[felevg.d[J+J1[K]][I+I1[K]],
                    (float) c1, //felevg.d[J+J2[K]][I+I2[K]],
                    DXX[ID1[K]], //dx or dy
                    DXX[ID2[K]], //dx or dy
                    DD, //Hypotenuse
                    &SK[K], //Slope Returned
                    &ANGLE[K]//Angle Reutnred
                    );
            if (SK[K] > SMAX) {
                SMAX = SK[K];
                KD = K;
            }
        } else if (tempShort1 > 0 && tempShort2 <= 0) {//E2 is out side of the flat and E1 is inside the flat, use DEM elevations
            float a = elevDEM.getData(J, I);
            //float b=elevDEM->getData(J+J1[K],I+I1[K],tempFloat);
            float c = elevDEM.getData(J + J2[K], I + I2[K]);
            if (a >= c) {
                if (!diagOutFound) {
                    ANGLE[K] = (float) atan2(DXX[ID2[K]], DXX[ID1[K]]);
                    SK[K] = 0.0;
                    KD = K;
                    diagOutFound = true;
                }
            } else {
                int a1 = elev2.getData(J, I);
                int b1 = elev2.getData(J + J1[K], I + I1[K]);
                int c1 = max(a1, b1);
                VSLOPE(
                        (float) a1, //felevg.d[J][I],
                        (float) b1, //[felevg.d[J+J1[K]][I+I1[K]],
                        (float) c1, //felevg.d[J+J2[K]][I+I2[K]],
                        DXX[ID1[K]], //dx or dy
                        DXX[ID2[K]], //dx or dy
                        DD, //Hypotenuse
                        &SK[K], //Slope Returned
                        &ANGLE[K]//Angle Reutnred
                        );
                if (SK[K] > SMAX) {
                    SMAX = SK[K];
                    KD = K;
                }

            }
        } else {//Both E1 and E2 are in the flat. Use artificial elevation to get slope and angle
            int a, b, c;
            a = elev2.getData(J, I);
            b = elev2.getData(J + J1[K], I + I1[K]);
            c = elev2.getData(J + J2[K], I + I2[K]);
            VSLOPE(
                    (float) a, //felevg.d[J][I],
                    (float) b, //[felevg.d[J+J1[K]][I+I1[K]],
                    (float) c, //felevg.d[J+J2[K]][I+I2[K]],
                    DXX[ID1[K]], //dx or dy
                    DXX[ID2[K]], //dx or dy
                    DD, //Hypotenuse
                    &SK[K], //Slope Returned
                    &ANGLE[K]//Angle Reutnred
                    );
            if (SK[K] > SMAX) {
                SMAX = SK[K];
                KD = K;
            }
        }
    }
    //USE -1 TO INDICATE DIRECTION NOT YET SET, 
    // but only for non pit grid cells.  Pits will have flowDir as no data
    if (!flowDir.isNodata(J, I)) {
        tempFloat = -1;
        flowDir.setData(J, I, tempFloat);
    }

    if (KD > 0)//We have a flow direction.  Calculate the Angle and save/write it.
    {
        tempFloat = (float) (ANGC[KD]*(PI / 2) + ANGF[KD] * ANGLE[KD]); //Calculate the Angle
        if (tempFloat >= 0.0)//Make sure the angle is positive
            flowDir.setData(J, I, tempFloat); //set the angle in the flowPartition
    }
}

//int setPosDirDinf(tdpartition *elevDEM, tdpartition *flowDir, tdpartition *slope, tdpartition *area, int useflowfile)

long setPosDirDinf(linearpart<float>& elevDEM, linearpart<float>& flowDir, linearpart<float>& slope, int useflowfile) {
    double dxA = elevDEM.getdxA();
    double dyA = elevDEM.getdyA();
    long nx = elevDEM.getnx();
    long ny = elevDEM.getny();
    float tempFloat;
    double tempdxc, tempdyc;
    int i, j, k, in, jn, con;
    long numFlat = 0;

    tempFloat = 0;
    for (j = 0; j < ny; j++) {
        for (i = 0; i < nx; i++) {


            //FlowDir is nodata if it is on the border OR elevDEM has no data
            if (elevDEM.isNodata(i, j) || !elevDEM.hasAccess(i - 1, j) || !elevDEM.hasAccess(i + 1, j) ||
                    !elevDEM.hasAccess(i, j - 1) || !elevDEM.hasAccess(i, j + 1)) {
                //do nothing			
            } else {
                //Check if cell is "contaminated" (neighbors have no data)
                //  set flowDir to noData if contaminated
                con = 0;
                for (k = 1; k <= 8 && con != -1; k++) {
                    in = i + d1[k];
                    jn = j + d2[k];
                    if (elevDEM.isNodata(in, jn)) con = -1;
                }
                if (con == -1) 
                    flowDir.setToNodata(i, j);
                    //If cell is not contaminated,
                else {
                    tempFloat = -1.;
                    flowDir.setData(i, j, tempFloat); //set to -1
                    elevDEM.getdxdyc(j, tempdxc, tempdyc);


                    float DXX[3] = {0, tempdxc, tempdyc}; //tardemlib.cpp ln 1291
                    float DD = sqrt(tempdxc * tempdxc + tempdyc * tempdyc); //tardemlib.cpp ln 1293
                    SET2(j, i, DXX, DD, elevDEM, flowDir, slope); //i=y in function form old code j is x switched on purpose
                    //  Use SET2 from serial code here modified to get what it has as felevg.d from elevDEM partition
                    //  Modify to return 0 if there is a 0 slope.  Modify SET2 to output flowDIR as no data (do nothing 
                    //  if verified initialization to nodata) and 
                    //  slope as 0 if a positive slope is not found

                    //setFlow( i,j, flowDir, elevDEM, area, useflowfile);
                    if (flowDir.getData(i, j, tempFloat) == -1)
                        numFlat++;
                }
            }
        }
    }
    return numFlat;
}


//************************************************************************

template<typename T>
void flowTowardsLower(T& elev, linearpart<float>& flowDir, std::vector<std::vector<node>>& islands, SparsePartition<int>& inc)
{
    long nx = flowDir.getnx();
    long ny = flowDir.getny();

    std::vector<node> lowBoundaries;

    // Find low boundaries. 
    for(auto& island : islands) {
        for(node flat : island) {
            float flatElev = elev.getData(flat.x, flat.y);

            for (int k = 1; k <= 8; k++) {
                if (dontCross(k, flat.x, flat.y, flowDir) == 0) {
                    int in = flat.x + d1[k];
                    int jn = flat.y + d2[k];

                    if (!flowDir.hasAccess(in, jn))
                        continue;

                    auto elevDiff = flatElev - elev.getData(in,jn);
                    float flow = flowDir.getData(in, jn);

                    bool edgeDrain = flowDir.isNodata(in, jn);

                    // Adjacent cell drains and is equal or lower in elevation so this is a low boundary
                    if ((elevDiff >= 0 && flow >= 0.0) || edgeDrain) {
                        lowBoundaries.push_back(flat);
                        inc.setData(flat.x, flat.y, -1);

                        // No need to check the other neighbors
                        break;
                    } 
                }
            }
        }
    }

    size_t numInc = propagateIncrements(flowDir, inc, lowBoundaries);

    // Not all grid cells were resolved - pits remain
    // Remaining grid cells are unresolvable pits
    if (numInc > 0)          
    {
        markPits(elev, flowDir, islands, inc);
    }
}

template<typename T>
void flowFromHigher(T& elev, linearpart<float>& flowDir, std::vector<std::vector<node>>&islands, SparsePartition<int>& inc) 
{
    long nx = flowDir.getnx();
    long ny = flowDir.getny();

    std::vector<node> highBoundaries;

    // Find high boundaries
    for (auto& island : islands) {
        for (node flat : island) {
            float flatElev = elev.getData(flat.x, flat.y);
            bool highBoundary = false;

            for (int k = 1; k <= 8; k++) {
                if (dontCross(k, flat.x, flat.y, flowDir) == 0) {
                    int in = flat.x + d1[k];
                    int jn = flat.y + d2[k];

                    if (!flowDir.hasAccess(in, jn))
                        continue;

                    auto elevDiff = flatElev - elev.getData(in, jn);
                    
                    if (elevDiff < 0) {
                        // Adjacent cell has higher elevation so this is a high boundary
                        highBoundary = true;
                        break;
                    }
                }
            }

            if (highBoundary) {
                inc.setData(flat.x, flat.y, -1);
                highBoundaries.push_back(flat);
            }
        }
    }

    propagateIncrements(flowDir, inc, highBoundaries);
}

template<typename T>
int markPits(T& elevDEM, linearpart<float>& flowDir, std::vector<std::vector<node>>&islands, SparsePartition<int>& inc) 
{
    int nx = flowDir.getnx();
    int ny = flowDir.getny();

    int numPits = 0;

    //There are pits remaining - set direction to no data
    for (auto& island : islands) {
        for (node flat : island) {
            bool skip = false;

            for (int k=1; k<=8; k++) {
                if (dontCross(k, flat.x, flat.y, flowDir)==0) {
                    int jn = flat.y + d2[k];
                    int in = flat.x + d1[k];

                    if (!flowDir.hasAccess(in, jn)) 
                        continue;

                    auto elevDiff = elevDEM.getData(flat.x, flat.y) - elevDEM.getData(in, jn);
                    float flow = flowDir.getData(in, jn);

                    // Adjacent cell drains and is equal or lower in elevation so this is a low boundary
                    if (elevDiff >= 0 && flow == -1) {
                        skip = true;
                        break;
                    } else if (flow == -1) {
                        // If neighbor is in flat

                        // FIXME: check if this is correct
                        if (inc.getData(in,jn) >= 0){ // && inc.getData(in,jn)<st) {
                            skip = true;
                            break;
                        }
                    }
                }
            }
            
            // mark pit
            if (!skip) {
                numPits++;
                flowDir.setToNodata(flat.x, flat.y);
            }  
        }
    }

    return numPits;
}

template<typename T>
long resolveFlats(T& elevDEM, SparsePartition<int>& inc, linearpart<float>& flowDir, std::vector<std::vector<node>>&islands, linearpart<float>& orelevDir) 
{
    long nx = flowDir.getnx();
    long ny = flowDir.getny();

    int rank;
    MPI_Comm_rank(MCW, &rank);
    
    if (rank==0) {
        fprintf(stderr,"Resolving flats\n");
        fflush(stderr);
    }

    flowTowardsLower(elevDEM, flowDir, islands, inc);

    // Drain flats away from higher adjacent terrain
    SparsePartition<int> s(nx, ny, 0);
    
    flowFromHigher(elevDEM, flowDir, islands, s);

    // High flow must be inverted before it is combined
    //
    // higherFlowMax has to be greater than all of the increments
    // higherFlowMax can be maximum value of the data type but it will cause overflow problems if more than one iteration is needed
    int higherFlowMax = 0;

    for (auto& island : islands) {
        for (node flat : island) {    
            int val = s.getData(flat.x, flat.y);

            if (val > higherFlowMax)
                higherFlowMax = val;
        }
    }

    for (auto& island : islands) {
        for (auto flat : island) {
            inc.addToData(flat.x, flat.y, higherFlowMax - s.getData(flat.x, flat.y));
        }
    }

    if (rank==0) {
        fprintf(stderr,"Setting directions\n");
        fflush(stderr);
    }

    long flatsRemaining = 0;
    double tempdxc, tempdyc;
    for (auto& island : islands) {
        for (node flat : island) {
            //setFlow2(flat.x, flat.y, flowDir, elevDEM, inc);
            orelevDir.getdxdyc(flat.y, tempdxc, tempdyc);
            float DXX[3] = {0, tempdxc, tempdyc}; //tardemlib.cpp ln 1291
            float DD = sqrt(tempdxc * tempdxc + tempdyc * tempdyc); //tardemlib.cpp ln 1293

            SET2(flat.y, flat.x, DXX, DD, elevDEM, inc, flowDir);

            if (flowDir.getData(flat.x, flat.y) == -1) {
                flatsRemaining++;
            }
        }
    }

    auto hasFlowDirection = [&](const node& n) { return flowDir.getData(n.x, n.y) != -1; };
    auto isEmpty = [&](const std::vector<node>& i) { return i.empty(); };
    
    // Remove flats which have flow direction set
    for (auto& island : islands) {
        island.erase(std::remove_if(island.begin(), island.end(), hasFlowDirection), island.end());
    }

    // Remove empty islands
    islands.erase(std::remove_if(islands.begin(), islands.end(), isEmpty), islands.end());

    return flatsRemaining;
}

template<typename T>
long resolveFlats_parallel(T& elev, SparsePartition<int>& inc, linearpart<float>& flowDir, std::vector<std::vector<node>>&islands, linearpart<float>& orelevDir) 
{
    int nx = flowDir.getnx();
    int ny = flowDir.getny();

    int rank;
    MPI_Comm_rank(MCW, &rank);

    uint64_t numFlatsChanged = 0, totalNumFlatsChanged = 0;

    flowTowardsLower(elev, flowDir, islands, inc);

    do {
        inc.share();
        numFlatsChanged = propagateBorderIncrements(flowDir, inc);

        MPI_Allreduce(&numFlatsChanged, &totalNumFlatsChanged, 1, MPI_UINT64_T, MPI_SUM, MCW);

        if (rank == 0) {
            printf("PRL: Lower gradient processed %llu flats this iteration\n", totalNumFlatsChanged);
        }
    } while(totalNumFlatsChanged > 0);

    // Not all grid cells were resolved - pits remain
    // Remaining grid cells are unresolvable pits
    markPits(elev, flowDir, islands, inc);

    // Drain flats away from higher adjacent terrain
    SparsePartition<int> higherGradient(nx, ny, 0);
   
    flowFromHigher(elev, flowDir, islands, higherGradient);

    do {
        higherGradient.share();
        numFlatsChanged = propagateBorderIncrements(flowDir, higherGradient);

        MPI_Allreduce(&numFlatsChanged, &totalNumFlatsChanged, 1, MPI_UINT64_T, MPI_SUM, MCW);

        if (rank == 0) {
            printf("PRL: Higher gradient processed %llu flats this iteration\n", totalNumFlatsChanged);
        }
    } while(totalNumFlatsChanged > 0);

    // High flow must be inverted before it is combined
    //
    // higherFlowMax has to be greater than all of the increments
    // higherFlowMax can be maximum value of the data type (e.g. 65535) but it will cause overflow problems if more than one iteration is needed
    int higherFlowMax = 0;

    for (auto& island : islands) {
        for (auto& flat : island) {
            int val = higherGradient.getData(flat.x, flat.y);
        
            if (val > higherFlowMax)
                higherFlowMax = val;
        }
    }

    // FIXME: Is this needed? would it affect directions at the border?
    // It is local to a flat area, but can that be reduced further to minimize comm?
    int globalHigherFlowmax = 0;
    MPI_Allreduce(&higherFlowMax, &globalHigherFlowmax, 1, MPI_INT, MPI_MAX, MCW);

    size_t badCells = 0;

    for (auto& island : islands) {
        for (auto flat : island) {
            auto val = inc.getData(flat.x, flat.y);
            auto highFlow = higherGradient.getData(flat.x, flat.y);

            inc.setData(flat.x, flat.y, val + (globalHigherFlowmax - highFlow));

            if (val < 0 || val == INT_MAX || highFlow < 0 || highFlow == INT_MAX) {
                badCells++;
            }
        }
    }

    if (badCells > 0) {
        printf("warning rank %d: %d increment values either incorrect or overflown\n", rank, badCells);
    }

    inc.share();

    if (rank==0) {
        fprintf(stderr,"\nPRL: Setting directions\n");
        fflush(stderr);
    }

    uint64_t localFlatsRemaining = 0, globalFlatsRemaining = 0;
    double tempdxc, tempdyc;
    
    for (auto& island : islands) {
        for (node flat : island) {
            //setFlow2(flat.x, flat.y, flowDir, elev, inc);
            orelevDir.getdxdyc(flat.y, tempdxc, tempdyc);
            float DXX[3] = {0, tempdxc, tempdyc}; //tardemlib.cpp ln 1291
            float DD = sqrt(tempdxc * tempdxc + tempdyc * tempdyc); //tardemlib.cpp ln 1293

            SET2(flat.y, flat.x, DXX, DD, elev, inc, flowDir);
            
            if (flowDir.getData(flat.x, flat.y) == -1) {
                localFlatsRemaining++;
            }
        }
    }

    flowDir.share();
    MPI_Allreduce(&localFlatsRemaining, &globalFlatsRemaining, 1, MPI_UINT64_T, MPI_SUM, MCW);

    auto hasFlowDirection = [&](const node& n) { return flowDir.getData(n.x, n.y) != -1; };
    auto isEmpty = [&](const std::vector<node>& i) { return i.empty(); };
    
    // Remove flats which have flow direction set
    for (auto& island : islands) {
        island.erase(std::remove_if(island.begin(), island.end(), hasFlowDirection), island.end());
    }

    // Remove empty islands
    islands.erase(std::remove_if(islands.begin(), islands.end(), isEmpty), islands.end());

    return globalFlatsRemaining;
}

size_t propagateIncrements(linearpart<float>& flowDir, SparsePartition<int>& inc, std::vector<node>& queue) {
    size_t numInc = 0;
    int st = 1;
    
    std::vector<node> newFlats;
    while (!queue.empty()) {
        for(node flat : queue) {
            // Duplicate. already set
            if (inc.getData(flat.x, flat.y) > 0)
                continue;

            for (int k = 1; k <= 8; k++) {
                if (dontCross(k, flat.x, flat.y, flowDir) == 0) {
                    int in = flat.x + d1[k];
                    int jn = flat.y + d2[k];

                    if (!flowDir.isInPartition(in, jn)) 
                        continue;

                    float flow = flowDir.getData(in, jn);

                    if (flow == -1 && inc.getData(in, jn) == 0) {
                        newFlats.push_back(node(in, jn));
                        inc.setData(in, jn, -1);
                    }
                }
            }

            numInc++;
            inc.setData(flat.x, flat.y, st);
        }

        queue.clear();
        queue.swap(newFlats);
        st++;
    }

    if (st < 0) {
        printf("WARNING: increment overflow during propagation (st = %d)\n", st);
    }

    return numInc;
}

size_t propagateBorderIncrements(linearpart<float>& flowDir, SparsePartition<int>& inc) 
{
    int nx = flowDir.getnx();
    int ny = flowDir.getny();

    std::vector<node> queue;

    // Find the starting nodes at the edge of the raster
    //
    // FIXME: don't scan border if not needed
    int ignoredGhostCells = 0;

    for (auto y : {-1, ny}) {
        for(int x = 0; x < nx; x++) {
            int st = inc.getData(x, y);

            if (st == 0)
                continue;

            if (st == INT_MAX) {
                ignoredGhostCells++;
                continue;
            }

            auto jn = y == -1 ? 0 : ny - 1;

            for (auto in : {x-1, x, x+1}) {
                if (!flowDir.isInPartition(in, jn))
                    continue;

                bool noFlow = flowDir.getData(in, jn) == -1;
                auto neighInc = inc.getData(in, jn);

                if (noFlow && (neighInc == 0 || std::abs(neighInc) > st + 1)) {
                    // If neighbor increment is positive, we are overriding a larger increment
                    // and it is not yet in the queue
                    if (neighInc >= 0) {
                        queue.emplace_back(in, jn);
                    }

                    // Here we set a negative increment if it's still not set
                    //
                    // Another flat might be neighboring the same cell with a lower increment,
                    // which has to override the higher increment (that hasn't been set yet but is in the queue).
                    inc.setData(in, jn, -(st + 1));
                }
            }
        }
    }

    if (ignoredGhostCells > 0) {
       printf("warning: ignored %d ghost cells which were at upper limit (%d)\n", ignoredGhostCells, SHRT_MAX);
    }

    size_t numChanged = 0;
    size_t abandonedCells = 0;

    std::vector<node> newFlats;

    while (!queue.empty()) {
        for(node flat : queue) {
            // Increments are stored as negative for the cells that have been added to the queue
            // (to signify that they need to be explored)
            auto st = -inc.getData(flat.x, flat.y);
          
            // I don't think this is possible anymore, but just in case.
            if (st <= 0) {
                printf("warning: unexpected non-negative increment @ (%d, %d) - %d\n", flat.x, flat.y, -st);
                continue;
            }

            inc.setData(flat.x, flat.y, st);
            numChanged++;

            if (st == INT_MAX) {
                abandonedCells++;
                continue;
            }

            for (int k = 1; k <= 8; k++) {
                if (dontCross(k, flat.x, flat.y, flowDir) == 0) {
                    int in = flat.x + d1[k];
                    int jn = flat.y + d2[k];

                    if (!flowDir.isInPartition(in, jn)) 
                        continue;

                    float flow = flowDir.getData(in, jn);
                    auto neighInc = inc.getData(in, jn);

                    if (flow == -1 && (neighInc == 0 || std::abs(neighInc) > st + 1)) {
                        // If neighbor increment is positive, we are overriding a larger increment
                        // and it is not yet in the queue
                        if (neighInc >= 0) {
                           newFlats.emplace_back(in, jn);
                        }

                        inc.setData(in, jn, -(st + 1));
                    }
                }
            }
        }

        queue.clear();
        queue.swap(newFlats);
    }

    if (abandonedCells > 0) {
        printf("warning: gave up propagating %zu cells because they were at upper limit (%d)\n", abandonedCells, INT_MAX);
    }

    return numChanged;
}
