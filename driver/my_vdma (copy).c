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

#include <linux/amba/xilinx_dma.h>
#include <linux/bitops.h>
#include <linux/dmapool.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/of_dma.h>
#include <linux/of_platform.h>
#include <linux/of_irq.h>
#include <linux/of_device.h>
#include <linux/slab.h>
#include <linux/dma-mapping.h>
#include <linux/poll.h>
#include <linux/cdev.h>
#include <linux/fs.h>
#include <linux/kernel.h>
#include <linux/delay.h>
#include <linux/uaccess.h>
#include <asm/io.h>

/****************** Xilinx files *******************/
/*
 * This driver currently supports 3 frames.
 */
#define DISPLAY_NUM_FRAMES 3
/*
 * XPAR redefines
 */
#define DYNCLK_BASEADDR XPAR_AXI_DYNCLK_0_BASEADDR
#define VGA_VDMA_ID XPAR_AXIVDMA_0_DEVICE_ID
#define DISP_VTC_ID XPAR_VTC_0_DEVICE_ID
#define VID_VTC_IRPT_ID XPS_FPGA3_INT_ID
#define VID_GPIO_IRPT_ID XPS_FPGA4_INT_ID
#define SCU_TIMER_ID XPAR_SCUTIMER_DEVICE_ID
#define UART_BASEADDR XPAR_PS7_UART_1_BASEADDR

#define vdma_contrl_address 0x43000000

char *pFrames_phys[DISPLAY_NUM_FRAMES]; //array of pointers to the frame buffers

/**
 * This typedef contains the hardware configuration information for a VDMA
 * device. Each VDMA device should have a configuration structure associated
 * with it.
 */

typedef struct {
    int irq;
    unsigned int mem_phy_start;
    unsigned int mem_phy_end;
    void __iomem *base_addr_vir;
} XAxiVdma_Config;


static char * VIDEO_BASEADDR;
static u32 src_phys;
#define GET_VIRTUAL_ADDRESS 0
#define GET_PHY_ADDRESS     1
#define VIDEO_WIDTH         1280
#define VIDEO_HEIGHT        720


static struct class *cls;
static struct cdev videobuf_cdev;

static int major = 0;

#define BUF_SIZE  (1280 * 720 * 4 * 6 )
#define FRAME_BUFFER_SIZE (1280 * 720 * 4)


// MM2S registers offsets
#define MM2S_VDMACR  0x00
#define MM2S_Start_Address1 0x98
#define MM2S_Start_Address2 0x60
#define MM2S_Start_Address3 0x64
#define MM2S_FRMDLY_STRIDE  0x58
#define MM2S_HSIZE          0x54
#define MM2S_VSIZE          0x50
// S2MM registers offsets
#define S2MM_VDMACR      0x30
#define S2MM_Start_Address1  0xAC
#define S2MM_Start_Address2  0xB0
#define S2MM_Start_Address3  0xB4
#define S2MM_FRMDLY_STRIDE   0xA8
#define S2MM_HSIZE           0xA4
#define S2MM_VSIZE           0xA0


#define XAxiVdma_WriteReg(BaseAddress, RegOffset, Data)   \
    iowrite32((Data) , (BaseAddress) + (RegOffset))


static ssize_t readSomeAttr(struct device *dev, struct device_attribute *attr, char *buf)
{
	printk("virtural address = ox%x08\n",VIDEO_BASEADDR) ;
	printk("physical address = ox%x08\n",src_phys) ;
    // sprintf(buf, "Busy is:%d\n", isBusyResp);
    return strlen(buf)+1;
}

// Control the execution of the IP core
static ssize_t writeSomeAttr(struct device *dev, struct device_attribute *attr,
		const char *buf, size_t count)
{

	printk(KERN_ALERT "Received %d bytes attribute %s\n",(int)count,buf);
	if(buf[0] == '='){
		printk("got = \n");
	}

	return count ;
}

