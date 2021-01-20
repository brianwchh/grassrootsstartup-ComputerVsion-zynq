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

#include <stdlib.h>
#include <iostream>
#include <sstream> // for converting the command line parameter to integer
#include <string>

#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/contrib/contrib.hpp>


#include "stdio.h"
#include <unistd.h>


#define MAX_SHORT std::numeric_limits<unsigned short>::max()
#define MAX_UCHART std::numeric_limits<unsigned char>::max()

#define  disparity_size_   64
#define PENALTY1 10
#define PENALTY2  60


using namespace cv ;
using namespace std;

static const int HOR = 9;
static const int VERT = 7;

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

//        std::cout << "********************************************" <<std::endl ;
//        for(int i = - VERT/2; i <= VERT/2  ; i++)
//        {
//            for(int j = - HOR/2; j <= HOR/2  ; j++ )   // indexing from top left to bottom right
//            {

//                int temp = 0 ;
//                int SorroundingPix_X  =  100  +  j ;
//                int SorroundingPix_Y  =   100 +  i ;
//                int  sorroundingPoint = SorroundingPix_Y * width + SorroundingPix_X ;
//                uchar    sorroundingPix_Value  = 0 ;
//                if(SorroundingPix_X >= 0 && SorroundingPix_X < width && SorroundingPix_Y >=0 && SorroundingPix_Y < height){
//                    sorroundingPix_Value =  d_source[sorroundingPoint] ;
//                    printf("%d ",sorroundingPix_Value) ;
//                }
//            }
//            std::cout << std::endl ;
//         }
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


        // depth wise add
        for( int r = 0 ; r < height ; r++)
            for(int c=0; c< width ; c++)
            {
                    int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
                    for(int d=0; d< disparity_size_; d++)
                    {
//                        d_scost[volPtr + d ] =  left_scan[volPtr + d]  +  right_scan[volPtr + d] + top_scan[volPtr + d]  +  bottom_scan[volPtr + d]  + topleft_scan[volPtr + d] + topright_scan[volPtr + d] + bottomleft_scan[volPtr+d] + bottomright_scan[volPtr+d];
                        d_scost[volPtr + d ] =  left_scan[volPtr + d]  +   top_scan[volPtr + d]    + topleft_scan[volPtr + d] + topright_scan[volPtr + d]  ;

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
                    diagVal = 0xFFFF ;   // maxmum , don't  add anything to it, otherwise it will overflow
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


uint32_t  circularShift(uint32_t  input_data)
{
    uint32_t tmp_data ;
    uint32_t shift_reg=0 ;

    tmp_data = input_data & 0x00000001 ;
    shift_reg |= tmp_data ;   // shift input_data's lsb to shift_reg's lsb
    for(int i=1; i<32;i++)
    {
        shift_reg = shift_reg << 1 ;  // shift  lsb to left by 1 bit, and ready to accept another bit
        input_data = input_data >> 1 ;  // ready to shift the next bit to shift_reg
        tmp_data = input_data & 0x00000001 ;
        shift_reg |= tmp_data ;   // shift input_data's lsb to shift_reg's lsb
    }

    return shift_reg ;
}


Mat remapx1 ;
Mat remapy1 ;
Mat remapx2 ;
Mat remapy2 ;


void my_remap(Mat& oriImg , Mat& remapImg , Mat& remapX, Mat& remapY  )
{
    printf("x_float = %f\n", remapX.at<float>(0,0)) ;

    for(int r = 0 ; r< oriImg.rows; r++)
        for(int c=0; c<oriImg.cols; c++)
        {
            float x_float =(float) remapX.at<float>(r,c) ;
            float y_float =(float) remapY.at<float>(r,c) ;

//            if (abs(r - y_float)  > 6 || abs(c - x_float) > 6)
//            {
//                cout << " distortion too big " << endl ;
//                cout << "r =  "  << r << "    c =  " << c ;
//                cout << " diff_y = " << (int)abs(r-y_float) << "    diff_x = " << (int)abs(c - x_float) << endl ;
////                return  ;
//            }

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

            if((x_int < 0 || x_int > oriImg.cols-1) || (y_int < 0 || y_int > oriImg.rows-1)  ||  abs(x_int - c) > 8  || abs(y_int - r) > 8 )
            {
                I_r_c = 0.0f ;
            }
            else {
                        int I_x_y      =  oriImg.at<uchar>(y_int, x_int) ;
                        int I_x1_y    = oriImg.at<uchar>(y_int, x_int+1) ;
                        int I_x_y1    = oriImg.at<uchar>(y_int+1, x_int) ;
                        int I_x1_y1 = oriImg.at<uchar>(y_int+1, x_int+1) ;

                        int top2Sum = (int) ( I_x_y * du + I_x1_y * (1.0-du) ) ;
                        int bottom2Sum = (int) ( I_x_y1 * du + I_x1_y1*(1.0-du) ) ;

                        I_r_c =   top2Sum * dv  + bottom2Sum * (1.0-dv)  ;
            }

            remapImg.at<uchar>(r,c) = (uchar) I_r_c ;

        }
}

#define   ROW_N  360
#define   COL_N    640

int main(int argc, char* argv[]) {
	if (argc < 3) {
        std::cerr << "usage: stereo_cpu left_img right_img " << std::endl;
		std::exit(EXIT_FAILURE);
	}

    cv::Mat left_col = cv::imread(argv[1],1);
    cv::Mat right_col = cv::imread(argv[2],1);

    Mat left_in ;
    Mat right_in ;

    cvtColor(left_col,left_in,CV_RGB2GRAY);
    cvtColor(right_col,right_in,CV_RGB2GRAY);

    Mat left(left_in.rows,left_in.cols,CV_8UC1) ;
    Mat right(left_in.rows,left_in.cols,CV_8UC1) ;

    FileStorage f_remapx1("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapx1.xml", FileStorage::READ);
    FileStorage f_remapy1("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapy1.xml", FileStorage::READ);
    FileStorage f_remapx2("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapx2.xml", FileStorage::READ);
    FileStorage f_remapy2("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapy2.xml", FileStorage::READ);

//    FileStorage f_remapx1("./parameters/remapx1.xml", FileStorage::READ);
//    FileStorage f_remapy1("./parameters/remapy1.xml", FileStorage::READ);
//    FileStorage f_remapx2("./parameters/remapx2.xml", FileStorage::READ);
//    FileStorage f_remapy2("./parameters/remapy2.xml", FileStorage::READ);

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


    remap(left_in,   left   , remapx1, remapy1,CV_INTER_LINEAR);
    remap(right_in, right, remapx2, remapy2,CV_INTER_LINEAR);

//    my_remap(left_in,   left   , remapx1, remapy1 );
//    my_remap(right_in, right, remapx2, remapy2 );

//    left_in.copyTo(left);
//    right_in.copyTo(right);


     FILE *p_remapX1 = fopen("./remapX1.txt", "wb");
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fprintf(p_remapX1, "%f\n", remapx1.at<float>(i,j) ); //  (i * COL_N + j) );
         }
     }
     fclose(p_remapX1);

     FILE *p_remapY1 = fopen("./remapY1.txt", "wb");
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fprintf(p_remapY1, "%f\n", remapy1.at<float>(i,j) ); // (i * COL_N + j) );
         }
     }
     fclose(p_remapY1);

     FILE *p_remapX2 = fopen("./remapX2.txt", "wb");
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
            fprintf(p_remapX2, "%f\n", remapx2.at<float>(i,j) ); //(i * COL_N + j) );
         }
     }
     fclose(p_remapX2);

     FILE *p_remapY2 = fopen("./remapY2.txt", "wb");
     for (int i = 0; i < ROW_N; i++)
     {
         for (int j = 0; j < COL_N ; j++)
         {
             fprintf(p_remapY2, "%f\n", remapy2.at<float>(i,j) ); //(i * COL_N + j) );
         }
     }
     fclose(p_remapY2);


    unsigned int  tempData ;

    Mat left_U_modelsim(left_in.rows,left_in.cols,CV_32F) ;
    Mat left_V_modelsim(left_in.rows,left_in.cols,CV_32F) ;
    Mat right_U_modelsim(left_in.rows,left_in.cols,CV_32F) ;
    Mat right_V_modelsim(left_in.rows,left_in.cols,CV_32F) ;


    int unMatchCnt = 0 ;

    FILE *fd_left_u = fopen("/media/brian/PRO/MyPro/StereoFPGA/stereoIP/moduleSims/sim_top/axiStreamTop/left_U_cord.txt", "rb");
    if (fd_left_u == NULL)
    {
        return  - 1;
    }
    for (int r  = 0;r < right.rows; r++)
    {
        for (int c = 0; c< right.cols; c++)
        {
                fscanf(fd_left_u, "%x\n", &tempData);

                float* tempData_ptr = reinterpret_cast<float*>(&tempData);
                float tempData_float = *tempData_ptr ;

                left_U_modelsim.at<float>(r,c)   =  tempData_float ;

                float left_cpu_U = (float)remapx1.at<float>(r,c) ;
                float  abs_diff = abs(left_cpu_U - tempData_float) ;

                if(abs_diff > 0.002 && tempData_float > 0.01)
                {
//                    cout << "r =  " << r << "          c =      " << c  << "       " ;
//                    printf("left_cpu_U = %f         " , left_cpu_U) ;
//                    printf("left_U_modelsim =  %f\n", tempData_float) ;
                    unMatchCnt ++ ;
                }
        }

        if(unMatchCnt > 20)
        {
            unMatchCnt = 0 ;
            break  ;
        }
    }
    fclose(fd_left_u);

    printf("*************************************************************************\n") ;

    FILE *fd_left_v = fopen("/media/brian/PRO/MyPro/StereoFPGA/stereoIP/moduleSims/sim_top/axiStreamTop/left_V_cord.txt", "rb");
    if (fd_left_v == NULL)
    {
        return  - 1;
    }
    for (int r  = 0;r < right.rows; r++)
    {
        for (int c = 0; c< right.cols; c++)
        {
                fscanf(fd_left_v, "%x\n", &tempData);

                float* tempData_ptr = reinterpret_cast<float*>(&tempData);
                float tempData_float = *tempData_ptr ;
                left_V_modelsim.at<float>(r,c)   = tempData_float ;

                float left_cpu_V = (float)remapy1.at<float>(r,c) ;
                float  abs_diff = abs(left_cpu_V - tempData_float) ;

                if(abs_diff > 0.002 && tempData_float > 0.01)
                {
//                    cout << "r =  " << r << "          c =      " << c  << "       " ;
//                    printf("left_cpu_V = %f         " , left_cpu_V) ;
//                    printf("left_V_modelsim =  %f\n", tempData_float) ;
                    unMatchCnt ++ ;
                }
        }

        if(unMatchCnt > 20)
        {
            unMatchCnt = 0 ;
            break  ;
        }
    }
    fclose(fd_left_v);

    printf("*************************************************************************\n") ;

    FILE *fd_right_u = fopen("/media/brian/PRO/MyPro/StereoFPGA/stereoIP/moduleSims/sim_top/axiStreamTop/right_U_cord.txt", "rb");
    if (fd_right_u == NULL)
    {
        return  - 1;
    }
    for (int r  = 0;r < right.rows; r++)
    {
        for (int c = 0; c< right.cols; c++)
        {
                fscanf(fd_right_u, "%x\n", &tempData);
                float* tempData_ptr = reinterpret_cast<float*>(&tempData);
                float tempData_float = *tempData_ptr ;
                left_U_modelsim.at<float>(r,c)   = tempData_float ;

                float right_cpu_U = (float)remapx2.at<float>(r,c) ;
                float  abs_diff = abs(right_cpu_U - tempData_float) ;

                if(abs_diff > 0.002 && tempData_float > 0.01)
                {
//                    cout << "r =  " << r << "          c =      " << c  << "       " ;
//                    printf("right_cpu_U = %f         " , right_cpu_U) ;
//                    printf("right_U_modelsim =  %f\n", tempData_float) ;
                    unMatchCnt ++ ;
                }
        }

        if(unMatchCnt > 20)
        {
            unMatchCnt = 0 ;
            break  ;
        }
    }
    fclose(fd_right_u);

        printf("*************************************************************************\n") ;

    FILE *fd_right_v = fopen("/media/brian/PRO/MyPro/StereoFPGA/stereoIP/moduleSims/sim_top/axiStreamTop/right_V_cord.txt", "rb");
    if (fd_left_u == NULL)
    {
        return  - 1;
    }
    for (int r  = 0;r < right.rows; r++)
    {
        for (int c = 0; c< right.cols; c++)
        {
                fscanf(fd_right_v, "%x\n", &tempData);
                float* tempData_ptr = reinterpret_cast<float*>(&tempData);
                float tempData_float = *tempData_ptr ;
                left_V_modelsim.at<float>(r,c)   = tempData_float ;

                float right_cpu_V = (float)remapy2.at<float>(r,c) ;
                float  abs_diff = abs(right_cpu_V - tempData_float) ;

               if(abs_diff > 0.002 && tempData_float > 0.01)
                {
//                    cout << "r =  " << r << "          c =      " << c  << "       " ;
//                    printf("right_cpu_V = %f         " , right_cpu_V) ;
//                    printf("right_V_modelsim =  %f\n", tempData_float) ;
                    unMatchCnt ++ ;
                }
        }

        if(unMatchCnt > 20)
        {
            unMatchCnt = 0 ;
            break  ;
        }
    }
    fclose(fd_right_v);

    printf("*************************************************************************\n") ;

	int disp_size = 64;
	if (argc >= 4) {
		disp_size = atoi(argv[3]);
	}

    uint64_t*  CT_left   = new uint64_t[left.cols * left.rows] ;
    uint64_t*  CT_right = new uint64_t[left.cols * left.rows] ;

    uint8_t*    H_matching_cost = new uint8_t[left.cols * left.rows* disparity_size_];
    uint16_t*    H_scan_cost              = new uint16_t[left.cols * left.rows* disparity_size_];

    uint16_t*    leftDisp                = new uint16_t[left.cols * left.rows];
    uint16_t*    rightDisp              = new uint16_t[left.cols * left.rows];

    uint16_t*    leftDisp_filtered              = new uint16_t[left.cols * left.rows];
    uint16_t*    rightDisp_filtered              = new uint16_t[left.cols * left.rows];

    uint8_t*       disparity  = new uint8_t[left.cols * left.rows];


    census_cpu(left.data,CT_left,left.cols,left.rows);
    census_cpu(right.data,CT_right,left.cols,left.rows);

    matchingCost_cpu(CT_left,CT_right,H_matching_cost,left.cols,left.rows);

    scan_scost_cpu(H_matching_cost,H_scan_cost,left.cols,left.rows) ;

    winner_takes_all_cpu(leftDisp,  rightDisp, H_scan_cost, left.cols,left.rows);

    median_filter(leftDisp,leftDisp_filtered, left.cols,left.rows);
    median_filter(rightDisp,rightDisp_filtered, left.cols,left.rows);

    check_consistency_cpu(leftDisp_filtered, rightDisp_filtered, disparity ,   left.cols, left.rows);

    cv::Mat disparity_cpu(cv::Size(left.cols, left.rows), CV_8UC1);
    disparity_cpu.data = disparity ;

    imshow("left image remaped", left) ;
    imshow("right image remaped", right) ;

    imshow("left image", left_in) ;
    imshow("right image", right_in) ;


    unsigned int  dataWord ;
    /*
        **********   wirte image for modelsim ********************
    */

    int sof = 0x01 << (24+1) ;
    int eol = 0x01 << (24) ;

    FILE *pfile=fopen("leftImgdata.txt","wb");
     if(pfile==NULL)
     {
      printf("Error opening imgdata.txt");
      return -1;
     }
     uchar *p;

     for(int i=0; i<10;i++)
     {
         fprintf(pfile,"%x\n", 0 );
     }

    for (int i = 0; i < left.rows; i++)
    {

        for (int j = 0; j < left.cols; j++)
        {
            dataWord =  0 ;
//            char B = left_col.at<cv::Vec3b>(i,j)[0] ;
//            char G = left_col.at<cv::Vec3b>(i,j)[1] ;
//            char R = left_col.at<cv::Vec3b>(i,j)[2] ;
            char B = j ;
            char G = 0 ;
            char R = 0 ;

            dataWord  = dataWord  | ( (R << 16)&0x00FF0000) | ( (G << 8)&0x0000FF00) | ( (B << 0)&0x000000FF) ;
            if(i == 0 && j == 0)
            {
                dataWord = dataWord | sof ;
            }
            if(j == left.cols - 1)
            {
                dataWord = dataWord | eol ;
            }

            fprintf(pfile,"%08x\n",  dataWord);
        }
    }
    fclose(pfile);

      pfile=fopen("rightImgdata.txt","wb");
      if(pfile==NULL)
      {
       printf("Error opening imgdata.txt");
       return -1;
      }

      for (int i = 0; i < left.rows; i++)
      {

          for (int j = 0; j < left.cols; j++)
          {
              dataWord =  0 ;
//              char B = right_col.at<cv::Vec3b>(i,j)[0] ;
//              char G = right_col.at<cv::Vec3b>(i,j)[1] ;
//              char R = right_col.at<cv::Vec3b>(i,j)[2] ;
              char B = j ;
              char G = 0 ;
              char R = 0 ;

              dataWord  = dataWord  | ( (R << 16)&0x00FF0000) | ( (G << 8)&0x0000FF00) | ( (B << 0)&0x000000FF) ;
              if(i == 0 && j == 0)
              {
                  dataWord = dataWord | sof ;
              }
              if(j == left.cols - 1)
              {
                  dataWord = dataWord | eol ;
              }

              fprintf(pfile,"%08x\n",  dataWord);
          }
      }
      fclose(pfile);


      /*
          **********   wirte image for FPGA debuging  ********************
      */


      pfile=fopen("imgdata_forFPGA.txt","wb");
       if(pfile==NULL)
       {
        printf("Error opening imgdata.txt");
        return -1;
       }

        // data layout in ddr should be [left0,right0,left1,right1]
       uint8_t data_cnt = 0;

          for (int i = 0; i < left.rows; i++)
          {
              data_cnt = 0;
              for (int j = 0; j < left.cols; j+=4)
              {


//                  dataWord = 0x00 ;
//                  dataWord = dataWord | ((0xFF << 0   )& ((data_cnt + 1)         << 0    )) ;
//                  dataWord =  dataWord| ((0xFF << 8   )& ((data_cnt + 1)      << 8    )) ;    // left1,right1 (low 16 bits)
//                  dataWord = dataWord | ((0xFF << 16)& ((data_cnt + 0) << 16  )) ;
//                  dataWord = dataWord | ((0xFF << 24)& ((data_cnt + 0) << 24 )) ; // left0,right0,  (high 16 bits)
////                  dataWord = circularShift (dataWord) ;
//                fprintf(pfile,"0x%08x\n",dataWord);
//                data_cnt  = data_cnt + 2;

//                dataWord = 0x00 ;
//                dataWord = dataWord | ((0xFF << 0   )& ((data_cnt + 1)         << 0    )) ;
//                dataWord =  dataWord| ((0xFF << 8   )& ((data_cnt + 1)      << 8    )) ;    // left1,right1 (low 16 bits)
//                dataWord = dataWord | ((0xFF << 16)& ((data_cnt + 0) << 16  )) ;
//                dataWord = dataWord | ((0xFF << 24)& ((data_cnt + 0) << 24 )) ; // left0,right0,  (high 16 bits)
////                  dataWord = circularShift (dataWord) ;
//                  fprintf(pfile,"0x%08x\n",dataWord);     // left_right

//                data_cnt  = data_cnt + 2 ;



                  dataWord = 0x00 ;
                  dataWord = dataWord | ((0xFF << 0   )& (right.at<uchar>(i,j+1)        << 0    )) ;
                  dataWord =  dataWord| ((0xFF << 8   )& (left.at<uchar>(i,j+1)     << 8    )) ;    // left1,right1 (low 16 bits)
                  dataWord = dataWord | ((0xFF << 16)& (right.at<uchar>(i,j)   << 16  )) ;
                  dataWord = dataWord | ((0xFF << 24)& (left.at<uchar>(i,j) << 24 )) ; // left0,right0,  (high 16 bits)
//                  dataWord = circularShift (dataWord) ;
                fprintf(pfile,"0x%08x\n",dataWord);

                dataWord = 0x00 ;
                dataWord = dataWord | ((0xFF << 0   )& (right.at<uchar>(i,j+3)        << 0    )) ;
                dataWord =  dataWord| ((0xFF << 8   )& (left.at<uchar>(i,j+3)     << 8    )) ;    // left1,right1 (low 16 bits)
                dataWord = dataWord | ((0xFF << 16)& (right.at<uchar>(i,j+2)   << 16  )) ;
                dataWord = dataWord | ((0xFF << 24)& (left.at<uchar>(i,j+2) << 24 )) ; // left0,right0,  (high 16 bits)
//                  dataWord = circularShift (dataWord) ;
                  fprintf(pfile,"0x%08x\n",dataWord);     // left_right

              }
          }
       fclose(pfile);

