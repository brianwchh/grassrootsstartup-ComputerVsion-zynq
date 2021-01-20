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

#include <opencv/highgui.h>
//#include "opencv2/imgproc/imgproc.hpp"
#include <opencv/cv.h>
#include <opencv2/opencv.hpp>

#include <sys/time.h>
#include <sstream>
#include <fstream>
#include <termios.h>
#include <unistd.h>

//#include "v4l2grab_2.h"

using namespace std ;

cv::Mat remapx1 ;
cv::Mat remapy1 ;
cv::Mat remapx2 ;
cv::Mat remapy2 ;


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




int main(int argc, char** argv)
{

//    std::string vdevice0 = "/dev/video0" ;
//    std::string vdevice1 = "/dev/video1" ;

//    v4l2grab_2 VedioGrab0(vdevice0.c_str());

    // cv::Mat wrapped(rows, cols, CV_32FC1, external_mem, CV_AUTOSTEP); // does not copy
//    cv::Mat frame1(720,2560,CV_8UC3,VedioGrab0.frame_buffer) ;

    cv::Mat frame1 ;

  cv::VideoCapture cap1(0);

  cv::Mat imgResized(360,1280,CV_8UC3);
  cv::Mat imgResized_gray(360,1280,CV_8UC1);
  cv::Mat imgL(360,640,CV_8UC1);
  cv::Mat imgR(360,640,CV_8UC1);

  cv::Mat imgL_remaped(360,640,CV_8UC1);
  cv::Mat imgR_remaped(360,640,CV_8UC1);


//  cv::FileStorage f_remapx1("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapx1.xml", cv::FileStorage::READ);
//  cv::FileStorage f_remapy1("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapy1.xml", cv::FileStorage::READ);
//  cv::FileStorage f_remapx2("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapx2.xml", cv::FileStorage::READ);
//  cv::FileStorage f_remapy2("/home/brian/catkin_ws/src/streamcamera/parameters/720/remapy2.xml", cv::FileStorage::READ);

  cv::FileStorage f_remapx1("./parameters/remapx1.xml", cv::FileStorage::READ);
  cv::FileStorage f_remapy1("./parameters/remapy1.xml", cv::FileStorage::READ);
  cv::FileStorage f_remapx2("./parameters/remapx2.xml", cv::FileStorage::READ);
  cv::FileStorage f_remapy2("./parameters/remapy2.xml", cv::FileStorage::READ);

  if(f_remapx1.isOpened())
  {
      f_remapx1["remapx1"] >> remapx1;
      f_remapx1.release();
  }
  if(f_remapy1.isOpened())
  {
      f_remapy1["remapy1"] >> remapy1;
      f_remapy1.release();
  }
  if(f_remapx2.isOpened())
  {
      f_remapx2["remapx2"] >> remapx2;
      f_remapx2.release();
  }
  if(f_remapy2.isOpened())
  {
      f_remapy2["remapy2"] >> remapy2;
      f_remapy2.release();
  }

  int svcnt = 0 ;
  int svcnt_outLoop = 0 ;
  char wkeyV  = 0 ;
  int capture_en = 0x1 ;
  int capture_interval_cnt = 0 ;

  while (1) {

        cap1 >> frame1 ;

//      cout <<"start reading one  image " <<endl ;

//       VedioGrab0.read_frame();

        resize(frame1, imgResized, cv::Size(1280, 720/2), 0, 0, cv::INTER_LINEAR);
        cvtColor(imgResized,imgResized_gray,CV_BGR2GRAY);

        for(int r=0; r <  imgResized_gray.rows ; r++ )
        for(int c=0 ; c < imgResized_gray.cols ; c++)
        {
          if(c < imgL.cols)
          {
              imgL.at<uchar>(r,c)  = imgResized_gray.at<uchar>(r,c) ;
          }
          else
          {
              imgR.at<uchar>(r,c - imgL.cols)  = imgResized_gray.at<uchar>(r,c) ;
          }
        }

        remap(imgL , imgL_remaped   , remapx1, remapy1,CV_INTER_LINEAR);
        remap(imgR , imgR_remaped,   remapx2, remapy2,CV_INTER_LINEAR);



//        if(capture_en==0)
//        {
//            wkeyV = getch();
//        }

//        if(wkeyV == 'b')  // begin
//        {
//            capture_en = 0x01;
//        }
//        else if (wkeyV == 's')  // stop
//        {
//            capture_en = 0x00 ;
//        }

//       if(capture_en== 0x1)
    //   if(svcnt_outLoop%3==0)
//       {
//           if(capture_interval_cnt == 100){
                     string left_gray   = "images/left_"+patch::to_string(svcnt)+".png" ;
                     string right_gray = "images/right_"+patch::to_string(svcnt)+".png" ;
                     imwrite(left_gray.c_str(),   imgL);
                     imwrite(right_gray.c_str(),imgR);
                     cout << "saving image_" << svcnt << endl ;

                    svcnt++ ;
//           }
//           else {
//               capture_interval_cnt ++ ;
//           }
//       }

//        cv::imshow("tt",imgResized_gray) ;
//        cv::imshow("tLt",imgL) ;
//        cv::imshow("tRt",imgR) ;
//        cv::imshow("tLt_re",imgL_remaped) ;
//        cv::imshow("tRt_re",imgR_remaped) ;
//        cv::waitKey(1) ;


  }

  return 0 ;
}
