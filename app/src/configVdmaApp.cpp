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
#include <unistd.h>

#include "xparameters.h"
#include "stereo.h"
#include "vga_modes.h"

#include "configVdmaApp.h"

using namespace std ;
using namespace cv;


#define vdma_contrl_address 0x43000000

static char * VDMA_BASEADDR      ; // 0x43000000

#define GET_VIRTUAL_ADDRESS 0
#define GET_PHY_ADDRESS     1

//#define AXI_VDMA_MM2S_VDMASR 0x04


#define   VDMA1_CONTROL_ADDRESS  0x43010000
#define   S2MM_VDMACR            0x00000030
#define   S2MM_START_ADDRESS0    0x000000AC
#define   S2MM_START_ADDRESS1    0x000000B0
#define   S2MM_START_ADDRESS2    0x000000B4
#define   PARK_PTR_REG           0x00000028
#define   S2MM_FRMDLY_STRIDE     0x000000A8
#define   S2MM_HSIZE             0x000000A4
#define   S2MM_VSIZE             0x000000A0

#define   MM2S_VDMACR            0x00000000
#define   MM2S_START_ADDRESS0    0x0000005C
#define   MM2S_START_ADDRESS1    0x00000060
#define   MM2S_START_ADDRESS2    0x00000064
#define   MM2S_FRMDLY_STRIDE     0x00000058
#define   MM2S_HSIZE             0x00000054
#define   MM2S_VSIZE             0x00000050


#define MM2S_PARK_BIT_MASK  (0x1F) << 0
#define S2MM_PARK_BIT_MASK  (0x1F) << 8

#define VDMA0_MM2S_IMAGE_WIDTH 1280   // 1280
#define VDMA0_MM2S_IMAGE_HEIGHT 720    // 720

#define MM2S_IMAGE_WIDTH 1280   // 1280
#define MM2S_IMAGE_HEIGHT 480    // 720

#define S2MM_IMAGE_WIDTH 640   // 1280
#define S2MM_IMAGE_HEIGHT 480    // 720

#define VDMA1_STRIDE 1280 * 4  // 1280 × 4




// VTC
#define VTC_CONFIG_ADDR   0x43c00000
//dynclk
#define DYNCLK_CONFIG_ADDR   0x43c10000



/*
 * WEDGE and NOCOUNT can't both be high, so this is used to signal an error state
 */
#define ERR_CLKDIVIDER (1 << CLK_BIT_WEDGE | 1 << CLK_BIT_NOCOUNT)

#define ERR_CLKCOUNTCALC 0xFFFFFFFF //This value is used to signal an error

#define OFST_DYNCLK_CTRL 0x0
#define OFST_DYNCLK_STATUS 0x4
#define OFST_DYNCLK_CLK_L 0x8
#define OFST_DYNCLK_FB_L 0x0C
#define OFST_DYNCLK_FB_H_CLK_H 0x10
#define OFST_DYNCLK_DIV 0x14
#define OFST_DYNCLK_LOCK_L 0x18
#define OFST_DYNCLK_FLTR_LOCK_H 0x1C

#define BIT_DYNCLK_START 0
#define BIT_DYNCLK_RUNNING 0

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

#define XVtc_In32		Xil_In32	/**< Input Operations */
#define XVtc_Out32		Xil_Out32	/**< Output Operations */

#define XAxiVdma_Out32 Xil_Out32

#define XVtc_WriteReg(BaseAddress, RegOffset, Data) 	\
        XVtc_Out32((BaseAddress) + (RegOffset), (u32)(Data))

#define XAxiVdma_WriteReg(BaseAddress, RegOffset, Data)          \
    XAxiVdma_Out32((BaseAddress) + (RegOffset), (Data))


typedef struct {
        u32 clk0L;
        u32 clkFBL;
        u32 clkFBH_clk0H;
        u32 divclk;
        u32 lockL;
        u32 fltr_lockH;
} ClkConfig;

typedef struct {
        double freq;
        u32 fbmult;
        u32 clkdiv;
        u32 maindiv;
} ClkMode;


