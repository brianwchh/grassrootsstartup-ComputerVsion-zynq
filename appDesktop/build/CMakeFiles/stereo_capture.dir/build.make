# CMAKE generated file: DO NOT EDIT!
# Generated by "Unix Makefiles" Generator, CMake Version 3.13

# Delete rule output on recipe failure.
.DELETE_ON_ERROR:


#=============================================================================
# Special targets provided by cmake.

# Disable implicit rules so canonical targets will work.
.SUFFIXES:


# Remove some rules from gmake that .SUFFIXES does not remove.
SUFFIXES =

.SUFFIXES: .hpux_make_needs_suffix_list


# Suppress display of executed commands.
$(VERBOSE).SILENT:


# A target that is always out of date.
cmake_force:

.PHONY : cmake_force

#=============================================================================
# Set environment variables for the build.

# The shell in which to execute make rules.
SHELL = /bin/sh

# The CMake executable.
CMAKE_COMMAND = /usr/local/bin/cmake

# The command to remove a file.
RM = /usr/local/bin/cmake -E remove -f

# Escaping for special characters.
EQUALS = =

# The top-level source directory on which CMake was run.
CMAKE_SOURCE_DIR = /media/brian/PRO/PROJ/StereoFPGA/appDesktop

# The top-level build directory on which CMake was run.
CMAKE_BINARY_DIR = /media/brian/PRO/PROJ/StereoFPGA/appDesktop/build

# Include any dependencies generated for this target.
include CMakeFiles/stereo_capture.dir/depend.make

# Include the progress variables for this target.
include CMakeFiles/stereo_capture.dir/progress.make

# Include the compile flags for this target's objects.
include CMakeFiles/stereo_capture.dir/flags.make

CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.o: CMakeFiles/stereo_capture.dir/flags.make
CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.o: ../src/stereo_capture.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/media/brian/PRO/PROJ/StereoFPGA/appDesktop/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_1) "Building CXX object CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.o"
	/usr/bin/c++  $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.o -c /media/brian/PRO/PROJ/StereoFPGA/appDesktop/src/stereo_capture.cpp

CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.i"
	/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /media/brian/PRO/PROJ/StereoFPGA/appDesktop/src/stereo_capture.cpp > CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.i

CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.s"
	/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /media/brian/PRO/PROJ/StereoFPGA/appDesktop/src/stereo_capture.cpp -o CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.s

CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.o: CMakeFiles/stereo_capture.dir/flags.make
CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.o: ../src/v4l2grab_2.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/media/brian/PRO/PROJ/StereoFPGA/appDesktop/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_2) "Building CXX object CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.o"
	/usr/bin/c++  $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.o -c /media/brian/PRO/PROJ/StereoFPGA/appDesktop/src/v4l2grab_2.cpp

CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.i"
	/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /media/brian/PRO/PROJ/StereoFPGA/appDesktop/src/v4l2grab_2.cpp > CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.i

CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.s"
	/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /media/brian/PRO/PROJ/StereoFPGA/appDesktop/src/v4l2grab_2.cpp -o CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.s

# Object files for target stereo_capture
stereo_capture_OBJECTS = \
"CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.o" \
"CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.o"

# External object files for target stereo_capture
stereo_capture_EXTERNAL_OBJECTS =

stereo_capture: CMakeFiles/stereo_capture.dir/src/stereo_capture.cpp.o
stereo_capture: CMakeFiles/stereo_capture.dir/src/v4l2grab_2.cpp.o
stereo_capture: CMakeFiles/stereo_capture.dir/build.make
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_videostab.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_ts.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_superres.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_stitching.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_contrib.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_nonfree.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_ocl.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_gpu.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_photo.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_objdetect.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_legacy.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_video.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_ml.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_calib3d.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_features2d.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_highgui.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_imgproc.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_flann.so.2.4.8
stereo_capture: /usr/lib/x86_64-linux-gnu/libopencv_core.so.2.4.8
stereo_capture: CMakeFiles/stereo_capture.dir/link.txt
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --bold --progress-dir=/media/brian/PRO/PROJ/StereoFPGA/appDesktop/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_3) "Linking CXX executable stereo_capture"
	$(CMAKE_COMMAND) -E cmake_link_script CMakeFiles/stereo_capture.dir/link.txt --verbose=$(VERBOSE)

# Rule to build all files generated by this target.
CMakeFiles/stereo_capture.dir/build: stereo_capture

.PHONY : CMakeFiles/stereo_capture.dir/build

CMakeFiles/stereo_capture.dir/clean:
	$(CMAKE_COMMAND) -P CMakeFiles/stereo_capture.dir/cmake_clean.cmake
.PHONY : CMakeFiles/stereo_capture.dir/clean

CMakeFiles/stereo_capture.dir/depend:
	cd /media/brian/PRO/PROJ/StereoFPGA/appDesktop/build && $(CMAKE_COMMAND) -E cmake_depends "Unix Makefiles" /media/brian/PRO/PROJ/StereoFPGA/appDesktop /media/brian/PRO/PROJ/StereoFPGA/appDesktop /media/brian/PRO/PROJ/StereoFPGA/appDesktop/build /media/brian/PRO/PROJ/StereoFPGA/appDesktop/build /media/brian/PRO/PROJ/StereoFPGA/appDesktop/build/CMakeFiles/stereo_capture.dir/DependInfo.cmake --color=$(COLOR)
.PHONY : CMakeFiles/stereo_capture.dir/depend

