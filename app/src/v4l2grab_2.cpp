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

#include "v4l2grab_2.h"

v4l2grab_2::v4l2grab_2(const char* FILE_VIDEO ){

        FILE_VIDEO_ = FILE_VIDEO ;
        n_buffers = 3 ;
        fd = open(FILE_VIDEO_,O_RDWR);
        if (!fd) {
            printf("Error opening device");
            exit (EXIT_FAILURE);
        }
        set_input();
        get_info();
        get_video_info();
        start_capturing();
}


void v4l2grab_2::set_input() {
    int index;
    index = 0;
    if (-1 == ioctl (fd, VIDIOC_S_INPUT, &index)) {
        printf ("VIDIOC_S_INPUT");
        exit (EXIT_FAILURE);
    }

    struct v4l2_capability cap;
    struct v4l2_cropcap cropcap;
    struct v4l2_crop crop;
    struct v4l2_format fmt;
    unsigned int min;

    struct v4l2_control control_s;
//    //--------- set brightness -------------
//    control_s.id =  V4L2_CID_BRIGHTNESS;
//    control_s.value  = 60 ;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//        printf("set V4L2_CID_BRIGHTNESS error \n");
//        exit(EXIT_FAILURE);
//    }
//     control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//        printf("Get V4L2_CID_BRIGHTNESS error \n");
//        exit(EXIT_FAILURE);
//    }
//    else  {
//        printf("brightness ==  %d \n" , control_s.value  );
//    }

//     //--------- set contrast -------------
//    control_s.id =  V4L2_CID_CONTRAST;
//    control_s.value  = 50 ;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//        printf("set V4L2_CID_CONTRAST error \n");
//        exit(EXIT_FAILURE);
//    }
//     control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//        printf("Get V4L2_CID_CONTRAST error \n");
//        exit(EXIT_FAILURE);
//    }
//    else  {
//        printf("contrast ==  %d \n" , control_s.value  );
//    }

//        //--------- set saturation -------------
//       control_s.id =  V4L2_CID_SATURATION;
//       control_s.value  = 50 ;
//       if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//       {
//           printf("set V4L2_CID_SATURATION error \n");
//           exit(EXIT_FAILURE);
//       }
//        control_s.value  =  0 ;
//       if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//       {
//           printf("Get V4L2_CID_SATURATION error \n");
//           exit(EXIT_FAILURE);
//       }
//       else  {
//           printf("saturation ==  %d \n" , control_s.value  );
//       }

//       //--------- set hue -------------
//      control_s.id =  V4L2_CID_HUE;
//      control_s.value  = 50 ;
//      if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//      {
//          printf("set V4L2_CID_HUE error \n");
//          exit(EXIT_FAILURE);
//      }
//       control_s.value  =  0 ;
//      if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//      {
//          printf("Get V4L2_CID_HUE error \n");
//          exit(EXIT_FAILURE);
//      }
//      else  {
//          printf("hue ==  %d \n" , control_s.value  );
//      }

//      //--------- set sharpness -------------
//     control_s.id =  V4L2_CID_SHARPNESS;
//     control_s.value  = 32 ;
//     if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//     {
//         printf("set V4L2_CID_SHARPNESS error \n");
//         exit(EXIT_FAILURE);
//     }
//      control_s.value  =  0 ;
//     if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//     {
//         printf("Get V4L2_CID_SHARPNESS error \n");
//         exit(EXIT_FAILURE);
//     }
//     else  {
//         printf("sharpness ==  %d \n" , control_s.value  );
//     }

     //--------- set gain -------------
//    control_s.id =  V4L2_CID_GAIN;
//    control_s.value  = 50 ;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//        printf("set V4L2_CID_GAIN error \n");
//        exit(EXIT_FAILURE);
//    }
//     control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//        printf("Get V4L2_CID_GAIN error \n");
//        exit(EXIT_FAILURE);
//    }
//    else  {
//        printf("gain ==  %d \n" , control_s.value  );
//    }


//    //--------- set exposure mode -------------
//    control_s.id =   V4L2_CID_EXPOSURE_AUTO;
//    control_s.value  =   V4L2_EXPOSURE_MANUAL ;  //  V4L2_EXPOSURE_APERTURE_PRIORITY ;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//       printf("set V4L2_CID_EXPOSURE_AUTO error \n");
//       exit(EXIT_FAILURE);
//    }
//    control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//       printf("Get V4L2_CID_EXPOSURE_AUTO error \n");
//       exit(EXIT_FAILURE);
//    }
//    else  {
//       printf("exposure mode  ==  %d \n" , control_s.value  );
//    }

//    //--------- set mannual exposure time  -------------
//    control_s.id =  V4L2_CID_EXPOSURE_ABSOLUTE ;
//    control_s.value  = 8000;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//       printf("set V4L2_CID_EXPOSURE_ABSOLUTE error \n");
//       exit(EXIT_FAILURE);
//    }
//    control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//       printf("Get V4L2_CID_EXPOSURE_ABSOLUTE error \n");
//       exit(EXIT_FAILURE);
//    }
//    else  {
//       printf("exposure time  ==  %d \n" , control_s.value  );
//    }


//    //--------- set white balance mode 0 : mannual-------------
//    control_s.id =  V4L2_CID_AUTO_WHITE_BALANCE;
//    control_s.value  = 0 ;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//       printf("set V4L2_CID_AUTO_WHITE_BALANCE error \n");
//       exit(EXIT_FAILURE);
//    }
//    control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//       printf("Get V4L2_CID_AUTO_WHITE_BALANCE error \n");
//       exit(EXIT_FAILURE);
//    }
//    else  {
//       printf("white balance mode ==  %d \n" , control_s.value  );
//    }

//    //--------- set white balance value  -------------
//    control_s.id =  V4L2_CID_WHITE_BALANCE_TEMPERATURE;
//    control_s.value  = 4900 ;
//    if(-1==ioctl(fd, VIDIOC_S_CTRL, &control_s))
//    {
//       printf("set V4L2_CID_WHITE_BALANCE_TEMPERATURE error \n");
//       exit(EXIT_FAILURE);
//    }
//    control_s.value  =  0 ;
//    if(-1==ioctl(fd, VIDIOC_G_CTRL, &control_s))
//    {
//       printf("Get V4L2_CID_WHITE_BALANCE_TEMPERATURE error \n");
//       exit(EXIT_FAILURE);
//    }
//    else  {
//       printf("white balance value ==  %d \n" , control_s.value  );
//    }








    if (-1 == ioctl (fd, VIDIOC_QUERYCAP, &cap)) {
        if (EINVAL == errno) {
            printf( "Device is no V4L2 device\n");
            exit (EXIT_FAILURE);
        } else {
            printf ("VIDIOC_QUERYCAP");
            exit(EXIT_FAILURE);
        }
    }

    if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
        printf( "Device is no video capture device\n");
        exit (EXIT_FAILURE);
    }


    if (!(cap.capabilities & V4L2_CAP_STREAMING)) {
        printf( "Device does not support streaming i/o\n");
        exit (EXIT_FAILURE);
    }

    memset(&cropcap, 0, sizeof(cropcap));

    cropcap.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;

    if (0 == ioctl (fd, VIDIOC_CROPCAP, &cropcap)) {
        crop.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        crop.c = cropcap.defrect; /* reset to default */

        if (-1 == ioctl (fd, VIDIOC_S_CROP, &crop)) {
            switch (errno) {
            case EINVAL:
                /* Cropping not supported. */
                break;
            default:
                /* Errors ignored. */
                break;
            }
        }
    } else {
        /* Errors ignored. */
    }

    memset(&fmt, 0, sizeof(fmt));

    fmt.type                = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width       = RESX;
    fmt.fmt.pix.height      = RESY;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    fmt.fmt.pix.field       = V4L2_FIELD_INTERLACED;

    if (-1 == ioctl (fd, VIDIOC_S_FMT, &fmt)) {
        printf ("VIDIOC_S_FMT");
        exit(EXIT_FAILURE);
    }

    /* Note VIDIOC_S_FMT may change width and height. */

    /* Buggy driver paranoia. */
    min = fmt.fmt.pix.width * 2;
    if (fmt.fmt.pix.bytesperline < min)
        fmt.fmt.pix.bytesperline = min;

    min = fmt.fmt.pix.bytesperline * fmt.fmt.pix.height;

    if (fmt.fmt.pix.sizeimage < min)
        fmt.fmt.pix.sizeimage = min;

    printf("%d %d\n", fmt.fmt.pix.width, fmt.fmt.pix.height);
    printf("%d\n",fmt.fmt.pix.sizeimage);

    // Init mmap
    struct v4l2_requestbuffers req;

    memset(&req, 0, sizeof(req));

    req.count               = 2;
    req.type                = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory              = V4L2_MEMORY_MMAP;

    if (-1 == ioctl (fd, VIDIOC_REQBUFS, &req)) {
        if (EINVAL == errno) {
            printf( "Device does not support memory mapping\n");
            exit (EXIT_FAILURE);
        } else {
            printf ("VIDIOC_REQBUFS");
            exit(EXIT_FAILURE);
        }
    }

    if (req.count < 2) {
        printf( "Insufficient buffer memory on device\n");
        exit (EXIT_FAILURE);
    }

    buffers = (struct buffer*)calloc (req.count, sizeof (*buffers));

    if (!buffers) {
        printf( "Out of memory\n");
        exit (EXIT_FAILURE);
    }

    for (n_buffers = 0; n_buffers < req.count; ++n_buffers) {
        struct v4l2_buffer buf;

        memset(&buf, 0, sizeof(buf));

        buf.type        = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory      = V4L2_MEMORY_MMAP;
        buf.index       = n_buffers;

        if (-1 == ioctl (fd, VIDIOC_QUERYBUF, &buf)) {
            printf ("VIDIOC_QUERYBUF");
            exit(EXIT_FAILURE);
        }

        buffers[n_buffers].length = buf.length;
        buffers[n_buffers].start =
            mmap (NULL /* start anywhere */,
                  buf.length,
                  PROT_READ | PROT_WRITE /* required */,
                  MAP_SHARED /* recommended */,
                  fd, buf.m.offset);

        if (MAP_FAILED == buffers[n_buffers].start) {
            printf ("mmap");
            exit(EXIT_FAILURE);
        }
    }
}


