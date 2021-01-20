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
module LPDiRightVolumn
#(
	parameter  MAXDISPARITY = 64 ,
	parameter  INPUTDATAWID = 513,    // 8 * 64 + 1(SOF)
	parameter  LPDI_WIDTH = 8 ,
	parameter  OUTPUTDATAWID = 513
  )
(
	input wire                      clk                               ,         // 150 Clock
	input wire                      en                                ,
	input wire                      pixelEN                           ,
	input wire                      sof_in                            , 
	input wire                   	eol_in                            ,
	output wire                  	sof_out                           ,
	output wire                  	eol_out                           ,
	input  wire[OUTPUTDATAWID-1:0]  LPDiLeft_in                          ,         // W*H*D volumn     
	output wire[OUTPUTDATAWID-1:0]  LPDiRight                         ,         // W*H*D volumn   
	output wire[OUTPUTDATAWID-1:0]  LPDiLeft                          ,         // W*H*D volumn               
	input wire						rst_n                                       // Asynchronous reset active low
	
);

wire [LPDI_WIDTH-1:0] LPDiLeftArrayShift_2dArray_wire [0:MAXDISPARITY-1] [0:MAXDISPARITY-1] ;
reg [OUTPUTDATAWID-1:0] LPDiLeft_1dArray_shift_reg_sclkrate [0:MAXDISPARITY-1] ;    // Lr0(P(x-1:x-DN,y),Di)
wire [LPDI_WIDTH-1:0] LPDiRight_2DArray_wire [0:MAXDISPARITY-1];    
(* MARK_DEBUG="true" *)wire SOF_atPxy  ; 

integer i,j;

// convert to 3D volumn wire 
genvar k, l ;
generate 
	for(l = 0 ; l < MAXDISPARITY; l=l+1)
		for (k = 0; k < MAXDISPARITY; k=k+1) 
		begin
			assign LPDiLeftArrayShift_2dArray_wire[l][k] = LPDiLeft_1dArray_shift_reg_sclkrate[l][(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] ;
		end
endgenerate

assign SOF_atPxy = LPDiLeft_1dArray_shift_reg_sclkrate[MAXDISPARITY-1][OUTPUTDATAWID-1] ;

/************************************************************************************************************
 ************************************************************************************************************
 					register based FIFO array 
 ************************************************************************************************************
 ************************************************************************************************************/
/*
	input signal :  Ll(P(x,y),Di) 
	output signal : Lr(P(x,y),Di)
                                ___________                                 ____
                               | + + + + + |                                 /|\
                               | + * + + + |                                  |
	Ll(P(x,y),Di) -----------> | + + * + + | ----------> Lr(P(x,y),Di)        | DN = 64
							   | + + + * + |                                  |
				WriteAddr ---> | + + + + * | <------- ReadAddr                |
							   |___________|                                 \|/
				                                                             ---
*/
always @(posedge clk ) 
if(en && pixelEN)
begin : ShiftArray
	LPDiLeft_1dArray_shift_reg_sclkrate[0] <= LPDiLeft_in ;
	for(i=1; i<MAXDISPARITY;i=i+1)
	begin
		LPDiLeft_1dArray_shift_reg_sclkrate[i] <= LPDiLeft_1dArray_shift_reg_sclkrate[i-1];
	end
end

generate 
		for (k = 0; k < MAXDISPARITY; k=k+1) 
		begin : diag_fetch
			assign LPDiRight_2DArray_wire[k] = LPDiLeftArrayShift_2dArray_wire[MAXDISPARITY-k-1][k];
		end
		for (k = 0; k < MAXDISPARITY; k=k+1) 
		begin : output_1D
			assign LPDiRight[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] = LPDiRight_2DArray_wire[k] ;
		end
endgenerate

assign LPDiLeft = LPDiLeft_1dArray_shift_reg_sclkrate[MAXDISPARITY-1] ;
assign LPDiRight[OUTPUTDATAWID-1] = SOF_atPxy ;

endmodule