// Define an attribute "parCrtl" (it will expanded to dev_attr_"parCrtl"
// Define an attribute "isBusy" (it will expanded to dev_attr_"isBusy"
static DEVICE_ATTR(parCrtl, S_IWUSR, NULL, writeSomeAttr);
// static DEVICE_ATTR(isBusy, S_IRUGO, readSomeAttr, NULL);
static DEVICE_ATTR(getAdrr, S_IRUGO, readSomeAttr, NULL);

static u32 video_buf_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	switch (cmd)
	{
		case GET_VIRTUAL_ADDRESS :
		{
			printk(KERN_ALERT "kerneal VIRTUAL_ADDRESS = 0x%08X\n",VIDEO_BASEADDR);
			printk(KERN_ALERT "kerneal cmd = 0x%08X\n",cmd);
			return (u32) VIDEO_BASEADDR ;
		}

		case GET_PHY_ADDRESS :
		{
			printk(KERN_ALERT "kerneal PHY_ADDRESS = 0x%08X\n",src_phys);
			printk(KERN_ALERT "kerneal cmd = 0x%08X\n",cmd);
			return src_phys ;
		}
	}

	return -1;
}

static struct file_operations fops = {
	.unlocked_ioctl  = video_buf_ioctl,
};

/**
 * xilinx_vdma_probe - Driver probe function
 * @pdev: Pointer to the platform_device structure
 *
 * Return: '0' on success and failure value on error
 */
static int xilinx_vdma_probe(struct platform_device *pdev)
{
	dev_t devid;
	struct device *subdev;

	struct device *dev = &pdev->dev;

	struct resource *r_irq; /* Interrupt resources */
	struct resource *r_mem; /* IO mem resources */

	int rc = 0 ;

	XAxiVdma_Config *XAxiVdma_Config_ptr = NULL;


	printk(" **************************************** \n");
	printk("     probing vdma device tree \n");
	printk(" **************************************** \n");

	// Get data of type IORESOURCE_MEM(reg-addr) from the device-tree
	// Other types defined here:
	// http://lxr.free-electrons.com/source/include/linux/ioport.h#L33
	r_mem = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!r_mem) {
		dev_err(dev, "invalid address\n");
		return -ENODEV;
	}
	// Allocate memory (continuous physical)to hold simpMod_local struct
	XAxiVdma_Config_ptr = (XAxiVdma_Config *) kmalloc(sizeof(XAxiVdma_Config), GFP_KERNEL);
	if (!XAxiVdma_Config_ptr) {
		printk("Cound not allocate XAxiVdma_Config device\n");
		return -ENOMEM;
	}

	// save the start and end address on the config structure   why r_mem->start is not right should be 0x4300_0000
	XAxiVdma_Config_ptr->mem_phy_start = r_mem->start ;
	XAxiVdma_Config_ptr->mem_phy_end  = r_mem->end  ;
	// XAxiVdma_Config_ptr->mem_phy_start = 0x43000000 ;
	// XAxiVdma_Config_ptr->mem_phy_end  =  0x4300FFFF ;

	dev_set_drvdata(dev, XAxiVdma_Config_ptr);   // pass the pointer to dev ??? why ??

#if 1
	// Ask the kernel the memory region defined on the device-tree and
	// prevent other drivers to overlap on this region
	// This is needed before the ioremap
	// reg = <0x41220000 0x10000>;
	if (!request_mem_region(XAxiVdma_Config_ptr->mem_phy_start,
				XAxiVdma_Config_ptr->mem_phy_end - XAxiVdma_Config_ptr->mem_phy_start + 1,
				"my_xilinx-vdma")) {
		dev_err(dev, "Couldn't lock memory region at %p\n",
			(void *)XAxiVdma_Config_ptr->mem_phy_start);
		rc = -EBUSY;
		goto error1;
	}
	printk("vdma controller start address = 0x%08X\n", XAxiVdma_Config_ptr->mem_phy_start);
	printk("vdma controller end  address =  0x%08X\n" ,XAxiVdma_Config_ptr->mem_phy_end);

	// Get an virtual address from the device physical address with a
	// range size: lp->mem_end - lp->mem_start + 1
	XAxiVdma_Config_ptr->base_addr_vir = ioremap(XAxiVdma_Config_ptr->mem_phy_start,
				XAxiVdma_Config_ptr->mem_phy_end - XAxiVdma_Config_ptr->mem_phy_start + 1);
	if (!XAxiVdma_Config_ptr->base_addr_vir) {
		dev_err(dev, "vdma: Could not allocate iomem\n");
		rc = -EIO;
		goto error1;
	}
