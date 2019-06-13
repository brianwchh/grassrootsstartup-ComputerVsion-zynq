cmake_minimum_required (VERSION 2.6) 

PROJECT(stereo)
SET(PROJECT_VERSION "0.1")

 
#################################################################################################
# Set this to the version of OpenCV that you need.
#   arm    : use zynq cross compile version
#   system : use system default version 
########################################################################################################

 set(OPENCV_LIB "system")

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




ADD_EXECUTABLE(stereo_cpu  src/stereo_cpu.cpp )

TARGET_LINK_LIBRARIES(stereo_cpu   ${OpenCV_LIBS})