static const  VideoMode VMODE_800x600 = {
     "800x600@60Hz",
     800,
     600,
     840,
     968,
     1055,
     1,
     601,
     605,
     627,
     1,
     40.0
};

typedef struct {
        u32* dynClkAddr; /*Virtural Base address of the dynclk core*/
        VideoMode vMode; /*Current Video mode*/
        double pxlFreq; /* Frequency of clock currently being generated */
        u32 curFrame; /* Current frame being displayed */
} DisplayCtrl;

/*
* The configuration table for devices
*/

u32 ClkDivider(u32 divide);


static void delay_ms(u32 ms_count) {
  u32 count;
  for (count = 0; count < ((ms_count * 800000) + 1); count++) {
  }
}



/*
 * {clk0L=0x00800042, clkFBL=0x000000c3, clkFBH_clk0H=0x00000000, divclk=0x00001041, lockL=0x7e8fa401, fltr_lockH=0x0073008c}
 */



void ClkStart(char*  dynClkAddr_vir)
{
    Xil_Out32(dynClkAddr_vir + OFST_DYNCLK_CTRL, (1 << BIT_DYNCLK_START));
    while(!(Xil_In32(dynClkAddr_vir + OFST_DYNCLK_STATUS) & (1 << BIT_DYNCLK_RUNNING)));

    return;
}

void ClkStop(char* dynClkAddr_vir)
{
    Xil_Out32(dynClkAddr_vir + OFST_DYNCLK_CTRL, 0);
    while((Xil_In32(dynClkAddr_vir + OFST_DYNCLK_STATUS) & (1 << BIT_DYNCLK_RUNNING)));

    return;
}

static void writeBuf (IplImage* frame , char* BuffAddress)
{
    u32 n;
    u32 d;
    u32 dcnt;
    u32 r;
    u32 g;
    u32 b;
    int row ;
    int col  ;
    int ptr ;

    dcnt = 0;
    for( row = 0; row< frame->height; row++ ) {
        ptr = frame->widthStep * row ;
        for(col = 0; col < frame->width; col++ ) {

            b = frame->imageData[ptr + col * 3 + 0] ; //b
            g = frame->imageData[ptr + col * 3 + 1] ; //g
            r = frame->imageData[ptr + col * 3 + 2] ; //r
            Xil_Out32((BuffAddress + (dcnt*4)), (r << 16) | (g << 8) | b);
            dcnt = dcnt + 1;
        }
    }
}

