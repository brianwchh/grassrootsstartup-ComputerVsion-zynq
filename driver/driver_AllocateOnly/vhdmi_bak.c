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


//#include "cf_adv7511_zed.h"
#include "xparameters.h"
#include "cf_hdmi.h"
#include "cf_hdmi_demo.h"
#include "iic_reg_config.h"
#include "720p_clkgen_regconfigfile.h"

static int major = 0;

static u32 * VIDEO_BASEADDR;
static u32 src_phys;

static struct class *cls;

#define BUF_SIZE  (1080 * 1920 * 4 * 3 )

#define GET_VIRTUAL_ADDRESS 0 
#define GET_PHY_ADDRESS     1



// #define CF_CLKGEN_BASEADDR  XPAR_AXI_HDMI_CLKGEN_BASEADDR
// #define CFV_BASEADDR        XPAR_AXI_HDMI_CORE_BASEADDR
// #define CFA_BASEADDR        XPAR_AXI_SPDIF_TX_CORE_BASEADDR
// #define DDR_BASEADDR        0x00000000
// #define UART_BASEADDR       0xe0001000
// #define VDMA_BASEADDR       0x43000000
// #define ADMA_BASEADDR       0x40400000
// #define IIC_BASEADDR        XPAR_AXI_IIC_MAIN_BASEADDR


#define H_STRIDE            1920
#define H_COUNT             2200
#define H_ACTIVE            1920
#define H_WIDTH             44
#define H_FP                88
#define H_BP                148
#define V_COUNT             1125
#define V_ACTIVE            1080
#define V_WIDTH             5
#define V_FP                4
#define V_BP                36
#define A_SAMPLE_FREQ       48000
#define A_FREQ              1400

#define H_DE_MIN (H_WIDTH+H_BP)
#define H_DE_MAX (H_WIDTH+H_BP+H_ACTIVE)
#define V_DE_MIN (V_WIDTH+V_BP)
#define V_DE_MAX (V_WIDTH+V_BP+V_ACTIVE)
#define VIDEO_LENGTH  (H_ACTIVE*V_ACTIVE)
#define AUDIO_LENGTH  (A_SAMPLE_FREQ/A_FREQ)



// #define VIDEO_BASEADDR DDR_BASEADDR + 0x2000000
// #define AUDIO_BASEADDR DDR_BASEADDR + 0x1000000


static char * CF_CLKGEN_BASEADDR ; // XPAR_AXI_HDMI_CLKGEN_BASEADDR
static char * CFV_BASEADDR       ; // XPAR_AXI_HDMI_CORE_BASEADDR
static char * CFA_BASEADDR       ; // XPAR_AXI_SPDIF_TX_CORE_BASEADDR
static char * DDR_BASEADDR       ; // 0x00000000
static char * UART_BASEADDR      ; // 0xe0001000
static char * VDMA_BASEADDR      ; // 0x43000000
static char * ADMA_BASEADDR      ; // 0x40400000
static char * IIC_BASEADDR       ; // XPAR_AXI_IIC_MAIN_BASEADDR







/*****************************************************************************/
/******************* Macros and Constants Definitions ************************/
/*****************************************************************************/
 #define MIN(x, y)				(x < y ? x : y)
 #define MAX(x, y) 				(x > y ? x : y)
 #define CLAMP(val, min, max)	(val < min ? min : (val > max ? max :val))


static const unsigned long clkgen_filter_table[] =
{
	0x01001990, 0x01001190, 0x01009890, 0x01001890,
	0x01008890, 0x01009090, 0x01009090, 0x01009090,
	0x01009090, 0x01000890, 0x01000890, 0x01000890,
	0x08009090, 0x01001090, 0x01001090, 0x01001090,
	0x01001090, 0x01001090, 0x01001090, 0x01001090,
	0x01001090, 0x01001090, 0x01001090, 0x01008090,
	0x01008090, 0x01008090, 0x01008090, 0x01008090,
	0x01008090, 0x01008090, 0x01008090, 0x01008090,
	0x01008090, 0x01008090, 0x01008090, 0x01008090,
	0x01008090, 0x08001090, 0x08001090, 0x08001090,
	0x08001090, 0x08001090, 0x08001090, 0x08001090,
	0x08001090, 0x08001090, 0x08001090
};

