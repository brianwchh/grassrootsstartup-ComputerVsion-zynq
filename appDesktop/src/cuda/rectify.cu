#include <iostream>

#include "cuda_funs.h"


/*
		assign k1_32bit         = 32'h0000222C ;         // DistortCoefArray[0]  =  0.133495    ; 
		assign k2_32bit         = 32'hFFFF45F3 ;         // DistortCoefArray[1]  =  -0.726764   ; 
		assign p1_32bit         = 32'h00000000 ;         // DistortCoefArray[2]  =  0.000000    ; 
		assign p2_32bit         = 32'h00000000 ;         // DistortCoefArray[3]  =  0.000000    ; 
		assign k3_32bit         = 32'h00016D18 ;         // DistortCoefArray[4]  =  1.426151    ; 
		assign k4_32bit         = 32'h00000000 ;         // DistortCoefArray[5]  =  0.000000    ; 
		assign k5_32bit         = 32'h00000000 ;         // DistortCoefArray[6]  =  0.000000    ; 
		assign k6_32bit         = 32'h00000000 ;         // DistortCoefArray[7]  =  0.000000    ; 
    
		assign ir_32bit[0] 	    = 32'h0000006D ;    	 // iRMatrix[0]  =  0.001665   ;  
		assign ir_32bit[1] 	    = 32'h00000000 ;    	 // iRMatrix[1]  =  0.000004   ;  
		assign ir_32bit[2] 	    = 32'hFFFF7A5D ;    	 // iRMatrix[2]  =  -0.522026  ;  
		assign ir_32bit[3] 	    = 32'h00000000 ;    	 // iRMatrix[3]  =  -0.000004  ;  
		assign ir_32bit[4] 	    = 32'h0000006D ;    	 // iRMatrix[4]  =  0.001665   ;  
		assign ir_32bit[5] 	    = 32'hFFFFB958 ;    	 // iRMatrix[5]  =  -0.276016  ;  
		assign ir_32bit[6] 	    = 32'hFFFFFFFE ;    	 // iRMatrix[6]  =  -0.000041  ;  
		assign ir_32bit[7] 	    = 32'h00000000 ;    	 // iRMatrix[7]  =  0.000004   ;  
		assign ir_32bit[8] 	    = 32'h00010332 ;    	 // iRMatrix[8]  =  1.012488   ;

		assign u0_32bit    	    = 32'h0133F0E2 ;         // AcameraMatrix[0]  =  307.940948   ;     
		assign v0_32bit    	    = 32'h00A33E4F ;         // AcameraMatrix[1]  =  163.243393   ;     
		assign fx_32bit    	    = 32'h025877D8 ;         // AcameraMatrix[2]  =  600.468140   ;     
		assign fy_32bit    	    = 32'h025877D8 ;         // AcameraMatrix[3]  =  600.468140   ; 

*/

/*
		32*20 X 6*80
	  _______________________________________________________________
   |             |                                                 |
   |   thread    |                                                 |
   |   block     |                                                 |
   |             |                                                 |
   |_____________|                                                 |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |                                                               |
   |_______________________________________________________________|

   1) each thread take cares of one destnation pixel (x,y)
   2) compute (u,v) from (x,y)
   3) texture fetch according to (u,v)
   4) colasely saving back to DDR2 memory
*/


namespace {

	static const int threadBlock_x = 32;    // TK1 has 1 SM * 192 cores/SM = 192 Cuda cores 
	static const int threadBlock_y = 6;     // only can process 1 block at a time 

	// Texture reference for 2D float texture
	static texture<float, 2, cudaReadModeElementType> tex;

