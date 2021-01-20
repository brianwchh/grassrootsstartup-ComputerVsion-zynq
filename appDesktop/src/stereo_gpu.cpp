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

#include "stdio.h"
#include <unistd.h>

#include "./cuda/stereogpucore.h"

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
                    printf("%d ",sorroundingPix_Value) ;
                }
            }
            std::cout << std::endl ;
         }
        std::cout << "********************************************" <<std::endl ;
        printf("........ ................  0x%016lx\n",d_dest[100* width + 100]) ;
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

//cudaMallocHost ( &host1, size ) ;   allocate pin memory on host side

int main(int argc, char* argv[]) {
//    if (argc < 2) {
//        std::cerr << "usage: stereosgm left_img right_img  " << std::endl;
//        std::exit(EXIT_FAILURE);
//    }

    Mat remapx1 ;
    Mat remapy1 ;
    Mat remapx2 ;
    Mat remapy2 ;

    cv::Mat left_in = cv::imread("left0.jpg",0);
    cv::Mat right_in = cv::imread("right0.jpg",0);

    Mat left(left_in.rows,left_in.cols,CV_8UC1) ;
    Mat right(left_in.rows,left_in.cols,CV_8UC1) ;


/****************************  GPU portion   ***********************************/

    stereoGPUcore MyStereoCore(left.cols,left.rows) ;

    Mat hDisp(left.rows,right.cols,CV_8UC1);
    hDisp.setTo(0);

    float* rectify_float = new float[left.rows * left.cols * sizeof(float)] ;

    MyStereoCore.execute(left_in.data,right_in.data,(void**)&rectify_float);

    // convert gray scale image to uint8 type
    for(int r=0; r< hDisp.rows; r++)
        for(int c=0; c<hDisp.cols; c++)
        {
            hDisp.at<uchar>(r,c) =  (uchar) rectify_float[ r*hDisp.cols + c ] ;
        }

    imshow("left_rectified_gpu", hDisp);

    cv::waitKey(0);


/***************************************************************************/








    FileStorage f_remapx1("./parameters/remapx1.xml", FileStorage::READ);
    FileStorage f_remapy1("./parameters/remapy1.xml", FileStorage::READ);
    FileStorage f_remapx2("./parameters/remapx2.xml", FileStorage::READ);
    FileStorage f_remapy2("./parameters/remapy2.xml", FileStorage::READ);

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

    int disp_size = 64;

    uint64_t*  CT_left   = new uint64_t[left.cols * left.rows] ;
    uint64_t*  CT_right = new uint64_t[left.cols * left.rows] ;

    uint8_t*    H_matching_cost = new uint8_t[left.cols * left.rows* disparity_size_];
    uint16_t*    H_scan_cost              = new uint16_t[left.cols * left.rows* disparity_size_];

    uint16_t*    leftDisp                = new uint16_t[left.cols * left.rows];
    uint16_t*    rightDisp              = new uint16_t[left.cols * left.rows];

    uint16_t*    leftDisp_filtered              = new uint16_t[left.cols * left.rows];
    uint16_t*    rightDisp_filtered              = new uint16_t[left.cols * left.rows];

    uint8_t*       disparity  = new uint8_t[left.cols * left.rows];

    uint8_t*   h_disp = new uint8_t[left.cols * left.rows];

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

    cv::imshow("disparity_c",disparity_cpu * 4 ) ;



    imshow("left_rectified_cpu",left) ;


    int key = cv::waitKey();


    delete[] CT_left ;
    delete[] CT_right ;
    delete[] H_matching_cost ;

    delete[]    H_scan_cost          ;

    delete[]    leftDisp                ;
    delete[]    rightDisp              ;

}