static const unsigned long clkgen_lock_table[] =
{
	0x060603e8, 0x060603e8, 0x080803e8, 0x0b0b03e8,
	0x0e0e03e8, 0x111103e8, 0x131303e8, 0x161603e8,
	0x191903e8, 0x1c1c03e8, 0x1f1f0384, 0x1f1f0339,
	0x1f1f02ee, 0x1f1f02bc, 0x1f1f028a, 0x1f1f0271,
	0x1f1f023f, 0x1f1f0226, 0x1f1f020d, 0x1f1f01f4,
	0x1f1f01db, 0x1f1f01c2, 0x1f1f01a9, 0x1f1f0190,
	0x1f1f0190, 0x1f1f0177, 0x1f1f015e, 0x1f1f015e,
	0x1f1f0145, 0x1f1f0145, 0x1f1f012c, 0x1f1f012c,
	0x1f1f012c, 0x1f1f0113, 0x1f1f0113, 0x1f1f0113
};


enum videoResolution
{
	RESOLUTION_640x480,
	RESOLUTION_800x600,
	RESOLUTION_1024x768,
	RESOLUTION_1280x720,
	RESOLUTION_1360x768,
	RESOLUTION_1600x900,
	RESOLUTION_1920x1080
};



enum detailedTimingElement
{
	PIXEL_CLOCK,
	H_ACTIVE_TIME,
	H_BLANKING_TIME,
	H_SYNC_OFFSET,
	H_SYNC_WIDTH_PULSE,
	V_ACTIVE_TIME,
	V_BLANKING_TIME,
	V_SYNC_OFFSET,
	V_SYNC_WIDTH_PULSE
};

static const unsigned long detailedTiming[7][9] =
{
	{25180000, 640, 144, 16, 96, 480, 29, 10, 2},
	{40000000, 800, 256, 40, 128, 600, 28, 1, 4},
	{65000000, 1024, 320, 136, 24, 768, 38, 3, 6},
	{74250000, 1280, 370, 110, 40, 720, 30, 5, 5},
	{84750000, 1360, 416, 136, 72, 768, 30, 3, 5},
	{108000000, 1600, 400, 32, 48, 900, 12, 3, 6},
	{148500000, 1920, 280, 44, 88, 1080, 45, 4, 5}
};

// extern int XDmaPs_Instr_DMAMOV(char *DmaProg, unsigned Rd, u32 Imm);
// extern int XDmaPs_Instr_DMAEND(char *DmaProg);
// extern int XDmaPs_Instr_DMALD(char *DmaProg);
// extern int XDmaPs_Instr_DMALP(char *DmaProg, unsigned Lc, unsigned LoopIterations);
// extern int XDmaPs_Instr_DMAST(char *DmaProg);
// extern int XDmaPs_Instr_DMALPEND(char *DmaProg, char *BodyStart, unsigned Lc);
// extern u32 XDmaPs_ToCCRValue(XDmaPs_ChanCtrl *ChanCtrl);



// static int CLKGEN_SetRate(unsigned long rate,
// 				   unsigned long parent_rate);
// static void DDRVideoWr(unsigned short horizontalActiveTime,
// 				unsigned short verticalActiveTime) ;
// static void InitHdmiVideoPcore(unsigned short horizontalActiveTime,
// 						unsigned short horizontalBlankingTime,
// 						unsigned short horizontalSyncOffset,
// 						unsigned short horizontalSyncPulseWidth,
// 						unsigned short verticalActiveTime,
// 						unsigned short verticalBlankingTime,
// 						unsigned short verticalSyncOffset,
// 						unsigned short verticalSyncPulseWidth);
// static void SetVideoResolution(unsigned char resolution) ;
// static unsigned long CLKGEN_LookupFilter(unsigned long m) ;
// static void CLKGEN_CalcParams(unsigned long fin,
// 					   unsigned long fout,
// 					   unsigned long *best_d,
// 					   unsigned long *best_m,
// 					   unsigned long *best_dout) ;
// static void CLKGEN_CalcClkParams(unsigned long divider,
// 						  unsigned long *low,
// 						  unsigned long *high,
// 						  unsigned long *edge,
// 						  unsigned long *nocount) ;
// static void CLKGEN_Write(unsigned long reg,
// 				  unsigned long val) ;
// static unsigned long CLKGEN_GetRate(unsigned long parent_rate)  ;
// static u32 ddr_video_wr(void) ;


/*****************************************************************************/
/**
*
* Performs an input operation for a 16-bit memory location by reading from the
* specified address and returning the Value read from that address.
*
* @param	Addr contains the address to perform the input operation
*		at.
*
* @return	The Value read from the specified input address.
*
* @note		None.
*
******************************************************************************/
static u32 Xil_In32(char* Addr)
{
	return *(u32* ) Addr;
}

