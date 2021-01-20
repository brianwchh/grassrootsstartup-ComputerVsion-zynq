#include <linux/module.h>
#include <linux/vermagic.h>
#include <linux/compiler.h>

MODULE_INFO(vermagic, VERMAGIC_STRING);

__visible struct module __this_module
__attribute__((section(".gnu.linkonce.this_module"))) = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

static const struct modversion_info ____versions[]
__used
__attribute__((section("__versions"))) = {
	{ 0x65137d02, __VMLINUX_SYMBOL_STR(module_layout) },
	{ 0x6bc3fbc0, __VMLINUX_SYMBOL_STR(__unregister_chrdev) },
	{ 0xfebc9f41, __VMLINUX_SYMBOL_STR(class_destroy) },
	{ 0x4f85f41d, __VMLINUX_SYMBOL_STR(device_destroy) },
	{ 0xa0e92810, __VMLINUX_SYMBOL_STR(arm_dma_ops) },
	{ 0xf3c34cd4, __VMLINUX_SYMBOL_STR(device_create) },
	{ 0xe257aab6, __VMLINUX_SYMBOL_STR(__class_create) },
	{ 0x45090270, __VMLINUX_SYMBOL_STR(cdev_add) },
	{ 0xba25b4e0, __VMLINUX_SYMBOL_STR(cdev_init) },
	{ 0x29537c9e, __VMLINUX_SYMBOL_STR(alloc_chrdev_region) },
	{ 0xd8e484f0, __VMLINUX_SYMBOL_STR(register_chrdev_region) },
	{ 0xefd6cf06, __VMLINUX_SYMBOL_STR(__aeabi_unwind_cpp_pr0) },
	{ 0x27e1a049, __VMLINUX_SYMBOL_STR(printk) },
};

static const char __module_depends[]
__used
__attribute__((section(".modinfo"))) =
"depends=";

