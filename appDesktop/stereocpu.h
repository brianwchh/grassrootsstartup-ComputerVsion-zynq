#ifndef STEREOCPU_H
#define STEREOCPU_H

#include <stdlib.h>
#include <iostream>
#include <sstream>
#include <string>
#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/contrib/contrib.hpp>
#include "stdio.h"
#include <unistd.h>

#define  disparity_size_   64


using namespace cv ;
using namespace std;

static const int HOR = 9;
static const int VERT = 7;

class stereoCPU
{
public:
    stereoCPU();
    void census_cpu(uchar* d_source, uint64_t* d_dest, int width, int height);
    void matchingCost_cpu(const uint64_t* h_left, const uint64_t* h_right, uint8_t* h_matching_cost, int width, int height);
    void execute() ;

};

#endif // STEREOCPU_H
