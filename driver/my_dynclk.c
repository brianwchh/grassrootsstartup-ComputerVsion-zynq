
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

// dynclk 
#define OFST_DYNCLK_CTRL 0x0
#define OFST_DYNCLK_STATUS 0x4
#define OFST_DYNCLK_CLK_L 0x8
#define OFST_DYNCLK_FB_L 0x0C
#define OFST_DYNCLK_FB_H_CLK_H 0x10
#define OFST_DYNCLK_DIV 0x14
#define OFST_DYNCLK_LOCK_L 0x18
#define OFST_DYNCLK_FLTR_LOCK_H 0x1C

#define BIT_DYNCLK_START 0
#define BIT_DYNCLK_RUNNING 0


typedef struct {
        u32 clk0L;
        u32 clkFBL;
        u32 clkFBH_clk0H;
        u32 divclk;
        u32 lockL;
        u32 fltr_lockH;
} ClkConfig;


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
} XAxiDynclk_Config;



void ClkStart(char*  dynClkAddr_vir)
{
    iowrite32((1 << BIT_DYNCLK_START) , dynClkAddr_vir + OFST_DYNCLK_CTRL);
    while(!(ioread32(dynClkAddr_vir + OFST_DYNCLK_STATUS) & (1 << BIT_DYNCLK_RUNNING)));

    return;
}

void ClkStop(char* dynClkAddr_vir)
{
    iowrite32(0, dynClkAddr_vir + OFST_DYNCLK_CTRL);
    while((ioread32(dynClkAddr_vir + OFST_DYNCLK_STATUS) & (1 << BIT_DYNCLK_RUNNING)));

    return;
}


/**
 * xilinx_dynclk_probe - Driver probe function
 * @pdev: Pointer to the platform_device structure
 *
 * Return: '0' on success and failure value on error
 */
static int xilinx_dynclk_probe(struct platform_device *pdev)
{
    struct device *subdev;

    struct device *dev = &pdev->dev;

    struct resource *r_irq; /* Interrupt resources */
    struct resource *r_mem; /* IO mem resources */

    int rc = 0 ;

    XAxiDynclk_Config *XdynclkPtr = NULL;

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
    XdynclkPtr = (XAxiDynclk_Config *) kmalloc(sizeof(XAxiDynclk_Config), GFP_KERNEL);
    if (!XdynclkPtr) {
        printk("Cound not allocate XAxiDynclk_Config device\n");
        return -ENOMEM;
    }

    // save the start and end address on the config structure   why r_mem->start is not right should be 0x4300_0000
    // XdynclkPtr->mem_phy_start = r_mem->start ;
    // XdynclkPtr->mem_phy_end  = r_mem->end  ;
    XdynclkPtr->mem_phy_start = 0x43C10000 ;
    XdynclkPtr->mem_phy_end  =  0x43C1FFFF ;

    dev_set_drvdata(dev, XdynclkPtr);   // pass the pointer to dev ??? why ??

#if 1
    // Ask the kernel the memory region defined on the device-tree and
    // prevent other drivers to overlap on this region     
    // This is needed before the ioremap
    // reg = <0x41220000 0x10000>;
    if (!request_mem_region(XdynclkPtr->mem_phy_start,
                XdynclkPtr->mem_phy_end - XdynclkPtr->mem_phy_start + 1,
                "my_xilinx-vdma")) {
        dev_err(dev, "Couldn't lock memory region at %p\n",
            (void *)XdynclkPtr->mem_phy_start);
        rc = -EBUSY;
        goto error1;
    }
    // printk("vdma controller start address = 0x%08X\n", XdynclkPtr->mem_phy_start);
    // printk("vdma controller end  address =  0x%08X\n" ,XdynclkPtr->mem_phy_end);

    // Get an virtual address from the device physical address with a 
    // range size: lp->mem_end - lp->mem_start + 1
    XdynclkPtr->base_addr_vir = ioremap(XdynclkPtr->mem_phy_start,
                XdynclkPtr->mem_phy_end - XdynclkPtr->mem_phy_start + 1);
    if (!XdynclkPtr->base_addr_vir) {
        dev_err(dev, "vdma: Could not allocate iomem\n");
        rc = -EIO;
        goto error1;
    }
#endif 

#if 0
    /* Request and map I/O memory */
    XdynclkPtr->base_addr_vir = devm_ioremap_resource(&pdev->dev, r_mem);   //
    if (IS_ERR(XdynclkPtr->base_addr_vir))
        return PTR_ERR(XdynclkPtr->base_addr_vir);
#endif 
    // u32 register0=(u32)ioread32(XdynclkPtr->base_addr_vir);
    // printk("readed data = 0x%08X\n",(u32)ioread32(XdynclkPtr->base_addr_vir));
    // printk("remapped vdma controller address = 0x%08X\n",XdynclkPtr->base_addr_vir);


    iowrite32(0x00000041 , XdynclkPtr->base_addr_vir + OFST_DYNCLK_CLK_L         ) ;
    iowrite32(0x0000069A , XdynclkPtr->base_addr_vir + OFST_DYNCLK_FB_L          ) ;
    iowrite32(0x00000000 , XdynclkPtr->base_addr_vir + OFST_DYNCLK_FB_H_CLK_H    ) ;
    iowrite32(0x000020C4 , XdynclkPtr->base_addr_vir + OFST_DYNCLK_DIV           ) ;
    iowrite32(0xCFAFA401 , XdynclkPtr->base_addr_vir + OFST_DYNCLK_LOCK_L        ) ;
    iowrite32(0x00A300FF , XdynclkPtr->base_addr_vir + OFST_DYNCLK_FLTR_LOCK_H   ) ;


    ClkStop (XdynclkPtr->base_addr_vir);
    ClkStart(XdynclkPtr->base_addr_vir);


    
    // printk(" **************************************** \n");
    // printk("     dynamic clk module started \r\n");
    // printk(" **************************************** \n");

    // printk("readed data = 0x%08X   @OFST_DYNCLK_CLK_L        0x%08X\n ",(u32)ioread32(XdynclkPtr->base_addr_vir + OFST_DYNCLK_CLK_L        ),    XdynclkPtr->base_addr_vir + OFST_DYNCLK_CLK_L        );
    // printk("readed data = 0x%08X   @OFST_DYNCLK_FB_L         0x%08X\n ",(u32)ioread32(XdynclkPtr->base_addr_vir + OFST_DYNCLK_FB_L         ),    XdynclkPtr->base_addr_vir + OFST_DYNCLK_FB_L         );
    // printk("readed data = 0x%08X   @OFST_DYNCLK_FB_H_CLK_H   0x%08X\n ",(u32)ioread32(XdynclkPtr->base_addr_vir + OFST_DYNCLK_FB_H_CLK_H   ),    XdynclkPtr->base_addr_vir + OFST_DYNCLK_FB_H_CLK_H   );
    // printk("readed data = 0x%08X   @OFST_DYNCLK_DIV          0x%08X\n ",(u32)ioread32(XdynclkPtr->base_addr_vir + OFST_DYNCLK_DIV          ),    XdynclkPtr->base_addr_vir + OFST_DYNCLK_DIV          );
    // printk("readed data = 0x%08X   @OFST_DYNCLK_LOCK_L       0x%08X\n ",(u32)ioread32(XdynclkPtr->base_addr_vir + OFST_DYNCLK_LOCK_L       ),    XdynclkPtr->base_addr_vir + OFST_DYNCLK_LOCK_L       );
    // printk("readed data = 0x%08X   @OFST_DYNCLK_FLTR_LOCK_H  0x%08X\n ",(u32)ioread32(XdynclkPtr->base_addr_vir + OFST_DYNCLK_FLTR_LOCK_H  ),    XdynclkPtr->base_addr_vir + OFST_DYNCLK_FLTR_LOCK_H  );
    


    return 0 ;

error1:
    dev_set_drvdata(dev, NULL);
    release_mem_region(XdynclkPtr->mem_phy_start,
                XdynclkPtr->mem_phy_end - XdynclkPtr->mem_phy_start + 1);

    kfree(XdynclkPtr);
    return rc;

}

