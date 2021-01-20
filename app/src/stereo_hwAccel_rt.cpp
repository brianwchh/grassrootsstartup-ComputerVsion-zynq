/*

author : ChengHe Wu  
email: brianwchh@gmail.com
github:  https://github.com/brianwchh/grassrootsstartup-ComputerVsion-zynq
linkedin: https://www.linkedin.com/in/brianwchh/

MIT-license

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


*/

#define u32 unsigned int
#define uchar unsigned char

//#include "xparameters.h"
#include "stereo.h"
//#include "vga_modes.h"

#include <sstream> // for converting the command line parameter to integer
#include <string>
#include <iostream>

#include <iomanip>
#include <string>
#include <fstream>

#include <sys/time.h>
#include <termios.h>

#include "v4l2grab_2.h"

using namespace std ;

#define vdma_contrl_address 0x43000000

static char * VDMA_BASEADDR      ; // 0x43000000

// ioctl cmds
/* 定义幻数 */
#define MEMDEV_IOC_MAGIC  'k'

/* 定义命令 */
#define MEMDEV_IOCPRINT         _IO(MEMDEV_IOC_MAGIC, 1)
#define MEMDEV_IOCGETPYADDRESS _IOR(MEMDEV_IOC_MAGIC, 2, int)
#define SET_COLOR_MAP     _IOW(MEMDEV_IOC_MAGIC, 3, int)
#define START_ONE_FRAME   _IOW(MEMDEV_IOC_MAGIC, 4, int)
#define MEMDEV_IOC_MAXNR 5


//#define AXI_VDMA_MM2S_VDMASR 0x04


// VTC
#define VTC_CONFIG_ADDR   0x43c00000
//dynclk
#define DYNCLK_CONFIG_ADDR   0x43c10000



/*
 * WEDGE and NOCOUNT can't both be high, so this is used to signal an error state
 */
#define ERR_CLKDIVIDER (1 << CLK_BIT_WEDGE | 1 << CLK_BIT_NOCOUNT)

#define ERR_CLKCOUNTCALC 0xFFFFFFFF //This value is used to signal an error

#define TOTAL_BUF_SIZE           1280 * 720 * 4 * 6
#define FRAME_BUFFER_SIZE (1280 * 720 * 4)

std::string vdevice0 = "/dev/video0" ;


static u32  FRAMEBUFFER_PHY1,FRAMEBUFFER_PHY2,FRAMEBUFFER_PHY3;  //Physical Address of Vbuf
static char*  FRAMEBUFFER_VIR1 ,*FRAMEBUFFER_VIR2,*FRAMEBUFFER_VIR3;    //Virtual Address of Vbuf

static char*  DYNCLK_CONFIG_BASEADDR_VIR ;
static char*  VTC_CONFIG_BASEADDR_VIR ;



namespace patch
{
    template < typename T > std::string to_string( const T& n )
    {
        std::ostringstream stm ;
        stm << n ;
        return stm.str() ;
    }
}


static void Xil_Out32(char * OutAddress, u32 Value)
{
    *(u32 *)OutAddress = Value;
}

static u32 Xil_In32(char* Addr)
{
    return *(u32* ) Addr;
}


#define   ROW_N  360
#define   COL_N    640

void my_remap(uchar* oriImg , uchar* remapImg , float* remapX, float* remapY  )
{
//    printf("x_float = %f\n", remapX.at<float>(0,0)) ;

    for(int r = 0 ; r< ROW_N; r++)
        for(int c=0; c< COL_N; c++)
        {
            float x_float = remapX[r * COL_N + c ]  ;
            float y_float = remapY[r * COL_N + c ]  ;
            int x_int = (int) x_float ;
            int y_int = (int) y_float ;
            float du = x_int + 1 -  x_float ;
            float dv = y_int + 1 -  y_float ;


//             printf("x_float = %f\n", x_float ) ;
//             printf("x_int = %d\n", x_int ) ;
//             printf("y_float = %f\n", y_float ) ;
//             printf("y_int = %d\n", y_int ) ;

//             printf("du = %f\n", du ) ;

            float I_r_c ;

            if((x_int < 0 || x_int > COL_N-1) || (y_int < 0 || y_int > ROW_N-1) )  {
                I_r_c = 0.0f ;
            }
            else {
                        int I_x_y    =  oriImg[y_int * COL_N + x_int] ;
                        int I_x1_y =  oriImg[y_int * COL_N + x_int + 1]  ;
                        int I_x_y1 =  oriImg[(y_int+1) * COL_N + x_int]  ;
                        int I_x1_y1 = oriImg[(y_int +1)* COL_N + x_int+1]  ;

                        int top2Sum = (int) ( I_x_y * du + I_x1_y * (1.0-du) ) ;
                        int bottom2Sum = (int) ( I_x_y1 * du + I_x1_y1*(1.0-du) ) ;

                        I_r_c =   top2Sum * dv  + bottom2Sum * (1.0-dv)  ;
            }

            remapImg[r * COL_N + c]  = (uchar) I_r_c ;
        }
}