/*****************************************************************************/
/**
*
* Performs an output operation for a 32-bit memory location by writing the
* specified Value to the the specified address.
*
* @param	OutAddress contains the address to perform the output operation
*		at.
* @param	Value contains the Value to be output at the specified address.
*
* @return	None.
*
* @note		None.
*
******************************************************************************/
static void Xil_Out32(char * OutAddress, u32 Value)
{
	*(u32 *)OutAddress = Value;
}


static void delay_ms(u32 ms_count) {
  u32 count;
  for (count = 0; count < ((ms_count * 800000) + 1); count++) {
  }
}

static void nops_num(u32 ms_count) {
  u32 count;
  for (count = 0; count < (ms_count + 1); count++) {
  }
}

static void iic_write(char* daddr, u32 waddr, u32 wdata) {

	Xil_Out32((IIC_BASEADDR + 0x100), 0x002); // reset tx fifo
	Xil_Out32((IIC_BASEADDR + 0x100), 0x001); // enable iic
	Xil_Out32((IIC_BASEADDR + 0x108), (0x100 | ((u32)daddr<<1))); // select
	Xil_Out32((IIC_BASEADDR + 0x108), waddr); // address
	Xil_Out32((IIC_BASEADDR + 0x108), (0x200 | wdata)); // data

  while ((Xil_In32(IIC_BASEADDR + 0x104) & 0x80) == 0x00) {delay_ms(1);}
  delay_ms(10);
}

static u32 iic_read(char* daddr, u32 raddr, u32 display) {
  u32 rdata;
  Xil_Out32((IIC_BASEADDR + 0x100), 0x002); // reset tx fifo
  Xil_Out32((IIC_BASEADDR + 0x100), 0x001); // enable iic
  Xil_Out32((IIC_BASEADDR + 0x108), (0x100 | ((u32)daddr<<1))); // select
  Xil_Out32((IIC_BASEADDR + 0x108), raddr); // address
  Xil_Out32((IIC_BASEADDR + 0x108), (0x101 | ((u32)daddr<<1))); // select
  Xil_Out32((IIC_BASEADDR + 0x108), 0x201); // data
  while ((Xil_In32(IIC_BASEADDR + 0x104) & 0x40) == 0x40) {delay_ms(1);}
  delay_ms(10);
  rdata = Xil_In32(IIC_BASEADDR + 0x10c) & 0xff;
  if (display == 1) {
    printk("iic_read: addr(%02x) data(%02x)\n\r", raddr, rdata);
  }
  delay_ms(10);
  return(rdata);
}

/****************************************************************************
 * @brief CLKGEN_LookupFilter.
******************************************************************************/
static unsigned long CLKGEN_LookupFilter(unsigned long m)
{
	if (m < 47)
	{
		return clkgen_filter_table[m];
	}
	return 0x08008090;
}

/***************************************************************************//**
 * @brief CLKGEN_LookupLock.
*******************************************************************************/
static unsigned long CLKGEN_LookupLock(unsigned long m)
{
	if (m < 36)
	{
		return clkgen_lock_table[m];
	}
	return 0x1f1f00fa;
}

/***************************************************************************//**
 * @brief CLKGEN_CalcParams.
*******************************************************************************/
static void CLKGEN_CalcParams(unsigned long fin,
					   unsigned long fout,
					   unsigned long *best_d,
					   unsigned long *best_m,
					   unsigned long *best_dout)
{
	const unsigned long fpfd_min = 10000;
	const unsigned long fpfd_max = 300000;
	const unsigned long fvco_min = 600000;
	const unsigned long	fvco_max = 1200000;
	unsigned long		d		 = 0;
	unsigned long		d_min	 = 0;
	unsigned long		d_max	 = 0;
	unsigned long		_d_min	 = 0;
	unsigned long		_d_max	 = 0;
	unsigned long		m		 = 0;
	unsigned long		m_min	 = 0;
	unsigned long		m_max	 = 0;
	unsigned long		dout	 = 0;
	unsigned long		fvco	 = 0;
	long				f		 = 0;
	long				best_f	 = 0;

	fin /= 1000;
	fout /= 1000;

	best_f = 0x7fffffff;
	*best_d = 0;
	*best_m = 0;
	*best_dout = 0;

	d_min = MAX(DIV_ROUND_UP(fin, fpfd_max), 1);
	d_max = MIN(fin / fpfd_min, 80);

	m_min = MAX(DIV_ROUND_UP(fvco_min, fin) * d_min, 1);
	m_max = MIN(fvco_max * d_max / fin, 64);

	for(m = m_min; m <= m_max; m++)
	{
		_d_min = MAX(d_min, DIV_ROUND_UP(fin * m, fvco_max));
		_d_max = MIN(d_max, fin * m / fvco_min);

		for (d = _d_min; d <= _d_max; d++)
		{
			fvco = fin * m / d;

			dout = DIV_ROUND_CLOSEST(fvco, fout);
			dout = CLAMP(dout, 1, 128);
			f = fvco / dout;
			if (abs(f - fout) < abs(best_f - fout))
			{
				best_f = f;
				*best_d = d;
				*best_m = m;
				*best_dout = dout;
				if (best_f == fout)
				{
					return;
				}
			}
		}
	}
}

