module axis2dvp (
	input 				clk    ,    // Clock
	input 				clk_en , // Clock Enable
	input 				rst_n  ,  // Asynchronous reset active low

	input wire[24:0]	sofRGB , 
	input wire          clk_24MHz , 

	// dvp signals 
	// output wire                                       cmos_scl,         //cmos i2c clock
	// inout  wire                                       cmos_sda,         //cmos i2c data
	input  wire                                       cmos_vsync,       //cmos vsync
	input  wire                                       cmos_href,        //cmos hsync refrence
	input  wire                                       cmos_pclk,        //cmos pxiel clock

	input  wire  [9:0]                                cmos_data,          //cmos data
	output wire                                       cmos_reset       //cmos reset
);

/*				
		main clk domain 		 _________       
								|         |
								|         |
	axis-from-ddr ------->		|         | -----------> axis-2-dvp
								| FIFO    |
								|         |
								|         |
								|_________|
                       
                       |<-------------- 510 x Tline  -------------------------------------------------->|
                        ______                                                                           ______
	VSYNC     _________|      |_________________________________________________________________________|      |________________
					   |<---->|
					   3x Tline
							  |<-17Tline->|<--------------------480Tline------------------->|<-10Tline->|
                                           __________         __________                     ________
	HREF _________________________________|          |_______|          |_______\\\\\\\\____|        |___________________________________
                                                     |<----->|
                                                 		144Tp
                                          |<-------->|
                                            640Tp
                                          |<---784Tp-------->|

	HSYNC -------\\\\\\\____________    ______________    ________________    ____......
	                                |__|              |__|                |__|
                                 -->|  |<---        ---->|   |<--     ->| |<----
									80Tp                  45Tp          19Tp


	*************************************************************************************************

                ____      ____       ____
	PCLK   ____|    |____|    |_____|    |_____  ?????? for VGA RGB656 1Tp = 2 PCLK , VGA YUV422 1Tp = 3 PCLK ?  check it out 
                _________ __________ _________  
	DATA   \\\\X__H______X__L_______X______     RGB656 

*/



































endmodule