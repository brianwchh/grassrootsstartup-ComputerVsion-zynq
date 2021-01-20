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



u32 pFrames_phys[8]; //array of pointers to the frame buffers


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

void __iomem *VDMA1_virtual_address ;
void __iomem *VDMA2_virtual_address ;
void __iomem *VDMA3_virtual_address ;
void __iomem *VDMA4_virtual_address ;
void __iomem *VDMA5_virtual_address ;

void __iomem *stereo_virtual_address ;

static char * VIDEO_BASEADDR;
static u32 src_phys;

u32 vdma3_writeBufferIndx = 0 ;
u32 vdma2_writeBufferIndx = 0 ;
u32 readRegValue =0 ; 

// #define START_ONE_FRAME 0
// #define GET_PHY_ADDRESS     1

// /* 定义幻数 */  
#define MEMDEV_IOC_MAGIC  'k'  
  
/* 定义命令 */  
#define MEMDEV_IOCPRINT         _IO(MEMDEV_IOC_MAGIC, 1)  
#define MEMDEV_IOCGETPYADDRESS _IOR(MEMDEV_IOC_MAGIC, 2, int)  
#define SET_COLOR_MAP     _IOW(MEMDEV_IOC_MAGIC, 3, int)  
#define START_ONE_FRAME   _IOW(MEMDEV_IOC_MAGIC, 4, int)   
#define SET_S2MM_PRK_NUM   _IOW(MEMDEV_IOC_MAGIC, 5, int)   
#define SET_MM2S_PRK_NUM   _IOW(MEMDEV_IOC_MAGIC, 6, int)   
#define CONFIG_REG_ADDR    _IOW(MEMDEV_IOC_MAGIC,7, int)
#define CONFIG_REG_VAL    _IOW(MEMDEV_IOC_MAGIC,8, int)
#define MEMDEV_IOC_MAXNR 9 


#define VIDEO_WIDTH         1280
#define VIDEO_HEIGHT        720


static struct class *cls;
static struct cdev videobuf_cdev;

static int major = 0;

static int RegAddr , RegVal ;

#define BUF_SIZE  (VIDEO_HEIGHT * VIDEO_WIDTH * 4 * 8 )
#define FRAME_BUFFER_SIZE (VIDEO_HEIGHT * VIDEO_WIDTH * 4)


#define vdma0_contrl_address 0x43000000
#define stereo_control_address 0x43C20000


#define   VDMA1_CONTROL_ADDRESS  0x43010000
#define   VDMA2_CONTROL_ADDRESS  0x43020000
#define   VDMA3_CONTROL_ADDRESS  0x43030000
#define   VDMA4_CONTROL_ADDRESS  0x43040000
#define   VDMA5_CONTROL_ADDRESS  0x43050000

#define   S2MM_VDMACR            0x00000030
#define   S2MM_START_ADDRESS0    0x000000AC
#define   S2MM_START_ADDRESS1    0x000000B0
#define   S2MM_START_ADDRESS2    0x000000B4
#define   PARK_PTR_REG           0x00000028
#define   S2MM_FRMDLY_STRIDE     0x000000A8
#define   S2MM_HSIZE             0x000000A4
#define   S2MM_VSIZE             0x000000A0

#define   MM2S_VDMACR            0x00000000
#define   MM2S_START_ADDRESS0    0x0000005C
#define   MM2S_START_ADDRESS1    0x00000060
#define   MM2S_START_ADDRESS2    0x00000064
#define   MM2S_FRMDLY_STRIDE     0x00000058
#define   MM2S_HSIZE             0x00000054
#define   MM2S_VSIZE             0x00000050


#define MM2S_PARK_BIT_MASK  (0x1F) << 0
#define S2MM_PARK_BIT_MASK  (0x1F) << 8

#define VDMA0_MM2S_IMAGE_WIDTH 1280   // 1280
#define VDMA0_MM2S_IMAGE_HEIGHT 720    // 720

#define MM2S_IMAGE_WIDTH 1280   // 1280
#define MM2S_IMAGE_HEIGHT 360    // 720

#define S2MM_IMAGE_WIDTH 640   // 1280
#define S2MM_IMAGE_HEIGHT 480    // 720

#define VDMA1_STRIDE 1280 * 4  // 1280 × 4


#define XAxiVdma_WriteReg(BaseAddress, RegOffset, Data)   \
    iowrite32((Data) , (BaseAddress + RegOffset))

#define XAxiVdma_ReadReg(BaseAddress , RegOffset) \
    ioread32(BaseAddress + RegOffset)

