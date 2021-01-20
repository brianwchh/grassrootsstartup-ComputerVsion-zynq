#include "stereocpu.h"

stereoCPU::stereoCPU()
{
}


void stereoCPU::census_cpu(uchar* d_source, uint64_t* d_dest, int width, int height)
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
                }

            d_dest[CenP] = value ;
        }
}


void stereoCPU::matchingCost_cpu(const uint64_t* h_left, const uint64_t* h_right, uint8_t* h_matching_cost, int width, int height)
{
        for(int r=0; r < height; r++)
            for(int c=0; c<width; c++)
            {
                int ptr = r * width + c ;
                uint64_t baseVal = h_left[ptr];

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
