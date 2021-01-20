#include <linux/kernel.h>
#include <linux/list.h>
#include <linux/module.h>
#include <linux/usb.h>
#include <linux/videodev2.h>
#include <linux/vmalloc.h>
#include <linux/wait.h>
#include <asm/atomic.h>
#include <asm/unaligned.h>

#include <media/v4l2-common.h>

static int myuvc_probe(struct usb_interface *intf,
		     const struct usb_device_id *id)
{
    static int cnt = 0;
	struct usb_device *dev = interface_to_usbdev(intf);
    struct usb_device_descriptor *descriptor = &dev->descriptor;
    struct usb_host_config *hostconfig;
    struct usb_config_descriptor *config;
    int i;

    printk("myuvc_probe : cnt = %d\n", cnt++);

    /* ŽòÓ¡Éè±žÃèÊö·û */
	printk("Device Descriptor:\n"
	       "  bLength             %5u\n"
	       "  bDescriptorType     %5u\n"
	       "  bcdUSB              %2x.%02x\n"
	       "  bDeviceClass        %5u \n"
	       "  bDeviceSubClass     %5u \n"
	       "  bDeviceProtocol     %5u \n"
	       "  bMaxPacketSize0     %5u\n"
	       "  idVendor           0x%04x \n"
	       "  idProduct          0x%04x \n"
	       "  bcdDevice           %2x.%02x\n"
	       "  iManufacturer       %5u\n"
	       "  iProduct            %5u\n"
	       "  iSerial             %5u\n"
	       "  bNumConfigurations  %5u\n",
	       descriptor->bLength, descriptor->bDescriptorType,
	       descriptor->bcdUSB >> 8, descriptor->bcdUSB & 0xff,
	       descriptor->bDeviceClass,
	       descriptor->bDeviceSubClass,
	       descriptor->bDeviceProtocol,
	       descriptor->bMaxPacketSize0,
	       descriptor->idVendor,  descriptor->idProduct,
	       descriptor->bcdDevice >> 8, descriptor->bcdDevice & 0xff,
	       descriptor->iManufacturer,
	       descriptor->iProduct,
	       descriptor->iSerialNumber,
	       descriptor->bNumConfigurations);

    for (i = 0; i < descriptor->bNumConfigurations; i++)
    {
        hostconfig = &dev->config[i];
        config     = &hostconfig->desc;
        printk("  Configuration Descriptor %d:\n"
               "    bLength             %5u\n"
               "    bDescriptorType     %5u\n"
               "    wTotalLength        %5u\n"
               "    bNumInterfaces      %5u\n"
               "    bConfigurationValue %5u\n"
               "    iConfiguration      %5u\n"
               "    bmAttributes         0x%02x\n",
               i,
               config->bLength, config->bDescriptorType,
               le16_to_cpu(config->wTotalLength),
               config->bNumInterfaces, config->bConfigurationValue,
               config->iConfiguration,
               config->bmAttributes);

    }


    return 0;
}

static void myuvc_disconnect(struct usb_interface *intf)
{
    static int cnt = 0;
    printk("myuvc_disconnect : cnt = %d\n", cnt++);
}

static struct usb_device_id myuvc_ids[] = {
	/* Generic USB Video Class */
	{ USB_INTERFACE_INFO(USB_CLASS_VIDEO, 1, 0) },  /* VideoControl Interface */
    { USB_INTERFACE_INFO(USB_CLASS_VIDEO, 2, 0) },  /* VideoStreaming Interface */
	{}
};

/* 1. ·ÖÅäusb_driver */
/* 2. ÉèÖÃ */
static struct usb_driver myuvc_driver = {
    .name       = "myuvc",
    .probe      = myuvc_probe,
    .disconnect = myuvc_disconnect,
    .id_table   = myuvc_ids,
};

static int myuvc_init(void)
{
    /* 3. ×¢²á */
    usb_register(&myuvc_driver);
    return 0;
}

static void myuvc_exit(void)
{
    usb_deregister(&myuvc_driver);
}

module_init(myuvc_init);
module_exit(myuvc_exit);

MODULE_LICENSE("GPL");
