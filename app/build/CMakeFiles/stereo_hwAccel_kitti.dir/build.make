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
CMAKE_SOURCE_DIR = /media/brian/PRO/PROJ/StereoFPGA/app

# The top-level build directory on which CMake was run.
CMAKE_BINARY_DIR = /media/brian/PRO/PROJ/StereoFPGA/app/build

# Include any dependencies generated for this target.
include CMakeFiles/stereo_hwAccel_kitti.dir/depend.make

# Include the progress variables for this target.
include CMakeFiles/stereo_hwAccel_kitti.dir/progress.make

# Include the compile flags for this target's objects.
include CMakeFiles/stereo_hwAccel_kitti.dir/flags.make

CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.o: CMakeFiles/stereo_hwAccel_kitti.dir/flags.make
CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.o: ../src/stereo_hwAccel_kitti.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/media/brian/PRO/PROJ/StereoFPGA/app/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_1) "Building CXX object CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.o"
	arm-xilinx-linux-gnueabi-g++  $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.o -c /media/brian/PRO/PROJ/StereoFPGA/app/src/stereo_hwAccel_kitti.cpp

CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.i"
	arm-xilinx-linux-gnueabi-g++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /media/brian/PRO/PROJ/StereoFPGA/app/src/stereo_hwAccel_kitti.cpp > CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.i

CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.s"
	arm-xilinx-linux-gnueabi-g++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /media/brian/PRO/PROJ/StereoFPGA/app/src/stereo_hwAccel_kitti.cpp -o CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.s

# Object files for target stereo_hwAccel_kitti
stereo_hwAccel_kitti_OBJECTS = \
"CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.o"

# External object files for target stereo_hwAccel_kitti
stereo_hwAccel_kitti_EXTERNAL_OBJECTS =

stereo_hwAccel_kitti: CMakeFiles/stereo_hwAccel_kitti.dir/src/stereo_hwAccel_kitti.cpp.o
stereo_hwAccel_kitti: CMakeFiles/stereo_hwAccel_kitti.dir/build.make
stereo_hwAccel_kitti: CMakeFiles/stereo_hwAccel_kitti.dir/link.txt
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --bold --progress-dir=/media/brian/PRO/PROJ/StereoFPGA/app/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_2) "Linking CXX executable stereo_hwAccel_kitti"
	$(CMAKE_COMMAND) -E cmake_link_script CMakeFiles/stereo_hwAccel_kitti.dir/link.txt --verbose=$(VERBOSE)

# Rule to build all files generated by this target.
CMakeFiles/stereo_hwAccel_kitti.dir/build: stereo_hwAccel_kitti

.PHONY : CMakeFiles/stereo_hwAccel_kitti.dir/build

CMakeFiles/stereo_hwAccel_kitti.dir/clean:
	$(CMAKE_COMMAND) -P CMakeFiles/stereo_hwAccel_kitti.dir/cmake_clean.cmake
.PHONY : CMakeFiles/stereo_hwAccel_kitti.dir/clean

CMakeFiles/stereo_hwAccel_kitti.dir/depend:
	cd /media/brian/PRO/PROJ/StereoFPGA/app/build && $(CMAKE_COMMAND) -E cmake_depends "Unix Makefiles" /media/brian/PRO/PROJ/StereoFPGA/app /media/brian/PRO/PROJ/StereoFPGA/app /media/brian/PRO/PROJ/StereoFPGA/app/build /media/brian/PRO/PROJ/StereoFPGA/app/build /media/brian/PRO/PROJ/StereoFPGA/app/build/CMakeFiles/stereo_hwAccel_kitti.dir/DependInfo.cmake --color=$(COLOR)
.PHONY : CMakeFiles/stereo_hwAccel_kitti.dir/depend

