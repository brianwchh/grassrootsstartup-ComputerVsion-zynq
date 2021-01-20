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