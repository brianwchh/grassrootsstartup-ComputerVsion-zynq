KERN_DIR=/media/brian/Files/xilinxFiles/ZynqFiles/kernel/linux
EXTRA_CFLAGS=-I$(PWD)/Xinclude
export CROSS_COMPILE=arm-xilinx-linux-gnueabi-
export ARCH=arm



all:
	make -C $(KERN_DIR) M=`pwd` modules

clean:
	make -C $(KERN_DIR) M=`pwd` modules clean
	rm -rf modules.order

obj-m	+= my_vdma.o
obj-m	+= my_vtc.o
obj-m   += my_dynclk.o
obj-m   += vhdmi.o
obj-m += usbCamera.o
obj-m += my_vdma_4cali.o
obj-m += my_vdma_4cali_long.o
obj-m += my_vdma_old.o
obj-m += my_vdma_long.o
obj-m += my_vdma_short.o