int main(int argc, char** argv)
{

//  v4l2grab_2 VedioGrab0(vdevice0.c_str());

//  // cv::Mat wrapped(rows, cols, CV_32FC1, external_mem, CV_AUTOSTEP); // does not copy
//  cv::Mat frame1(720,2560,CV_8UC3,VedioGrab0.frame_buffer) ;

//  cv::Mat imgResized;
//  int count = 0 ;

//  while (1) {
//            VedioGrab0.read_frame();
////            cv::resize(frame1, imgResized, cv::Size(2560/2, 720/2), 0, 0, cv::INTER_CUBIC);    // imgResized

//    //        imwrite("savedImage.png",imgResized ) ;
//            std::cout << count  << std::endl ;

//            count ++ ;

//       }



    int fbmem;
    int fbVbuf;

    fbmem = open("/dev/mem", O_RDWR | O_SYNC);

    //  allocate video buffers
    fbVbuf = open("/dev/Vbuf",O_RDWR | O_SYNC);
    if(fbVbuf < 0)
    {
        printf("Vbuf open failed\n");
        return -1 ;
    }
    FRAMEBUFFER_PHY1 =  ioctl(fbVbuf, GET_PHY_ADDRESS);
    printf("Vbuf PHY_ADDRESS is 0x%08x\n",FRAMEBUFFER_PHY1);
    FRAMEBUFFER_VIR1 = (char*) mmap(NULL,FrameSize  , PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)FRAMEBUFFER_PHY1);
    if(FRAMEBUFFER_VIR1 == MAP_FAILED) {
        perror("VIDEO_BASEADDR_vir mapping for absolute memory access failed.\n");
        return -1;
    }
    printf("Vbuf Virtual_ADDRESS is 0x%08x\n",FRAMEBUFFER_VIR1);
    memset(FRAMEBUFFER_VIR1, 0x00, FrameSize);

    VTC_CONFIG_BASEADDR_VIR =(char *) mmap(NULL, 0xFFF, PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)VTC_CONFIG_ADDR);
    if(VTC_CONFIG_BASEADDR_VIR == MAP_FAILED) {
        perror("VTC_CONFIG_ADDR mapping for absolute memory access failed.\n");
        return -1;
    }

    DYNCLK_CONFIG_BASEADDR_VIR =(char *) mmap(NULL, 0xFFF, PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)DYNCLK_CONFIG_ADDR);
    if(DYNCLK_CONFIG_BASEADDR_VIR == MAP_FAILED) {
        perror("DYNCLK_CONFIG_ADDR mapping for absolute memory access failed.\n");
        return -1;
    }

    VDMA_BASEADDR =(char *) mmap(NULL, 0xFFF, PROT_READ | PROT_WRITE, MAP_SHARED, fbmem, (off_t)0x43000000);
    if(VDMA_BASEADDR == MAP_FAILED) {
        perror("VDMA_BASEADDR mapping for absolute memory access failed.\n");
        return -1;
    }


    printf("mmap successful---------\n");


    /*******************      config dynamic clock module                **************************/
    cout << "start config dynclk" << endl ;

    Xil_Out32(DYNCLK_CONFIG_BASEADDR_VIR + OFST_DYNCLK_CLK_L                   , 0x00000041 ) ;
    usleep(30000);
    Xil_Out32(DYNCLK_CONFIG_BASEADDR_VIR + OFST_DYNCLK_FB_L                      , 0x0000069A ) ;
    usleep(30000);
    Xil_Out32(DYNCLK_CONFIG_BASEADDR_VIR + OFST_DYNCLK_FB_H_CLK_H      , 0x00000000 ) ;
    usleep(30000);
    Xil_Out32(DYNCLK_CONFIG_BASEADDR_VIR + OFST_DYNCLK_DIV                        , 0x000020C4 ) ;
    usleep(30000);
    Xil_Out32(DYNCLK_CONFIG_BASEADDR_VIR + OFST_DYNCLK_LOCK_L                , 0xCFAFA401 ) ;
    usleep(30000);
    Xil_Out32(DYNCLK_CONFIG_BASEADDR_VIR + OFST_DYNCLK_FLTR_LOCK_H    , 0x00A300FF ) ;
    usleep(30000);

    ClkStop(DYNCLK_CONFIG_BASEADDR_VIR);
    ClkStart(DYNCLK_CONFIG_BASEADDR_VIR);


    /******************  config vtc ***********************************/
    cout << "start config dynclk" << endl ;

//    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000000  ,  0x80000000)  ;
//    usleep(30000);
//    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000000  ,  0x00000002)  ;
//    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x0000006C  ,  0x0000007F)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000070  ,  0x00000672)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000074  ,  0x02EE02EE)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000060  ,  0x02D00500)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000078  ,  0x0596056E)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000080  ,  0x02D902D4)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x0000008C  ,  0x02D902D4)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000068  ,  0x00000002)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x0000007C  ,  0x05000500)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000084  ,  0x056E056E)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000088  ,  0x05000500)  ;
    usleep(30000);
    printf("0x00000088  = %08X\n\r",Xil_In32( (VTC_CONFIG_BASEADDR_VIR + 0x00000088)));
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000090  ,  0x056E056E)  ;
    usleep(30000);
    printf("0x00000090  = %08X\n\r",Xil_In32( (VTC_CONFIG_BASEADDR_VIR + 0x00000090)));
//    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000000  ,  0x03F7EF02)  ;
    usleep(30000);
    XVtc_WriteReg(VTC_CONFIG_BASEADDR_VIR,  0x00000000  ,  0x03F7EF06)  ;
    usleep(30000);
    printf("0x00000000  = %08X\n\r",Xil_In32( (VTC_CONFIG_BASEADDR_VIR + 0x00000000)));




    /* ************************ config VDMA *******************************/    
    cout << "config done " << endl ;

