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


using namespace std ;
using namespace cv;


#define vdma_contrl_address 0x43000000

static char * VDMA_BASEADDR      ; // 0x43000000

#define GET_VIRTUAL_ADDRESS 0
#define GET_PHY_ADDRESS     1

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

#define FrameSize 1280 * 720 * 4 * 6

std::string vdevice0 = "/dev/video0" ;


static u32  FRAMEBUFFER_PHY1,FRAMEBUFFER_PHY2,FRAMEBUFFER_PHY3;  //Physical Address of Vbuf
static char*  FRAMEBUFFER_VIR1 ,*FRAMEBUFFER_VIR2,*FRAMEBUFFER_VIR3;    //Virtual Address of Vbuf

static char*  DYNCLK_CONFIG_BASEADDR_VIR ;
static char*  VTC_CONFIG_BASEADDR_VIR ;


static void Xil_Out32(char * OutAddress, u32 Value)
{
    *(u32 *)OutAddress = Value;
}

static u32 Xil_In32(char* Addr)
{
    return *(u32* ) Addr;
}

int main(int argc, char** argv)
{

//  v4l2grab_2 VedioGrab0(vdevice0.c_str());

//    VideoCapture VedioGrab0("./Stereo_video.avi"); // open the default camera
//    if(!VedioGrab0.isOpened())  // check if we succeeded
//    {
//        cout << "can't open file " << endl ;
//        return -1;
//    }

  // cv::Mat wrapped(rows, cols, CV_32FC1, external_mem, CV_AUTOSTEP); // does not copy
//    cv::Mat frame1(720,2560,CV_8UC3,VedioGrab0.frame_buffer) ;


    int count = 0 ;


    int fbmem;
    int fbVbuf;

    fbmem = open("/dev/mem", O_RDWR | O_SYNC);

    //  allocate video buffers
    fbVbuf = open("/dev/vdma",O_RDWR | O_SYNC);
    if(fbVbuf < 0)
    {
        printf("Vbuf open failed\n");
        return -1 ;
    }
    FRAMEBUFFER_PHY1 =  ioctl(fbVbuf, GET_PHY_ADDRESS);
//    printf("Vbuf PHY_ADDRESS is 0x%08x\n",FRAMEBUFFER_PHY1);
    FRAMEBUFFER_VIR1 = (char*) mmap(NULL,FrameSize  , PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)FRAMEBUFFER_PHY1);
    if(FRAMEBUFFER_VIR1 == MAP_FAILED) {
        perror("VIDEO_BASEADDR_vir mapping for absolute memory access failed.\n");
        return -1;
    }
//    printf("Vbuf Virtual_ADDRESS is 0x%08x\n",FRAMEBUFFER_VIR1);
//    memset(FRAMEBUFFER_VIR1, 0x00, FrameSize);


    /*************  fill in the frame buffer content here***************** */
    u32 iPixelAddr = 0 ;
    int heigh = 720 ;
    int width = 1280 ;
    int stride = 1280 * 4 ;
    for(int r=0 ; r < heigh; r++){
        for(int c=0; c < width*4 ; c+=4)
        {
            if(r == 16 || c == 16 || r == heigh -16 || c == width * 4 -16 )
                Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr + c   , 0x0000FF00);
            else
                Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr +  c  , 0x00FFFF00);
        }
        iPixelAddr += stride ;
    }



//    //----------opecv part------------------------
//    CvCapture *input_video = cvCreateFileCapture("/root/road.avi");
//    IplImage* img ;
//    CvSize video_size;
//    video_size.height = 360 ;
//    video_size.width  = 1280  ;
//    IplImage *frame = cvCreateImage(video_size,IPL_DEPTH_8U,3);

////    frame->imageData = VIDEO_BASEADDR_vir;

//    if (input_video == NULL) {
//        fprintf(stderr, "Error: Can't open video\n");
//        return -1;
//    }

//    u32 index= 0;
//    char* BuffAddress ;
//    while(1) {
//        img = cvQueryFrame(input_video);
//        if (img == NULL) {
//            fprintf(stderr, "Error: null frame received\n");
//            return -1;
//        }
//    }



    cv::Mat imgResized = imread("test.png");

    while (1) {
//              VedioGrab0.read_frame();
//              cv::resize(frame1, imgResized, cv::Size(2560/2, 720/2), 0, 0, cv::INTER_CUBIC);    // imgResized

//               VedioGrab0  >> imgResized ;

//               cout << "width = " << imgResized.cols << " height  =  " << imgResized.rows  << endl ;

                iPixelAddr = 0 ;
              for(int r=0; r< imgResized.rows ; r++){
                  for(int c=0; c<imgResized.cols; c++)
                  {
                      uchar R = imgResized.at<cv::Vec3b>(r,c)[2];
                      uchar G = imgResized.at<cv::Vec3b>(r,c)[1];
                      uchar B = imgResized.at<cv::Vec3b>(r,c)[0];
                      unsigned int  Val  =  (0xFF & B) <<  0 ;
                      Val = Val | (0xFF & G) <<  8 ;
                      Val = Val | (0xFF & R) <<  16 ;
                      Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr +  c * 4  , Val);
                  }
                  iPixelAddr += stride ;
              }

              imwrite("savedImage.png",imgResized ) ;


         }


    // ----------------------------------------------------------------------------

    munmap((void*)FRAMEBUFFER_VIR1,FrameSize) ;
    close(fbVbuf);

    cout<< " config done" << endl;

  return 0 ;
}