#endif

#if 0
	/* Request and map I/O memory */
    XAxiVdma_Config_ptr->base_addr_vir = devm_ioremap_resource(&pdev->dev, r_mem);   //
	if (IS_ERR(XAxiVdma_Config_ptr->base_addr_vir))
		return PTR_ERR(XAxiVdma_Config_ptr->base_addr_vir);
#endif
	// u32 register0=(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir);
	printk("readed data = 0x%08X\n",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir));
	printk("remapped vdma controller address = 0x%08X\n",XAxiVdma_Config_ptr->base_addr_vir);


	/* 1. allocate a continuous memory for buffer allocation */
	VIDEO_BASEADDR = (char *)dma_alloc_writecombine(NULL, BUF_SIZE, &src_phys, GFP_KERNEL);
	if (NULL == VIDEO_BASEADDR)
	{
		printk(KERN_ALERT "can't alloc buffer for VIDEO_BASEADDR\n");
		return -ENOMEM;
	}

	memset(VIDEO_BASEADDR, 0x00, BUF_SIZE);
	// int i = 0 , j = 0 ;
	// for(i = 0 ; i < 20 ; i++){
	// 	printk(" Memory test : readed data = 0x%08X  @address =  0x%08X\n ",(u32)ioread32(VIDEO_BASEADDR + i),VIDEO_BASEADDR + i);
	// }

	//  fill in one frame data for test
    int iPixelAddr = 0 ;
    int heigh = 720 ;
    int width = 1280 ;
    int stride = 1280 * 4 ;
    int r,c ;
    for( r=0 ; r < heigh; r++){
        for( c=0; c < width*4 ; c+=4)
        {
            if(r == 16 || c == 16 || r == heigh -16 || c == width * 4 -16 )
                iowrite32(0x0000FF00,  VIDEO_BASEADDR  + iPixelAddr +  c   );
            else
                iowrite32(0x00FF0000 , VIDEO_BASEADDR  + iPixelAddr +  c  );
        }
        iPixelAddr += stride ;
    }


	printk(KERN_ALERT "VIRTUAL_ADDRESS = 0x%08X\n",VIDEO_BASEADDR);
	printk(KERN_ALERT "PHY_ADDRESS = 0x%08X\n",src_phys);

	pFrames_phys[0]=src_phys ;
	pFrames_phys[1]=src_phys + FRAME_BUFFER_SIZE ;
	pFrames_phys[2]=src_phys + FRAME_BUFFER_SIZE * 2 ;



	// ****************** NORMAL Device diver *************************
	// register a range of char device numbers
	if (alloc_chrdev_region(&devid, 0, 1, "videobuff") < 0){
		printk(KERN_ALERT "alloc_chrdev_region failed\n");
		return -1;
	}
	major = MAJOR(devid);

	cdev_init(&videobuf_cdev, &fops);
	cdev_add(&videobuf_cdev, devid, 1);


	cls = class_create(THIS_MODULE, "videobuf");
	subdev=device_create(cls, NULL, MKDEV(major, 0), NULL, "vdma"); /* /dev/dma */
	if (IS_ERR(subdev))
	{
		printk(KERN_ALERT "device create error\n");
		return PTR_ERR(subdev);
	}

 	// device_create_file: Create sysfs attribute file for device on the sysfs (/sys/class/"class_name"/"attribute")
	// Create the attribute file on /sysfs/class/CLASS_TUT/ called
	// parCrtl and isBusy
	if (device_create_file(subdev, &dev_attr_parCrtl) < 0){
		printk(KERN_ALERT "Attribute device creation failed\n");
		return -1;
	}
	if (device_create_file(subdev, &dev_attr_getAdrr) < 0){
		printk(KERN_ALERT "Attribute device creation failed\n");
		return -1;
	}

	// printk("readed data = 0x%08X   @MM2S_VDMACR          0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_VDMACR),XAxiVdma_Config_ptr->base_addr_vir + MM2S_VDMACR);
	// printk("readed data = 0x%08X   @MM2S_Start_Address1  0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_Start_Address1),XAxiVdma_Config_ptr->base_addr_vir + MM2S_Start_Address1);
	// printk("readed data = 0x%08X   @MM2S_FRMDLY_STRIDE   0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_FRMDLY_STRIDE),XAxiVdma_Config_ptr->base_addr_vir + MM2S_FRMDLY_STRIDE);
	// printk("readed data = 0x%08X   @MM2S_HSIZE           0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_HSIZE),XAxiVdma_Config_ptr->base_addr_vir + MM2S_HSIZE);
	// printk("readed data = 0x%08X   @MM2S_VSIZE           0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_VSIZE),XAxiVdma_Config_ptr->base_addr_vir + MM2S_VSIZE);



    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000000  ,  0x00010002);   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000054  ,  0x00001400);   // MM2S_HSIZE   1280 * 4
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000058  ,  0x00001400);   // MM2S_FRMDLY_STRIDE    // note that here stride =  1280 * 4
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x0000005C  ,  src_phys);   // 5c - 98 : MM2S_START_ADDRESS
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000000  ,  0x00010003);
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000050  ,  0x000002D0);   // MM2S_VSIZE    720
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000028  ,  0x00000000);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000000  ,  0x00010001);   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run

	return 0 ;