/**
 * xilinx_dynclk_remove - Driver remove function
 * @pdev: Pointer to the platform_device structure
 *
 * Return: Always '0'
 */
static int xilinx_dynclk_remove(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    XAxiDynclk_Config *XdynclkPtr = dev_get_drvdata(dev);
    // free_irq(XdynclkPtr->irq, XdynclkPtr);
    release_mem_region(XdynclkPtr->mem_phy_start,
                XdynclkPtr->mem_phy_end - XdynclkPtr->mem_phy_start + 1);
    iounmap(XdynclkPtr->base_addr_vir);   // vdma controll register address 

    printk(KERN_ALERT "dynclk driver removed\n") ;
    return 0;
}


static const struct of_device_id xilinx_dynclk_of_ids[] = {
    { .compatible = "digilent,axi-dynclk-my",},
    {}
};

MODULE_DEVICE_TABLE(of, xilinx_dynclk_of_ids);

static struct platform_driver xilinx_dynclk_driver = {
    .driver = {
        .name = "my_xilinx-dynclk",
        .owner = THIS_MODULE,
        .of_match_table = xilinx_dynclk_of_ids,
    },
    .probe = xilinx_dynclk_probe,
    .remove = xilinx_dynclk_remove,
};

static int __init myDynclk_init(void)
{
    printk("my dynclk driver.\n");

    return platform_driver_register(&xilinx_dynclk_driver);
}

static void __exit myDynclk_exit(void)
{
    platform_driver_unregister(&xilinx_dynclk_driver);
    printk(KERN_ALERT "8888888888 .\n");
}

// module_platform_driver(xilinx_dynclk_driver);   // module_init(&xilinx_dynclk_driver) + module_exit(&xilinx_dynclk_driver) ???

module_init(myDynclk_init);
module_exit(myDynclk_exit);

MODULE_AUTHOR("BrianWu");
MODULE_DESCRIPTION("xilinx_dynclk_driver");
MODULE_LICENSE("GPL");