/***************************************************************************//**
 * @brief CLKGEN_CalcClkParams.
*******************************************************************************/
static void CLKGEN_CalcClkParams(unsigned long divider,
						  unsigned long *low,
						  unsigned long *high,
						  unsigned long *edge,
						  unsigned long *nocount)
{
	if (divider == 1)
	{
		*nocount = 1;
	}
	else
	{
		*nocount = 0;
	}
	*high = divider / 2;
	*edge = divider % 2;
	*low = divider - *high;
}

/***************************************************************************//**
 * @brief CLKGEN_Write.
*******************************************************************************/
static void CLKGEN_Write(unsigned long reg,
				  unsigned long val)
{
	Xil_Out32(CF_CLKGEN_BASEADDR + reg, val);
}

/***************************************************************************//**
 * @brief CLKGEN_Read.
*******************************************************************************/
static void CLKGEN_Read(unsigned long reg,
						unsigned long *val)
{
	*val = Xil_In32(CF_CLKGEN_BASEADDR + reg);
}

/***************************************************************************//**
 * @brief CLKGEN_MMCMRead.
*******************************************************************************/
static void CLKGEN_MMCMRead(unsigned long reg,
							unsigned long *val)
{
	unsigned long timeout = 1000000;
	unsigned long reg_val;

	do {
		CLKGEN_Read(AXI_CLKGEN_V2_REG_DRP_STATUS, &reg_val);
	} while ((reg_val & AXI_CLKGEN_V2_DRP_STATUS_BUSY) && --timeout);

	if (timeout == 0) {
		return;
	}

	reg_val = AXI_CLKGEN_V2_DRP_CNTRL_SEL | AXI_CLKGEN_V2_DRP_CNTRL_READ;
	reg_val |= (reg << 16);

	CLKGEN_Write(AXI_CLKGEN_V2_REG_DRP_CNTRL, 0x00);
	CLKGEN_Write(AXI_CLKGEN_V2_REG_DRP_CNTRL, reg_val);
	do {
		CLKGEN_Read(AXI_CLKGEN_V2_REG_DRP_STATUS, val);
	} while ((*val & AXI_CLKGEN_V2_DRP_STATUS_BUSY) && --timeout);

	if (timeout == 0) {
		return;
	}

	*val &= 0xffff;
}

/***************************************************************************//**
 * @brief CLKGEN_MMCMWrite.
*******************************************************************************/
static void CLKGEN_MMCMWrite(unsigned long reg,
					  unsigned long val,
					  unsigned long mask)
{
	unsigned long timeout = 1000000;
	unsigned long reg_val;

	do {
		CLKGEN_Read(AXI_CLKGEN_V2_REG_DRP_STATUS, &reg_val);
	} while ((reg_val & AXI_CLKGEN_V2_DRP_STATUS_BUSY) && --timeout);

	if (timeout == 0) {
		return;
	}

	if (mask != 0xffff) {
		CLKGEN_MMCMRead(reg, &reg_val);
		reg_val &= ~mask;
	} else {
		reg_val = 0;
	}

	reg_val |= AXI_CLKGEN_V2_DRP_CNTRL_SEL | (reg << 16) | (val & mask);

	Xil_Out32(CF_CLKGEN_BASEADDR + AXI_CLKGEN_V2_REG_DRP_CNTRL, 0x00);
	Xil_Out32(CF_CLKGEN_BASEADDR + AXI_CLKGEN_V2_REG_DRP_CNTRL, reg_val);
}

/***************************************************************************//**
 * @brief CLKGEN_MMCMEnable.
*******************************************************************************/
static void CLKGEN_MMCMEnable(char enable)
{
        unsigned long val = AXI_CLKGEN_V2_RESET_ENABLE;

        if (enable)
                val |= AXI_CLKGEN_V2_RESET_MMCM_ENABLE;

        CLKGEN_Write(AXI_CLKGEN_V2_REG_RESET, val);
}



