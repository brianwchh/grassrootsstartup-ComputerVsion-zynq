#ifndef V4L2GRAB2_H
#define V4L2GRAB2_H

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <linux/types.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <errno.h>

#include <stdio.h>
#include<opencv/highgui.h>
#include <math.h>


#define RESX 1280
#define RESY 720

struct buffer {
        void *                  start;
        size_t                  length;
};


class v4l2grab_2  {
public:

    v4l2grab_2(const char* FILE_VIDEO );
    ~v4l2grab_2();

    const char* FILE_VIDEO_ ;
    unsigned char frame_buffer[RESX*RESY*3];

    struct buffer *         buffers                ;
    unsigned int     n_buffers       ;
    struct v4l2_buffer buf;

    int fd ;

    void set_input() ;
    void get_info() ;
    void get_video_info() ;
    void start_capturing (void) ;
    int read_frame (void) ;
    int yuyv_2_rgb888(int index);

};

#endif
