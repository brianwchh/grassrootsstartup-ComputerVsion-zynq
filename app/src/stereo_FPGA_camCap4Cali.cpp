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

#include "xparameters.h"
#include "stereo.h"
#include "vga_modes.h"

#include <opencv/highgui.h>
#include "opencv2/imgproc/imgproc.hpp"
#include <opencv/cv.h>
#include "opencv2/objdetect/objdetect.hpp"
#include <opencv2/opencv.hpp>

#include <sys/time.h>
#include <sstream>
#include <fstream>
#include <termios.h>


#include <sstream>

using namespace std ;
using namespace cv;


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
#define SET_S2MM_PRK_NUM   _IOW(MEMDEV_IOC_MAGIC, 5, int)
#define MEMDEV_IOC_MAXNR 8


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

#define TOTAL_BUF_SIZE           1280 * 720 * 4 * 8
#define FRAME_BUFFER_SIZE (1280 * 720 * 4)

std::string vdevice0 = "/dev/video0" ;


static u32  FRAMEBUFFER_PHY1,FRAMEBUFFER_PHY2,FRAMEBUFFER_PHY3;  //Physical Address of Vbuf
static char*  FRAMEBUFFER_VIR1 ,*FRAMEBUFFER_VIR2,*FRAMEBUFFER_VIR3;    //Virtual Address of Vbuf

static char*  DYNCLK_CONFIG_BASEADDR_VIR ;
static char*  VTC_CONFIG_BASEADDR_VIR ;

#define IMG_WIDTH  640
#define IMG_HEIGHT 480

namespace patch
{
    template < typename T > std::string to_string( const T& n )
    {
        std::ostringstream stm ;
        stm << n ;
        return stm.str() ;
    }
}

// detect keyboard
char getch()
{
//    cout << "key pressed  \n " << endl ;
    fd_set set;
    struct timeval timeout;
    int rv;
    char buff = 0;
    int len = 1;
    int filedesc = 0;
    FD_ZERO(&set);
    FD_SET(filedesc, &set);

    timeout.tv_sec = 0;
    timeout.tv_usec = 1000;

    rv = select(filedesc + 1, &set, NULL, NULL, &timeout);

    struct termios old = {0};
    if (tcgetattr(filedesc, &old) < 0)
        printf("tcsetattr()");
    old.c_lflag &= ~ICANON;
    old.c_lflag &= ~ECHO;
    old.c_cc[VMIN] = 1;
    old.c_cc[VTIME] = 0;
    if (tcsetattr(filedesc, TCSANOW, &old) < 0)
        printf("tcsetattr ICANON");

    if(rv == -1)
        printf("select");
    else if(rv == 0)
//        ROS_INFO("no_key_pressed");
        rv = 0 ;
    else
        ssize_t siz = read(filedesc, &buff, len );

    old.c_lflag |= ICANON;
    old.c_lflag |= ECHO;
    if (tcsetattr(filedesc, TCSADRAIN, &old) < 0)
        printf ("tcsetattr ~ICANON");
    return (buff);
}


static void Xil_Out32(char * OutAddress, u32 Value)
{
    *(u32 *)OutAddress = Value;
}

static u32 Xil_In32(char* Addr)
{
    return *(u32* ) Addr;
}


void median_filter(const uint16_t* d_src, uint16_t* d_dst , int width, int height)
{
    // 3 * 3 kernel  median filter
    for(int r=0; r< height ; r++)
        for(int c=0; c<width; c++)
        {
            uint16_t  windowValue[9] ;

            // load data to window
            for(int indy=-1; indy<2; indy++)
                for(int indx=-1; indx<2; indx++)
            {
                    if(r+indy < 0 || r+indy >= height || c+indx < 0 || c+indx >= width)
                    {
                        windowValue[(indy+1)*3 + indx+1] = 0 ;
                    }
                    else
                    {
                        windowValue[(indy+1)*3 + indx+1] =  d_src[(r+indy)*width + indx+c] ;
                    }
            }

            // caculate the median value for each pixel
            /*  sorting   */
            for(int rank=0; rank < 8 ; rank++)
            {
                uint16_t  tmp  ;  // = windowValue[rank];
                for(int k= rank+1; k < 9 ; k++ )
                {
                    if(windowValue[k] <  windowValue[rank])  // swap values
                    {
                        tmp =  windowValue[rank];
                        windowValue[rank]= windowValue[k] ;
                        windowValue[k] = tmp;
                    }
                }
            }


            // assign median value to output
            d_dst[r*width + c] = windowValue[4];

        }

}