int main(int argc, char** argv)
{

  v4l2grab_2 VedioGrab0(vdevice0.c_str());


    printf("press c for color depth map , g  for gray depth display  \n\r") ;


    int count = 0 ;


    int fbmem;
    int fbVbuf;

    char *FB[6] ;
    char * VDMA1_MM2S_FB[6] ;
    char * VDMA1_S2MM_FB[6] ;
    char * VDMA0_MM2S_FB[6];

    fbmem = open("/dev/mem", O_RDWR | O_SYNC);

    //  allocate video buffers
    fbVbuf = open("/dev/vdma",O_RDWR | O_SYNC);
    if(fbVbuf < 0)
    {
        printf("Vbuf open failed\n");
        return -1 ;
    }

    int ioct_args ;

     ioctl(fbVbuf, MEMDEV_IOCGETPYADDRESS , &FRAMEBUFFER_PHY1);


    FRAMEBUFFER_VIR1 = (char*) mmap(NULL,TOTAL_BUF_SIZE  , PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)FRAMEBUFFER_PHY1);
    if(FRAMEBUFFER_VIR1 == MAP_FAILED) {
        perror("VIDEO_BASEADDR_vir mapping for absolute memory access failed.\n");
        return -1;
    }

    /*************  fill in the frame buffer content here***************** */
    int  iPixelAddr = 0 ;
    int heigh = 720 ;
    int width = 1280 ;
    int stride = 1280 * 4 ;


    u32 dataWord ;
    iPixelAddr = 0;
    int stride1280  = 1280 ;

    FB[0] = FRAMEBUFFER_VIR1 ;
    FB[1] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE ;
    FB[2] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 2 ;
    FB[3] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 3 ;
    FB[4] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 4 ;
    FB[5] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 5 ;


    VDMA0_MM2S_FB[0] =  FB[0] ;

    VDMA1_MM2S_FB[0] =  FB[3] ;
    VDMA1_MM2S_FB[1] =  FB[4] ;
    VDMA1_MM2S_FB[2] =  FB[5] ;

    VDMA1_S2MM_FB[0] =  FB[0] ;
    VDMA1_S2MM_FB[1] =  FB[1] ;
    VDMA1_S2MM_FB[2] =  FB[2] ;

     int imgCnt = 0;

     iPixelAddr = 0 ;

     uchar*    left_gray        = new uchar[ROW_N * COL_N] ;
     uchar*    right_gray      = new uchar[ROW_N * COL_N] ;
     uchar*   frame_buffer  = new uchar[2560*720*3] ;

     float*   remapX1 = new float[ROW_N * COL_N] ;
     float*   remapY1 = new float[ROW_N * COL_N] ;
     float*   remapX2 = new float[ROW_N * COL_N] ;
     float*   remapY2 = new float[ROW_N * COL_N] ;

     uchar* left_rectified       = new uchar[ROW_N * COL_N] ;
     uchar*    right_rectified     = new uchar[ROW_N * COL_N] ;

     float tempData ;

     FILE *p_remapX1 = fopen("./param/remapX1.txt", "rb");
     if (p_remapX1 == NULL)
     {
         printf("no data read x1");
         return  - 1;
     }
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fscanf(p_remapX1, "%f\n", &tempData);

