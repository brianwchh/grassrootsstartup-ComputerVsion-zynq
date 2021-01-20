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


using namespace cv ;
using namespace std;

static const int HOR = 9;
static const int VERT = 7;

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

#define FrameSize 1280 * 720 * 4 * 6

std::string vdevice0 = "/dev/video0" ;


static u32  FRAMEBUFFER_PHY1,FRAMEBUFFER_PHY2,FRAMEBUFFER_PHY3;  //Physical Address of Vbuf
static char*  FRAMEBUFFER_VIR1 ,*FRAMEBUFFER_VIR2,*FRAMEBUFFER_VIR3;    //Virtual Address of Vbuf

static char*  DYNCLK_CONFIG_BASEADDR_VIR ;
static char*  VTC_CONFIG_BASEADDR_VIR ;


#define  disparity_size_   64
#define PENALTY1 10
#define PENALTY2  60



static void Xil_Out32(char * OutAddress, u32 Value)
{
    *(u32 *)OutAddress = Value;
}

static u32 Xil_In32(char* Addr)
{
    return *(u32* ) Addr;
}



/************************ stereo  part ******************************************/


void census_cpu(uchar* d_source, uint64_t* d_dest, int width, int height)
{
    int r,c;
    int i,j;
    for(r = 0 ; r < height; r++)
        for(c = 0 ; c < width ; c++)
        {
            uint64_t   value = 1 ;

            int CenP = r * width + c ;
            int  cenVal = d_source[CenP];
            for(i = - VERT/2; i <= VERT/2  ; i++)
                for(j = - HOR/2; j <= HOR/2  ; j++ )   // indexing from top left to bottom right
                {
                    if(i == 0 && j==0)  // do not compare to itself
                        continue ;

                    uint64_t  temp = 0 ;
                    int SorroundingPix_X  =  c  +  j ;
                    int SorroundingPix_Y  =  r  +  i ;
                    int  sorroundingPoint = SorroundingPix_Y * width + SorroundingPix_X ;
                    int    sorroundingPix_Value  = 0 ;
                    if(SorroundingPix_X >= 0 && SorroundingPix_X < width  &&  SorroundingPix_Y >=0  &&  SorroundingPix_Y < height){
                        sorroundingPix_Value = d_source[sorroundingPoint] ;
                    }

                    if(cenVal > sorroundingPix_Value)
                    {
                        temp = 0x4000000000000000;
                    }

                    value = value | (0x4000000000000000 & temp) ;
                   value = value >>1 ;

//                    printf("central value =  %d ,   neighbor value = %d  temp  = %lx  value =  %016lx \n ", cenVal, sorroundingPix_Value,temp, value);

                }
//            printf("........ ................  0x%016lx\n", value );

            d_dest[CenP] = value ;
        }

        std::cout << "********************************************" <<std::endl ;
        for(int i = - VERT/2; i <= VERT/2  ; i++)
        {
            for(int j = - HOR/2; j <= HOR/2  ; j++ )   // indexing from top left to bottom right
            {

                int temp = 0 ;
                int SorroundingPix_X  =  100  +  j ;
                int SorroundingPix_Y  =   100 +  i ;
                int  sorroundingPoint = SorroundingPix_Y * width + SorroundingPix_X ;
                uchar    sorroundingPix_Value  = 0 ;
                if(SorroundingPix_X >= 0 && SorroundingPix_X < width && SorroundingPix_Y >=0 && SorroundingPix_Y < height){
                    sorroundingPix_Value =  d_source[sorroundingPoint] ;
//                    printf("%d ",sorroundingPix_Value) ;
                }
            }
//            std::cout << std::endl ;
         }
//        std::cout << "********************************************" <<std::endl ;
//        printf("........ ................  0x%016lx\n",d_dest[100* width + 100]) ;
}


