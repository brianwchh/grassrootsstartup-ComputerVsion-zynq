#include <linux/list.h>
#include <linux/device.h>
#include <linux/module.h>
#include <linux/io.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/sched.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/spinlock.h>
#include <linux/mutex.h>
#include <linux/crc32.h>
#include <linux/poll.h>
#include <linux/delay.h>
#include <linux/slab.h>
#include <linux/workqueue.h>

// #include <linux/module.h>
// #include <linux/kernel.h>
// #include <linux/fs.h>
// #include <linux/init.h>
// #include <linux/delay.h>
// #include <linux/irq.h>
// #include <asm/uaccess.h>
// #include <asm/irq.h>
// #include <asm/io.h>
// #include <linux/poll.h>
// #include <linux/cdev.h>
//  #include <linux/device.h>

/* 1. 确定主设备号 */
static int major;

static int hello_open(struct inode *inode, struct file *file)
{
	printk("hello_open\n");
	return 0;
}


/* 2. 构造file_operations */
static struct file_operations hello_fops = {
	.owner = THIS_MODULE,
	.open  = hello_open,
};

#define HELLO_CNT   2

static struct cdev hello_cdev;
static struct class *cls;

static int hello_init(void)
{
	dev_t devid;
	int rc ;
	
	/* 3. 告诉内核 */
#if 0
	major = register_chrdev(0, "hello", &hello_fops); /* (major,  0), (major, 1), ..., (major, 255)都对应hello_fops */
#else
	if (major) {
		devid = MKDEV(major, 0);
		register_chrdev_region(devid, HELLO_CNT, "hello");  /* (major,0~1) 对应 hello_fops, (major, 2~255)都不对应hello_fops */
	} else {
		rc = alloc_chrdev_region(&devid, 0, HELLO_CNT, "hello"); /* (major,0~1) 对应 hello_fops, (major, 2~255)都不对应hello_fops */
		if (rc) {
		printk("Failed to obtain major/minors\n");
		return rc;
	}
		major = MAJOR(devid);                     
	}
	
	cdev_init(&hello_cdev, &hello_fops);
	cdev_add(&hello_cdev, devid, HELLO_CNT);
#endif

	cls = class_create(THIS_MODULE, "hello");
	device_create(cls, NULL, MKDEV(major, 0), NULL, "hello0"); /* /dev/hello0 */
	device_create(cls, NULL, MKDEV(major, 1), NULL, "hello1"); /* /dev/hello1 */
	device_create(cls, NULL, MKDEV(major, 2), NULL, "hello2"); /* /dev/hello2 */
	
	
	return 0;
}

static void hello_exit(void)
{
	device_destroy(cls, MKDEV(major, 0));
	device_destroy(cls, MKDEV(major, 1));
	device_destroy(cls, MKDEV(major, 2));
	class_destroy(cls);

	cdev_del(&hello_cdev);
	unregister_chrdev_region(MKDEV(major, 0), HELLO_CNT);
}

module_init(hello_init);
module_exit(hello_exit);


MODULE_LICENSE("GPL");