	__global__
		// void census_kernel(float* d_dest, int width, int height, const float* DistortCoefArray, const float* iRMatrix , const float* AcameraMatrix )
	void census_kernel(float* d_dest, int width, int height ) 
		{
             int x_dest = threadIdx.x + blockIdx.x * blockDim.x;     // col index in image
             int y_dest = threadIdx.y + blockIdx.y * blockDim.y;    //  row  index

        	/*
				x_middle_p = ir[0] * x_dest + ir[1] * y_dest + ir[2] * w_dest ;   
				y_middle_p = ir[3] * x_dest + ir[4] * y_dest + ir[5] * w_dest ;
				w_middle_p = ir[6] * x_dest + ir[7] * y_dest + ir[8] * w_dest ;

				x_middle  = x_middle_p / w_middle_p ;    // one pixel clok 
				y_middle  = y_middle_p / w_middle_p ;

			    double x2 = x*x, y2 = y*y;
			    double r2 = x2 + y2,
			    		 _2xy = 2*x*y;
			    double kr = 1 + ((k3*r2 + k2)*r2 + k1)*r2 
			    double u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*xx)) + u0;
			    double v = fy*(y*kr + p1*(r2 + 2*yy) + p2*_2xy) + v0;
			*/

			float iRMatrix[9] ;
			float DistortCoefArray[8];
			float AcameraMatrix[4] ;         

            DistortCoefArray[0]  =  -0.512378  ;
            DistortCoefArray[1]  =  0.390507   ;
            DistortCoefArray[2]  =  0.000000   ;
            DistortCoefArray[3]  =  0.000000   ;
            DistortCoefArray[4]  =  -0.572942  ;
            DistortCoefArray[5]  =  0.000000   ;
            DistortCoefArray[6]  =  0.000000   ;
            DistortCoefArray[7]  =  0.000000   ;

            AcameraMatrix[0]  =  300.947083    ;
            AcameraMatrix[1]  =  177.569168    ;
            AcameraMatrix[2]  =  982.246826    ;
            AcameraMatrix[3]  =  982.246826    ;

            iRMatrix[0]       =  0.001096           ;
            iRMatrix[1]       =  -0.000012          ;
            iRMatrix[2]       =  -0.320153          ;
            iRMatrix[3]       =  0.000012           ;
            iRMatrix[4]       =  0.001097           ;
            iRMatrix[5]       =  -0.201621          ;
            iRMatrix[6]       =  0.000039           ;
            iRMatrix[7]       =  0.000002           ;
            iRMatrix[8]       =  0.988872           ;

            float x_middle_p = iRMatrix[0] * (float)x_dest + iRMatrix[1] * (float)y_dest + iRMatrix[2] ;
            float y_middle_p = iRMatrix[3] * (float)x_dest + iRMatrix[4] * (float)y_dest + iRMatrix[5] ;
            float w_middle_p = iRMatrix[6] * (float)x_dest + iRMatrix[7] * (float)y_dest + iRMatrix[8] ;
            float x_middle   = x_middle_p / w_middle_p ;
            float y_middle   = y_middle_p / w_middle_p ;

            float x2 = x_middle*x_middle ;
            float y2 = y_middle*y_middle ;
            float r2 = x2 + y2 ;
            float _2xy = 2*x_middle*y_middle ;

            float k1 = DistortCoefArray[0]  ;
            float k2 = DistortCoefArray[1]  ;
            float p1 = DistortCoefArray[2]  ;
            float p2 = DistortCoefArray[3]  ;
            float k3 = DistortCoefArray[4]  ;
            float k4 = DistortCoefArray[5]  ;
            float k5 = DistortCoefArray[6]  ;
            float k6 = DistortCoefArray[7]  ;

            float u0 = AcameraMatrix[0] ;
            float v0 = AcameraMatrix[1] ;
            float fx = AcameraMatrix[2] ;
            float fy = AcameraMatrix[3] ;

            float kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
            float u  = fx*(x_middle*kr + p1*_2xy + p2*(r2 + 2*x2))  + u0;
            float v  = fy*(y_middle*kr + p1*(r2 + 2*y2) + p2*_2xy)  + v0;

            u = (u)/((float)width );
            v = (v)/((float)height) ;
            // make sure u v is not greater than 1.0f

//            __syncthreads();

            d_dest[y_dest*width + x_dest] = tex2D(tex, u, v);

           //  float u =((float) (x_dest))/((float)width) * 1.3f;
           //  float v =((float) (y_dest))/((float)height) *1.3f;

           // d_dest[y_dest*width + x_dest] =  tex2D(tex, u , v);

//           if(x_dest < 15 && (y_dest < 10)){
//               printf( "index %d   =  %f  u = %f   ,  v = %f \n" , x_dest, tex2D(tex, u , v),u,v);
//           }

		}

}


namespace cuda_calls {

		void rectify(const uint8_t* h_src, const void* d_unrect_img, float* d_rect_img,int width, int height,
					 const float* DistortCoefArray, const float* iRMatrix , const float* AcameraMatrix ) 
		{

			const dim3   dimGrid((width + threadBlock_x - 1) / threadBlock_x, (height + threadBlock_y - 1) / threadBlock_y);
			const dim3   dimBlock(threadBlock_x, threadBlock_y);

			unsigned int size = width * height * sizeof(float);

            printf("width = %d   ;  height = %d \n", width, height ) ;

            float* hData  =  (float*)malloc( size);
//            CudaHelper( cudaMallocHost ( (void**)&hData, size ) ) ;   why not working ?????

			// convert gray scale image to float type 
			for(int r=0; r< height; r++)
				for(int c=0; c<width; c++)
				{
//                    temp =  temp + 1 ;
//                    if(temp > 255)
//                    {
//                        temp = 0 ;
//                    }
                    hData[ r*width + c ]  =  (float) h_src[ r*width + c ] ;
				}

//            for(int r=0; r< 15; r++)
//                for(int c=0; c<10; c++)
//                {
//                    printf(" hData value = %f \n ", hData[ r*width + c ] ) ;
//                }

		    // Allocate array and copy image data
		    cudaChannelFormatDesc channelDesc = cudaCreateChannelDesc(32, 0, 0, 0, cudaChannelFormatKindFloat);
		    cudaArray *cuArray;
		    CudaHelper(cudaMallocArray(&cuArray,
		                                    &channelDesc,
		                                    width,
		                                    height));
		    CudaHelper(cudaMemcpyToArray(cuArray,
                                              0,
		                                      0,
		                                      hData,
		                                      size,
		                                      cudaMemcpyHostToDevice));  // copy data from host to device 

			// Set texture parameters
//		    tex.addressMode[0] = cudaAddressModeWrap;
//		    tex.addressMode[1] = cudaAddressModeWrap;
            tex.addressMode[0] = cudaAddressModeBorder;
            tex.addressMode[1] = cudaAddressModeBorder;
		    tex.filterMode = cudaFilterModeLinear;
		    tex.normalized = true;    // access with normalized texture coordinates

            // Bind the array to the texture
            CudaHelper(cudaBindTextureToArray(tex, cuArray, channelDesc));

            // census_kernel<<<dimGrid, dimBlock, 0 >>> (d_rect_img, width, height,  DistortCoefArray,  iRMatrix , AcameraMatrix ) ;  wrong invokation
			census_kernel<<<dimGrid, dimBlock, 0 >>> (d_rect_img, width, height ) ;

           delete [] hData ;

		}

	}
