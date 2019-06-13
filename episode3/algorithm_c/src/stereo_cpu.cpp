
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

                }

            d_dest[CenP] = value ;
        }
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
                          if(Lpr_minus1_DiPlus0 > minPre  &&  Lpr_minus1_DiPlus1 > minPre &&   Lpr_minus1_DiMinus1> minPre )   // minPre is the minumum
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

/*
            for other path scan, you can implement yourself to have some fun

*/


        // depth wise add
        for( int r = 0 ; r < height ; r++)
            for(int c=0; c< width ; c++)
            {
                    int volPtr = r * width * disparity_size_ + c * disparity_size_ ;
                    for(int d=0; d< disparity_size_; d++)
                    {
//                        d_scost[volPtr + d ] =  left_scan[volPtr + d]  +  right_scan[volPtr + d] + top_scan[volPtr + d]  +  bottom_scan[volPtr + d]  + topleft_scan[volPtr + d] + topright_scan[volPtr + d] + bottomleft_scan[volPtr+d] + bottomright_scan[volPtr+d];
                        d_scost[volPtr + d ] =  left_scan[volPtr + d]  ;   // +   top_scan[volPtr + d]    + topleft_scan[volPtr + d] + topright_scan[volPtr + d]  ;

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

void winner_takes_all_cpu(uint16_t* leftDisp, uint16_t* rightDisp, const uint16_t*  h_cost, int width, int height){

    uint16_t*    right_cost            = new uint16_t[width * height * disparity_size_];
    //1.  given left cost  volumn , derive the theoreticl right right cost volumn
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

    //2.  calculate the minimum Lr(P,Di) for left and right cost using winner takes all method
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




#define   ROW_N  375
#define   COL_N    1242

int main(int argc, char* argv[]) {
	if (argc < 3) {
        std::cerr << "usage: stereo_cpu left_img right_img " << std::endl;
		std::exit(EXIT_FAILURE);
	}

    cv::Mat left = cv::imread(argv[1],-1);
    cv::Mat right = cv::imread(argv[2],-1);

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

    imshow("left image ", left) ;
    imshow("right image ", right) ;


	// show image

       cv::Mat   genColorMapMat(256,256,CV_8UC1) ;
       cv::applyColorMap(disparity_cpu * 4 , genColorMapMat  , cv::COLORMAP_JET);

    cv::imshow("disparity_c",disparity_cpu * 4) ;
    cv::imshow("color_depth",genColorMapMat) ;
	
     cv::waitKey(0);


    delete[] CT_left ;
    delete[] CT_right ;
    delete[] H_matching_cost ;

    delete[]    H_scan_cost          ;

    delete[]    leftDisp                ;
    delete[]    rightDisp              ;

}