//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000000  ,  0x00010002);   // MM2S_VDMACR
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000054  ,  0x00001400);   // MM2S_HSIZE
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000058  ,  0x00001400);   // MM2S_FRMDLY_STRIDE    // note that here stride =  1280 * 4
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x0000005C  ,  FRAMEBUFFER_PHY1);   // 5c - 98 : MM2S_START_ADDRESS
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000000  ,  0x00010003);
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000050  ,  0x000002D0);   // MM2S_VSIZE
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000028  ,  0x00000000);   // PARK_PTR_REG
//    XAxiVdma_WriteReg(VDMA_BASEADDR, 0x00000000  ,  0x00010001);



    XAxiVdma_WriteReg(VDMA_BASEADDR, MM2S_VDMACR  ,              0x00000004);    // MM2S_VDMACR
    printf("MM2S_VDMACR  = %08X\n\r",Xil_In32( (VDMA_BASEADDR + MM2S_VDMACR)));
    XAxiVdma_WriteReg(VDMA_BASEADDR, MM2S_VDMACR  ,              0x00000001);    // MM2S_VDMACR
    printf("MM2S_VDMACR  = %08X\n\r",Xil_In32( (VDMA_BASEADDR + MM2S_VDMACR)));

    XAxiVdma_WriteReg(VDMA_BASEADDR, MM2S_HSIZE        ,                 VDMA0_MM2S_IMAGE_WIDTH * 4);   // MM2S_HSIZE
    usleep(30000);
    XAxiVdma_WriteReg(VDMA_BASEADDR, MM2S_FRMDLY_STRIDE  ,  VDMA0_MM2S_IMAGE_WIDTH * 4);   // MM2S_FRMDLY_STRIDE
    usleep(30000);
    XAxiVdma_WriteReg(VDMA_BASEADDR, MM2S_START_ADDRESS0  ,  FRAMEBUFFER_PHY1);   // 5c - 98 : MM2S_START_ADDRESS
    usleep(30000);
    XAxiVdma_WriteReg(VDMA_BASEADDR, PARK_PTR_REG  ,  0x00000000);   // PARK_PTR_REG
    printf("PARK_PTR_REG  = %08X\n\r",Xil_In32( (VDMA_BASEADDR + PARK_PTR_REG)));
    usleep(30000);
    XAxiVdma_WriteReg(VDMA_BASEADDR, MM2S_VSIZE  ,  VDMA0_MM2S_IMAGE_HEIGHT);   // MM2S_VSIZE
    usleep(30000);

    printf("MM2S_VDMACR  = %08X\n\r",Xil_In32( (VDMA_BASEADDR + MM2S_VDMACR)));
    printf("MM2S_HSIZE  = %08X\n\r",Xil_In32( VDMA_BASEADDR +  MM2S_HSIZE));
    printf("MM2S_FRMDLY_STRIDE  = %08X\n\r",Xil_In32(  VDMA_BASEADDR + MM2S_FRMDLY_STRIDE));
     printf("MM2S_START_ADDRESS0  = %08X\n\r",Xil_In32(  VDMA_BASEADDR + MM2S_START_ADDRESS0));

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
                Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr +  c  , 0x00FF0000);
        }
        iPixelAddr += stride ;
    }

//    iPixelAddr = 0 ;
//    for(int r=0 ; r < 4; r++){
//        for(int c=0; c < 4*4 ; c+=4)
//        {
////            if(r == 16 || c == 16 || r == heigh -16 || c == width * 4 -16 )
////                Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr + c   , 0x0000FF00);
////            else
//               printf ( "%08X\n\r",Xil_In32(FRAMEBUFFER_VIR1  + iPixelAddr +  c ));
//        }
//        iPixelAddr += stride ;
//    }


    munmap((void *)VDMA_BASEADDR, 0xFFF);
    munmap((void *)VTC_CONFIG_BASEADDR_VIR, 0xFFF);
    munmap((void *)DYNCLK_CONFIG_BASEADDR_VIR, 0xFFF);
    munmap((void*)FRAMEBUFFER_VIR1,FrameSize) ;
    close(fbVbuf);

    cout<< " config done" << endl;

  return 0 ;
}