//             if((j < 10) && ( i <1) ) {
//                 printf("x1:         %f\n", tempData) ;
//             }

             remapX1[i * COL_N + j] = tempData;
         }
     }
     fclose(p_remapX1);

     FILE *p_remapY1 = fopen("./param/remapY1.txt", "rb");
     if (p_remapY1 == NULL)
     {
         printf("no data read Y1");
         return  - 1;
     }
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fscanf(p_remapY1, "%f\n", &tempData);
//             if((j < 10) && ( i < 1) ) {
//                 printf("y1:         %f\n", tempData) ;
//             }
             remapY1[i * COL_N + j] = tempData;
         }
     }
     fclose(p_remapY1);

     FILE *p_remapX2 = fopen("./param/remapX2.txt", "rb");
     if (p_remapX2 == NULL)
     {
         printf("no data read Y1");
         return  - 1;
     }
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fscanf(p_remapX2, "%f\n", &tempData);
//             if((j < 10) && ( i <1) ) {
//                 printf("x2:         %f\n", tempData) ;
//             }
             remapX2[i * COL_N + j] = tempData;
         }
     }
     fclose(p_remapX2);

     FILE *p_remapY2 = fopen("./param/remapY2.txt", "rb");
     if (p_remapY2 == NULL)
     {
         printf("no data read Y1");
         return  - 1;
     }
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fscanf(p_remapY2, "%f\n", &tempData);
//             if((j < 10) && ( i <1) ) {
//                 printf("y2:         %f\n", tempData) ;
//             }
             remapY2[i * COL_N + j] = tempData;
         }
     }
     fclose(p_remapY2);


     // rgb to grayscale Y'=0.299R'+0.587G'+0.114B'

    while(1){

                        VedioGrab0.read_frame() ;

                        for(int r=0; r<360; r=r+1)
                            for(int c=0; c<1280; c=c+1)
                            {
                                char  R =  VedioGrab0.frame_buffer[2*r*2560 *3 + 3*c*2 +0] ;  // R
                                char G  =  VedioGrab0.frame_buffer[2*r*2560 *3 + 3*c*2 +1] ;  // G
                                char B  =  VedioGrab0.frame_buffer[2*r*2560 *3  + 3*c*2 +2] ;  // B
                                if(c < 640)  // left image
                                {
                                    left_gray[r*640  + c  ] =  0.299*R+0.587*G+0.114*B ;
                                }
                                else
                                {
                                    right_gray[r*640  + c-640  ] =  0.299*R+0.587*G+0.114*B ;
                                }
                            }

                        my_remap(left_gray,left_rectified,remapX1,remapY1);
                        my_remap(right_gray,right_rectified,remapX2,remapY2);

                        // write original image data to frame buffer  1280 * 480
                          iPixelAddr = 0 ;
                          for(int r=0; r< 360 ; r++)
                          {
                              for(int c=640; c<640 * 2; c++)
                              {
                                  u32 data_r =  left_rectified[r*640  + c-640  ] ;  //   right.at<uchar>(r,c-640);
                                  u32 data_r_w = 0 ;
                                  data_r_w   |= ( (data_r << 16)&0x00FF0000) | ( (data_r << 8)&0x0000FF00) | ( (data_r << 0)&0x000000FF) ;
                                  Xil_Out32(VDMA0_MM2S_FB[0]  + iPixelAddr +  c * 4  , data_r_w);
                              }
                              iPixelAddr += stride1280 *4;
                          }



                        // *********  cpy to MM2S frame buffer *****************8

                         iPixelAddr = 0;
                        for (int i = 0; i < 360; i++)
                        {
                            int  sj = 0;
                            for (int j = 0; j <640; j+=4,sj+=8)
                            {
                                dataWord = 0x00 ;
                                   dataWord = dataWord | ((0xFF << 0   )& (right_rectified[i*640 + j+1]   << 0    )) ;
                                   dataWord = dataWord | ((0xFF << 8   )& (left_rectified[i*640 + j+1]   << 8    )) ;  // left1,right1 (low 16 bits)
                                   dataWord = dataWord | ((0xFF << 16   )& (right_rectified[i*640 + j]   << 16    )) ;
                                   dataWord = dataWord | ((0xFF << 24   )& (left_rectified[i*640 + j]   << 24    )) ;

                              Xil_Out32(VDMA1_MM2S_FB[0]  + iPixelAddr +  sj   , dataWord);

                              dataWord = 0x00 ;
                              dataWord = dataWord | ((0xFF << 0   )& (right_rectified[i*640 + j+3]   << 0    )) ;
                              dataWord = dataWord | ((0xFF << 8   )& (left_rectified[i*640 + j+3]   << 8    )) ;  // left1,right1 (low 16 bits)
                              dataWord = dataWord | ((0xFF << 16   )& (right_rectified[i*640 + j+2]   << 16    )) ;
                              dataWord = dataWord | ((0xFF << 24   )& (left_rectified[i*640 + j+2]   << 24    )) ;

                                Xil_Out32(VDMA1_MM2S_FB[0]  + iPixelAddr +  sj  + 4 , dataWord);

                            }
                            iPixelAddr += stride1280 ;
                        }




//                            int keyV  = getch();
                            int tint = 0x01 ;

//                            if(keyV == 'c')
//                            {
                                    tint = 0x01 ;
                                     ioctl(fbVbuf,SET_COLOR_MAP, &tint) ;
//                            }
//                            if(keyV == 'g')
//                            {
//                                    tint = 0x00;
//                                     ioctl(fbVbuf,SET_COLOR_MAP, &tint) ;
//                            }



                        // start stereo process in FPGA
                        ioct_args = 1 ;
                        ioctl(fbVbuf, START_ONE_FRAME,&ioct_args );
                        ioct_args = 0 ;
                        ioctl(fbVbuf, START_ONE_FRAME,&ioct_args );

                        imgCnt ++ ;

        }

    // ----------------------------------------------------------------------------

    munmap((void*)FRAMEBUFFER_VIR1,TOTAL_BUF_SIZE) ;


    close(fbVbuf);



    delete[]     left_gray   ;
     delete[]    right_gray     ;
     delete[]    frame_buffer  ;

     delete[]    remapX1  ;
     delete[]    remapY1   ;
     delete[]    remapX2   ;
     delete[]    remapY2   ;

    cout<< " done" << endl;

  return 0 ;
}


