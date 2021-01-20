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



/*
	author : WuChengHe
	
	funtion discription : 
		derive Lr(P,Di) from Ll(P,Di)

*/
`timescale 1 ns / 1 ps
module LeftRightCheck
#(
	parameter  MAXDISPARITY = 64 ,
	parameter  INPUTDATAWID = 9,    // 8   + 1(SOF)
	parameter  DISP_WIDTH   = 8 ,
	parameter  OUTPUTDATAWID = 9
  )
(
	input wire                      clk                               ,         // 150 Clock
	input wire                      en                                ,
	input wire                      pixelEN                           ,
	input wire[INPUTDATAWID-1:0]    Disparity_Left                     ,         
	input wire[INPUTDATAWID-1:0]    Disparity_Right                    ,         
	output wire[OUTPUTDATAWID-1:0]  dispOutput_left                   ,  
	output wire                     dispOutput_left_valid             ,
	input  wire							rst_n                                        
	
);


/*
	input signal :  Ll(P(x,y),Di) 
	output signal : Lr(P(x,y),Di) 

                            P(x0,y)                                
			---Dl(p)------------------------------------------------
                                                                    |
                                 ________________________           |
			---Dr(p)----------->|____D___________________|------(abs(-))----------
							                         P(x0-d,y)
			d=Dl(x,y);
			abs(Dr(x-d,y) - Dl(x,y)) > 1 ???? 
				
*/
integer i ;
reg [INPUTDATAWID-2:0] Disparity_Right_shiftRegisterArray_sclkrate [0:MAXDISPARITY-1] ;
reg [INPUTDATAWID-2:0] Disparity_Left_shiftRegisterArray_sclkrate [0:MAXDISPARITY-1] ;
reg [0:0] SOF_dly_sclkrate [0:MAXDISPARITY-1] ;

wire SOF_atLeftPxy ;
reg SOF_atLeftPxy_Dly1_sclkrate ;
wire[DISP_WIDTH-1:0] dispValueAtLeft , dispValueAtRight ;
wire [DISP_WIDTH-1:0]  finalDispOutput_wire ;
reg [DISP_WIDTH-1:0]  finalDispOutput_reg_sclkrate ;
wire signed [DISP_WIDTH:0] LeftMinusRight ;
wire [DISP_WIDTH:0] abs_LeftMinusRight ; 

assign SOF_atLeftPxy = SOF_dly_sclkrate[0];

always@(posedge clk)
if(en && pixelEN)
begin
	Disparity_Right_shiftRegisterArray_sclkrate[0] <=  Disparity_Right[INPUTDATAWID-2:0] ;
	Disparity_Left_shiftRegisterArray_sclkrate[0] <=  Disparity_Left [INPUTDATAWID-2:0];
	SOF_dly_sclkrate[0] <= Disparity_Left[INPUTDATAWID-1];
	for(i=1; i < MAXDISPARITY ; i = i+1)
	begin 
		Disparity_Right_shiftRegisterArray_sclkrate[i] <= Disparity_Right_shiftRegisterArray_sclkrate[i-1] ;
		Disparity_Left_shiftRegisterArray_sclkrate[i] <= Disparity_Left_shiftRegisterArray_sclkrate[i-1] ;
		SOF_dly_sclkrate[i] <= SOF_dly_sclkrate[i-1] ;
	end
end

assign dispValueAtLeft  = Disparity_Left_shiftRegisterArray_sclkrate[0] ;
assign dispValueAtRight = Disparity_Right_shiftRegisterArray_sclkrate[ dispValueAtLeft ] ;   // P(x - dispValueAtLeft,y)

// signed , make sure the first bit is 1'b0, or signed expand {dispValueAtRight[9],dispValueAtRight}, here , dispValueAtRight is unsigned , pad 1'b0 in MSB
// should be very careful about this 
assign	LeftMinusRight = $signed({1'b0,dispValueAtLeft}) - $signed({1'b0,dispValueAtRight}) ;   
assign  abs_LeftMinusRight = (LeftMinusRight[DISP_WIDTH]==1'b0) ? LeftMinusRight : ~(LeftMinusRight) + 1'b1  ;  // abs(l-r)
assign  finalDispOutput_wire = (abs_LeftMinusRight > 1)? 8'h0 : dispValueAtLeft[DISP_WIDTH-1:0]  ;

always@(posedge clk)
if(en && pixelEN)
begin
	SOF_atLeftPxy_Dly1_sclkrate   <= SOF_atLeftPxy ;
	finalDispOutput_reg_sclkrate <= finalDispOutput_wire ;
end 

assign dispOutput_left[OUTPUTDATAWID-2:0] = finalDispOutput_reg_sclkrate ;
assign dispOutput_left[OUTPUTDATAWID-1]   =  SOF_atLeftPxy_Dly1_sclkrate ;

reg data_out_is_valid =0;
always@(posedge clk)
if(en && pixelEN)
begin
	if(~rst_n)
		data_out_is_valid <= 1'b0 ;
	else if(SOF_atLeftPxy)
		data_out_is_valid <= 1'b1 ;
end
assign dispOutput_left_valid = data_out_is_valid & en & pixelEN ;


endmodule