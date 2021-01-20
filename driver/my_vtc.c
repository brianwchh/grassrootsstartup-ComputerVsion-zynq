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

#include "xvtc_hw.h"

/****************** Xilinx files *******************/

// VTC
#define VTC_CONFIG_ADDR   0x43c00000

#define XVtc_WriteReg(BaseAddress, RegOffset, Data)     \
        iowrite32((Data) , (BaseAddress) + (RegOffset)  )

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
} XAxiVtc_Config;


/**
 * xilinx_vtc_probe - Driver probe function
 * @pdev: Pointer to the platform_device structure
 *
 * Return: '0' on success and failure value on error
 */
static int xilinx_vtc_probe(struct platform_device *pdev)
{
	struct device *subdev;

	struct device *dev = &pdev->dev;

	struct resource *r_irq; /* Interrupt resources */
	struct resource *r_mem; /* IO mem resources */

	int rc = 0 ;

	XAxiVtc_Config *XvtcPtr = NULL;

	// printk(" **************************************** \n");
	// printk("     probing vtc device tree \n");
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
	XvtcPtr = (XAxiVtc_Config *) kmalloc(sizeof(XAxiVtc_Config), GFP_KERNEL);
	if (!XvtcPtr) {
		printk("Cound not allocate XAxiVtc_Config device\n");
		return -ENOMEM;
	}

	// save the start and end address on the config structure   why r_mem->start is not right should be 0x4300_0000
	// XvtcPtr->mem_phy_start = r_mem->start ;
	// XvtcPtr->mem_phy_end  = r_mem->end  ;
	XvtcPtr->mem_phy_start = 0x43C00000 ;
	XvtcPtr->mem_phy_end  =  0x43C0FFFF ;

	dev_set_drvdata(dev, XvtcPtr);   // pass the pointer to dev ??? why ??

#if 1
	// Ask the kernel the memory region defined on the device-tree and
	// prevent other drivers to overlap on this region     
	// This is needed before the ioremap
	// reg = <0x41220000 0x10000>;
	if (!request_mem_region(XvtcPtr->mem_phy_start,
				XvtcPtr->mem_phy_end - XvtcPtr->mem_phy_start + 1,
				"my_xilinx-vdma")) {
		dev_err(dev, "Couldn't lock memory region at %p\n",
			(void *)XvtcPtr->mem_phy_start);
		rc = -EBUSY;
		goto error1;
	}
	// printk("vdma controller start address = 0x%08X\n", XvtcPtr->mem_phy_start);
	// printk("vdma controller end  address =  0x%08X\n" ,XvtcPtr->mem_phy_end);

	// Get an virtual address from the device physical address with a 
	// range size: lp->mem_end - lp->mem_start + 1
	XvtcPtr->base_addr_vir = ioremap(XvtcPtr->mem_phy_start,
				XvtcPtr->mem_phy_end - XvtcPtr->mem_phy_start + 1);
	if (!XvtcPtr->base_addr_vir) {
		dev_err(dev, "vdma: Could not allocate iomem\n");
		rc = -EIO;
		goto error1;
	}
#endif 

#if 0
	/* Request and map I/O memory */
    XvtcPtr->base_addr_vir = devm_ioremap_resource(&pdev->dev, r_mem);   //
	if (IS_ERR(XvtcPtr->base_addr_vir))
		return PTR_ERR(XvtcPtr->base_addr_vir);
#endif 
	// u32 register0=(u32)ioread32(XvtcPtr->base_addr_vir);
	// printk("readed data = 0x%08X\n",(u32)ioread32(XvtcPtr->base_addr_vir));
	// printk("remapped vdma controller address = 0x%08X\n",XvtcPtr->base_addr_vir);

 
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000000  ,  0x00000002)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x0000006C  ,  0x0000007F)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000070  ,  0x00000672)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000074  ,  0x02EE02EE)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000060  ,  0x02D00500)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000078  ,  0x0596056E)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000080  ,  0x02D902D4)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x0000008C  ,  0x02D902D4)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000068  ,  0x00000002)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x0000007C  ,  0x05000500)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000084  ,  0x056E056E)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000088  ,  0x05000500)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000090  ,  0x056E056E)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000000  ,  0x03F7EF02)  ;
    XVtc_WriteReg(XvtcPtr->base_addr_vir,  0x00000000  ,  0x03F7EF06)  ;
 

	return 0 ;

error1:
	dev_set_drvdata(dev, NULL);
	release_mem_region(XvtcPtr->mem_phy_start,
				XvtcPtr->mem_phy_end - XvtcPtr->mem_phy_start + 1);

	kfree(XvtcPtr);
	return rc;

}

/**
 * xilinx_vtc_remove - Driver remove function
 * @pdev: Pointer to the platform_device structure
 *
 * Return: Always '0'
 */
static int xilinx_vtc_remove(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	XAxiVtc_Config *XvtcPtr = dev_get_drvdata(dev);
	// free_irq(XvtcPtr->irq, XvtcPtr);
	release_mem_region(XvtcPtr->mem_phy_start,
				XvtcPtr->mem_phy_end - XvtcPtr->mem_phy_start + 1);
	iounmap(XvtcPtr->base_addr_vir);   // vdma controll register address 

	printk(KERN_ALERT "vtc driver removed\n") ;
	return 0;
}


static const struct of_device_id xilinx_vtc_of_ids[] = {
	{ .compatible = "xlnx,v-tc-5.01.a-my",},
	{}
};

MODULE_DEVICE_TABLE(of, xilinx_vtc_of_ids);

static struct platform_driver xilinx_vtc_driver = {
	.driver = {
		.name = "my_xilinx-vtc",
		.owner = THIS_MODULE,
		.of_match_table = xilinx_vtc_of_ids,
	},
	.probe = xilinx_vtc_probe,
	.remove = xilinx_vtc_remove,
};

static int __init myVtc_init(void)
{
	printk("my vtc driver.\n");

	return platform_driver_register(&xilinx_vtc_driver);
}

static void __exit myVtc_exit(void)
{
	platform_driver_unregister(&xilinx_vtc_driver);
	printk(KERN_ALERT "8888888888 .\n");
}

// module_platform_driver(xilinx_vtc_driver);   // module_init(&xilinx_vtc_driver) + module_exit(&xilinx_vtc_driver) ???

module_init(myVtc_init);
module_exit(myVtc_exit);

MODULE_AUTHOR("BrianWu");
MODULE_DESCRIPTION("xilinx_vtc_driver");
MODULE_LICENSE("GPL");