void v4l2grab_2::get_info() {
    struct v4l2_input input;
    int index;

    if (-1 == ioctl (fd, VIDIOC_G_INPUT, &index)) {
        printf ("VIDIOC_G_INPUT");
        exit (EXIT_FAILURE);
    }

    memset (&input, 0, sizeof (input));
    input.index = index;

    if (-1 == ioctl (fd, VIDIOC_ENUMINPUT, &input)) {
        printf ("VIDIOC_ENUMINPUT");
        exit (EXIT_FAILURE);
    }

    printf ("Current input: %s\n", input.name);
}

void v4l2grab_2::get_video_info() {
    struct v4l2_input input;
    struct v4l2_fmtdesc formats;

    memset (&input, 0, sizeof (input));

    if (-1 == ioctl (fd, VIDIOC_G_INPUT, &input.index)) {
        printf ("VIDIOC_G_INPUT");
        exit (EXIT_FAILURE);
    }

    printf ("Current input %s supports:\n", input.name);

    memset (&formats, 0, sizeof (formats));
    formats.index = 0;
    formats.type  = V4L2_BUF_TYPE_VIDEO_CAPTURE;

    while (0 == ioctl (fd, VIDIOC_ENUM_FMT, &formats)) {
        printf ("%s\n", formats.description);
        formats.index++;
    }

    if (errno != EINVAL || formats.index == 0) {
        printf ("VIDIOC_ENUMFMT");
        exit(EXIT_FAILURE);
    }
}