void matchingCost_cpu(const uint64_t* h_left, const uint64_t* h_right, uint8_t* h_matching_cost, int width, int height)
{
        for(int r=0; r < height; r++)
            for(int c=0; c<width; c++)
            {
                int ptr = r * width + c ;
                uint64_t baseVal = h_left[ptr];
                //for each pixel in the left image,  compare to 64  candidates in the right image
                for(int i= 0; i< disparity_size_ ; i++)
                {
                   int destPtr = r *(width * disparity_size_) +  c * disparity_size_  +  i  ;
                   if(c - i < 0 ){     //compared element is  out of bounds
                        h_matching_cost[destPtr] = 62 ;
                   }
                   else {
                        uint64_t comparedVal = h_right[ptr - i] ;
                        uint64_t  xor_result = baseVal ^ comparedVal ;
                        uint64_t  pattern = 0x01 ;
                        uint8_t bit1count = 0 ;
                        for(int k=0; k< 64;k++)   // counting # of 1s
                        {
                            if(xor_result & pattern ){
                                bit1count ++ ;
                            }
                            xor_result = xor_result >> 1 ;
                        }
                        h_matching_cost[destPtr] = bit1count  ;
                    }
                 }
            }
}



uint16_t  calMin(uint16_t  a, uint16_t b)
{
    if(a > b )
        return b ;
    else
        return a ;
}