//  /sys/devices/virtual/videobuf/vdma
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

	// printk(KERN_ALERT "Received %d bytes : %d\n",(int)count,buf[0]);
	if(buf[0] == '0')  // 48
	{
		iowrite32(0,stereo_virtual_address + 0);
	}
	else if(buf[0] == '1')  // 49
	{
		iowrite32(1,stereo_virtual_address + 0);
	}
	else {
		printk(KERN_ALERT " wrong input number, try :  echo '0/1' >  parCrtl   \n");
	}
	
	// if(buf[0] == '='){
	// 	printk("got = \n");
	// }
	// iowrite32(buf[0],stereo_virtual_address + 0);

	return count ;
}

// Define an attribute "parCrtl" (it will expanded to dev_attr_"parCrtl"
// Define an attribute "isBusy" (it will expanded to dev_attr_"isBusy"
static DEVICE_ATTR(parCrtl, S_IWUSR, NULL, writeSomeAttr);
// static DEVICE_ATTR(isBusy, S_IRUGO, readSomeAttr, NULL);
static DEVICE_ATTR(getAdrr, S_IRUGO, readSomeAttr, NULL);

// static u32 video_buf_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
// {
// 	int nn = 0 ;
// 	int ret ;
// 	int ioarg = 1; 

// 	switch (cmd)
// 	{
// 		case START_ONE_FRAME :
// 		{
// 			// printk(" starting a new frame \n");
// 			iowrite32( 1, stereo_virtual_address + 0);
// 			// for(nn=0; nn < 1000000; nn++);
// 			iowrite32( 0, stereo_virtual_address + 0);  // generate a falling edge to triger a new transform

// 			break;
// 		}

// 		case GET_PHY_ADDRESS :
// 		{
// 			printk(KERN_ALERT "kerneal PHY_ADDRESS = 0x%08X\n",src_phys);
// 			// printk(KERN_ALERT "kerneal cmd = 0x%08X\n",cmd);
// 			return src_phys ;
// 		}

// 		case SET_COLOR_MAP :
// 		{
// 			printk(KERN_ALERT " set depth type \n\r");
// 			ret = __get_user(ioarg, (int *)arg);  
//         	printk("<--- In Kernel ioarg = %d --->\n\n",ioarg);  
//         	iowrite32( ioarg, stereo_virtual_address + 8);  // generate a falling edge to triger a new transform
//         	break;  
// 		}
// 	}

// 	return ret;
// }


/*IO操作*/  

