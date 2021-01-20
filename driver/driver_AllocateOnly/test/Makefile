KERN_DIR=/opt/FILES/Myfiles/Xilinx-linux-files/linux-xlnx
export CROSS_COMPILE=arm-xilinx-linux-gnueabi-
export ARCH=arm

all:
	make -C $(KERN_DIR) M=`pwd` modules 

clean:
	make -C $(KERN_DIR) M=`pwd` modules clean
	rm -rf modules.order

obj-m	+= hello.o