void scan_scost_cpu(const uint8_t* d_matching_cost, uint16_t* d_scost, int width, int height)
{
    uint16_t*    left_scan            = new uint16_t[width * height * disparity_size_];
    uint16_t*    right_scan           = new uint16_t[width * height * disparity_size_];
    uint16_t*    top_scan             = new uint16_t[width * height * disparity_size_];
    uint16_t*    bottom_scan          = new uint16_t[width * height * disparity_size_];
    uint16_t*    topleft_scan         = new uint16_t[width * height * disparity_size_];
    uint16_t*    bottomleft_scan      = new uint16_t[width * height * disparity_size_];
    uint16_t*    topright_scan        = new uint16_t[width * height * disparity_size_];
    uint16_t*    bottomright_scan     = new uint16_t[width * height * disparity_size_];

     uint16_t minPre = 0;
     uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

     //*****************************  left scan **************************************

      for(int r=0; r<height; r++)
          for(int c=0; c<width; c++)
          {
              int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
              if(c == 0)              // ------------------- first column points ---------------------------------------------------
              {
                  for(int d=0; d< disparity_size_; d++)
                  {
                      left_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                      if(d == 0)
                          minPre = left_scan[volPtr + d ];
                      else {
                          if( left_scan[volPtr + d ]  < minPre)
                               minPre = left_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                      }
                  }
              }
              else                // ----------------------------------------------------------------------------------------------
              {
                      int volPtrPre = r * width * disparity_size_ + (c -1)* disparity_size_ ;
                      uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                      uint16_t  currentMin = 0;

                      for(int d=0; d< disparity_size_; d++ )
                      {
                          if((d - 1)>=0) {
                             Lpr_minus1_DiMinus1  =  left_scan[volPtrPre + d -1];
                          }
                          else {
                              Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                          }

                          if((d + 1) < disparity_size_) {
                             Lpr_minus1_DiPlus1  =  left_scan[volPtrPre + d +1];
                          }
                          else {
                              Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                          }

                          Lpr_minus1_DiPlus0  = left_scan[volPtrPre + d ]    ;

                          uint16_t tmp  = 0 ;
                          if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                          {
                              tmp = minPre + PENALTY2;
                              tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                              tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                              tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                              tmp = tmp - minPre ;
                          }
                          else    // minPre is among  D+/- 1
                          {
                              tmp =  Lpr_minus1_DiPlus0 ;
                              tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                              tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                              tmp = tmp - minPre ;
                          }

                          if(tmp > PENALTY2)
                          {
                              cout << "tmp > PENALTY2   = " << tmp <<endl;
                          }

                          uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                          left_scan[volPtr + d ] =  tValue ;

                          if(tValue > 255)
                          {
                              cout<< "tValue > FF   = " << tValue << "     d_matching_cost[volPtr + d]      " << (uint16_t)d_matching_cost[volPtr + d]  <<  endl;
                          }

                          if(d==0)
                          {
                              currentMin = tValue ;
                          }
                          else if (currentMin > tValue)     // find current min
                          {
                              currentMin = tValue ;
                          }
                      }

                      minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
              }
          }


      //*****************************  top scan **************************************
      for(int c=0; c<width; c++)
          for(int r=0; r<height; r++)
          {
              int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
              if(r == 0)              // ------------------- first column points ---------------------------------------------------
              {
                  for(int d=0; d< disparity_size_; d++)
                  {
                      top_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                      if(d == 0)
                          minPre = top_scan[volPtr + d ];
                      else {
                          if( top_scan[volPtr + d ]  < minPre)
                               minPre = top_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                      }
                  }
              }
              else                // ----------------------------------------------------------------------------------------------
              {
                      int volPtrPre = (r-1) * width * disparity_size_ + (c )* disparity_size_ ;
                      uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                      uint16_t  currentMin = 0;

                      for(int d=0; d< disparity_size_; d++ )
                      {

                          if((d - 1)>=0) {
                             Lpr_minus1_DiMinus1  =  top_scan[volPtrPre + d -1];
                          }
                          else {
                              Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                          }

                          if((d + 1) < disparity_size_) {
                             Lpr_minus1_DiPlus1  =  top_scan[volPtrPre + d +1];
                          }
                          else {
                              Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                          }

                          Lpr_minus1_DiPlus0  = top_scan[volPtrPre + d ]    ;

                          uint16_t tmp  = 0 ;
                          if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                          {
                              tmp = minPre + PENALTY2;
                              tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                              tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                              tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                              tmp = tmp - minPre ;
                          }
                          else    // minPre is amount  D+/- 1
                          {
                              tmp =  Lpr_minus1_DiPlus0 ;
                              tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                              tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                              tmp = tmp - minPre ;
                          }

                          uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                          top_scan[volPtr + d ] =  tValue ;

                          if(d==0)
                          {
                              currentMin = tValue ;
                          }
                          else if (currentMin > tValue)     // find current min
                          {
                              currentMin = tValue ;
                          }
                      }

                      minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
              }
          }


      //*****************************  topright scan **************************************
      for(int c=width-1 ; c >=0; c--)   // along first row
          {
                  // construct a line search path
 //                    for(int col = c ,  r=0; col < width, r < height ; col++ , r++)
                  int col = c ;
                  int r = 0 ;
                  while(1)
                  {

                          if(col == 0 || r == height )   // line hit the bottom or left boundery
                          {
                              break ;
                          }

                          int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                          if(r == 0 || col == width-1)              // ------------------- first row points ---------------------------------------------------
                          {
                              for(int d=0; d< disparity_size_; d++)
                              {
                                  topright_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                  if(d == 0)
                                      minPre = topright_scan[volPtr + d ];
                                  else {
                                      if( topright_scan[volPtr + d ]  < minPre)
                                           minPre = topright_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                  }
                              }
                          }
                          else                // ----------------------------------------------------------------------------------------------
                          {
                                  int volPtrPre = (r-1) * width * disparity_size_ + (col + 1 )* disparity_size_ ;
                                  uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                  uint16_t  currentMin = 0;

                                  for(int d=0; d< disparity_size_; d++ )
                                  {

                                      if((d - 1)>=0) {
                                         Lpr_minus1_DiMinus1  =  topright_scan[volPtrPre + d -1];
                                      }
                                      else {
                                          Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                                      }

                                      if((d + 1) < disparity_size_) {
                                         Lpr_minus1_DiPlus1  =  topright_scan[volPtrPre + d +1];
                                      }
                                      else {
                                          Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                      }

                                      Lpr_minus1_DiPlus0  = topright_scan[volPtrPre + d ]    ;

                                      uint16_t tmp  = 0 ;
                                      if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                      {
                                          tmp = minPre + PENALTY2;
                                          tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                          tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                          tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                          tmp = tmp - minPre ;
                                      }
                                      else    // minPre is amount  D+/- 1
                                      {
                                          tmp =  Lpr_minus1_DiPlus0 ;
                                          tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                          tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                          tmp = tmp - minPre ;
                                      }

                                      uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                      topright_scan[volPtr + d ] =  tValue ;

                                      if(d==0)
                                      {
                                          currentMin = tValue ;
                                      }
                                      else if (currentMin > tValue)     // find current min
                                      {
                                          currentMin = tValue ;
                                      }
                                  }

                                  minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                          }


                          col -- ;
                          r++;

              }
          }


#if 0

     /****************************  right scan  *******************************************/

     for(int r=0; r<height; r++)
         for(int c=width-1; c>=0; c--)
         {
             int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
             if(c == width-1)              // ------------------- first column points ---------------------------------------------------
             {
                 for(int d=0; d< disparity_size_; d++)
                 {
                     right_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                     if(d == 0)
                         minPre = right_scan[volPtr + d ];
                     else {
                         if( right_scan[volPtr + d ]  < minPre)
                              minPre = right_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                     }
                 }
             }
             else                // ----------------------------------------------------------------------------------------------
             {
                     int volPtrPre = r * width * disparity_size_ + (c + 1)* disparity_size_ ;
                     uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                     uint16_t  currentMin = 0;

                     for(int d=0; d< disparity_size_; d++ )
                     {

                         if((d - 1)>=0) {
                            Lpr_minus1_DiMinus1  =  right_scan[volPtrPre + d -1];
                         }
                         else {
                             Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                         }

                         if((d + 1) < disparity_size_) {
                            Lpr_minus1_DiPlus1  =  right_scan[volPtrPre + d +1];
                         }
                         else {
                             Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                         }

                         Lpr_minus1_DiPlus0  = right_scan[volPtrPre + d ]    ;

                         uint16_t tmp  = 0 ;
                         if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                         {
                             tmp = minPre + PENALTY2;
                             tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                             tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                             tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                             tmp = tmp - minPre ;
                         }
                         else    // minPre is amount  D+/- 1
                         {
                             tmp =  Lpr_minus1_DiPlus0 ;
                             tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                             tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                             tmp = tmp - minPre ;
                         }

                         uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                         right_scan[volPtr + d ] =  tValue ;

                         if(d==0)
                         {
                             currentMin = tValue ;
                         }
                         else if (currentMin > tValue)     // find current min
                         {
                             currentMin = tValue ;
                         }
                     }

                     minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
             }
         }




     //*****************************  bottom scan **************************************
     for(int c=0; c<width; c++)
         for(int r=height-1; r>=0; r--)
         {
             int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
             if(r == height-1)              // ------------------- first column points ---------------------------------------------------
             {
                 for(int d=0; d< disparity_size_; d++)
                 {
                     bottom_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                     if(d == 0)
                         minPre = bottom_scan[volPtr + d ];
                     else {
                         if( bottom_scan[volPtr + d ]  < minPre)
                              minPre = bottom_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                     }
                 }
             }
             else                // ----------------------------------------------------------------------------------------------
             {
                     int volPtrPre = (r+1) * width * disparity_size_ + (c )* disparity_size_ ;
                     uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                     uint16_t  currentMin = 0;

                     for(int d=0; d< disparity_size_; d++ )
                     {

                         if((d - 1)>=0) {
                            Lpr_minus1_DiMinus1  =  bottom_scan[volPtrPre + d -1];
                         }
                         else {
                             Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                         }

                         if((d + 1) < disparity_size_) {
                            Lpr_minus1_DiPlus1  =  bottom_scan[volPtrPre + d +1];
                         }
                         else {
                             Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                         }

                         Lpr_minus1_DiPlus0  = bottom_scan[volPtrPre + d ]    ;

                         uint16_t tmp  = 0 ;
                         if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                         {
                             tmp = minPre + PENALTY2;
                             tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                             tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                             tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                             tmp = tmp - minPre ;
                         }
                         else    // minPre is amount  D+/- 1
                         {
                             tmp =  Lpr_minus1_DiPlus0 ;
                             tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                             tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                             tmp = tmp - minPre ;
                         }

                         uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                         bottom_scan[volPtr + d ] =  tValue ;

                         if(d==0)
                         {
                             currentMin = tValue ;
                         }
                         else if (currentMin > tValue)     // find current min
                         {
                             currentMin = tValue ;
                         }
                     }

                     minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
             }
         }


     //*****************************  topleft scan **************************************
     for(int c=0; c<width; c++)   // along first row
         {
                 // construct a line search path
//                    for(int col = c ,  r=0; col < width, r < height ; col++ , r++)
                 int col = c ;
                 int r = 0 ;
                 while(1)
                 {

                         if(col == width || r == height )   // line hit the bottom or left boundery
                         {
                             break ;
                         }

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == 0 || col == 0)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 topleft_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = topleft_scan[volPtr + d ];
                                 else {
                                     if( topleft_scan[volPtr + d ]  < minPre)
                                          minPre = topleft_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r-1) * width * disparity_size_ + (col -1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  topleft_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  topleft_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = topleft_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     topleft_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }


                         col ++ ;
                         r++;

             }
         }

     for(int rr=1; rr<height; rr++)       // allong first colomn
         {
                 // construct a line search path
//                    for(int col = 0 , r=rr; col < width, r < height ; col++ , r++)
                 int col = 0 ;
                 int r = rr ;

                 while(1)
                 {
                     if(col == width || r == height )   // line hit the bottom or left boundery
                     {
                         break ;
                     }

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == 0 || col == 0)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 topleft_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = topleft_scan[volPtr + d ];
                                 else {
                                     if( topleft_scan[volPtr + d ]  < minPre)
                                          minPre = topleft_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r-1) * width * disparity_size_ + (col -1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  topleft_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum (be careful of overflow)
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  topleft_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = topleft_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);     // be careful , do not overflow
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     topleft_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }


                         r++ ;
                         col++;

             }
         }


     //*****************************  topright scan **************************************
     for(int c=width-1 ; c >=0; c--)   // along first row
         {
                 // construct a line search path
//                    for(int col = c ,  r=0; col < width, r < height ; col++ , r++)
                 int col = c ;
                 int r = 0 ;
                 while(1)
                 {

                         if(col == 0 || r == height )   // line hit the bottom or left boundery
                         {
                             break ;
                         }

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == 0 || col == width-1)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 topright_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = topright_scan[volPtr + d ];
                                 else {
                                     if( topright_scan[volPtr + d ]  < minPre)
                                          minPre = topright_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r-1) * width * disparity_size_ + (col + 1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  topright_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  topright_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = topright_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     topright_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }


                         col -- ;
                         r++;

             }
         }

     for(int rr=1; rr<height; rr++)       // allong first colomn
         {
                 // construct a line search path
//                    for(int col = 0 , r=rr; col < width, r < height ; col++ , r++)
                 int col = 0 ;
                 int r = rr ;

                 while(1)
                 {
                     if(col == 0 || r == height )   // line hit the bottom or left boundery
                     {
                         break ;
                     }

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == 0 || col == 0)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 topright_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = topright_scan[volPtr + d ];
                                 else {
                                     if( topright_scan[volPtr + d ]  < minPre)
                                          minPre = topright_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r-1) * width * disparity_size_ + (col -1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  topright_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum (be careful of overflow)
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  topright_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = topright_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);     // be careful , do not overflow
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     topright_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }


                         r++ ;
                         col--;

             }
         }




     //*****************************  bottomleft scan **************************************
     for(int c= 0  ; c < width; c++)   // along first row
         {
                 // construct a line search path
//                    for(int col = c ,  r=0; col < width, r < height ; col++ , r++)
                 int col = c ;
                 int r = height-1 ;
                 while(1)
                 {

                         if(col == width || r == 0 )   // line hit the bottom or left boundery
                         {
                             break ;
                         }

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == height-1 || col == 0)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 bottomleft_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = bottomleft_scan[volPtr + d ];
                                 else {
                                     if( bottomleft_scan[volPtr + d ]  < minPre)
                                          minPre = bottomleft_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r + 1) * width * disparity_size_ + (col - 1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  bottomleft_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  bottomleft_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = bottomleft_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     bottomleft_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }


                         col ++ ;
                         r--;

             }
         }

     for(int rr= height -2 ; rr >=0 ; rr--)       // allong first colomn
         {
                 // construct a line search path
//                    for(int col = 0 , r=rr; col < width, r < height ; col++ , r++)
                 int col = 0 ;
                 int r = rr ;

                 while(1)
                 {
                     if(col == width  || r == 0 )   // line hit the bottom or left boundery
                     {
                         break ;
                     }

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == height-1 || col == 0)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 bottomleft_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = bottomleft_scan[volPtr + d ];
                                 else {
                                     if( bottomleft_scan[volPtr + d ]  < minPre)
                                          minPre = bottomleft_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r+1) * width * disparity_size_ + (col - 1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  bottomleft_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum (be careful of overflow)
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  bottomleft_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = bottomleft_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);     // be careful , do not overflow
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     bottomleft_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }

                         r-- ;
                         col++;

             }
         }


     //*****************************  bottomright scan **************************************
     for(int c= width -1   ; c  >= 0; c--)   // along first row
         {
                 // construct a line search path
//                    for(int col = c ,  r=0; col < width, r < height ; col++ , r++)
                 int col = c ;
                 int r = height - 1 ;
                 while(1)
                 {

                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == height-1 || col == width-1)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 bottomright_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = bottomright_scan[volPtr + d ];
                                 else {
                                     if( bottomright_scan[volPtr + d ]  < minPre)
                                          minPre = bottomright_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r + 1) * width * disparity_size_ + (col + 1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  bottomright_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  bottomright_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = bottomright_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     bottomright_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }

                         if(col == 0 || r == 0 )   // line hit the bottom or left boundery
                         {
                             break ;
                         }

                         col -- ;
                         r--;

             }
         }

     for(int rr= height -2 ; rr >=0 ; rr--)       // allong first colomn
         {
                 // construct a line search path
//                    for(int col = 0 , r=rr; col < width, r < height ; col++ , r++)
                 int col = 0 ;
                 int r = rr ;

                 while(1)
                 {
                         int volPtr = r * width * disparity_size_ + col * disparity_size_ ;
                         if(r == 0 || col == 0)              // ------------------- first row points ---------------------------------------------------
                         {
                             for(int d=0; d< disparity_size_; d++)
                             {
                                 bottomright_scan[volPtr + d ] = (uint16_t)d_matching_cost[volPtr + d] ;
                                 if(d == 0)
                                     minPre = bottomright_scan[volPtr + d ];
                                 else {
                                     if( bottomright_scan[volPtr + d ]  < minPre)
                                          minPre = bottomright_scan[volPtr + d ] ;       // find the minimum  L(Pr-1,Di)
                                 }
                             }
                         }
                         else                // ----------------------------------------------------------------------------------------------
                         {
                                 int volPtrPre = (r+1) * width * disparity_size_ + (col+1 )* disparity_size_ ;
                                 uint16_t  Lpr_minus1_DiMinus1 , Lpr_minus1_DiPlus1, Lpr_minus1_DiPlus0 ;

                                 uint16_t  currentMin = 0;

                                 for(int d=0; d< disparity_size_; d++ )
                                 {

                                     if((d - 1)>=0) {
                                        Lpr_minus1_DiMinus1  =  bottomright_scan[volPtrPre + d -1];
                                     }
                                     else {
                                         Lpr_minus1_DiMinus1 = 0xFF00 ;   //  if d=0 , set this value to be maxmum (be careful of overflow)
                                     }

                                     if((d + 1) < disparity_size_) {
                                        Lpr_minus1_DiPlus1  =  bottomright_scan[volPtrPre + d +1];
                                     }
                                     else {
                                         Lpr_minus1_DiPlus1 = 0xFF00 ;   //  if d = D-1 , set this value to be maxmum
                                     }

                                     Lpr_minus1_DiPlus0  = bottomright_scan[volPtrPre + d ]    ;

                                     uint16_t tmp  = 0 ;
                                     if(Lpr_minus1_DiPlus0 > minPre  ||  Lpr_minus1_DiPlus1 > minPre ||   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
                                     {
                                         tmp = minPre + PENALTY2;
                                         tmp = calMin(tmp, Lpr_minus1_DiPlus0);
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);     // be careful , do not overflow
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }
                                     else    // minPre is amount  D+/- 1
                                     {
                                         tmp =  Lpr_minus1_DiPlus0 ;
                                         tmp = calMin(tmp , Lpr_minus1_DiMinus1 + PENALTY1);
                                         tmp = calMin(tmp,Lpr_minus1_DiPlus1 + PENALTY1);
                                         tmp = tmp - minPre ;
                                     }

                                     uint16_t   tValue =  (uint16_t)d_matching_cost[volPtr + d]  + tmp ;   // Lr(P,Di) = C(P,Di) + min(...........) - min(......)
                                     bottomright_scan[volPtr + d ] =  tValue ;

                                     if(d==0)
                                     {
                                         currentMin = tValue ;
                                     }
                                     else if (currentMin > tValue)     // find current min
                                     {
                                         currentMin = tValue ;
                                     }
                                 }

                                 minPre = currentMin ;    // set current min as the prevous min for next pixel caculation
                         }


                     if(col == 0 || r == 0 )   // line hit the bottom or left boundery
                     {
                         break ;
                     }

                         r-- ;
                         col--;

             }
         }