/***************************************************************************//**
 * @brief CLKGEN_SetRate.
*******************************************************************************/
static int CLKGEN_SetRate(unsigned long rate,
				   unsigned long parent_rate)
{
	unsigned long d		  = 0;
	unsigned long m		  = 0;
	unsigned long dout	  = 0;
	unsigned long nocount = 0;
	unsigned long high	  = 0;
	unsigned long edge	  = 0;
	unsigned long low	  = 0;
	unsigned long filter  = 0;
	unsigned long lock	  = 0;

	printk("CLKGEN_SetRate %d\n",rate);

	if (parent_rate == 0 || rate == 0)
	{
		return 0;
	}

	CLKGEN_CalcParams(parent_rate, rate, &d, &m, &dout);

	if (d == 0 || dout == 0 || m == 0)
	{
		return 0;
	}

	filter = CLKGEN_LookupFilter(m - 1);
	lock = CLKGEN_LookupLock(m - 1);

	CLKGEN_MMCMEnable(0);

	CLKGEN_CalcClkParams(dout, &low, &high, &edge, &nocount);
	CLKGEN_MMCMWrite(MMCM_REG_CLKOUT0_1, (high << 6) | low, 0xefff);
	CLKGEN_MMCMWrite(MMCM_REG_CLKOUT0_2, (edge << 7) | (nocount << 6), 0x03ff);


	CLKGEN_CalcClkParams(d, &low, &high, &edge, &nocount);
	CLKGEN_MMCMWrite(MMCM_REG_CLK_DIV, (edge << 13) | (nocount << 12) | (high << 6) | low, 0x3fff);

	CLKGEN_CalcClkParams(m, &low, &high, &edge, &nocount);
	CLKGEN_MMCMWrite(MMCM_REG_CLK_FB1, (high << 6) | low, 0xefff);
	CLKGEN_MMCMWrite(MMCM_REG_CLK_FB2, (edge << 7) | (nocount << 6), 0x03ff);

	CLKGEN_MMCMWrite(MMCM_REG_LOCK1, lock & 0x3ff, 0x3ff);
	CLKGEN_MMCMWrite(MMCM_REG_LOCK2, (((lock >> 16) & 0x1f) << 10) | 0x1, 0x7fff);
	CLKGEN_MMCMWrite(MMCM_REG_LOCK3, (((lock >> 24) & 0x1f) << 10) | 0x3e9, 0x7fff);
	CLKGEN_MMCMWrite(MMCM_REG_FILTER1, filter >> 16, 0x9900);
	CLKGEN_MMCMWrite(MMCM_REG_FILTER2, filter, 0x9900);
	CLKGEN_MMCMEnable(1);

	return 0;
}

/***************************************************************************//**
 * @brief CLKGEN_GetRate.
*******************************************************************************/
static unsigned long CLKGEN_GetRate(unsigned long parent_rate)
{
	unsigned long d, m, dout;
	unsigned long reg;
	unsigned long tmp;

	CLKGEN_MMCMRead(MMCM_REG_CLKOUT0_1, &reg);
	dout = (reg & 0x3f) + ((reg >> 6) & 0x3f);
	CLKGEN_MMCMRead(MMCM_REG_CLK_DIV, &reg);
	d = (reg & 0x3f) + ((reg >> 6) & 0x3f);
	CLKGEN_MMCMRead(MMCM_REG_CLK_FB1, &reg);
	m = (reg & 0x3f) + ((reg >> 6) & 0x3f);

	if (d == 0 || dout == 0)
		return 0;

	tmp = (unsigned long)(parent_rate / d) * m;
	tmp = tmp / dout;

	if (tmp > 0xffffffff)
	{
		return 0xffffffff;
	}

	return (unsigned long)tmp;
 }




/***************************************************************************//**
 * @brief DDRVideoWr.
*******************************************************************************/
static void DDRVideoWr(unsigned short horizontalActiveTime,
				unsigned short verticalActiveTime)
{
	unsigned long  pixel      = 0;
	unsigned long  backup     = 0;
	unsigned short line       = 0;
	unsigned long  index      = 0;
	unsigned char  repetition = 0;

	while(line < verticalActiveTime)
	{
		for(index = 0; index < IMG_LENGTH; index++)
		{
			for (repetition = 0; repetition < ((IMG_DATA[index]>>24) & 0xff); repetition++)
			{
				backup = pixel;
				while((pixel - line*horizontalActiveTime) < horizontalActiveTime)
				{
					Xil_Out32((VIDEO_BASEADDR+(pixel*4)), (IMG_DATA[index] & 0xffffff));
					pixel += 640;
				}
				pixel = backup;
				if((pixel - line*horizontalActiveTime) < 639)
				{
					pixel++;
				}
				else
				{
					line++;
					if(line == verticalActiveTime)
					{
						return;
					}
					pixel = line*horizontalActiveTime;
				}
			}
		}
	}
}


