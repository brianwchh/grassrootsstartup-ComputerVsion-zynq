#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/delay.h>
#include <linux/irq.h>
#include <asm/uaccess.h>
#include <asm/irq.h>
#include <asm/io.h>
#include <linux/poll.h>
#include <linux/dma-mapping.h>
#include <linux/cdev.h>

static int major = 0;

static u32 * VIDEO_BASEADDR;
static u32 src_phys;

static struct class *cls;
static struct cdev videobuf_cdev;

#define BUF_SIZE  (1920 * 1080 * 3 * 10 )

#define GET_VIRTUAL_ADDRESS 0 
#define GET_PHY_ADDRESS     1



static u32 video_buf_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	switch (cmd)
	{
		case GET_VIRTUAL_ADDRESS :
		{
			printk(KERN_ALERT "kerneal VIRTUAL_ADDRESS = 0x%08x\n",VIDEO_BASEADDR);
			printk(KERN_ALERT "kerneal cmd = 0x%08x\n",cmd);
			return (u32) VIDEO_BASEADDR ;
		}

		case GET_PHY_ADDRESS :
		{
			printk(KERN_ALERT "kerneal PHY_ADDRESS = 0x%08x\n",src_phys);
			printk(KERN_ALERT "kerneal cmd = 0x%08x\n",cmd);
			return src_phys ;
		}
	}

	return 0;
}

static struct file_operations dma_fops = {
	.owner  = THIS_MODULE,
	.unlocked_ioctl  = video_buf_ioctl,
};

static int video_buf_init(void)
{ 
	struct device *subdev;
	dev_t devid;

	VIDEO_BASEADDR = (u32 *)dma_alloc_writecombine(NULL, BUF_SIZE, &src_phys, GFP_KERNEL);
	if (NULL == VIDEO_BASEADDR)
	{
		printk(KERN_ALERT "can't alloc buffer for VIDEO_BASEADDR\n");
		return -ENOMEM;
	}

	printk(KERN_ALERT "VIRTUAL_ADDRESS = 0x%08x\n",VIDEO_BASEADDR);
	printk(KERN_ALERT "PHY_ADDRESS = 0x%08x\n",src_phys);

	if (major) {
		devid = MKDEV(major, 0);
		register_chrdev_region(devid, 1, "videobuf");   
	} else {
		alloc_chrdev_region(&devid, 0, 1, "videobuf");  
		major = MAJOR(devid);                     
	}
	
	cdev_init(&videobuf_cdev, &dma_fops);
	cdev_add(&videobuf_cdev, devid, 1);


	cls = class_create(THIS_MODULE, "videobuf");
	subdev=device_create(cls, NULL, MKDEV(major, 0), NULL, "Vbuf"); /* /dev/dma */
	if (IS_ERR(subdev))
	{
		printk(KERN_ALERT "device create error\n");
		return PTR_ERR(subdev);
	}

	return 0;
}

static void video_buf_exit(void)
{
	dma_free_writecombine(NULL, BUF_SIZE, VIDEO_BASEADDR, src_phys);
	device_destroy(cls, MKDEV(major, 0));
	class_destroy(cls);
	unregister_chrdev(major, "videobuf");
	printk(KERN_ALERT "vhdma driver removed\n") ;
}

module_init(video_buf_init);
module_exit(video_buf_exit);

MODULE_LICENSE("GPL");