int video_buf_ioctl(struct file *filp,  
                 unsigned int cmd, unsigned long arg)  
{  
  
    int err = 0;  
    int ret = 0;  
    int ioarg = 0;  
      
    /* 检测命令的有效性 */  
    if (_IOC_TYPE(cmd) != MEMDEV_IOC_MAGIC)   
        return -EINVAL;  
    if (_IOC_NR(cmd) > MEMDEV_IOC_MAXNR)   
        return -EINVAL;  
  
    /* 根据命令类型，检测参数空间是否可以访问 */  
    if (_IOC_DIR(cmd) & _IOC_READ)  
        err = !access_ok(VERIFY_WRITE, (void *)arg, _IOC_SIZE(cmd));  
    else if (_IOC_DIR(cmd) & _IOC_WRITE)  
        err = !access_ok(VERIFY_READ, (void *)arg, _IOC_SIZE(cmd));  
    if (err)   
        return -EFAULT;  
  
    /* 根据命令，执行相应的操作 */  
    switch(cmd) {  
  
      /* 打印当前设备信息 */  
      case MEMDEV_IOCPRINT:  
	        printk("<--- CMD MEMDEV_IOCPRINT Done--->\n\n");  
	        break;  
        
      /* 获取参数 */  
      case MEMDEV_IOCGETPYADDRESS:    
	        // printk("physical address = %08X\n\r",src_phys) ;
	        ret = __put_user((u32)src_phys, (u32 *)arg);  
	        break;  
        
      /* 设置参数 */  
      case SET_COLOR_MAP:   
			ret = __get_user(ioarg, (int *)arg);   
			iowrite32( ioarg, stereo_virtual_address + 8); 
			// printk("setting value = %08x\n\r", ioarg) ;
			break;  

      case START_ONE_FRAME : 
			ret = __get_user(ioarg, (int *)arg);
			iowrite32( ioarg, stereo_virtual_address + 0);  	
			break ;

	  case SET_S2MM_PRK_NUM : 
	  		ret = __get_user(ioarg, (int *)arg); 
	  		// set S2MM parking frame index  VDMA2
		    readRegValue = XAxiVdma_ReadReg(VDMA2_virtual_address,PARK_PTR_REG);
		    readRegValue = readRegValue & (~S2MM_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
		    readRegValue = readRegValue | ((ioarg << 8) & S2MM_PARK_BIT_MASK) ;
		    XAxiVdma_WriteReg(VDMA2_virtual_address, PARK_PTR_REG  ,  readRegValue);   

 	  		// set S2MM parking frame index  VDMA3
		    readRegValue = XAxiVdma_ReadReg(VDMA3_virtual_address,PARK_PTR_REG);
		    readRegValue = readRegValue & (~S2MM_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
		    readRegValue = readRegValue | ((ioarg << 8) & S2MM_PARK_BIT_MASK) ;
		    XAxiVdma_WriteReg(VDMA3_virtual_address, PARK_PTR_REG  ,  readRegValue);   

		    // printk("set s2mm_park_idx = %d\n",(readRegValue & S2MM_PARK_BIT_MASK) >> 8) ;

	  case SET_MM2S_PRK_NUM : 
	  		ret = __get_user(ioarg, (int *)arg); 
	  		// set S2MM parking frame index  VDMA2
		    readRegValue = XAxiVdma_ReadReg(VDMA4_virtual_address,PARK_PTR_REG);
		    readRegValue = readRegValue & (~MM2S_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
		    readRegValue = readRegValue | ((ioarg << 0) & MM2S_PARK_BIT_MASK) ;
		    XAxiVdma_WriteReg(VDMA4_virtual_address, PARK_PTR_REG  ,  readRegValue);   

 	  		// set S2MM parking frame index  VDMA3
		    readRegValue = XAxiVdma_ReadReg(VDMA5_virtual_address,PARK_PTR_REG);
		    readRegValue = readRegValue & (~MM2S_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
		    readRegValue = readRegValue | ((ioarg << 0) & MM2S_PARK_BIT_MASK) ;
		    XAxiVdma_WriteReg(VDMA5_virtual_address, PARK_PTR_REG  ,  readRegValue);   

	   case CONFIG_REG_VAL :
	   		 ret = __get_user(RegVal,(int*)arg) ;

	   case CONFIG_REG_ADDR : 
	   		ret = __get_user(RegAddr, (int*)arg) ;
	   		if (RegAddr > 64 || RegAddr < 3){
	   			// printk("address is out of range \n");
	   		}
	   		else { 
		   		iowrite32( RegVal, stereo_virtual_address + RegAddr * 4);
		   		iowrite32( 0, stereo_virtual_address + 4);
		   		printk("write address : %d     ",RegAddr) ;
		   		printk("Value : 0x%08X \n",RegVal) ;
	   		}

      default:    
        return -EINVAL;  
    }  
    return ret;  
  
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


	// printk(" **************************************** \n");
	// printk("     probing vdma device tree \n");
	// printk(" **************************************** \n");

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
	// XAxiVdma_Config_ptr->mem_phy_start = r_mem->start ;
	// XAxiVdma_Config_ptr->mem_phy_end  = r_mem->end  ;
	XAxiVdma_Config_ptr->mem_phy_start =  0x43000000 ;
	XAxiVdma_Config_ptr->mem_phy_end   =  0x4300FFFF ;

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
	// printk("vdma controller start address = 0x%08X\n", XAxiVdma_Config_ptr->mem_phy_start);
	// printk("vdma controller end  address =  0x%08X\n" ,XAxiVdma_Config_ptr->mem_phy_end);

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
	// printk("readed data = 0x%08X\n",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir));
	// printk("remapped vdma controller address = 0x%08X\n",XAxiVdma_Config_ptr->base_addr_vir);


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

	// printk(KERN_ALERT "VIRTUAL_ADDRESS = 0x%08X\n",VIDEO_BASEADDR);
	// printk(KERN_ALERT "PHY_ADDRESS = 0x%08X\n",src_phys);

	pFrames_phys[0]=src_phys ;
	pFrames_phys[1]=src_phys + FRAME_BUFFER_SIZE  ;
	pFrames_phys[2]=src_phys + FRAME_BUFFER_SIZE * 2 ;
	pFrames_phys[3]=src_phys + FRAME_BUFFER_SIZE * 3 ;
	pFrames_phys[4]=src_phys + FRAME_BUFFER_SIZE * 4 ;
	pFrames_phys[5]=src_phys + FRAME_BUFFER_SIZE * 5 ;
	pFrames_phys[6]=src_phys + FRAME_BUFFER_SIZE * 6 ;
	pFrames_phys[7]=src_phys + FRAME_BUFFER_SIZE * 7 ;

	//  fill in one frame data for test
    int iPixelAddr = 0 ;
    int heigh = 720 ;
    int width = 1280 ;
    int stride = 1280 * 4 ;
    int r,c ;
    for( r=0 ; r < heigh; r++){
        for( c=0; c < width*4 ; c+=4)
        {
            // if(r == 16 || c == 16 || r == heigh -16 || c == width * 4 -16 )
            //     iowrite32(0x0000FF00,  VIDEO_BASEADDR + FRAME_BUFFER_SIZE * 0  + iPixelAddr +  c   );
            // else
                // iowrite32( c/4 & 0xFF , VIDEO_BASEADDR + FRAME_BUFFER_SIZE * 0 + iPixelAddr +  c  );
        }
        iPixelAddr += stride ;
    }


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
	// Create the attribute file on /sys/devices/virtual/videobuf/vdma called
	// parCrtl and isBusy
	if (device_create_file(subdev, &dev_attr_parCrtl) < 0){
		printk(KERN_ALERT "Attribute device creation failed\n");
		return -1;
	}
	if (device_create_file(subdev, &dev_attr_getAdrr) < 0){
		printk(KERN_ALERT "Attribute device creation failed\n");
		return -1;
	}


    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000000  ,  0x00010002);   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000054  ,  0x00001400);   // MM2S_HSIZE   1280 * 4
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000058  ,  0x00001400);   // MM2S_FRMDLY_STRIDE    // note that here stride =  1280 * 4
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x0000005C  ,  pFrames_phys[0]);   // 5c - 98 : MM2S_START_ADDRESS
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000000  ,  0x00010003);
    
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000028  ,  0x00000000);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm
    XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000000  ,  0x00010001);   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
	XAxiVdma_WriteReg(XAxiVdma_Config_ptr->base_addr_vir, 0x00000050  ,  0x000002D0);   // MM2S_VSIZE    720

	// printk("readed data = 0x%08X   @MM2S_VDMACR          0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_VDMACR),XAxiVdma_Config_ptr->base_addr_vir + MM2S_VDMACR);
	// printk("readed data = 0x%08X   @MM2S_START_ADDRESS0  0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_START_ADDRESS0),XAxiVdma_Config_ptr->base_addr_vir + MM2S_START_ADDRESS0);
	// printk("readed data = 0x%08X   @MM2S_FRMDLY_STRIDE   0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_FRMDLY_STRIDE),XAxiVdma_Config_ptr->base_addr_vir + MM2S_FRMDLY_STRIDE);
	// printk("readed data = 0x%08X   @MM2S_HSIZE           0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_HSIZE),XAxiVdma_Config_ptr->base_addr_vir + MM2S_HSIZE);
	// printk("readed data = 0x%08X   @MM2S_VSIZE           0x%08X\n ",(u32)ioread32(XAxiVdma_Config_ptr->base_addr_vir + MM2S_VSIZE),XAxiVdma_Config_ptr->base_addr_vir + MM2S_VSIZE);


    /************************ config VDMA1    **********************************/

	if (!request_mem_region(VDMA1_CONTROL_ADDRESS,
				0xFFFF,
				"my_xilinx-vdma1")) {
		dev_err(dev, "Couldn't lock memory region at %p\n",
			(void *)VDMA1_CONTROL_ADDRESS);
		rc = -EBUSY;
		return rc;
	}

	VDMA1_virtual_address = ioremap(VDMA1_CONTROL_ADDRESS,
				0xFFFF);
	if (!VDMA1_virtual_address) {
		dev_err(dev, "vdma1: Could not allocate iomem\n");
		rc = -EIO;
		return rc;
	}

	u32 readBufferIndx = 0 ;
	u32 writeBufferIndx = 0 ;
	
	//config S2MM
	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_VDMACR  ,  0x00000001);   // S2MM_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_START_ADDRESS0  ,  pFrames_phys[0] + 640 * 4);   //   S2MM_START_ADDRESS
	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_START_ADDRESS1  ,  pFrames_phys[0] + 640 * 4);   //  S2MM_START_ADDRESS
	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_START_ADDRESS2  ,  pFrames_phys[0] + 640 * 4);   //   S2MM_START_ADDRESS
	// set S2MM parking frame index
	readRegValue = XAxiVdma_ReadReg(VDMA1_virtual_address,PARK_PTR_REG);
	readRegValue = readRegValue & (~S2MM_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
	readRegValue = readRegValue | ((writeBufferIndx << 8) & S2MM_PARK_BIT_MASK) ;
	XAxiVdma_WriteReg(VDMA1_virtual_address, PARK_PTR_REG  ,  readRegValue);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm

	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_FRMDLY_STRIDE  ,  1280 * 4 );   // S2MM_FRMDLY_STRIDE    // note that here stride =  1280 * 4
	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_HSIZE  ,          640 *  4 );   // S2MM_HSIZE   640
	XAxiVdma_WriteReg(VDMA1_virtual_address, S2MM_VSIZE  ,          480      );   // S2MM_VSIZE    480

	// config M2SS
	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_VDMACR  ,  0x00000001   );   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_START_ADDRESS0  ,  pFrames_phys[7]);   // 5c - 98 : MM2S_START_ADDRESS
	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_START_ADDRESS1  ,  pFrames_phys[7]);   // 5c - 98 : MM2S_START_ADDRESS
	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_START_ADDRESS2  ,  pFrames_phys[7]);   // 5c - 98 : MM2S_START_ADDRESS
	// // set MM2S parking frame index
	// readRegValue = XAxiVdma_ReadReg(VDMA1_virtual_address,PARK_PTR_REG);
	// readRegValue = readRegValue & (~MM2S_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
	// readRegValue = readRegValue | ((readBufferIndx << 0) & MM2S_PARK_BIT_MASK) ;

	// XAxiVdma_WriteReg(VDMA1_virtual_address, PARK_PTR_REG  ,  readRegValue);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm

	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_FRMDLY_STRIDE  ,  1280  * 4  );   // MM2S_FRMDLY_STRIDE    // note that here stride =  1280 * 4
	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_HSIZE  ,  640 * 4   );   // MM2S_HSIZE   1280
	// XAxiVdma_WriteReg(VDMA1_virtual_address, MM2S_VSIZE  ,  480   );   // MM2S_VSIZE    720



    /* ************************* config stereo IP ***************************** */

	if (!request_mem_region(stereo_control_address,
				0xFFFF,
				"my_xilinx-vdma1")) {
		dev_err(dev, "Couldn't lock memory region at %p\n",
			(void *)stereo_control_address);
		rc = -EBUSY;
		return rc;
	}

	stereo_virtual_address = ioremap(stereo_control_address,
				0xFFFF);
	if (!stereo_virtual_address) {
		dev_err(dev, "stereo: Could not allocate iomem\n");
		rc = -EIO;
		return rc;
	}


	/*                         0x00RGB(32bit)                                           
			
	 NOTE :   here is how we store the 480 image 

	 |<----------- stride = 1280 * 4 ----------->|
	 |<--img w = 640 ----->|
      ___________________________________________
	 |                     |                     |
	 |                     |                     |
	 |      image zone     |      blank area     |
	 |                     |                     |
	 |                     |                     |
	 |                     |                     |
	 |_____________________|_____________________|


	          VDMA2        __________            
		                  |  buffer1 |          
                  S2MM    |__________|          VDMA4                                        
		cam_left  ------> | buffer2  | -----MM2S-----------                                                  
		                  |__________|                     |                              
		                  | buffer3  |                 ____|___         ___640___ __________
		                  |__________|                | stereo |_______| buffer0 |          |__________
                                                      |________|       |___depth_|__leftimg_|          |vdma0
                                                           |    s2MM_vdma1                             |MM2S 
                VDMA3      __________                      |      480p                                \|/
		                  |  buffer4 |                     |                                     to display port
                  S2MM    |__________|                     |                                            
		cam_right ------> | buffer5  | ---MM2S-------------
		                  |__________|       VDMA5
		                  | buffer6  |
		                  |__________|         

	*/

	/* ************************ VDMA2 S2MM ***************************************** */
   /************************ config VDMA2    **********************************/

    if (!request_mem_region(VDMA2_CONTROL_ADDRESS,
                0xFFFF,
                "my_xilinx-vdma2")) {
        dev_err(dev, "Couldn't lock memory region at %p\n",
            (void *)VDMA2_CONTROL_ADDRESS);
        rc = -EBUSY;
        return rc;
    }

    VDMA2_virtual_address = ioremap(VDMA2_CONTROL_ADDRESS,
                0xFFFF);
    if (!VDMA2_virtual_address) {
        dev_err(dev, "vdma1: Could not allocate iomem\n");
        rc = -EIO;
        return rc;
    }


    //config S2MM
    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_VDMACR  ,  0x00000001);   // S2MM_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_START_ADDRESS0  ,  pFrames_phys[1] + 640 * 4 * 1 );   // FOR quick test set to pFrames_phys[0] for direct display  S2MM_START_ADDRESS
    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_START_ADDRESS1  ,  pFrames_phys[1] + 640 * 4 * 1 );   //  S2MM_START_ADDRESS
    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_START_ADDRESS2  ,  pFrames_phys[1] + 640 * 4 * 1 );   //   S2MM_START_ADDRESS
    // set S2MM parking frame index
    readRegValue = XAxiVdma_ReadReg(VDMA2_virtual_address,PARK_PTR_REG);
    readRegValue = readRegValue & (~S2MM_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
    readRegValue = readRegValue | ((vdma2_writeBufferIndx << 8) & S2MM_PARK_BIT_MASK) ;
    XAxiVdma_WriteReg(VDMA2_virtual_address, PARK_PTR_REG  ,  readRegValue);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm

    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_FRMDLY_STRIDE  ,  1280 * 4 );   // S2MM_FRMDLY_STRIDE    // note that here stride =  1280 * 4
    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_HSIZE          ,  640 * 4 );   // S2MM_HSIZE   640
    XAxiVdma_WriteReg(VDMA2_virtual_address, S2MM_VSIZE          ,  480      );   // S2MM_VSIZE    480



	/* ************************ VDMA3 S2MM ***************************************** */
    if (!request_mem_region(VDMA3_CONTROL_ADDRESS,
                0xFFFF,
                "my_xilinx-vdma3")) {
        dev_err(dev, "Couldn't lock memory region at %p\n",
            (void *)VDMA3_CONTROL_ADDRESS);
        rc = -EBUSY;
        return rc;
    }

    VDMA3_virtual_address = ioremap(VDMA3_CONTROL_ADDRESS,
                0xFFFF);
    if (!VDMA3_virtual_address) {
        dev_err(dev, "vdma1: Could not allocate iomem\n");
        rc = -EIO;
        return rc;
    }

    //config S2MM
    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_VDMACR  ,  0x00000001);   // S2MM_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_START_ADDRESS0  ,  pFrames_phys[0]  );   //   S2MM_START_ADDRESS
    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_START_ADDRESS1  ,  pFrames_phys[0]  );   //  S2MM_START_ADDRESS
    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_START_ADDRESS2  ,  pFrames_phys[0]  );   //   S2MM_START_ADDRESS
    // set S2MM parking frame index
    readRegValue = XAxiVdma_ReadReg(VDMA3_virtual_address,PARK_PTR_REG);
    readRegValue = readRegValue & (~S2MM_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
    readRegValue = readRegValue | ((vdma3_writeBufferIndx << 8) & S2MM_PARK_BIT_MASK) ;
    XAxiVdma_WriteReg(VDMA3_virtual_address, PARK_PTR_REG  ,  readRegValue);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm

    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_FRMDLY_STRIDE  ,  1280 * 4 );   // S2MM_FRMDLY_STRIDE    // note that here stride =  1280 * 4
    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_HSIZE          ,  640  * 4 );   // S2MM_HSIZE   640
    XAxiVdma_WriteReg(VDMA3_virtual_address, S2MM_VSIZE          ,  480     );   // S2MM_VSIZE    480


    /* ************************ VDMA4 MM2S ***************************************** */
    if (!request_mem_region(VDMA4_CONTROL_ADDRESS,
                0xFFFF,
                "my_xilinx-vdma1")) {
        dev_err(dev, "Couldn't lock memory region at %p\n",
            (void *)VDMA4_CONTROL_ADDRESS);
        rc = -EBUSY;
        return rc;
    }

    VDMA4_virtual_address = ioremap(VDMA4_CONTROL_ADDRESS,
                0xFFFF);
    if (!VDMA4_virtual_address) {
        dev_err(dev, "vdma1: Could not allocate iomem\n");
        rc = -EIO;
        return rc;
    }

    // config M2SS
    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_VDMACR  ,  0x00000001   );   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_START_ADDRESS0  ,  pFrames_phys[0]);   // 5c - 98 : MM2S_START_ADDRESS
    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_START_ADDRESS1  ,  pFrames_phys[0]);   // 5c - 98 : MM2S_START_ADDRESS
    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_START_ADDRESS2  ,  pFrames_phys[0]);   // 5c - 98 : MM2S_START_ADDRESS
    // set MM2S parking frame index
    readRegValue = XAxiVdma_ReadReg(VDMA4_virtual_address,PARK_PTR_REG);
    readRegValue = readRegValue & (~MM2S_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
    readRegValue = readRegValue | ((readBufferIndx << 0) & MM2S_PARK_BIT_MASK) ;

    XAxiVdma_WriteReg(VDMA4_virtual_address, PARK_PTR_REG  ,  readRegValue);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm

    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_FRMDLY_STRIDE  ,  1280 * 4    	);   // MM2S_FRMDLY_STRIDE    // note that here stride =  1280 * 4
    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_HSIZE  ,  		640 * 4   	);   // MM2S_HSIZE   1280
    XAxiVdma_WriteReg(VDMA4_virtual_address, MM2S_VSIZE  ,  		480      	);   // MM2S_VSIZE    720


    //  ************************ VDMA5 MM2S ***************************************** 
    if (!request_mem_region(VDMA5_CONTROL_ADDRESS,
                0xFFFF,
                "my_xilinx-vdma1")) {
        dev_err(dev, "Couldn't lock memory region at %p\n",
            (void *)VDMA5_CONTROL_ADDRESS);
        rc = -EBUSY;
        return rc;
    }

    VDMA5_virtual_address = ioremap(VDMA5_CONTROL_ADDRESS,
                0xFFFF);
    if (!VDMA5_virtual_address) {
        dev_err(dev, "vdma1: Could not allocate iomem\n");
        rc = -EIO;
        return rc;
    }

    // config M2SS
    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_VDMACR          ,  0x00000001     );   // MM2S_VDMACR  , bit1: 0:parking mode ,1: cicular mode . bit0--0：stop , 1:run
    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_START_ADDRESS0  ,  pFrames_phys[1] + 640 * 4);   // 5c - 98 : MM2S_START_ADDRESS
    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_START_ADDRESS1  ,  pFrames_phys[1] + 640 * 4);   // 5c - 98 : MM2S_START_ADDRESS
    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_START_ADDRESS2  ,  pFrames_phys[1] + 640 * 4);   // 5c - 98 : MM2S_START_ADDRESS
    // set MM2S parking frame index
    readRegValue = XAxiVdma_ReadReg(VDMA5_virtual_address,PARK_PTR_REG);
    readRegValue = readRegValue & (~MM2S_PARK_BIT_MASK)  ;  // keep the other bits , clear the corresponding bits
    readRegValue = readRegValue | ((readBufferIndx << 0) & MM2S_PARK_BIT_MASK) ;

    XAxiVdma_WriteReg(VDMA5_virtual_address, PARK_PTR_REG  ,  readRegValue);   // PARK_PTR_REG 4-0: Read Frame Pointer Reference MM2S , 12-8: Write Frame Pointer Reference s2mm

    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_FRMDLY_STRIDE  ,  1280 * 4    	);   // MM2S_FRMDLY_STRIDE    // note that here stride =  1280 * 4
    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_HSIZE  ,  		640 * 4   	);   // MM2S_HSIZE   1280
    XAxiVdma_WriteReg(VDMA5_virtual_address, MM2S_VSIZE  ,  		480      	);   // MM2S_VSIZE    720






    // slv_reg[3 ]  = 1		     ;
    iowrite32( 1, stereo_virtual_address + 1  * 4);

    // iowrite32( 0x0000174A , stereo_virtual_address +  4  * 4 );
    // iowrite32( 0xFFFF5AF7 , stereo_virtual_address +  5  * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  6  * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  7  * 4 );
    // iowrite32( 0x0001CE1D , stereo_virtual_address +  8  * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  9  * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  10 * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  11 * 4 );
    // iowrite32( 0x00000057 , stereo_virtual_address +  12 * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  13 * 4 );
    // iowrite32( 0xFFFF7D8F , stereo_virtual_address +  14 * 4 );
    // iowrite32( 0x00000000 , stereo_virtual_address +  15 * 4 ) ;
    // iowrite32( 0x00000057 , stereo_virtual_address +  16 * 4 ) ;
    // iowrite32( 0xFFFF9F79 , stereo_virtual_address +  17 * 4 ) ;
    // iowrite32( 0xFFFFFFFD , stereo_virtual_address +  18 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  19 * 4 ) ;
    // iowrite32( 0x0001056B , stereo_virtual_address +  20 * 4 ) ;
    // iowrite32( 0x017AE29C , stereo_virtual_address +  21 * 4 ) ;
    // iowrite32( 0x0119DAE8 , stereo_virtual_address +  22 * 4 ) ;
    // iowrite32( 0x02EC4F10 , stereo_virtual_address +  23 * 4 ) ;
    // iowrite32( 0x02EC4F10 , stereo_virtual_address +  24 * 4 ) ;
    // iowrite32( 0x00001796 , stereo_virtual_address +  25 * 4 ) ;
    // iowrite32( 0xFFFF7553 , stereo_virtual_address +  26 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  27 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  28 * 4 ) ;
    // iowrite32( 0x00010202 , stereo_virtual_address +  29 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  30 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  31 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  32 * 4 ) ;
    // iowrite32( 0x00000057 , stereo_virtual_address +  33 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  34 * 4 ) ;
    // iowrite32( 0xFFFF7DC5 , stereo_virtual_address +  35 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  36 * 4 ) ;
    // iowrite32( 0x00000057 , stereo_virtual_address +  37 * 4 ) ;
    // iowrite32( 0xFFFFA0E8 , stereo_virtual_address +  38 * 4 ) ;
    // iowrite32( 0xFFFFFFFE , stereo_virtual_address +  39 * 4 ) ;
    // iowrite32( 0x00000000 , stereo_virtual_address +  40 * 4 ) ;
    // iowrite32( 0x00010416 , stereo_virtual_address +  41 * 4 ) ;
    // iowrite32( 0x0178FA74 , stereo_virtual_address +  42 * 4 ) ;
    // iowrite32( 0x011B88C8 , stereo_virtual_address +  43 * 4 ) ;
    // iowrite32( 0x02EC4F10 , stereo_virtual_address +  44 * 4 ) ;
    // iowrite32( 0x02EC4F10 , stereo_virtual_address +  45 * 4 ) ;


    iowrite32( 0xFFFFB5E5 , stereo_virtual_address +  4  * 4 );
    iowrite32( 0xFFECFB79 , stereo_virtual_address +  5  * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  6  * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  7  * 4 );
    iowrite32( 0x022682A0 , stereo_virtual_address +  8  * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  9  * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  10 * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  11 * 4 );
    iowrite32( 0x00000017 , stereo_virtual_address +  12 * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  13 * 4 );
    iowrite32( 0xFFFFDC2B , stereo_virtual_address +  14 * 4 );
    iowrite32( 0x00000000 , stereo_virtual_address +  15 * 4 ) ;
    iowrite32( 0x00000017 , stereo_virtual_address +  16 * 4 ) ;
    iowrite32( 0xFFFFE085 , stereo_virtual_address +  17 * 4 ) ;
    iowrite32( 0x00000004 , stereo_virtual_address +  18 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  19 * 4 ) ;
    iowrite32( 0x0000FE08 , stereo_virtual_address +  20 * 4 ) ;
    iowrite32( 0x018ECE8A , stereo_virtual_address +  21 * 4 ) ;
    iowrite32( 0x014DC86A , stereo_virtual_address +  22 * 4 ) ;
    iowrite32( 0x0AE79870 , stereo_virtual_address +  23 * 4 ) ;
    iowrite32( 0x0AE79870 , stereo_virtual_address +  24 * 4 ) ;
    iowrite32( 0xFFFFB81D , stereo_virtual_address +  25 * 4 ) ;
    iowrite32( 0xFFED9C3F , stereo_virtual_address +  26 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  27 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  28 * 4 ) ;
    iowrite32( 0x0167AB10 , stereo_virtual_address +  29 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  30 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  31 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  32 * 4 ) ;
    iowrite32( 0x00000017 , stereo_virtual_address +  33 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  34 * 4 ) ;
    iowrite32( 0xFFFFDC53 , stereo_virtual_address +  35 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  36 * 4 ) ;
    iowrite32( 0x00000017 , stereo_virtual_address +  37 * 4 ) ;
    iowrite32( 0xFFFFE20D , stereo_virtual_address +  38 * 4 ) ;
    iowrite32( 0x00000004 , stereo_virtual_address +  39 * 4 ) ;
    iowrite32( 0x00000000 , stereo_virtual_address +  40 * 4 ) ;
    iowrite32( 0x0000FE14 , stereo_virtual_address +  41 * 4 ) ;
    iowrite32( 0x018BEB96 , stereo_virtual_address +  42 * 4 ) ;
    iowrite32( 0x014D785A , stereo_virtual_address +  43 * 4 ) ;
    iowrite32( 0x0AE79870 , stereo_virtual_address +  44 * 4 ) ;
    iowrite32( 0x0AE79870 , stereo_virtual_address +  45 * 4 ) ;

    int ii = 0 ;

    for (ii = 4 ; ii < 46 ; ii++)
    {
    	readRegValue = XAxiVdma_ReadReg(stereo_virtual_address,ii * 4 );
    	printk("reg address %08x  =  %08x \n", ii, readRegValue) ;
    }


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

	// vdma1 
	release_mem_region(VDMA1_CONTROL_ADDRESS,0xFFFF);
	iounmap(VDMA1_virtual_address);
		// vdma2
	release_mem_region(VDMA2_CONTROL_ADDRESS,0xFFFF);
	iounmap(VDMA2_virtual_address);
		// vdma3
	release_mem_region(VDMA3_CONTROL_ADDRESS,0xFFFF);
	iounmap(VDMA3_virtual_address);
		// vdma4
	release_mem_region(VDMA4_CONTROL_ADDRESS,0xFFFF);
	iounmap(VDMA4_virtual_address);
		// vdma5
	release_mem_region(VDMA5_CONTROL_ADDRESS,0xFFFF);
	iounmap(VDMA5_virtual_address);
	// stereo 
	release_mem_region(stereo_control_address,0xFFFF);
	iounmap(stereo_virtual_address);


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