int main(int argc, char** argv)
{

    Mat remapx1 ;
    Mat remapy1 ;
    Mat remapx2 ;
    Mat remapy2 ;

    printf("press c for color depth map , g  for gray depth display  \n\r") ;


    int count = 0 ;


    int fbmem;
    int fbVbuf;

    char *FB[8] ;
    char * VDMA2_S2MM_FB[3] ;
    char * VDMA3_S2MM_FB[3] ;

    char * VDMA1_MM2S_FB[3] ;
    char * VDMA1_S2MM_FB[3] ;
    char * VDMA0_MM2S_FB[3];

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

//     printf("physical address returned from kernel = %08X\n\r", FRAMEBUFFER_PHY1) ;
//     FRAMEBUFFER_PHY1 = (u32) ioct_args ;

//    printf("Vbuf PHY_ADDRESS is 0x%08x\n",FRAMEBUFFER_PHY1);

    FRAMEBUFFER_VIR1 = (char*) mmap(NULL,TOTAL_BUF_SIZE  , PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)FRAMEBUFFER_PHY1);
    if(FRAMEBUFFER_VIR1 == MAP_FAILED) {
        perror("VIDEO_BASEADDR_vir mapping for absolute memory access failed.\n");
        return -1;
    }
//    printf("Vbuf Virtual_ADDRESS is 0x%08x\n",FRAMEBUFFER_VIR1);
//    memset(FRAMEBUFFER_VIR1, 0x00, TOTAL_BUF_SIZE);


    /*************  fill in the frame buffer content here***************** */
    int  iPixelAddr = 0 ;
    int heigh = 720 ;
    int width = 1280 ;
    int stride = 1280 * 4 ;
//    for(int r=0 ; r < heigh; r++){
//        for(int c=0; c < width*4 ; c+=4)
//        {
//            if(r == 16 || c == 16 || r == heigh -16 || c == width * 4 -16 )
//                Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr + c   , 0x0000FF00);
//            else
//                Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr +  c  , 0x00000FFF);
//        }
//        iPixelAddr += stride ;
//    }



