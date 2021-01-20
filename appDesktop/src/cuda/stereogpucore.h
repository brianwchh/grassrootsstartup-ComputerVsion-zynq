#ifndef STEREOGPUCORE_H
#define STEREOGPUCORE_H

#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/contrib/contrib.hpp>

using namespace cv ;


#include "cuda_funs.h"

class stereoGPUcore
{
public:
    stereoGPUcore(const int image_width, const int image_height);
    ~stereoGPUcore();
    /*
        left_pixels     : the left input image pointer , unrectified
        right_pixels  :  the right input image pointer, unrectified
        h_output      :  pointer to  depth img address at host side , must be pin memory
    */
    void execute(const void* left_pixels, const void* right_pixels, void** h_output) ;

    int width_ ;
    int height_ ;

    float DistortCoefArray_left[8] ;
    float AcameraMatrix_left[4] ;
    float iRMatrix_left[9] ;

    void* d_unrect_img ;
    float* d_rect_img ;

    void* d_left_unrectified ;
    void* d_right_unrectified;
    void* disparity_data ;

    float * h_data_left_rect_float ;


};

#endif // STEREOGPUCORE_H