/***************************************************************************//**
 * @brief InitHdmiVideoPcore.
*******************************************************************************/
static void InitHdmiVideoPcore(unsigned short horizontalActiveTime,
						unsigned short horizontalBlankingTime,
						unsigned short horizontalSyncOffset,
						unsigned short horizontalSyncPulseWidth,
						unsigned short verticalActiveTime,
						unsigned short verticalBlankingTime,
						unsigned short verticalSyncOffset,
						unsigned short verticalSyncPulseWidth)
{
	unsigned short horizontalCount	   = 0;
	unsigned short verticalCount	   = 0;
	unsigned short horizontalBackPorch = 0;
	unsigned short verticalBackPorch   = 0;
	unsigned short horizontalDeMin	   = 0;
	unsigned short horizontalDeMax	   = 0;
	unsigned short verticalDeMin	   = 0;
	unsigned short verticalDeMax	   = 0;

	DDRVideoWr(horizontalActiveTime, verticalActiveTime);

	horizontalCount = horizontalActiveTime +
					  horizontalBlankingTime;
	verticalCount = verticalActiveTime +
					verticalBlankingTime;
	horizontalBackPorch = horizontalBlankingTime -
						  horizontalSyncOffset -
						  horizontalSyncPulseWidth;
	verticalBackPorch = verticalBlankingTime -
						verticalSyncOffset -
						verticalSyncPulseWidth;
	horizontalDeMin = horizontalSyncPulseWidth +
					  horizontalBackPorch;
	horizontalDeMax = horizontalDeMin +
					  horizontalActiveTime;
	verticalDeMin = verticalSyncPulseWidth +
					verticalBackPorch;
	verticalDeMax = verticalDeMin +
					verticalActiveTime;

	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_HTIMING1),
			  ((horizontalActiveTime << 16) | horizontalCount));
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_HTIMING2),
			  horizontalSyncPulseWidth);
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_HTIMING3),
			  ((horizontalDeMax << 16) | horizontalDeMin));
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_VTIMING1),
			  ((verticalActiveTime << 16) | verticalCount));
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_VTIMING2),
			  verticalSyncPulseWidth);
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_VTIMING3),
			  ((verticalDeMax << 16) | verticalDeMin));
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_RESET), 0x1);
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_SOURCE_SEL), 0x0);
	Xil_Out32((CFV_BASEADDR + AXI_HDMI_REG_SOURCE_SEL), 0x1);

	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_DMA_CTRL),
			  0x00000003); // enable circular mode
	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_START_1),
			  VIDEO_BASEADDR); // start address
	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_START_2),
			  VIDEO_BASEADDR); // start address
	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_START_3),
			  VIDEO_BASEADDR); // start address
	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_FRMDLY_STRIDE),
			  (horizontalActiveTime*4)); // h offset
	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_H_SIZE),
			  (horizontalActiveTime*4)); // h size
	Xil_Out32((VDMA_BASEADDR + AXI_VDMA_REG_V_SIZE),
			  verticalActiveTime); // v size
}

/***************************************************************************//**
 * @brief SetVideoResolution.
*******************************************************************************/
static void SetVideoResolution(unsigned char resolution)
{
	CLKGEN_SetRate(detailedTiming[resolution][PIXEL_CLOCK], 200000000);
	InitHdmiVideoPcore(detailedTiming[resolution][H_ACTIVE_TIME],
					   detailedTiming[resolution][H_BLANKING_TIME],
					   detailedTiming[resolution][H_SYNC_OFFSET],
					   detailedTiming[resolution][H_SYNC_WIDTH_PULSE],
					   detailedTiming[resolution][V_ACTIVE_TIME],
					   detailedTiming[resolution][V_BLANKING_TIME],
					   detailedTiming[resolution][V_SYNC_OFFSET],
					   detailedTiming[resolution][V_SYNC_WIDTH_PULSE]);
}