//    cv::Mat left  (480,640,CV_8UC1)         ;          // = imread("left1.png",0);
//    cv::Mat right(480,640,CV_8UC1)        ;          //  = imread("right1.png",0);

    u32 dataWord ;
    iPixelAddr = 0;
    int stride1280  = 1280 ;



    FB[0] = FRAMEBUFFER_VIR1 ;
    FB[1] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE ;
    FB[2] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 2 ;
    FB[3] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 3 ;
    FB[4] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 4 ;
    FB[5] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 5 ;
    FB[6] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 6 ;
    FB[7] = FRAMEBUFFER_VIR1 + FRAME_BUFFER_SIZE * 7 ;

    // capture left image
    VDMA2_S2MM_FB[0] =  FB[1] ;
    VDMA2_S2MM_FB[1] =  FB[2] ;
    VDMA2_S2MM_FB[2] =  FB[3] ;
    // capture right image
    VDMA3_S2MM_FB[0] =  FB[4] ;
    VDMA3_S2MM_FB[1] =  FB[5] ;
    VDMA3_S2MM_FB[2] =  FB[6] ;

    // stereo
    VDMA1_MM2S_FB[0]  = FB[7] ;
    VDMA1_MM2S_FB[1]  = FB[7] ;
    VDMA1_MM2S_FB[2]  = FB[7] ;

    VDMA1_S2MM_FB[0]  = FB[0] ;
    VDMA1_S2MM_FB[1]  = FB[0] ;
    VDMA1_S2MM_FB[2]  = FB[0] ;

    // display buffer
    VDMA0_MM2S_FB[0]  = FB[0] ;


     int imgCnt = 0;

     Mat   back_ground(720-480,1280,CV_8UC3);

     for(int r=0; r< back_ground.rows ; r++)
     {
         for(int c=0; c<back_ground.cols ; c++)
         {
             back_ground.at<cv::Vec3b>(r,c)[0]  = 0xFF;
             back_ground.at<cv::Vec3b>(r,c)[1]  = 0x00;
             back_ground.at<cv::Vec3b>(r,c)[2]  = 0x00;
         }
     }

     putText(back_ground, "early stage project demo , will be updated soon...... ", Point(80, 30), CV_FONT_HERSHEY_SIMPLEX, 1, Scalar(0, 0, 200), 2);
     putText(back_ground, "Stereo vision proccessed by FPGA, ", Point(600, 80), CV_FONT_HERSHEY_SIMPLEX, 1, Scalar(0, 0, 200), 2);
     putText(back_ground, "core speed 60+FPS , 640 X 480 resolution", Point(600, 120), CV_FONT_HERSHEY_SIMPLEX, 1, Scalar(0, 0, 200), 2);
     putText(back_ground, "email:1503352326@qq.com", Point(80, 80), CV_FONT_HERSHEY_SIMPLEX, 1, Scalar(0, 0, 200), 2);
     putText(back_ground, "brianwchh@gmail.com", Point(80, 140), CV_FONT_HERSHEY_SIMPLEX, 1, Scalar(0, 0, 200), 2);


     iPixelAddr = 0 ;
     for(int r=0; r< back_ground.rows ; r++)
     {
         for(int c= 0; c<back_ground.cols ; c++)
         {
             char B  = back_ground.at<cv::Vec3b>(r,c)[0]  ;
             char G = back_ground.at<cv::Vec3b>(r,c)[1]  ;
             char R =  back_ground.at<cv::Vec3b>(r,c)[2]  ;
             u32 data_w= 0;
            data_w  = data_w  | ( (R << 16)&0x00FF0000) | ( (G << 8)&0x0000FF00) | ( (B << 0)&0x000000FF) ;

             Xil_Out32(FB[0]  +  1280*480*4 +    iPixelAddr +  c * 4  , data_w);

         }
         iPixelAddr += stride1280 *4;
     }


     Mat  left_rgb(IMG_HEIGHT ,IMG_WIDTH,CV_8UC3);
     Mat right_rgb(IMG_HEIGHT ,IMG_WIDTH,CV_8UC3);

     int imageStride = 1280 * 4 ;


     /*  rectify the images   */
     FileStorage f_remapx1("./parameters/onboard/remapx1.xml", FileStorage::READ);
     FileStorage f_remapy1("./parameters/onboard/remapy1.xml", FileStorage::READ);
     FileStorage f_remapx2("./parameters/onboard/remapx2.xml", FileStorage::READ);
     FileStorage f_remapy2("./parameters/onboard/remapy2.xml", FileStorage::READ);

     if(f_remapx1.isOpened())
     {
         f_remapx1["remapx1"] >> remapx1;
 //        cout << "cameraRotationMatrix1 = " << endl <<cameraRotationMatrix1 << endl ;
         f_remapx1.release();
     }
     if(f_remapy1.isOpened())
     {
         f_remapy1["remapy1"] >> remapy1;
 //        cout << "cameraRotationMatrix1 = " << endl <<cameraRotationMatrix1 << endl ;
         f_remapy1.release();
     }
     if(f_remapx2.isOpened())
     {
         f_remapx2["remapx2"] >> remapx2;
 //        cout << "cameraRotationMatrix1 = " << endl <<cameraRotationMatrix1 << endl ;
         f_remapx2.release();
     }
     if(f_remapy2.isOpened())
     {
         f_remapy2["remapy2"] >> remapy2;
 //        cout << "cameraRotationMatrix1 = " << endl <<cameraRotationMatrix1 << endl ;
         f_remapy2.release();
     }

    int  s2mm_park_index =0 ;
    int  s2mm_read_buf_indx = 0 ;

    ofstream LRCam ("LRCam.txt");

    while(1){

                        s2mm_read_buf_indx = s2mm_park_index ;

                        // set read buffer index = s2mm_park_index -1
                        if(s2mm_park_index == 2)
                        {
                            s2mm_park_index = 0 ;
                        }
                        else {
                            s2mm_park_index = s2mm_park_index + 1 ;
                        }
                        // set vdma2 and vdma3 s2mm write parking index , start capturing a new frame while cpu is processing current frame
                        ioct_args = s2mm_park_index ;
                        ioctl(fbVbuf, SET_S2MM_PRK_NUM,&ioct_args );


                       // read left and right image from buffer[1] & buffer[4] respectively
                        /*  1.  read left image from FB[1]  */
                        for(int r=0; r<480; r=r+1)
                            for(int c=0; c<640*4; c=c+4)
                            {
                                char* Data_ptr = FB[s2mm_read_buf_indx] +  r * imageStride + c ;
                                u32 datatemp = Xil_In32(Data_ptr) ;
                                uchar  R = (datatemp >> 16) & 0xFF ;
                                uchar  G = (datatemp >> 8  ) & 0xFF ;
                                uchar  B = (datatemp >> 0  ) & 0xFF ;
                                left_rgb.at<cv::Vec3b>(r,c/4)[0] = B ;
                                left_rgb.at<cv::Vec3b>(r,c/4)[1] = G ;
                                left_rgb.at<cv::Vec3b>(r,c/4)[2] = R ;

                                // test , move to display buffer for debug
                                Xil_Out32(FB[0] + r * imageStride  + c , datatemp );
                            }

                        /*  2.  read right image from FB[4]  */
                        for(int r=0; r<480; r=r+1)
                            for(int c=0; c<640*4; c=c+4*1)
                            {
                                char* Data_ptr = FB[s2mm_read_buf_indx] +  r * imageStride + 640*4  + c ;
                                u32 datatemp = Xil_In32(Data_ptr ) ;
                                uchar  R = (datatemp >> 16) & 0xFF ;
                                uchar  G = (datatemp >>  8 ) & 0xFF ;
                                uchar  B = (datatemp >>  0 ) & 0xFF ;
                                right_rgb.at<cv::Vec3b>(r,c/4)[0] = B ;
                                right_rgb.at<cv::Vec3b>(r,c/4)[1] = G ;
                                right_rgb.at<cv::Vec3b>(r,c/4)[2] = R ;

                                // test , move to display buffer for debug
                                Xil_Out32(FB[0] + r * imageStride + 640*4  +  c , datatemp );
                            }



                        // *********  cpy to MM2S frame buffer *****************

//                        // convert to grayscale
//                        cvtColor(left_rgb,left_unrectified,CV_BGR2GRAY);
//                        cvtColor(right_rgb,right_unrectified,CV_BGR2GRAY);
//                        // rectity
//                        remap(left_unrectified,   left   , remapx1, remapy1,CV_INTER_LINEAR);
//                        remap(right_unrectified, right, remapx2, remapy2,CV_INTER_LINEAR);


                        // debug only,   write rectified image to display buffer
//                        iPixelAddr = 0 ;
//                        for(int r=0; r< left.rows ; r++)
//                        {
//                            for(int c=640; c<640 * 2; c++)
//                            {
//                                u32 data_r = right.at<uchar>(r,c-640);
//                                u32 data_r_w = 0 ;
//                                data_r_w   |= ( (data_r << 16)&0x00FF0000) | ( (data_r << 8)&0x0000FF00) | ( (data_r << 0)&0x000000FF) ;
//                                Xil_Out32(VDMA0_MM2S_FB[0]  + iPixelAddr +  c * 4  , data_r_w);
//                            }
//                            iPixelAddr += stride1280 *4;
//                        }

                        string left_imgName   = "caliImgs/left"   +patch::to_string(imgCnt)+".png" ;
                        string right_imgName = "caliImgs/right"+patch::to_string(imgCnt)+".png" ;

                        int keyV  = getch();

                        if(keyV == 's')
                        {
                            imwrite(left_imgName.c_str()   , left_rgb) ;
                            imwrite(right_imgName.c_str() , right_rgb) ;

                            LRCam << left_imgName << endl ;    //  left and right has been mistakenly swaped , change the print order to reverse it in calibration proccess
                            LRCam << right_imgName << endl ;
//                            LRCam << left_imgName << endl ;
                             printf("image %d pair have been saved to disk \n ", imgCnt);
                            imgCnt ++ ;
                        }


#if 0

                        // ****************** copy from MM2S buffer *******************************
                          iPixelAddr = 0 ;
                          for(int r=0; r< left.rows ; r++)
                          {
                              for(int c=0; c<left.cols * 1; c++)
                              {
                                        dataWord = Xil_In32(VDMA1_S2MM_FB[1]  + iPixelAddr +  c * 4  );
                                    dispFromMM2S[r * left.cols + c]  =  dataWord & 0xFF ;
                              }
                              iPixelAddr += stride1280 *4;
                          }

                        median_filter(dispFromMM2S,filteredDisp2MM2S, left.cols,left.rows);

                        // *********  cpy to MM2S frame buffer *****************8

                         iPixelAddr = 0;
                          for(int r=0; r< left.rows ; r++)
                          {
                              for(int c= 0 ; c<left.cols ; c++)
                              {
                                  u32 data_l_w = 0 ;
                                  uint16_t ttt = filteredDisp2MM2S[r * left.cols + c]   ;
                                  data_l_w = data_l_w | ( (ttt << 16)&0x00FF0000) | ( (ttt << 8)&0x0000FF00) | ( (ttt << 0)&0x000000FF) ;
                                    if(c < left.cols)  // left
                                        Xil_Out32(VDMA1_S2MM_FB[0]  + iPixelAddr +  c * 4  , data_l_w);
                              }
                              iPixelAddr += stride1280 *4;
                          }

#endif

        }



    // ----------------------------------------------------------------------------

    munmap((void*)FRAMEBUFFER_VIR1,TOTAL_BUF_SIZE) ;

//    fclose(LR_fd);
//    LRCam.close();
    close(fbVbuf);

    cout<< " done" << endl;

  return 0 ;
}