#endif

        // depth wise add
        for( int r = 0 ; r < height ; r++)
            for(int c=0; c< width ; c++)
            {
                    int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
                    for(int d=0; d< disparity_size_; d++)
                    {
                        d_scost[volPtr + d ] =  left_scan[volPtr + d]  +  right_scan[volPtr + d] + top_scan[volPtr + d]  +  bottom_scan[volPtr + d]  + topleft_scan[volPtr + d] + topright_scan[volPtr + d] + bottomleft_scan[volPtr+d] + bottomright_scan[volPtr+d];
                    }
            }


        delete[]    left_scan         ;
        delete[]    right_scan        ;
        delete[]    top_scan          ;
        delete[]    bottom_scan       ;
        delete[]    topleft_scan      ;
        delete[]    bottomleft_scan   ;
        delete[]    topright_scan     ;
        delete[]    bottomright_scan  ;


}

void winner_takes_all_cpu(uint16_t* leftDisp, uint16_t* rightDisp, const uint16_t* __restrict__ h_cost, int width, int height){

    uint16_t*    right_cost            = new uint16_t[width * height * disparity_size_];
    //1.  given left disparity  volumn , derive the theoreticl right right disparity volumn
    for(int r=0; r<height; r++)
        for(int c=0; c<width; c++)
        {
            int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
            for(int d=0; d< disparity_size_; d++)
            {
                uint16_t  diagVal = 0 ;
                if(c+d>width)
                {
                    diagVal = 0xFFFF ;   // maxmum , don't not add anything to it, otherwise it will overflow
                    right_cost[volPtr + d] = diagVal ;
                }
                else
                {
                    int diag_ptr =  r * width * disparity_size_ + (c+d) * disparity_size_  + d;
                    right_cost[volPtr + d] =  h_cost[diag_ptr] ;
                }
            }
        }

    //2.  calculate the minimum Lr(P,Di) for left and right disparity using winner takes all method
    for(int r=0; r<height; r++)
        for(int c=0; c<width; c++)
        {
            int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
            uint16_t  left_min = 0 ;
            uint16_t right_min = 0 ;
            uint16_t  leftMinIndex, rightMinIndex;
            for(int d=0; d< disparity_size_; d++)
            {
                if(d==0)
                {
                    left_min = h_cost[volPtr + d] ;
                    right_min = right_cost[volPtr + d] ;
                    leftMinIndex =(uint16_t) d ;
                    rightMinIndex= (uint16_t) d ;
                }
                else
                {
                    if(left_min > h_cost[volPtr + d]){
                        left_min = h_cost[volPtr + d];
                        leftMinIndex =(uint16_t) d ;
                    }

                    if(right_min > right_cost[volPtr + d]){
                        right_min = right_cost[volPtr + d];
                        rightMinIndex= (uint16_t) d ;
                    }
                }
            }

            leftDisp[r*width + c]  = leftMinIndex ;
            rightDisp[r*width + c]  = rightMinIndex ;

        }


    delete[]  right_cost ;
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


void check_consistency_cpu(const uint16_t* d_leftDisp, const uint16_t* d_rightDisp, uint8_t*  disparity ,   int width, int height)
{
        for(int r=0; r < height; r++)
            for(int c=0; c<width; c++)
            {
                uint16_t  d_left   = d_leftDisp[r*width+c];
                uint16_t  d_right = d_rightDisp[r*width+c - d_left] ;
                if(abs(d_left - d_right) > 1)   // left and right unconsistent
                {
                    disparity[r*width+c] = 0 ;  // infinite distance
                }
                else
                {
                    disparity[r*width+c] = (uint8_t) d_leftDisp[r*width+c];
                }
            }
}


/******************************************************************************************/




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
    ioctl(fbVbuf, MEMDEV_IOCGETPYADDRESS , &FRAMEBUFFER_PHY1);
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


    // stereo variables

    cv::Mat left = imread("left1.png",0);
    cv::Mat right = imread("right1.png",0);

//    cv::Mat left(480,640,CV_8UC1);
//    cv::Mat right(480,640,CV_8UC1);

//    cv::cvtColor(left_rgb,left,CV_BGR2GRAY) ;
//    cv::cvtColor(right_rgb,right,CV_BGR2GRAY) ;

    uint64_t*  CT_left   = new uint64_t[left.cols * left.rows] ;
    uint64_t*  CT_right = new uint64_t[left.cols * left.rows] ;

    uint8_t*    H_matching_cost = new uint8_t[left.cols * left.rows* disparity_size_];
    uint16_t*    H_scan_cost              = new uint16_t[left.cols * left.rows* disparity_size_];

    uint16_t*    leftDisp                = new uint16_t[left.cols * left.rows];
    uint16_t*    rightDisp              = new uint16_t[left.cols * left.rows];

    uint16_t*    leftDisp_filtered              = new uint16_t[left.cols * left.rows];
    uint16_t*    rightDisp_filtered              = new uint16_t[left.cols * left.rows];

    uint8_t*       disparity  = new uint8_t[left.cols * left.rows];



              // write original image data to frame buffer  1280 * 480
                iPixelAddr = 0 ;
                for(int r=0; r< left.rows ; r++)
                {
                    for(int c=0; c<left.cols * 2; c++)
                    {
                        u32 data_l = left.at<uchar>(r,c);
                        u32 data_r = right.at<uchar>(r,c);
                        u32 data_l_w= 0;
                        data_l_w = data_l_w | ( (data_l << 16)&0x00FF0000) | ( (data_l << 8)&0x0000FF00) | ( (data_l << 0)&0x000000FF) ;
                        u32 data_r_w = 0 ;
                        data_r_w   |= ( (data_r << 16)&0x00FF0000) | ( (data_r << 8)&0x0000FF00) | ( (data_r << 0)&0x000000FF) ;
                          if(c < left.cols)  // left
                              Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr +  c * 4  , data_l_w);
                          else
                              Xil_Out32(FRAMEBUFFER_VIR1 + iPixelAddr +  c * 4  , data_r_w);
                    }
                    iPixelAddr +=  stride ;
                }


                  // start stereo processing slow version
                  census_cpu(left.data,CT_left,left.cols,left.rows);
                  census_cpu(right.data,CT_right,left.cols,left.rows);

                  matchingCost_cpu(CT_left,CT_right,H_matching_cost,left.cols,left.rows);

                  delete[] CT_left ;
                  delete[] CT_right ;

                  scan_scost_cpu(H_matching_cost,H_scan_cost,left.cols,left.rows) ;

                  delete[] H_matching_cost ;

                  winner_takes_all_cpu(leftDisp,  rightDisp, H_scan_cost, left.cols,left.rows);

                   delete[] H_scan_cost ;


                  median_filter(leftDisp,leftDisp_filtered, left.cols,left.rows);
                  median_filter(rightDisp,rightDisp_filtered, left.cols,left.rows);


                  check_consistency_cpu(leftDisp_filtered, rightDisp_filtered, disparity ,   left.cols, left.rows);

                  delete[] leftDisp ;
                  delete[] rightDisp ;

                  delete[] leftDisp_filtered ;
                  delete[] rightDisp_filtered ;

                  cv::Mat disparity_cpu(cv::Size(left.cols, left.rows), CV_8UC1);
                  disparity_cpu.data = disparity ;

                  // write disparity to frame buffer
                  iPixelAddr = 0 ;
                for(int r=0; r< left.rows ; r++)
                {
                    for(int c=left.cols ; c<left.cols * 2; c++)
                    {
                        uchar dispVal = disparity_cpu.at<uchar>(r,c);

                         // write to right side
                              Xil_Out32(FRAMEBUFFER_VIR1  + iPixelAddr +  c * 4  , dispVal);
                    }
                    iPixelAddr += stride ;
                }

                // write original image data to frame buffer  1280 * 480
                  iPixelAddr = 0 ;
                  for(int r=0; r< left.rows ; r++)
                  {
                      for(int c=left.cols; c<left.cols * 2; c++)
                      {
                          u32 data_r = disparity_cpu.at<uchar>(r,c) << 2;
                          u32 data_r_w= 0;
                          data_r_w   |= ( (data_r << 16)&0x00FF0000) | ( (data_r << 8)&0x0000FF00) | ( (data_r << 0)&0x000000FF) ;
                          Xil_Out32(FRAMEBUFFER_VIR1 + iPixelAddr +  c * 4  , data_r_w);
                      }
                      iPixelAddr +=  stride ;
                  }



              imwrite("savedImage.png",disparity_cpu ) ;



    // ----------------------------------------------------------------------------

    munmap((void*)FRAMEBUFFER_VIR1,FrameSize) ;
    close(fbVbuf);

    cout<< "slow  stereo process done" << endl;

  return 0 ;
}