static u32 ddr_video_wr(void) {

  u32 n;
  u32 d;
  u32 dcnt;
  u32 r;
  u32 g;
  u32 b;
  u32 i ;

  dcnt = 0;
  printk("DDR write: started (length %d)\n", IMG_LENGTH);
   for (n = 0; n < IMG_LENGTH; n++) {
    for (d = 0; d < ((IMG_DATA[n]>>24) & 0xff); d++) {
      //r = (IMG_DATA[n] & 0x0000ff);
      //g = (IMG_DATA[n] & 0x00ff00);
      //b = ((IMG_DATA[n] & 0xff0000) >> 16);
      //Xil_Out32((VIDEO_BASEADDR+(dcnt*4)), (IMG_DATA[n] & 0x00ff00) | b << 16 | r);
      //Xil_Out32((VIDEO_BASEADDR+(dcnt*4)), (IMG_DATA[n] & 0xffffff));

     	Xil_Out32((VIDEO_BASEADDR+(dcnt*4)), (IMG_DATA[n] & 0xffffff));
		dcnt = dcnt + 1;
    }
  }

 //   memset(VIDEO_BASEADDR, 0xFF, BUF_SIZE);

 //   for (i = 0; i < BUF_SIZE/4; i++)
	// 	VIDEO_BASEADDR[i] = 0xa00a ; //VIDEO_BASEADDR[BUF_SIZE -i];
	// printk("VIDEO_BASEADDR[i] = 0xa0 \n") ;
  printk("DDR write: completed (total %d)\n", dcnt);

  return 0 ;
}