void v4l2grab_2::start_capturing (void)
{
    unsigned int i;
    enum v4l2_buf_type type;


    for (i = 0; i < n_buffers; ++i) {
        struct v4l2_buffer buf;

        memset(&buf, 0, sizeof(buf));

        buf.type        = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory      = V4L2_MEMORY_MMAP;
        buf.index       = i;

        if (-1 == ioctl (fd, VIDIOC_QBUF, &buf)) {
            printf ("VIDIOC_QBUF");
            exit(EXIT_FAILURE);
        }
    }

    type = V4L2_BUF_TYPE_VIDEO_CAPTURE;

    if (-1 == ioctl (fd, VIDIOC_STREAMON, &type)) {
        printf ("VIDIOC_STREAMON");
        exit(EXIT_FAILURE);
    }

    std::cout << "VIDIOC_STREAMON" << std::endl ;

}


int v4l2grab_2::read_frame (void)
{
    unsigned int i;

    memset(&buf, 0, sizeof(buf));

    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;

    struct pollfd tFds[1];
    int iRet;

    /* poll */
    tFds[0].fd     = fd;
    tFds[0].events = POLLIN;

    iRet = poll(tFds, 1, -1);
    if (iRet <= 0)
    {
        printf("poll error!\n");
        return -1;
    }


    if (-1 == ioctl (fd, VIDIOC_DQBUF, &buf)) {
        switch (errno) {
        case EAGAIN:
            return 0;

        case EIO:
            /* Could ignore EIO, see spec. */

            /* fall through */

        default:
            printf ("VIDIOC_DQBUF");
            exit(EXIT_FAILURE);
        }
    }

    assert (buf.index < n_buffers);

    yuyv_2_rgb888(buf.index);

    if (-1 == ioctl (fd, VIDIOC_QBUF, &buf)) {
        printf ("VIDIOC_QBUF");
        exit(EXIT_FAILURE);
    }

    return 1;
}

