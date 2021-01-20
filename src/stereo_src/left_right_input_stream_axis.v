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




`timescale 1 ns / 1 ps

module stereo_v1_0_S00_AXIS #
(
	// Users to add parameters here
	parameter integer STREAM_WIDTH = 18 ,
	// User parameters ends
	// Do not modify the parameters beyond this line

	// AXI4Stream sink: Data Width
	parameter integer C_S_AXIS_TDATA_WIDTH	= 32
)
(
	// Users to add ports here
	output  wire[STREAM_WIDTH-1:0]    READFIFO_OUTPUT ,    // {sof, 8_bit_image_data}
	output  wire         READ_FIFO_EMPTY          , 
	input   wire         PIXEL_EN                 ,    // pixel clock  en 
	input   wire         EN                       ,  


	input  	wire         MCLK                     ,
	input   wire         CORE_RSTN                ,

	// User ports ends
	// Do not modify the ports beyond this line

	/*********** left stream interface *****************/
	// AXI4Stream sink: Clock
	input wire  S_AXIS_ACLK_LEFT,
	// AXI4Stream sink: Reset
	input wire  S_AXIS_ARESETN_LEFT,
	// Ready to accept data in
	output wire  S_AXIS_TREADY_LEFT,
	// Data in
	input wire [C_S_AXIS_TDATA_WIDTH-1 : 0]     S_AXIS_TDATA_LEFT,
	// Byte qualifier
	input wire [0 : 0] S_AXIS_TUSER_LEFT,
	// Indicates boundary of last packet
	input wire  S_AXIS_TLAST_LEFT,
	// Data is in valid
	input wire  S_AXIS_TVALID_LEFT ,


	/***************** right stream interface *************/
	// AXI4Stream sink: Clock
	input wire  S_AXIS_ACLK_RIGHT,
	// AXI4Stream sink: Reset
	input wire  S_AXIS_ARESETN_RIGHT,
	// Ready to accept data in
	output wire  S_AXIS_TREADY_RIGHT,
	// Data in
	input wire [C_S_AXIS_TDATA_WIDTH-1 : 0]     S_AXIS_TDATA_RIGHT,
	// Byte qualifier
	input wire [0 : 0] S_AXIS_TUSER_RIGHT,
	// Indicates boundary of last packet
	input wire  S_AXIS_TLAST_RIGHT,
	// Data is in valid
	input wire  S_AXIS_TVALID_RIGHT
);


integer i ;
/*
input data layout : [0x00,R,G,B]

the capture model can not use the fifo,it is supposed to stream without pause . this is how the camera sensor works . 
rewrite the capture model if neccessary !

state machine : 
it is quite simple to do the synchronization, just use two buffer line, 
		      _____                 ___ ___ ___ ___ ____  
_____________|     |___ sof_left   |___|___|___|___|____|------> 
                                    
              _____                 ___ ___ ___ ___ ____
_____________|     |___ sof_right  |___|___|___|___|____|------>
			                       
ideally, the two SOFs should be aligned, if not, the delay between them is constant, so the pupose of the buffer line here is to 
compensate the delay, so that the output of the buffer line is aligned !!! 

*/

// synchronize left and right stream 

reg [23+1:0] left_stream_taps  [0:8] ;
reg [23+1:0] right_stream_taps [0:8] ;
reg [24:0] left_stream_from_tap , right_stream_from_tap ;

always@(posedge MCLK)
if(PIXEL_EN && EN)
begin
	for(i=1;i<8;i=i+1)
	begin
		left_stream_taps[i]  <= left_stream_taps[i-1];
		right_stream_taps[i] <= right_stream_taps[i-1];
	end
	left_stream_taps[0]  <= {S_AXIS_TUSER_LEFT,S_AXIS_TDATA_LEFT} ;
	right_stream_taps[0] <= {S_AXIS_TUSER_RIGHT,S_AXIS_TDATA_RIGHT} ;
end

wire [4:0] selbits = {left_stream_taps[1][24],left_stream_taps[2][24],left_stream_taps[3][24],left_stream_taps[4][24],left_stream_taps[5][24]} ;
reg[3:0] index_sel ;

always@(*)
if(left_stream_taps[3][24] == 1'b1)  // sof at left stream 
begin
	case(selbits) 
		5'b10000 :  index_sel = 0;
		5'b01000 :  index_sel = 1;
		5'b00100 :  index_sel = 2;
		5'b10010 :  index_sel = 3;
		5'b10001 :  index_sel = 4;
		default  :  index_sel = 2;
end

always@(posedge MCLK)
if(PIXEL_EN && EN)
begin
	left_stream_from_tap <= left_stream_taps[3] ; // from the middle tap postition
	right_stream_from_tap <= right_stream_taps[index_sel] ;
end


// RGB to grayscale G =  B*0.07 + G*0.72 + R* 0.21









endmodule