error1:
	dev_set_drvdata(dev, NULL);
	release_mem_region(XAxiVdma_Config_ptr->mem_phy_start,
				XAxiVdma_Config_ptr->mem_phy_end - XAxiVdma_Config_ptr->mem_phy_start + 1);

	kfree(XAxiVdma_Config_ptr);
	return rc;

}

/**
 * xilinx_vdma_remove - Driver remove function
 * @pdev: Pointer to the platform_device structure
 *
 * Return: Always '0'
 */
static int xilinx_vdma_remove(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	XAxiVdma_Config *XAxiVdma_Config_ptr = dev_get_drvdata(dev);
	// free_irq(XAxiVdma_Config_ptr->irq, XAxiVdma_Config_ptr);
	release_mem_region(XAxiVdma_Config_ptr->mem_phy_start,
				XAxiVdma_Config_ptr->mem_phy_end - XAxiVdma_Config_ptr->mem_phy_start + 1);

	iounmap(XAxiVdma_Config_ptr->base_addr_vir);   // vdma controll register address
	dma_free_writecombine(NULL, BUF_SIZE, VIDEO_BASEADDR, src_phys);
	device_destroy(cls, MKDEV(major, 0));
	class_destroy(cls);
	unregister_chrdev(major, "videobuf");
	printk(KERN_ALERT "vhdma driver removed\n") ;
	return 0;
}


static const struct of_device_id xilinx_vdma_of_ids[] = {
	{ .compatible = "xlnx,axi-vdma-my",},
	{}
};

MODULE_DEVICE_TABLE(of, xilinx_vdma_of_ids);

static struct platform_driver xilinx_vdma_driver = {
	.driver = {
		.name = "my_xilinx-vdma",
		.owner = THIS_MODULE,
		.of_match_table = xilinx_vdma_of_ids,
	},
	.probe = xilinx_vdma_probe,
	.remove = xilinx_vdma_remove,
};

static int __init myvdma_init(void)
{
	printk("my vdma driver.\n");

	return platform_driver_register(&xilinx_vdma_driver);
}

static void __exit myvdma_exit(void)
{
	platform_driver_unregister(&xilinx_vdma_driver);
	printk(KERN_ALERT "8888888888 .\n");
}

// module_platform_driver(xilinx_vdma_driver);   // module_init(&xilinx_vdma_driver) + module_exit(&xilinx_vdma_driver) ???

module_init(myvdma_init);
module_exit(myvdma_exit);

MODULE_AUTHOR("BrianWu");
MODULE_DESCRIPTION("Xilinx_VDMA_driver");
MODULE_LICENSE("GPL");
