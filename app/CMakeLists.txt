cmake_minimum_required (VERSION 2.6) 

PROJECT(stereo)
SET(PROJECT_VERSION "0.1")

 
#################################################################################################
# Set this to the version of OpenCV that you need.
#   arm    : use zynq cross compile version
#   system : use system default version 
########################################################################################################

 set(OPENCV_LIB "arm")

#################################################################################################
#   DO NOT CHANGE BELOW
########################################################################################################
 if(OPENCV_LIB STREQUAL "arm") 
	# this one is important
	set( CMAKE_SYSTEM_NAME Linux )
	#this one not so much
	set( CMAKE_SYSTEM_PROCESSOR arm )
	# specify the cross compiler
	set( CMAKE_C_COMPILER arm-xilinx-linux-gnueabi-gcc )
	set( CMAKE_CXX_COMPILER arm-xilinx-linux-gnueabi-g++ )
	message(STATUS "Using my own compiled OpenCV.") 
	include_directories("/opt/ZynqOpencv-lib/include/opencv" "/opt/ZynqOpencv-lib/include") 
	link_directories("/opt/ZynqOpencv-lib/lib") 
	set(OpenCV_LIBS 
	"opencv_core;opencv_imgproc;opencv_highgui;opencv_ml;opencv_video;opencv_features2d;opencv_calib3d;opencv_objdetect;opencv_contrib;opencv_legacy;opencv_flann")	 
elseif(OPENCV_LIB STREQUAL "system") 
	message(STATUS "Using OpenCV that got automatically detected.") 
	find_package( OpenCV REQUIRED ) 
	IF (${OpenCV_VERSION} VERSION_LESS 2.3.0)
		MESSAGE(FATAL_ERROR "OpenCV version is not compatible : ${OpenCV_VERSION}")
	ENDIF()
endif() 

include_directories("Xinclude")

SET(SRC
        src/stereo.cpp
	src/v4l2grab_2.cpp
        src/vga_modes.h
)

ADD_EXECUTABLE( ${PROJECT_NAME} ${SRC} )
TARGET_LINK_LIBRARIES( ${PROJECT_NAME}  ${OpenCV_LIBS} )

SET(stereo_hwAccel_src
        src/stereo_hwAccel.cpp
        src/v4l2grab_2.cpp
        src/vga_modes.h
)

ADD_EXECUTABLE( stereo_hwAccel  ${stereo_hwAccel_src} )
#link_libraries("-static")
TARGET_LINK_LIBRARIES( stereo_hwAccel  ${OpenCV_LIBS} )


SET(stereo_hwAccel_kitti_src
        src/stereo_hwAccel_kitti.cpp
#        src/v4l2grab_2.cpp
#        src/vga_modes.h
)

ADD_EXECUTABLE( stereo_hwAccel_kitti  ${stereo_hwAccel_kitti_src} )
TARGET_LINK_LIBRARIES( stereo_hwAccel_kitti  ${OpenCV_LIBS}   )



ADD_EXECUTABLE( stereo_hwAccel_one_image  src/stereo_hwAccel_one_image.cpp )
TARGET_LINK_LIBRARIES( stereo_hwAccel_one_image  ${OpenCV_LIBS} )

#SET(SRC_config
#        src/configVdmaApp.cpp
#        src/v4l2grab_2.cpp
#        src/vga_modes.h
#)

#ADD_EXECUTABLE( configVdma ${SRC_config} )
#TARGET_LINK_LIBRARIES( configVdma  ${OpenCV_LIBS} )


SET(SRC_stereo_slow
        src/stereo_slow.cpp
        src/v4l2grab_2.cpp
        src/vga_modes.h
)

ADD_EXECUTABLE( stereo_slow ${SRC_stereo_slow} )
TARGET_LINK_LIBRARIES( stereo_slow  ${OpenCV_LIBS} )


ADD_EXECUTABLE(stereo_cpu  src/stereo_cpu.cpp )

TARGET_LINK_LIBRARIES(stereo_cpu   ${OpenCV_LIBS})


#ADD_EXECUTABLE( stereo_hwAccel_rt   src/stereo_hwAccel_rt.cpp )



ADD_EXECUTABLE(stereo_FPGA_camCap4Cali  src/stereo_FPGA_camCap4Cali.cpp )

TARGET_LINK_LIBRARIES(stereo_FPGA_camCap4Cali   ${OpenCV_LIBS})


ADD_EXECUTABLE(stereo_FPGA_softUcal  src/stereo_FPGA_softUcal.cpp )
TARGET_LINK_LIBRARIES(stereo_FPGA_softUcal   ${OpenCV_LIBS})

ADD_EXECUTABLE(stereo_FPGA_hardUcal  src/stereo_FPGA_hardUcal.cpp )
TARGET_LINK_LIBRARIES(stereo_FPGA_hardUcal   ${OpenCV_LIBS})

ADD_EXECUTABLE(stereo_FPGA_hardUcal_realtime  src/stereo_FPGA_hardUcal_realtime.cpp )
TARGET_LINK_LIBRARIES(stereo_FPGA_hardUcal_realtime   ${OpenCV_LIBS})