//        pfile=fopen("rightImgdata_forFPGA.txt","wb");
//        if(pfile==NULL)
//        {
//         printf("Error opening imgdata.txt");
//         return -1;
//        }
//           for (int i = 0; i < right.rows; i++)
//           {
//               for (int j = 0; j < right.cols; j++)
//               {
//                   dataWord = 0x00 ;
//                   dataWord =  ((0xFF << 0)& (right.at<uchar>(i,j) << 0 )) ;
//                   dataWord = dataWord | ((0xFF << 8)& (right.at<uchar>(i,j+1) << 8 )) ;
//                   dataWord = dataWord | ((0xFF << 16)& (right.at<uchar>(i,j+2) << 16 )) ;
//                   dataWord = dataWord | ((0xFF << 24)& (right.at<uchar>(i,j+3) << 24 )) ;
//                   fprintf(pfile,"%08x\n",dataWord);
//               }
//           }
//        fclose(pfile);

     /*
         **********   print  census transform to file  for modelsim  comparason********************
     */

     // FILE *pLeftCensus_file=fopen("leftImageCensusTransform.txt","wb");
     //  if(pLeftCensus_file==NULL)
     //  {
     //   printf("Error opening imgdata.txt");
     //   return -1;
     //  }
     //     for (int i = 0; i < left.rows; i++)
     //     {
     //         for (int j = 0; j < left.cols; j++)
     //         {
     //             fprintf(pLeftCensus_file,"%016lx\n", CT_left[i*left.cols+j]);
     //         }
     //     }
     //  fclose(pLeftCensus_file);






	// show image

       cv::Mat   genColorMapMat(256,256,CV_8UC1) ;
       cv::applyColorMap(disparity_cpu * 4 , genColorMapMat  , cv::COLORMAP_JET);

    cv::imshow("disparity_c",disparity_cpu * 4) ;
    cv::imshow("color_depth",genColorMapMat) ;
	
	int key = cv::waitKey();
	int mode = 0;
	while (key != 27) {
		key = cv::waitKey();
	}


    delete[] CT_left ;
    delete[] CT_right ;
    delete[] H_matching_cost ;

    delete[]    H_scan_cost          ;

    delete[]    leftDisp                ;
    delete[]    rightDisp              ;

}
