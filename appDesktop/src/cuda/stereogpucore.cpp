#include "stereogpucore.h"

stereoGPUcore::stereoGPUcore(const int image_width, const int image_height)
{
    width_ = image_width ;
    height_ = image_height ;

    // allocate memories on GPU side
    CudaHelper(cudaMalloc(&d_left_unrectified,  width_ * height_));  // allocate memory on device side for left unrectified image
    CudaHelper(cudaMalloc(&d_right_unrectified,  width_ * height_));  // allocate memory on device side for right unrectified image
    CudaHelper(cudaMalloc(&disparity_data,  width_ * height_));
    CudaHelper(cudaMalloc((void**)&d_rect_img,  width_ * height_ * sizeof(float)));

    // parameters initilazition
    DistortCoefArray_left[0]  =  -0.512378  ;
    DistortCoefArray_left[1]  =  0.390507   ;
    DistortCoefArray_left[2]  =  0.000000   ;
    DistortCoefArray_left[3]  =  0.000000   ;
    DistortCoefArray_left[4]  =  -0.572942  ;
    DistortCoefArray_left[5]  =  0.000000   ;
    DistortCoefArray_left[6]  =  0.000000   ;
    DistortCoefArray_left[7]  =  0.000000   ;

    AcameraMatrix_left[0]  =  300.947083    ;
    AcameraMatrix_left[1]  =  177.569168    ;
    AcameraMatrix_left[2]  =  982.246826    ;
    AcameraMatrix_left[3]  =  982.246826    ;

    iRMatrix_left[0]       =  0.001096           ;
    iRMatrix_left[1]       =  -0.000012          ;
    iRMatrix_left[2]       =  -0.320153          ;
    iRMatrix_left[3]       =  0.000012           ;
    iRMatrix_left[4]       =  0.001097           ;
    iRMatrix_left[5]       =  -0.201621          ;
    iRMatrix_left[6]       =  0.000039           ;
    iRMatrix_left[7]       =  0.000002           ;
    iRMatrix_left[8]       =  0.988872           ;

}


void stereoGPUcore::execute(const void* left_pixels, const void* right_pixels, void** h_output ) {

        CudaHelper(cudaMemcpy(d_left_unrectified   , left_pixels  ,   width_ * height_, cudaMemcpyHostToDevice));
        CudaHelper(cudaMemcpy(d_right_unrectified , right_pixels,   width_ * height_, cudaMemcpyHostToDevice));

        /*  rectify  */
        cuda_calls::rectify( (uint8_t*)left_pixels, d_unrect_img,  d_rect_img, width_,   height_,
                       DistortCoefArray_left,   iRMatrix_left ,   AcameraMatrix_left ) ;

        printf("cuda core done \n") ;
//        Mat hDisp(height_,width_,CV_8UC1);
//        hDisp.setTo(0);

        CudaHelper(cudaDeviceSynchronize());  // usfull for multiple streams, here is not necessary

//        CudaHelper(cudaMemcpy((void*)hDisp.data , d_left_unrectified,  width_ * height_, cudaMemcpyDeviceToHost));
        CudaHelper(cudaMemcpy((void*)*h_output , d_rect_img,  width_ * height_ * sizeof(float), cudaMemcpyDeviceToHost));

}

stereoGPUcore::~stereoGPUcore()
{

    // free memories on GPU side
    CudaHelper(cudaFree(d_left_unrectified));  // allocate memory on device side for left unrectified image
    CudaHelper(cudaFree(d_right_unrectified));  // allocate memory on device side for right unrectified image
    CudaHelper(cudaFree(disparity_data));
    CudaHelper(cudaFree(d_rect_img));

}
