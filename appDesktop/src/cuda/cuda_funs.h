#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>

#include <stdexcept>

#include <cuda_runtime.h>
#include <cuda_runtime_api.h>

#define CudaHelper(error)  cuda_calls::cuda_debug_helper(error, __FILE__, __LINE__)

namespace cuda_calls {

    void rectify(const uint8_t* h_src , const void* d_unrect_img, float* d_rect_img,int width, int height,	 const float* DistortCoefArray, const float* iRMatrix , const float* AcameraMatrix ) ;

    void census(const void* d_src, uint64_t* d_dst, int window_width, int window_height, int width, int height, int depth_bits, cudaStream_t cuda_stream);

    void matching_cost(const uint64_t* d_left, const uint64_t* d_right, uint8_t* d_matching_cost, int width, int height, int disp_size);

    void scan_scost(const uint8_t* d_matching_cost, uint16_t* d_scost, int width, int height, int disp_size, cudaStream_t cuda_streams[]);

    void winner_takes_all(const uint16_t* d_scost, uint16_t* d_left_disp, uint16_t* d_right_disp, int width, int height, int disp_size);

    void median_filter(const uint16_t* d_src, uint16_t* d_dst, void* median_filter_buffer, int width, int height);

    void check_consistency(uint16_t* d_left_disp, const uint16_t* d_right_disp, const void* d_src_left, int width, int height, int depth_bits);

    inline void cuda_debug_helper(cudaError error, const char *file, const int line)
    {
        if (error != cudaSuccess) {
            fprintf(stderr, "cuda error %s : %d %s\n", file, line, cudaGetErrorString(error));
            exit(-1);
        }
    }

}
