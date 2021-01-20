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


module TimeGen
#(
	parameter IMAGE_WIDTH = 640 ,
	parameter IMAGE_HEIGHT = 480
)
(
	input  wire  clk,    // Clock
	input  wire clk_en, // Clock Enable
	input  wire rst_n,  // reset active low
	input  wire inStreamIsSynedAndFifoIsNotEmpty ,
	input  wire  EN ,
	output wire  EN_OUT ,
	input  wire  wirte_fifo_full ,
	input  wire  read_fifo_empty ,
	input  wire  CPU_DATA_IS_READY ,
	output wire  MM2S_FSYN         ,
	input  wire  RSTN_STEREOIP_FROM_CPU ,
	output wire  SYSTEM_RSTN ,
	output wire  sof ,
	output wire  eol ,
	output wire[9:0] colCntAlignedWithSOF_wire ,
	output wire[9:0] rowCntAlignedWithSOF_wire ,
	output wire[9:0] colCnt_wire ,
	output wire[9:0] rowCnt_wire ,
	output wire    PIXEL_EN_div2 ,
	output wire  pixelEN
);

/*
            ____ _____ _____ _____
	colCnt  ____X__0__X__1__X_____
	        ____ _______________
	rowCnt  ____X__0_________
                       _____
	sof     __________|	    |_______
	        __________ _____ _____ _____
inputData_left _______X_D0__X_D1__X__D2__

*/

reg pixelEN_reg = 0 ;
reg [2:0] pixelEN_cnt = 0 ;
reg [3:0] PIXEL_EN_div2_cnt = 0;
reg sof_reg = 0;
reg eol_reg = 0;
reg[2:0] cpu_data_is_ready_dly;
reg [2:0] restn_stereoip_from_cpu_dly ;

reg[9:0] colCnt=0;
reg[9:0] rowCnt=1;

reg mm2s_fsyn_reg ;
reg SYSTEM_RSTN_reg = 0 ;

reg[9:0] colCntAlignedWithSOF ;
reg[9:0] rowCntAlignedWithSOF ;

reg pixelEN_div2_reg = 0;

// when fifo is full(stillhave several position open) , it can write at the current time step, but write enable is deassertted at the next time step 
// when fifi is empty(still have several left) , it can still read at the current time step, but read enable is deasserted at the next time step 
// EN signal is only controlled by write_fifo_wen  &  read_fifo_ren & transmitting_state
/*
                                       _______________________________________
	write_fifo_is_full _______________|                 read_fifo_is_empty    |_________________________
              _____ ______ ______ ____ _____ ________________________________________________ _______ ______ ___________
	data     ______X______X______X____X_____X________________________________________________X_______X______X___......
                       _____________________                                           ___________________
	EN                                      |_________________________________________|
                       _____________________                                           ___________________
	write_fifo_wen                          |_________________________________________|
                       _____________________                                           ___________________
	read_fifo_ren                           |_________________________________________|

*/



reg en_reg = 0 ;  

assign EN_OUT =  en_reg ;

always@(posedge clk)
if(pixelEN)
begin
	if ((~wirte_fifo_full) && inStreamIsSynedAndFifoIsNotEmpty )
		en_reg <= 1'b1 ;
	else 
		en_reg <= 1'b0 ;
end

always@(posedge clk)  // from low clock domain to high speed clock domain 
begin
	cpu_data_is_ready_dly <= {cpu_data_is_ready_dly[1:0],CPU_DATA_IS_READY} ;
	restn_stereoip_from_cpu_dly <= {restn_stereoip_from_cpu_dly[1:0],RSTN_STEREOIP_FROM_CPU} ;
	mm2s_fsyn_reg <= cpu_data_is_ready_dly[2] & (~cpu_data_is_ready_dly[1]) ;       // falling edge 
	SYSTEM_RSTN_reg <= (~restn_stereoip_from_cpu_dly[2]) & (restn_stereoip_from_cpu_dly[1]) ;  //rising edge 
end
assign MM2S_FSYN   = mm2s_fsyn_reg  ;
assign SYSTEM_RSTN = ~SYSTEM_RSTN_reg;

always@(posedge clk)
begin
	if(pixelEN_cnt==7)
	begin
		pixelEN_cnt <= 0 ;
	end
	else begin
		pixelEN_cnt <= pixelEN_cnt + 1'b1 ;
	end

	if(pixelEN_cnt == 7 )
		pixelEN_reg <= 1'b1 ;
	else
		pixelEN_reg <= 1'b0 ;
end


always@(posedge clk)
begin
	if(PIXEL_EN_div2_cnt == 15)
	begin
		PIXEL_EN_div2_cnt <= 0 ;
	end
	else begin
		PIXEL_EN_div2_cnt <= PIXEL_EN_div2_cnt + 1'b1 ;
	end

	if(PIXEL_EN_div2_cnt == 15)
		pixelEN_div2_reg <= 1'b1 ;
	else 
		pixelEN_div2_reg <= 1'b0 ;

end


assign PIXEL_EN_div2 = pixelEN_div2_reg ;

always@(posedge clk )
begin
	if(~rst_n)
	begin
		colCnt<= 0;
		rowCnt<= 0;
	end
	else if(EN) begin
		if(colCnt == IMAGE_WIDTH -1)
			colCnt <= 0 ;
		else
			colCnt <= colCnt + 1'b1;
		if(rowCnt == IMAGE_HEIGHT-1 && colCnt == IMAGE_WIDTH -1)
		begin
			rowCnt <= 0 ;
		end
		else if(colCnt == IMAGE_WIDTH -1) begin
			rowCnt <= rowCnt + 1'b1 ;
		end
	end
end


always@(posedge clk)
if(EN)
begin
	if(colCnt == 0 && rowCnt == 0)
		sof_reg <= 1'b1 ;
	else
		sof_reg <= 1'b0 ;
	if(colCnt == IMAGE_WIDTH-1)
		eol_reg <= 1'b1 ;
	else
		eol_reg <= 1'b0 ;

	colCntAlignedWithSOF <= colCnt ;
	rowCntAlignedWithSOF <= rowCnt ;
end


assign pixelEN = pixelEN_reg ;
assign sof = sof_reg ;
assign eol = eol_reg ;
assign colCntAlignedWithSOF_wire = colCntAlignedWithSOF ;
assign rowCntAlignedWithSOF_wire = rowCntAlignedWithSOF ;
assign rowCnt_wire = rowCnt ;
assign colCnt_wire = colCnt ;



endmodule