static u32 video_buf_ioctl(struct inode *inode, struct file *file, unsigned int cmd, unsigned long arg)
{
	switch (cmd)
	{
		case GET_VIRTUAL_ADDRESS :
		{
			return (u32) VIDEO_BASEADDR ;
		}

		case GET_PHY_ADDRESS :
		{
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
	 
	VIDEO_BASEADDR = (u32 *)dma_alloc_writecombine(NULL, BUF_SIZE, &src_phys, GFP_KERNEL);
	if (NULL == VIDEO_BASEADDR)
	{
		printk("can't alloc buffer for VIDEO_BASEADDR\n");
		return -ENOMEM;
	}
	
	major = register_chrdev(0, "videobuf", &dma_fops);

	 
	cls = class_create(THIS_MODULE, "videobuf");
	device_create(cls, NULL, MKDEV(major, 0), NULL, "Vbuf"); /* /dev/dma */

	ddr_video_wr();  //set all 0xFF
	//ioremap to user space 
	CF_CLKGEN_BASEADDR =(char *) ioremap(XPAR_AXI_HDMI_CLKGEN_BASEADDR, 0xFF);
	if (!CF_CLKGEN_BASEADDR){
		printk("ioremap for CF_CLKGEN_BASEADDR error\n");
		return -ENOMEM;
	}
	printk("CF_CLKGEN_BASEADDR is 0x%08x  , XPAR_AXI_HDMI_CLKGEN_BASEADDR is 0x%08x\n",CF_CLKGEN_BASEADDR,XPAR_AXI_HDMI_CLKGEN_BASEADDR);
	CFV_BASEADDR  =(char *) ioremap(XPAR_AXI_HDMI_CORE_BASEADDR, 0xFFF);
	CFA_BASEADDR  =(char *) ioremap(XPAR_AXI_SPDIF_TX_CORE_BASEADDR, 0xFFF);
	VDMA_BASEADDR =(char *) ioremap(0x43000000, 0xFFF);
	ADMA_BASEADDR =(char *) ioremap(0x40400000, 0xFFF);
	IIC_BASEADDR  =(char *) ioremap(XPAR_AXI_IIC_MAIN_BASEADDR, 0xFFF);


	SetVideoResolution(RESOLUTION_640x480);
	//CLKGEN_SetRate(detailedTiming[RESOLUTION_640x480][PIXEL_CLOCK], 200000000);
	u32 i = 0;
//	for(i = 0 ; i < clk_gen_reg_length; i++)
	for(i = 0 ; i < 10; i++)
	{
		Xil_Out32(CF_CLKGEN_BASEADDR + clk_gen_reg[i], clk_gen_reg_val[i]);
		printk("write address is 0x%08x \n",CF_CLKGEN_BASEADDR + clk_gen_reg[i]);
		delay_ms(1);
	}


	u32 data ;

	data = Xil_In32(CF_CLKGEN_BASEADDR + (0x17*4));
	if ((data & 0x1) == 0x0) {
		printk("CLKGEN out of lock (0x%04x)\n\r", data);
		return -1;
	}
	printk("CLKGEN locked (0x%04x)\n\r", data);


	// data = Xil_In32(CF_CLKGEN_BASEADDR + (0x0*4));
	// printk("CLKGEN_PCORE_VERSION 0x%08x\n",data);
	// data = Xil_In32(CF_CLKGEN_BASEADDR + (0x01*4));
	// printk("CLKGEN_PCORE_VERSION 0x%08x\n",data);
	// data = Xil_In32(CF_CLKGEN_BASEADDR + (0x1c*4));
	// printk("CLKGEN_PCORE_VERSION 0x%08x\n",data);
	// data = Xil_In32(CF_CLKGEN_BASEADDR + (0x1d*4));
	// printk("CLKGEN_PCORE_VERSION 0x%08x\n",data);



// //	static void iic_write(char* daddr, u32 waddr, u32 wdata) {
// 	u32 loopcnt =0 ;
// 	printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 	Xil_Out32((IIC_BASEADDR + 0x100), 0x002); // reset tx fifo
// 	printk("(IIC_BASEADDR + 0x100) = %04x\n",Xil_In32(IIC_BASEADDR + 0x100));
// 	printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 	Xil_Out32((IIC_BASEADDR + 0x100), 0x001); // enable iic
// 	printk("(IIC_BASEADDR + 0x100) = %04x\n",Xil_In32(IIC_BASEADDR + 0x100));
// 	printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 	Xil_Out32((IIC_BASEADDR + 0x108), (0x100 | ((char)0x39<<1))); // select
// 	printk("(IIC_BASEADDR + 0x108) = %04x\n",Xil_In32(IIC_BASEADDR + 0x108));
// 	printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 	Xil_Out32((IIC_BASEADDR + 0x108), 0x02); // address
// 	printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 	Xil_Out32((IIC_BASEADDR + 0x108), (0x200 | 0x18)); // data
// 	printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 	while ((Xil_In32(IIC_BASEADDR + 0x104) & 0x80) == 0x00) 
// 	{
// 		delay_ms(1);
// 		if(loopcnt == 0xfffff)
// 		{
// 			printk("timeout\n") ;
// 			printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 			break;
// 		}
// 		loopcnt++ ;
// 	}
// 	printk("succeed\n") ;
// //	iic_write(0x39, 0x02, 0x18);
// 	delay_ms(10);
// //}


// //	static u32 iic_read(char* daddr, u32 raddr, u32 display) {
//   u32 rdata;
//   Xil_Out32((IIC_BASEADDR + 0x100), 0x002); // reset tx fifo
//   Xil_Out32((IIC_BASEADDR + 0x100), 0x001); // enable iic
//   Xil_Out32((IIC_BASEADDR + 0x108), (0x100 | ((u32)0x39<<1))); // select
//   Xil_Out32((IIC_BASEADDR + 0x108), 0x02); // address
//   Xil_Out32((IIC_BASEADDR + 0x108), (0x101 | ((u32)0x39<<1))); // select
//   Xil_Out32((IIC_BASEADDR + 0x108), 0x201); // data
//   loopcnt = 0 ;
//   	while ((Xil_In32(IIC_BASEADDR + 0x104) & 0x80) == 0x00) 
// 	{
// 		delay_ms(1);
// 		if(loopcnt == 0xfffff)
// 		{
// 			printk("timeout\n") ;
// 			printk("(IIC_BASEADDR + 0x104) = %04x\n",Xil_In32(IIC_BASEADDR + 0x104));
// 			break;
// 		}
// 		loopcnt++ ;
// 	}
//   delay_ms(10);
//   rdata = Xil_In32(IIC_BASEADDR + 0x10c) & 0xff;
//   if ( 1) {
//     printk("iic_read: addr(%02x) data(%02x)\n\r", 0x2, rdata);
//   }
//   delay_ms(10);

	// int j = 0 ;
	// for(j = 0 ; j < 0xFE ; j++){
	//   iic_write(0x39, j, iic_regVal[j]);
	// }


	 Xil_Out32((CFV_BASEADDR + 0x18), 0xff); // clear status


	return 0;
}

static void video_buf_exit(void)
{
	iounmap(CF_CLKGEN_BASEADDR);
	iounmap(CFV_BASEADDR);
	iounmap(CFA_BASEADDR);
	iounmap(VDMA_BASEADDR);
	iounmap(ADMA_BASEADDR);
	iounmap(IIC_BASEADDR);

	dma_free_writecombine(NULL, BUF_SIZE, VIDEO_BASEADDR, src_phys);
	device_destroy(cls, MKDEV(major, 0));
	class_destroy(cls);
	unregister_chrdev(major, "videobuf");
	printk("vhdma driver removed\n") ;
}

module_init(video_buf_init);
module_exit(video_buf_exit);

MODULE_LICENSE("GPL");