int v4l2grab_2::yuyv_2_rgb888(int index)
{
    int           i,j;
    unsigned char y1,y2,u,v;
    int r1,g1,b1,r2,g2,b2;
    char * pointer;

    pointer = (char*)buffers[index].start;

    for(i=0;i<RESY;i++)
    {
        for(j=0;j<RESX/2;j++)
        {
            y1 = *( pointer + (i*RESX/2+j)*4);
            u  = *( pointer + (i*RESX/2+j)*4 + 1);
            y2 = *( pointer + (i*RESX/2+j)*4 + 2);
            v  = *( pointer + (i*RESX/2+j)*4 + 3);

            r1 = y1 + 1.042*(v-128);
            g1 = y1 - 0.34414*(u-128) - 0.71414*(v-128);
            b1 = y1 + 1.772*(u-128);

            r2 = y2 + 1.042*(v-128);
            g2 = y2 - 0.34414*(u-128) - 0.71414*(v-128);
            b2 = y2 + 1.772*(u-128);

            if(r1>255)
                r1 = 255;
            else if(r1<0)
                r1 = 0;

            if(b1>255)
                b1 = 255;
            else if(b1<0)
                b1 = 0;

            if(g1>255)
                g1 = 255;
            else if(g1<0)
                g1 = 0;

            if(r2>255)
                r2 = 255;
            else if(r2<0)
                r2 = 0;

            if(b2>255)
                b2 = 255;
            else if(b2<0)
                b2 = 0;

            if(g2>255)
                g2 = 255;
            else if(g2<0)
                g2 = 0;

            *(frame_buffer + (i*RESX/2+j)*6    ) = (unsigned char)b1;
            *(frame_buffer + (i*RESX/2+j)*6 + 1) = (unsigned char)g1;
            *(frame_buffer + (i*RESX/2+j)*6 + 2) = (unsigned char)r1;
            *(frame_buffer + (i*RESX/2+j)*6 + 3) = (unsigned char)b2;
            *(frame_buffer + (i*RESX/2+j)*6 + 4) = (unsigned char)g2;
            *(frame_buffer + (i*RESX/2+j)*6 + 5) = (unsigned char)r2;

        }
    }
}


v4l2grab_2::~v4l2grab_2()
{
    if(fd != -1)
    {
        close(fd);
    }
}


