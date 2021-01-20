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
	x_dest and y_dest is the final output 
	
	basic idea : 
		the main proccess of rectification is as follows : 
		1. undistort the camera distortion due to tangential and radial lens distortion , which is the long formula , 
		   the paramters are k1,k2,...,p1,p2 , U0,V0
		2. rotate the left and right camera to set their epipolar line to be horizontal. 

		in application we need to do in the reverse way to index from dest_index to source_index , the derived source_index is 
		normally not integer, then we do the GPU-like texture fetching .
		so the actual process is as following : 

		1. undo the rotation , which is an 3*3 matrix,  to get the middle index x_middle and y_middle 
		2. from x_middle and y_middle undo the distortion and then we get the source index x_src and y_src


	    don't be scared by the long long long augly formula , may the strenth be with you ! hahahahaha ...... 
	    HDL is an piece of art , not a scary and tedious job , hahahahahahahah , really ?  2B , hurry up .....

    TODO : this is a FPGA resource hungery algorithm, should move to high speed ARM/(embeded GPU) in future release 

	STUPID MISTAKES :  
		1) mix up divisor with divident

	RECAP   :   

	         _______    4'b1111   : 4'd-1
                /|\
		         |
                 |
              negative 
                 |
                 |
            ____\|/__  4'b1000    : 4'd-8
            _________  4'b0111    : 4'd7
                /|\
                 |
                 |
              postive 
                 |
                 |
            ____\|/___ 4'b0000    :  4'd0


	QUATIZATION :  
         sign-bit  
		 _______ _____________________________
		|       |                             |
		| Bit15 |      Bit14~Bit0             |
		|_______|_____________________________|

		step one : 
			x_middle_p = ir[0] * x_dest + ir[1] * y_dest + ir[2] * w_dest ;   
			y_middle_p = ir[3] * x_dest + ir[4] * y_dest + ir[5] * w_dest ;
			w_middle_p = ir[6] * x_dest + ir[7] * y_dest + ir[8] * w_dest ;

			x_middle  = x_middle_p / w_middle_p ;    // one pixel clok 
			y_middle  = y_middle_p / w_middle_p ; 

			here :
			|x_middle_p| < 1   |y_middle_p| < 1  |w_middle_p| < 1 
			|x_middle| < 1     |y_middle| < 1 
		
		step two : 
			double x2 = x*x, y2 = y*y;
			double r2 = x2 + y2,
				   _2xy = 2*x*y;
			double kr = 1 + ((k3*r2 + k2)*r2 + k1)*r2 
			double u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x)) + u0;
			double v = fy*(y*kr + p1*(r2 + 2*y) + p2*_2xy) + v0;

		so according the value range of x_middle , y_middle w_middle , .... 
		assign the Quantization flow as : 

		x_dest      : 11Q0 
		y_dest      : 11Q0 

		x_middle_p  : 2Q16 
		x2       :    2Q16 
		r2       :    2Q16 
		kr       :    2Q16   ------- check it out in c to see if overflow occurs 
		
		fx,fy    :    11Q16  
		u0, v0   :    11Q16
*/

// `define  debug  

`timescale 1 ns / 1 ps
// `default_nettype none
module rectify
#(
	parameter  LEFT_RIGHT    = "L" ,          
	parameter  INPUTDATAWID  = 9,    
	parameter  IMAGE_WIDTH   = 640 ,
	parameter  IMAGE_HEIGHT  = 480 ,
	parameter  OUTPUTDATAWID = 9
  )
(
	input wire                      clk                               ,         // 150 Clock   
	input wire                      en                                ,     
	input wire                      pixelEN                           ,
	input  wire[INPUTDATAWID-1:0]   image_stream                         ,         // W*H       
	output wire[OUTPUTDATAWID-1:0]  rectified_stream                ,            
	input wire						rst_n                                       // Asynchronous reset active low
	
);

/*
	note : x_dest = [0:639] , y_dest = [0:479]
*/

localparam  BLOCK_X = 13 ;
localparam  BLOCK_Y = 13 ;
localparam  DECIMAL_BITS = 11 ;
localparam  FRACTIONAL_BITS = 16 ;

localparam DELAY_TAP_LEN = 23 ;   // 22+1   u . v is aligned with delay[22]


wire [31:0] ir_float32 [0:8] ;
wire [9 :0] linebufferout [0:BLOCK_Y-1] ; 
reg  [9 :0] input_delay [0:31] ;
wire sof_PreStart ;

wire signed [16+2-1:0] one_2Q16 = 18'h0FFFF ;


wire signed [31:0] k1_32bit   ;  
wire signed [31:0] k2_32bit   ;  
wire signed [31:0] p1_32bit   ;  
wire signed [31:0] p2_32bit   ;  
wire signed [31:0] k3_32bit   ;  
wire signed [31:0] k4_32bit   ;  
wire signed [31:0] k5_32bit   ;  
wire signed [31:0] k6_32bit   ;  
      
wire signed [31:0] u0_32bit   ;  
wire signed [31:0] v0_32bit   ;  
wire signed [31:0] fx_32bit   ;  
wire signed [31:0] fy_32bit   ; 

wire signed [31:0] ir_32bit [0:8]  ;  


wire signed [16+2-1:0] k1_2Q16   ;  
wire signed [16+2-1:0] k2_2Q16   ;  
wire signed [16+2-1:0] p1_2Q16   ;  
wire signed [16+2-1:0] p2_2Q16   ;  
wire signed [16+2-1:0] k3_2Q16   ;  
wire signed [16+2-1:0] k4_2Q16   ;  
wire signed [16+2-1:0] k5_2Q16   ;  
wire signed [16+2-1:0] k6_2Q16   ;  
      
wire signed [11+16-1:0] u0_11Q16 ;  
wire signed [11+16-1:0] v0_11Q16 ;  
wire signed [11+16-1:0] fx_11Q16 ;  
wire signed [11+16-1:0] fy_11Q16 ;  
 
wire signed [16+2-1:0] ir_2Q16 [0:8]  ;  


generate 
	// Q16 : x 2^16
	if(LEFT_RIGHT  == "L") 
	begin
		assign k1_32bit         = 32'h0000174A ;         // DistortCoefArray[0]  =  0.090984   
		assign k2_32bit         = 32'hFFFF5AF7 ;         // DistortCoefArray[1]  =  -0.644682  
		assign p1_32bit         = 32'h00000000 ;         // DistortCoefArray[2]  =  0.000000   
		assign p2_32bit         = 32'h00000000 ;         // DistortCoefArray[3]  =  0.000000   
		assign k3_32bit         = 32'h0001CE1D ;         // DistortCoefArray[4]  =  1.805132   
		assign k4_32bit         = 32'h00000000 ;         // DistortCoefArray[5]  =  0.000000   
		assign k5_32bit         = 32'h00000000 ;         // DistortCoefArray[6]  =  0.000000   
		assign k6_32bit         = 32'h00000000 ;         // DistortCoefArray[7]  =  0.000000   
    
		assign ir_32bit[0] 	    = 32'h00000057 ;    	 // iRMatrix[0]  =  0.001335     
		assign ir_32bit[1] 	    = 32'h00000000 ;    	 // iRMatrix[1]  =  0.000006     
		assign ir_32bit[2] 	    = 32'hFFFF7D8F ;    	 // iRMatrix[2]  =  -0.509538    
		assign ir_32bit[3] 	    = 32'h00000000 ;    	 // iRMatrix[3]  =  -0.000006    
		assign ir_32bit[4] 	    = 32'h00000057 ;    	 // iRMatrix[4]  =  0.001336     
		assign ir_32bit[5] 	    = 32'hFFFF9F79 ;    	 // iRMatrix[5]  =  -0.377067    
		assign ir_32bit[6] 	    = 32'hFFFFFFFD ;    	 // iRMatrix[6]  =  -0.000056    
		assign ir_32bit[7] 	    = 32'h00000000 ;    	 // iRMatrix[7]  =  0.000004     
		assign ir_32bit[8] 	    = 32'h0001056B ;    	 // iRMatrix[8]  =  1.021173   

		assign u0_32bit    	    = 32'h017AE29C ;         // AcameraMatrix[0]  =  378.885193        
		assign v0_32bit    	    = 32'h0119DAE8 ;         // AcameraMatrix[1]  =  281.855103        
		assign fx_32bit    	    = 32'h02EC4F10 ;         // AcameraMatrix[2]  =  748.308838        
		assign fy_32bit    	    = 32'h02EC4F10 ;         // AcameraMatrix[3]  =  748.308838   
	end 
	else if (LEFT_RIGHT  == "R")
	begin
		assign k1_32bit         = 32'h00001796 ;         // DistortCoefArray[0]  =  0.092139     
		assign k2_32bit         = 32'hFFFF7553 ;         // DistortCoefArray[1]  =  -0.541703    
		assign p1_32bit         = 32'h00000000 ;         // DistortCoefArray[2]  =  0.000000     
		assign p2_32bit         = 32'h00000000 ;         // DistortCoefArray[3]  =  0.000000     
		assign k3_32bit         = 32'h00010202 ;         // DistortCoefArray[4]  =  1.007850     
		assign k4_32bit         = 32'h00000000 ;         // DistortCoefArray[5]  =  0.000000     
		assign k5_32bit         = 32'h00000000 ;         // DistortCoefArray[6]  =  0.000000     
		assign k6_32bit         = 32'h00000000 ;         // DistortCoefArray[7]  =  0.000000     
    
		assign ir_32bit[0] 	    = 32'h00000057 ;    	 // iRMatrix[0]  =  0.001336      
		assign ir_32bit[1] 	    = 32'h00000000 ;    	 // iRMatrix[1]  =  0.000006      
		assign ir_32bit[2] 	    = 32'hFFFF7DC5 ;    	 // iRMatrix[2]  =  -0.508723     
		assign ir_32bit[3] 	    = 32'h00000000 ;    	 // iRMatrix[3]  =  -0.000006     
		assign ir_32bit[4] 	    = 32'h00000057 ;    	 // iRMatrix[4]  =  0.001336      
		assign ir_32bit[5] 	    = 32'hFFFFA0E8 ;    	 // iRMatrix[5]  =  -0.371466     
		assign ir_32bit[6] 	    = 32'hFFFFFFFE ;    	 // iRMatrix[6]  =  -0.000038     
		assign ir_32bit[7] 	    = 32'h00000000 ;    	 // iRMatrix[7]  =  -0.000004     
		assign ir_32bit[8] 	    = 32'h00010416 ;    	 // iRMatrix[8]  =  1.015965     

		assign u0_32bit    	    = 32'h0178FA74 ;         // AcameraMatrix[0]  =  376.978333       
		assign v0_32bit    	    = 32'h011B88C8 ;         // AcameraMatrix[1]  =  283.534302       
		assign fx_32bit    	    = 32'h02EC4F10 ;         // AcameraMatrix[2]  =  748.308838       
		assign fy_32bit    	    = 32'h02EC4F10 ;         // AcameraMatrix[3]  =  748.308838       
	end
endgenerate



// 648 x 360 
// generate 
// 	if(LEFT_RIGHT  == "L") 
// 	begin
// 		assign k1_32bit         = 32'h0000222C ;         // DistortCoefArray[0]  =  0.133495     
// 		assign k2_32bit         = 32'hFFFF45F3 ;         // DistortCoefArray[1]  =  -0.726764    
// 		assign p1_32bit         = 32'h00000000 ;         // DistortCoefArray[2]  =  0.000000     
// 		assign p2_32bit         = 32'h00000000 ;         // DistortCoefArray[3]  =  0.000000     
// 		assign k3_32bit         = 32'h00016D18 ;         // DistortCoefArray[4]  =  1.426151     
// 		assign k4_32bit         = 32'h00000000 ;         // DistortCoefArray[5]  =  0.000000     
// 		assign k5_32bit         = 32'h00000000 ;         // DistortCoefArray[6]  =  0.000000     
// 		assign k6_32bit         = 32'h00000000 ;         // DistortCoefArray[7]  =  0.000000     
    
// 		assign ir_32bit[0] 	    = 32'h0000006D ;    	 // iRMatrix[0]  =  0.001665     
// 		assign ir_32bit[1] 	    = 32'h00000000 ;    	 // iRMatrix[1]  =  0.000004     
// 		assign ir_32bit[2] 	    = 32'hFFFF7A5D ;    	 // iRMatrix[2]  =  -0.522026    
// 		assign ir_32bit[3] 	    = 32'h00000000 ;    	 // iRMatrix[3]  =  -0.000004    
// 		assign ir_32bit[4] 	    = 32'h0000006D ;    	 // iRMatrix[4]  =  0.001665     
// 		assign ir_32bit[5] 	    = 32'hFFFFB958 ;    	 // iRMatrix[5]  =  -0.276016    
// 		assign ir_32bit[6] 	    = 32'hFFFFFFFE ;    	 // iRMatrix[6]  =  -0.000041    
// 		assign ir_32bit[7] 	    = 32'h00000000 ;    	 // iRMatrix[7]  =  0.000004     
// 		assign ir_32bit[8] 	    = 32'h00010332 ;    	 // iRMatrix[8]  =  1.012488   

// 		assign u0_32bit    	    = 32'h0133F0E2 ;         // AcameraMatrix[0]  =  307.940948        
// 		assign v0_32bit    	    = 32'h00A33E4F ;         // AcameraMatrix[1]  =  163.243393        
// 		assign fx_32bit    	    = 32'h025877D8 ;         // AcameraMatrix[2]  =  600.468140        
// 		assign fy_32bit    	    = 32'h025877D8 ;         // AcameraMatrix[3]  =  600.468140    
// 	end 
// 	else if (LEFT_RIGHT  == "R")
// 	begin
// 		assign k1_32bit         = 32'h000020D3 ;         // DistortCoefArray[0]  =  0.128226     
// 		assign k2_32bit         = 32'hFFFF3362 ;         // DistortCoefArray[1]  =  -0.799291    
// 		assign p1_32bit         = 32'h00000000 ;         // DistortCoefArray[2]  =  0.000000     
// 		assign p2_32bit         = 32'h00000000 ;         // DistortCoefArray[3]  =  0.000000     
// 		assign k3_32bit         = 32'h00021348 ;         // DistortCoefArray[4]  =  2.075326     
// 		assign k4_32bit         = 32'h00000000 ;         // DistortCoefArray[5]  =  0.000000     
// 		assign k5_32bit         = 32'h00000000 ;         // DistortCoefArray[6]  =  0.000000     
// 		assign k6_32bit         = 32'h00000000 ;         // DistortCoefArray[7]  =  0.000000     
    
// 		assign ir_32bit[0] 	    = 32'h0000006D ;    	 // iRMatrix[0]  =  0.001665    
// 		assign ir_32bit[1] 	    = 32'h00000000 ;    	 // iRMatrix[1]  =  0.000004    
// 		assign ir_32bit[2] 	    = 32'hFFFF7C13 ;    	 // iRMatrix[2]  =  -0.515348   
// 		assign ir_32bit[3] 	    = 32'h00000000 ;    	 // iRMatrix[3]  =  -0.000004   
// 		assign ir_32bit[4] 	    = 32'h0000006D ;    	 // iRMatrix[4]  =  0.001665    
// 		assign ir_32bit[5] 	    = 32'hFFFFBAB6 ;    	 // iRMatrix[5]  =  -0.270675   
// 		assign ir_32bit[6] 	    = 32'hFFFFFFFF ;    	 // iRMatrix[6]  =  -0.000025   
// 		assign ir_32bit[7] 	    = 32'h00000000 ;    	 // iRMatrix[7]  =  -0.000005   
// 		assign ir_32bit[8] 	    = 32'h00010229 ;    	 // iRMatrix[8]  =  1.008441   

// 		assign u0_32bit    	    = 32'h01302F92 ;         // AcameraMatrix[0]  =  304.185822       
// 		assign v0_32bit    	    = 32'h00A4BB17 ;         // AcameraMatrix[1]  =  164.730820       
// 		assign fx_32bit    	    = 32'h025877D8 ;         // AcameraMatrix[2]  =  600.468140       
// 		assign fy_32bit    	    = 32'h025877D8 ;         // AcameraMatrix[3]  =  600.468140   
// 	end
// endgenerate



/*
	construct the following condition to test the timing 

        double kr = 1 + ((k3(0)*r2 + k2(0))*r2 + k1(0))*r2 
        double u = fx(1)*(x*kr + p1(0)*_2xy + p2(0)*(r2 + 2*x)) + u0(0);
        double v = fy(1)*(y*kr + p1(0)*(r2 + 2*y) + p2(0)*_2xy) + v0(0);

        expected u,v output is : x, y 
*/


assign k1_2Q16          = k1_32bit[2+16-1:0] ; 
assign k2_2Q16          = k2_32bit[2+16-1:0] ; 
assign p1_2Q16          = p1_32bit[2+16-1:0] ; 
assign p2_2Q16          = p2_32bit[2+16-1:0] ; 
assign k3_2Q16          = k3_32bit[2+16-1:0] ; 
assign k4_2Q16          = k4_32bit[2+16-1:0] ; 
assign k5_2Q16          = k5_32bit[2+16-1:0] ; 
assign k6_2Q16          = k6_32bit[2+16-1:0] ; 
assign ir_2Q16[0] 	    = ir_32bit[0][2+16-1:0] ; 
assign ir_2Q16[1] 	    = ir_32bit[1][2+16-1:0] ; 
assign ir_2Q16[2] 	    = ir_32bit[2][2+16-1:0] ; 
assign ir_2Q16[3] 	    = ir_32bit[3][2+16-1:0] ; 
assign ir_2Q16[4] 	    = ir_32bit[4][2+16-1:0] ; 
assign ir_2Q16[5] 	    = ir_32bit[5][2+16-1:0] ; 
assign ir_2Q16[6] 	    = ir_32bit[6][2+16-1:0] ; 
assign ir_2Q16[7] 	    = ir_32bit[7][2+16-1:0] ; 
assign ir_2Q16[8] 	    = ir_32bit[8][2+16-1:0] ; 

assign u0_11Q16    	    = u0_32bit[11+16-1:0] ; 
assign v0_11Q16    	    = v0_32bit[11+16-1:0] ; 
assign fx_11Q16    	    = fx_32bit[11+16-1:0] ; 
assign fy_11Q16    	    = fy_32bit[11+16-1:0] ; 


integer i ;

genvar k , r,c; 


 // shift array 
 //*******  shift input and linebuffer  **************

//delay the input stream to match the index-calculation delay 
wire input_stream_sof = image_stream[8] ;
always @(posedge clk)
if(en && pixelEN)
begin
	for(i=1; i<32; i=i+1)
		input_delay[i][8:0] <= input_delay[i-1][8:0] ;
	input_delay[0][8:0] <= image_stream ;

	if(input_stream_sof)
		input_delay[DELAY_TAP_LEN][9] <=  1'b1 ;
	else 
		input_delay[DELAY_TAP_LEN][9] <=  1'b0 ;
end

reg  [9:0] shiftRegArray_sclkrate [0:BLOCK_X-1][0:BLOCK_Y-2] ; // [r][c]
wire [9:0] matrixNbyNArray_wire   [0:BLOCK_X-1][0:BLOCK_Y-1] ; 

generate
for(r=0; r<BLOCK_Y; r=r+1)
	for(c=1;c<BLOCK_X; c=c+1)
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			shiftRegArray_sclkrate[r][c] <= shiftRegArray_sclkrate[r][c-1] ;
	    end
	end

for(r=1; r<BLOCK_Y; r=r+1)
begin
	always@(posedge clk)
	if(en && pixelEN)
	begin
		shiftRegArray_sclkrate[r][0] <= linebufferout[r-1] ;
	end
end

always@(posedge clk)
if(en && pixelEN)
begin
	shiftRegArray_sclkrate[0][0] <= input_delay[DELAY_TAP_LEN] ;
end

//  10 X 10 matrix array , used for address indexing 
for(r=1; r<BLOCK_Y; r=r+1)
begin
	assign matrixNbyNArray_wire[r][0]  = linebufferout[r-1] ;
end

	assign matrixNbyNArray_wire[0][0] = input_delay[DELAY_TAP_LEN] ;

for(r=0; r<BLOCK_Y; r=r+1)
	for(c=1;c<BLOCK_X; c=c+1)
	begin
		assign matrixNbyNArray_wire[r][c] = shiftRegArray_sclkrate[r][c-1] ;
	end

endgenerate


// ******************  generating the dest index    ***********************************
reg [31:0] sof_PreStart_dly ;
reg signed [11-1:0] colCnt_11Q0_sclkrate = 0 ;
reg signed [11-1:0] rowCnt_11Q0_sclkrate = 0;

always@(posedge clk)
if(en && pixelEN)
begin
	sof_PreStart_dly <= {sof_PreStart_dly[30:0],sof_PreStart} ;
end

assign  sof_PreStart = (matrixNbyNArray_wire[6][6][9] == 1'b1)? 1'b1 : 1'b0  ;   // the real sof is 20taps behind, this signal is use to 
																				 // calculate the index which is surposed to be matched with real sof 

// generate  colcnt and rowcnt counter which is (dest_x,dest_y)
always@(posedge clk )
if(en && pixelEN ) 
begin
		if((sof_PreStart == 1'b1) && (colCnt_11Q0_sclkrate != 0))
			colCnt_11Q0_sclkrate <= 1 ;
		else if(colCnt_11Q0_sclkrate == IMAGE_WIDTH -1)
			colCnt_11Q0_sclkrate <= 0 ;
		else
			colCnt_11Q0_sclkrate <= colCnt_11Q0_sclkrate + 1'b1;

		if((rowCnt_11Q0_sclkrate == IMAGE_HEIGHT-1 && colCnt_11Q0_sclkrate == IMAGE_WIDTH -1) || sof_PreStart)
		begin
			rowCnt_11Q0_sclkrate <= 0 ;
		end
		else if(colCnt_11Q0_sclkrate == IMAGE_WIDTH -1) begin
			rowCnt_11Q0_sclkrate <= rowCnt_11Q0_sclkrate + 1'b1 ;
		end
end


/***********************************************************************************************************
************************************************************************************************************

 				step 1: derive the middle index x_middle , y_middle 

 ***********************************************************************************************************
 ***********************************************************************************************************/

/*
	x_middle_p = ir[0] * x_dest + ir[1] * y_dest + ir[2] * w_dest ;   
	y_middle_p = ir[3] * x_dest + ir[4] * y_dest + ir[5] * w_dest ;
	w_middle_p = ir[6] * x_dest + ir[7] * y_dest + ir[8] * w_dest ;

	x_middle  = x_middle_p / w_middle_p ;    // one pixel clok 
	y_middle  = y_middle_p / w_middle_p ;
*/
/*
	timing of div (keep in mind period is 6 clock cycle)
                    __    __    __    __    __    __    __    __    __    __    __    __    __
	clk       _____|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |___
                    _____                               _____
	tready    _____|     |_____________________________|     |___________________________________
                          ____                                _____
	output_tvalid _______|    |______________________________|     |_____________________________
                          ___________________________________ _________________________________
	dout_tdata    ///////X___________________________________X_________________________________

	due to observation from modelsim , input_tready will be asserted high untill inpu_tvalid is set, 
	output_tvalid will be set high 6-pixel-clock cycle later, so input_tvalid = en & pixelEN , this garandtees 
	within one pixel clock division will be carried out. 
	important note : read the output at the rising edge of output_tvalid , this guarantees the result is not affected by
	the unknow pipline of div-core

*/
// 1. convert x_dest y_dest to floating numbers 
wire [11-1:0] x_dest_11Q0  =  colCnt_11Q0_sclkrate ;
wire [11-1:0] y_dest_11Q0  =  rowCnt_11Q0_sclkrate ;


reg [11-1:0] x_dest_11Q0_sclkrate ;
reg [11-1:0] y_dest_11Q0_sclkrate ;

// make sure y_dest_float16_at_valid is stable when pixelEN arrives 
always@(posedge clk)      // aligned with sof_PreStart_dly[0] , 1 pixelEN clock delay 
if(en && pixelEN)
begin
	x_dest_11Q0_sclkrate <= x_dest_11Q0 ;   // aligned with sof_PreStart_dly[0]
	y_dest_11Q0_sclkrate <= y_dest_11Q0 ;
end

// 2. conpute x_middle_p , y_middle_p, and w_middle_p 
/*
	x_middle_p = ir[0] * x_dest + ir[1] * y_dest + ir[2] * 1.0 ;   
	y_middle_p = ir[3] * x_dest + ir[4] * y_dest + ir[5] * 1.0 ;
	w_middle_p = ir[6] * x_dest + ir[7] * y_dest + ir[8] * 1.0 ;
*/
/*
    float16 :  
     _______
    |_bit15_|  sign-bit 
             ________________________
            |_bit14____________bit10_|  Exponent width : 5 
                                 ____ __________________________
                                |_1.0|__________________________| Fraction bit width : 11 . there is a hidden bit in bit10 which is always eq. to 1'b1
*/

wire signed [11+16-1:0] ir0_xDest_11Q16 ;   
wire signed [11+16-1:0] ir1_yDest_11Q16 ;   
wire signed [11+16-1:0] ir2_wDest_11Q16_const ;   
wire signed [11+16-1:0] ir3_xDest_11Q16 ;   
wire signed [11+16-1:0] ir4_yDest_11Q16 ;   
wire signed [11+16-1:0] ir5_wDest_11Q16_const ;   
wire signed [11+16-1:0] ir6_xDest_11Q16 ;   
wire signed [11+16-1:0] ir7_yDest_11Q16 ;   
wire signed [11+16-1:0] ir8_wDest_11Q16_const ;   


/* *************************** row 0 ***********************************************************/
// aligned with sof_PreStart_dly[1] , 2 pixelEN clock delay 
mult_11Q0_by_2Q16_one_pixel_clock ir0_time_xDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_dest_11Q0_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_2Q16[0])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir0_xDest_11Q16)      			// aligned with sof_PreStart_dly[1] 
);

mult_11Q0_by_2Q16_one_pixel_clock ir1_time_yDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_dest_11Q0_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_2Q16[1])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir1_yDest_11Q16)      			// aligned with sof_PreStart_dly[1] 
);

/* *************************** row 1 ***********************************************************/
mult_11Q0_by_2Q16_one_pixel_clock ir3_time_xDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_dest_11Q0_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_2Q16[3])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir3_xDest_11Q16)      			// aligned with sof_PreStart_dly[1] 
);

mult_11Q0_by_2Q16_one_pixel_clock ir4_time_yDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_dest_11Q0_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_2Q16[4])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir4_yDest_11Q16)      			// aligned with sof_PreStart_dly[1] 
);

/* *************************** row 2 ***********************************************************/
mult_11Q0_by_2Q16_one_pixel_clock ir6_time_xDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_dest_11Q0_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_2Q16[6])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir6_xDest_11Q16)      			// aligned with sof_PreStart_dly[1] 
);

mult_11Q0_by_2Q16_one_pixel_clock ir7_time_yDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_dest_11Q0_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_2Q16[7])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir7_yDest_11Q16)      			// aligned with sof_PreStart_dly[1] 
);

wire signed [11+16-1:0] x_middle_p ;
wire signed [11+16-1:0] y_middle_p ;
wire signed [11+16-1:0] w_middle_p ;
wire signed [11+16-1:0] x_middle_temp ;
wire signed [11+16-1:0] y_middle_temp ;
wire signed [11+16-1:0] w_middle_temp ;

wire signed [2+16-1:0] x_middle ;
wire signed [2+16-1:0] y_middle ;

assign ir2_wDest_11Q16_const =  $signed(ir_2Q16[2]) ;   // {{(27-18){ir_2Q16[2][17]}},ir_2Q16[2]} ;     // constant  expand sign bits  
assign ir5_wDest_11Q16_const =  $signed(ir_2Q16[5]) ;   // {{(27-18){ir_2Q16[5][17]}},ir_2Q16[5]} ;     // constant 
assign ir8_wDest_11Q16_const =  $signed(ir_2Q16[8]) ;   // {{(27-18){ir_2Q16[8][17]}},ir_2Q16[8]} ;     // constant 
// 



/************************************ compute x *************************************************************/
//  ir[0] * x_dest + ir[1] * y_dest
_11Q16_add_11Q16_one_pixel_clock u_x_middle_p_tmp
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(ir0_xDest_11Q16)     ,    // aligned with sof_PreStart_dly[1]
	  .B 			(ir1_yDest_11Q16)     ,    // aligned with sof_PreStart_dly[1]
	  .SUM 			(x_middle_temp)      			// aligned with sof_PreStart_dly[2] 
);
// ir[0] * x_dest + ir[1] * y_dest + ir[2] * w_dest
_11Q16_add_11Q16_one_pixel_clock u_x_middle_p
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_middle_temp)     ,    // aligned with sof_PreStart_dly[2]
	  .B 			(ir2_wDest_11Q16_const)     ,    // constant
	  .SUM 			(x_middle_p)      			// aligned with sof_PreStart_dly[3] 
);
/************************************ compute y *************************************************************/
//  ir[3] * x_dest + ir[4] * y_dest
_11Q16_add_11Q16_one_pixel_clock u_y_middle_p_tmp
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(ir3_xDest_11Q16)     ,   // aligned with sof_PreStart_dly[1]
	  .B 			(ir4_yDest_11Q16)     	,  // aligned with sof_PreStart_dly[1]
	  .SUM 			(y_middle_temp)      			// aligned with sof_PreStart_dly[2] 
);
// ir[3] * x_dest + ir[4] * y_dest + ir[5] * w_dest
_11Q16_add_11Q16_one_pixel_clock u_y_middle_p
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_middle_temp)     ,    // aligned with sof_PreStart_dly[2]
	  .B 			(ir5_wDest_11Q16_const)     ,    // constant
	  .SUM 			(y_middle_p)      			// aligned with sof_PreStart_dly[3] 
);

/************************************ compute w *************************************************************/
//  ir[6] * x_dest + ir[7] * y_dest
_11Q16_add_11Q16_one_pixel_clock u_w_middle_p_tmp
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(ir6_xDest_11Q16)     ,   // aligned with sof_PreStart_dly[1]
	  .B 			(ir7_yDest_11Q16)     	,  // aligned with sof_PreStart_dly[1]
	  .SUM 			(w_middle_temp)      			// aligned with sof_PreStart_dly[2] 
);
// ir[6] * x_dest + ir[7] * y_dest + ir[8]
_11Q16_add_11Q16_one_pixel_clock u_w_middle_p
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(w_middle_temp)     ,    // aligned with sof_PreStart_dly[2]
	  .B 			(ir8_wDest_11Q16_const)     ,    // constant
	  .SUM 			(w_middle_p)      			// aligned with sof_PreStart_dly[3] 
);


// 3. compute x_middle , y_middle 
/*
    x_middle  = x_middle_p / w_middle_p ;     
    y_middle  = y_middle_p / w_middle_p ;
*/
wire signed [2+16-1:0] x_middle_p_2Q16 ;
wire signed [2+16-1:0] y_middle_p_2Q16 ;
wire signed [2+16-1:0] w_middle_p_2Q16 ;

assign x_middle_p_2Q16 = x_middle_p[17:0] ;    // abs(x_middle_p) < 1 , discard the unneccesary MSBs 
assign y_middle_p_2Q16 = y_middle_p[17:0] ; 
assign w_middle_p_2Q16 = w_middle_p[17:0] ; 

wire x_midle_p_overflow = (x_middle_p[11+16-1] != x_middle_p[17]); // sign bits are not equal
wire y_midle_p_overflow = (y_middle_p[11+16-1] != y_middle_p[17]); // sign bits are not equal
wire w_midle_p_overflow = (w_middle_p[11+16-1] != w_middle_p[17]); // sign bits are not equal

div_4_pixel_clock U_x_div_w (
	.clk        (clk) 	,    // Clock
	.en 		(en)	,
	.pixelEN 	(pixelEN)	,
	.x_middle_p_2Q16 (x_middle_p_2Q16)	,   // aligned with sof_PreStart_dly[3] 
    .w_middle_p_2Q16 (w_middle_p_2Q16) ,      // aligned with sof_PreStart_dly[3] 
    .x_middle_2qQ16   (x_middle)          // aligned with sof_PreStart_dly[7]
);

div_4_pixel_clock U_y_div_w (
	.clk        (clk) 	,    // Clock
	.en 		(en)	,
	.pixelEN 	(pixelEN)	,
	.x_middle_p_2Q16 (y_middle_p_2Q16)	,   // aligned with sof_PreStart_dly[3] 
    .w_middle_p_2Q16 (w_middle_p_2Q16) ,      // aligned with sof_PreStart_dly[3] 
    .x_middle_2qQ16   (y_middle)          // aligned with sof_PreStart_dly[7]
);


/***********************************************************************************************************
************************************************************************************************************

 				step 2: derive the source index x_source , y_source 

 ***********************************************************************************************************
 ***********************************************************************************************************/
/*
			// P_src    = Mr.inv * Distortion(P_middle)        // Mr is camera matrix_middle 3*3            
            double x2 = x*x, y2 = y*y;
            double r2 = x2 + y2,
            		 _2xy = 2*x*y;
            double kr = 1 + ((k3*r2 + k2)*r2 + k1)*r2 
            double u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*xx)) + u0;
            double v = fy*(y*kr + p1*(r2 + 2*yy) + p2*_2xy) + v0;

            note : here x , y is x_middle and y_middle   and they are both less than 1 
*/
wire signed [16+2-1:0] r2 ;    // x^2 + y^2
wire signed [16+2-1:0] _xy ;   // x*y 
wire signed [16+2-1:0] _2xy ;  // 2*x*y

wire signed [16+2-1:0] k3r2 ;           // k3*r2 
wire signed [16+2-1:0] k3r2_k2 ;        // k3*r2 + k2
wire signed [16+2-1:0] k3r2_k2_r2 ;      //  (k3*r2 + k2)*r2
wire signed [16+2-1:0] k3r2_k2_r2_k1 ;     // (k3*r2 + k2)*r2 + k1
wire signed [16+2-1:0] k3r2_k2_r2_k1_r2 ;        // ((k3*r2 + k2)*r2 + k1)*r2
wire signed [16+2-1:0] _1_k3r2_k2_r2_k1_r2 ;     // 1 + ((k3*r2 + k2)*r2 + k1)*r2


wire signed [16+2-1:0] kr ;           //kr = 1 + ((k3*r2 + k2)*r2 + k1)*r2 
wire signed [16+2-1:0] p1_2xy ;       // p1*_2xy     
wire signed [16+2-1:0] x_kr ;         // x*kr 
wire signed [16+2-1:0] _xx ;          // x*x
wire signed [16+2-1:0] _2xx ;         // 2*x*x
wire signed [16+2-1:0] _yy ;          // y*y 
wire signed [16+2-1:0] _2yy ;         // 2*y*y
wire signed [16+2-1:0] r2_2xx ;       // r^2 + 2x^2
wire signed [16+2-1:0] p2_r2_2xx ;     // p2*(r2 + 2*xx)
wire signed [16+2-1:0] add_terms_0 ;   //  x*kr + p1*_2xy
wire signed [16+2-1:0] add_terms_0_0 ;  // x*kr + p1*_2xy + p2*(r2 + 2*xx)
wire signed [16+11-1:0] fx_add_terms_0_0 ;       // fx*(x*kr + p1*_2xy + p2*(r2 + 2*xx))
wire signed [16+11-1:0] fx_add_terms_0_0_u0 ;    // fx*(x*kr + p1*_2xy + p2*(r2 + 2*xx)) + u0

wire signed [16+2-1:0] y_kr ;              // y*kr
wire signed [16+2-1:0] r2_2yy ;            // r2 + 2*yy 
wire signed [16+2-1:0] p1_r2_2yy ;         // p1*(r2 + 2*yy)
wire signed [16+2-1:0] p2_2xy ;            // p2*_2xy
wire signed [16+2-1:0] add_terms_1 ;       // y*kr + p1*(r2 + 2*y2)
wire signed [16+2-1:0] add_terms_1_1 ;     // y*kr + p1*(r2 + 2*yy) + p2*_2xy
wire signed [16+11-1:0] fy_add_terms_1_1 ;        // fy*(y*kr + p1*(r2 + 2*yy) + p2*_2xy)
wire signed [16+11-1:0] fy_add_terms_1_1_v0 ;     // fy*(y*kr + p1*(r2 + 2*yy) + p2*_2xy) + v0

wire signed [15:0] u , v ;

reg signed [16+2-1:0] r2_dly_sclkrate [0:31]; 
reg signed [16+2-1:0] x_middle_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] _2xx_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] p1_2xy_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] p2_r2_2xx_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] y_middle_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] _2yy_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] p1_r2_2yy_dly_sclkrate [0:31] ;
reg signed [16+2-1:0] p2_2xy_dly_sclkrate [0:31] ;

reg signed [10:0] x_dest_11Q0_dly_sclkrate [0:31] ;
reg signed [10:0] y_dest_11Q0_dly_sclkrate [0:31] ;  //x_dest_11Q0

// some delay taps to match the add or mul input timing
always@(posedge clk)
if(en && pixelEN)
begin
	for(i=1; i<32 ; i=i+1)
	begin
		r2_dly_sclkrate[i] <= r2_dly_sclkrate[i-1] ;
	end
	r2_dly_sclkrate[0] <= r2;

	for(i=1; i<32 ; i=i+1)
	begin
		x_middle_dly_sclkrate[i] <= x_middle_dly_sclkrate[i-1] ;
	end
	x_middle_dly_sclkrate[0] <= x_middle;

	for(i=1; i<32 ; i=i+1)
	begin
		_2xx_dly_sclkrate[i] <= _2xx_dly_sclkrate[i-1] ;
	end
	_2xx_dly_sclkrate[0] <= _2xx ;

	for(i=1; i<32 ; i=i+1)
	begin
		p1_2xy_dly_sclkrate[i] <= p1_2xy_dly_sclkrate[i-1] ;
	end
	p1_2xy_dly_sclkrate[0] <= p1_2xy ;

	for(i=1; i<32 ; i=i+1)
	begin
		p2_r2_2xx_dly_sclkrate[i] <= p2_r2_2xx_dly_sclkrate[i-1] ;
	end
	p2_r2_2xx_dly_sclkrate[0] <= p2_r2_2xx ;

	for(i=1; i<32 ; i=i+1)
	begin
		y_middle_dly_sclkrate[i] <= y_middle_dly_sclkrate[i-1] ;
	end
	y_middle_dly_sclkrate[0] <= y_middle ;

	for(i=1; i<32 ; i=i+1)
	begin
		_2yy_dly_sclkrate[i] <= _2yy_dly_sclkrate[i-1] ;
	end
	_2yy_dly_sclkrate[0] <= _2yy ;

	for(i=1; i<32 ; i=i+1)
	begin
		p1_r2_2yy_dly_sclkrate[i] <= p1_r2_2yy_dly_sclkrate[i-1] ;
	end
	p1_r2_2yy_dly_sclkrate[0] <= p1_r2_2yy ;

	for(i=1; i<32 ; i=i+1)
	begin
		p2_2xy_dly_sclkrate[i] <= p2_2xy_dly_sclkrate[i-1] ;
	end
	p2_2xy_dly_sclkrate[0] <= p2_2xy ;

	for(i=1; i<32 ; i=i+1)
	begin
		x_dest_11Q0_dly_sclkrate[i] <= x_dest_11Q0_dly_sclkrate[i-1] ;
	end
	x_dest_11Q0_dly_sclkrate[0] <= x_dest_11Q0 ;

	for(i=1; i<32 ; i=i+1)
	begin
		y_dest_11Q0_dly_sclkrate[i] <= y_dest_11Q0_dly_sclkrate[i-1] ;
	end
	y_dest_11Q0_dly_sclkrate[0] <= y_dest_11Q0  ;

end

// compute x^2, y^2 xy
mult_2Q16_by_2Q16_one_pixel_clock u_xx
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_middle)     		,  // aligned with sof_PreStart_dly[7]
	  .B 			(x_middle)     		,  // aligned with sof_PreStart_dly[7]
	  .P 			(_xx)      			// aligned with sof_PreStart_dly[8] 
);

mult_2Q16_by_2Q16_one_pixel_clock u_yy
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_middle)     		,  // aligned with sof_PreStart_dly[7]
	  .B 			(y_middle)     		,  // aligned with sof_PreStart_dly[7]
	  .P 			(_yy)      			// aligned with sof_PreStart_dly[8] 
);

mult_2Q16_by_2Q16_one_pixel_clock u_xy
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_middle)     		,  // aligned with sof_PreStart_dly[7]
	  .B 			(y_middle)     		,  // aligned with sof_PreStart_dly[7]
	  .P 			(_xy)      			// aligned with sof_PreStart_dly[8] 
);




assign _2xx = _xx << 1 ; // should not changed the sign
assign _2yy = _yy << 1 ; // should not changed the sign
assign _2xy = _xy << 1 ; // should not changed the sign

// r2 = xx + yy 
_2Q16_add_2Q16_one_pixel_clock u_r2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(_xx)               ,          // aligned with sof_PreStart_dly[8]
	  .B 			(_yy)  ,          				// aligned with sof_PreStart_dly[8]
	  .SUM 			(r2)      			   // aligned with sof_PreStart_dly[9] 
);

// k3*r2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2) 
/*
	in case of big distortion, ki is greater than +/-2 , which is beyond 2Q16 , the MSB become 1 , which is negative .
	simple solution : right shift by one bit and then after mutiplication , left shift by 1 bit 

	below is just a solution for this camera , should be updated in the future 
*/
wire [16+2-1:0] k3_2Q16_rightshift1 = ( (k3_2Q16[17]==1'b1) && (k3_2Q16[16]==1'b0) ) ? k3_2Q16 >> 1 : $signed(k3_2Q16[17:1]);
wire [16+2-1:0] k3r2_div2 ;
assign k3r2 = k3r2_div2 << 1 ;
mult_2Q16_by_2Q16_one_pixel_clock u_k3r2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(r2)     ,            // aligned with sof_PreStart_dly[9]
	  .B 			(k3_2Q16_rightshift1)     		,  // constant
	  .P 			(k3r2_div2)      			// aligned with sof_PreStart_dly[10] 
);

// k3*r2 + k2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
_2Q16_add_2Q16_one_pixel_clock u_k3r2_k2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(k3r2)     ,            // aligned with sof_PreStart_dly[10]
	  .B 			(k2_2Q16)       ,         // constant
	  .SUM 			(k3r2_k2)      			   // aligned with sof_PreStart_dly[11] 
);

// (k3*r2 + k2)*r2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
mult_2Q16_by_2Q16_one_pixel_clock u_k3r2_k2_r2
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(k3r2_k2)     								,            // aligned with sof_PreStart_dly[11]
	  .B 			(r2_dly_sclkrate[11-9-1])      ,    // r2 is aligned with sof_PreStart_dly[9]
	  .P 			(k3r2_k2_r2)      								// aligned with sof_PreStart_dly[12] 
);

// (k3*r2 + k2)*r2 + k1   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
_2Q16_add_2Q16_one_pixel_clock u_k3r2_k2_r2_k1
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(k3r2_k2_r2)     ,            // aligned with sof_PreStart_dly[12]
	  .B 			(k1_2Q16)       ,         // constant
	  .SUM 			(k3r2_k2_r2_k1)      			   // aligned with sof_PreStart_dly[13] 
);

// ((k3*r2 + k2)*r2 + k1)*r2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
mult_2Q16_by_2Q16_one_pixel_clock u_k3r2_k2_r2_k1_r2
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(k3r2_k2_r2_k1)     ,            // aligned with sof_PreStart_dly[13]
	  .B 			(r2_dly_sclkrate[13-9-1])       ,         // r2 is aligned with sof_PreStart_dly[9]
	  .P 			(k3r2_k2_r2_k1_r2)      								// aligned with sof_PreStart_dly[14] 
);

// 1 + ((k3*r2 + k2)*r2 + k1)*r2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
_2Q16_add_2Q16_one_pixel_clock u_1_k3r2_k2_r2_k1_r2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(k3r2_k2_r2_k1_r2)     ,            // aligned with sof_PreStart_dly[14]
	  .B 			(one_2Q16)       ,         // constant
	  .SUM 			(_1_k3r2_k2_r2_k1_r2)      			   // aligned with sof_PreStart_dly[15] 
);

assign kr = _1_k3r2_k2_r2_k1_r2 ;    // aligned with sof_PreStart_dly[15]

// x*kr           -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
mult_2Q16_by_2Q16_one_pixel_clock u_x_kr
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(kr)     ,            					  // aligned with sof_PreStart_dly[15]
	  .B 			(x_middle_dly_sclkrate[15-7-1])       ,  // x_middle is aligned with sof_PreStart_dly[7]
	  .P 			(x_kr)      								// aligned with sof_PreStart_dly[16] 
);

// p1*_2xy        -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
mult_2Q16_by_2Q16_one_pixel_clock u_p1_2xy
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(_2xy)     ,            				// aligned with sof_PreStart_dly[8]
	  .B 			(p1_2Q16)       ,         // constant
	  .P 			(p1_2xy)      								// aligned with sof_PreStart_dly[9] 
);

// r2 + 2*x2      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
_2Q16_add_2Q16_one_pixel_clock u_r2_2xx
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(_2xx_dly_sclkrate[9-8-1])     ,            // _2xx is aligned with sof_PreStart_dly[8]
	  .B 			(r2)       ,         // r2  is aligned with sof_PreStart_dly[9]
	  .SUM 			(r2_2xx)      			   // aligned with sof_PreStart_dly[10] 
);

// p2*(r2 + 2*x2)      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
mult_2Q16_by_2Q16_one_pixel_clock u_p2_r2_2xx
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(r2_2xx )     ,            // aligned with sof_PreStart_dly[10]
	  .B 			(p2_2Q16)       ,         // constant
	  .P 			(p2_r2_2xx)      								// aligned with sof_PreStart_dly[11] 
);

// x*kr + p1*_2xy       -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
_2Q16_add_2Q16_one_pixel_clock u_add_terms_0 
(
	 .clk 		(clk)	,  
	 .clk_en	(1'b1)	,  
	 .rst_n		(rst_n)	,  
	 .en    	(en)	,
	 .pixelEN 	(pixelEN)	,
	 .A 		(x_kr)	,     // aligned with sof_PreStart_dly[16]
	 .B 		(p1_2xy_dly_sclkrate[16-9-1])       ,        // p1_2xy is aligned with sof_PreStart_dly[9]
	 .SUM 		(add_terms_0)            // aligned with sof_PreStart_dly[17] 
);

// x*kr + p1*_2xy + p2*(r2 + 2*x2)      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
_2Q16_add_2Q16_one_pixel_clock u_add_terms_0_0 
(
	 .clk 		(clk)	,    	 
	 .clk_en	(1'b1)	, 		 
	 .rst_n		(rst_n)	,  		 
	 .en    	(en)	,
	 .pixelEN 	(pixelEN)	,
	 .A 		(add_terms_0)	,     // aligned with sof_PreStart_dly[17] 
	 .B 		(p2_r2_2xx_dly_sclkrate[17-11-1])       ,        // p2_r2_2xx is aligned with sof_PreStart_dly[11]
	 .SUM 		(add_terms_0_0)     // aligned with sof_PreStart_dly[18] 
);

// fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2))      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
mult_2Q16_by_11Q16_one_pixel_clock u_fx_add_terms_0_0
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(add_terms_0_0)		,   // aligned with sof_PreStart_dly[18] 
	  .B 			(fx_11Q16)		,   // constant
	  .P 			(fx_add_terms_0_0)      // aligned with sof_PreStart_dly[19] 
);

// u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
_11Q16_add_11Q16_one_pixel_clock u_fx_add_terms_0_0_u0 
(
	 .clk 		(clk)	,  
	 .clk_en	(1'b1)	,  
	 .rst_n		(rst_n)	,  
	 .en    	(en)	,
	 .pixelEN 	(pixelEN)	,
	 .A 		(u0_11Q16)	,     // constant
	 .B 		(fx_add_terms_0_0)       ,        // aligned with sof_PreStart_dly[19] 
	 .SUM 		(fx_add_terms_0_0_u0 )            // aligned with sof_PreStart_dly[20] -------------> u 
);

// y*kr          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
mult_2Q16_by_2Q16_one_pixel_clock u_y_kr
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(kr)				,   				// aligned with sof_PreStart_dly[15] 
	  .B 			(y_middle_dly_sclkrate[15-7-1])       ,        // aligned with sof_PreStart_dly[7] 
	  .P 			(y_kr)                                     // aligned with sof_PreStart_dly[16] 
);
// r2 + 2*y2          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
_2Q16_add_2Q16_one_pixel_clock u_r2_2yy
(
	  .clk 			(clk)				        ,    	 
	  .clk_en		(1'b1)				        , 		 
	  .rst_n		(rst_n)				        ,  		 
	  .en    		(en)				        ,
	  .pixelEN 		(pixelEN)	    	        ,
	  .A 			(r2 )          ,   								// aligned with sof_PreStart_dly[9])				
	  .B 			(_2yy_dly_sclkrate[9-8-1])  ,        			// aligned with sof_PreStart_dly[8]
	  .SUM 			(r2_2yy)      							        // aligned with sof_PreStart_dly[10] 
);
// p1*(r2 + 2*y2)          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
mult_2Q16_by_2Q16_one_pixel_clock u_p1_r2_2yy
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(r2_2yy)			,       // aligned with sof_PreStart_dly[10] 
	  .B 			(p1_2Q16)       ,        // constant
	  .P 			(p1_r2_2yy)      			// aligned with sof_PreStart_dly[11] 
);

// p2*_2xy          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
mult_2Q16_by_2Q16_one_pixel_clock u_p2_2xy
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(_2xy)			    ,       // aligned with sof_PreStart_dly[8]
	  .B 			(p2_2Q16)        ,       // constant
	  .P 			(p2_2xy)      			    // aligned with sof_PreStart_dly[9] 
);

// y*kr + p1*(r2 + 2*y2)          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
_2Q16_add_2Q16_one_pixel_clock u_add_terms_1
(
	  .clk 			(clk)				        ,    	 
	  .clk_en		(1'b1)				        , 		 
	  .rst_n		(rst_n)				        ,  		 
	  .en    		(en)				        ,
	  .pixelEN 		(pixelEN)	    	        ,
	  .A 			(y_kr )          ,   				// y_kr is aligned with sof_PreStart_dly[16] 		
	  .B 			(p1_r2_2yy_dly_sclkrate[16-11-1])  ,        			    // p1_r2_2yy is aligned with sof_PreStart_dly[11]
	  .SUM 			(add_terms_1)      					// aligned with sof_PreStart_dly[17] 
);

// y*kr + p1*(r2 + 2*y2) + p2*_2xy          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
_2Q16_add_2Q16_one_pixel_clock u_add_terms_1_1
(
	  .clk 			(clk)				        ,    	 
	  .clk_en		(1'b1)				        , 		 
	  .rst_n		(rst_n)				        ,  		 
	  .en    		(en)				        ,
	  .pixelEN 		(pixelEN)	    	        ,
	  .A 			(add_terms_1 )          	,   				// y_kr is aligned with sof_PreStart_dly[17] 		
	  .B 			(p2_2xy_dly_sclkrate[17-9-1])  ,        			    // p2_2xy is aligned with sof_PreStart_dly[9] 
	  .SUM 			(add_terms_1_1)      					// aligned with sof_PreStart_dly[18] 
);

// fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy)          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
mult_2Q16_by_11Q16_one_pixel_clock u_fy_add_terms_1_1
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(add_terms_1_1)			,       // aligned with sof_PreStart_dly[18]
	  .B 			(fy_11Q16)       ,    		// constant
	  .P 			(fy_add_terms_1_1)      			// aligned with sof_PreStart_dly[19] 
);

// v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
_11Q16_add_11Q16_one_pixel_clock u_fy_add_terms_1_1_v0
(
	  .clk 			(clk)				        ,    	 
	  .clk_en		(1'b1)				        , 		 
	  .rst_n		(rst_n)				        ,  		 
	  .en    		(en)				        ,
	  .pixelEN 		(pixelEN)	    	        ,
	  .A 			(fy_add_terms_1_1 )          	,   		// aligned with sof_PreStart_dly[19] 		
	  .B 			(v0_11Q16             )  ,        			    // constant
	  .SUM 			(fy_add_terms_1_1_v0)      					// aligned with sof_PreStart_dly[20] 
);

/***********************************************************************************************************
************************************************************************************************************
                     texture fetching  according to u v 
 ***********************************************************************************************************
 ***********************************************************************************************************/
/*

              (x,y)                             (x+1,y)
                o<----------1-du------->.<----du-->o------
                |                       |          |  /|\
                |                       |          |   |  1-dv
                |                  (u,v)|          |  \|/
                |-----------------------o----------|------
                |                       |          |  /|\
                |                       |          |   |
                |                       |          |   | dv
                |                       |          |  \|/
                o----------------------------------o------
              (x,y+1)                              (x+1,y+1)

    I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 

    u,v is float number , (x_dest,y_dest) is integer which is the central position in the shift register matrix kernel , 
    p0 = [6,6] for 13*13 matrix , in image coordinate system , it is (colcnt,rowcnt) . 
    u_to_central = u - x_dest 
    v_to_central = v - y_dest 
    is the float coordinate away from the central position of matrix , they should be within +/-6 bounds . 

    u_in_matrix = u_to_central + 6 
    v_in_matrix = v_to_central + 6
    are the coordinates in the matrix , they are Q10 type , do not use float type here , fix point type is very convinient here
    for calculating the above formula 
*/


wire signed [10+11-1:0] u_11Q10 , v_11Q10 ;   // aligned with sof_PreStart_dly[20]  
reg  signed [10+11-1:0] u_11Q10_dly_sclkrate [0:1]  ; 
reg  signed [10+11-1:0] v_11Q10_dly_sclkrate [0:1] ;
wire signed [11+10-1:0] u_actual_11Q10, v_actual_11Q10 ;


assign  u_11Q10 = fx_add_terms_0_0_u0[16+11-1:6] ;     // aligned with sof_PreStart_dly[20] 
assign  v_11Q10 = fy_add_terms_1_1_v0[16+11-1:6] ;     // aligned with sof_PreStart_dly[20] 

always@(posedge clk)
if(en && pixelEN)
begin
	v_11Q10_dly_sclkrate[1] <= v_11Q10_dly_sclkrate[0] ;  // aligned with sof_PreStart_dly[22]
	u_11Q10_dly_sclkrate[1] <= u_11Q10_dly_sclkrate[0] ;  // aligned with sof_PreStart_dly[22]

	v_11Q10_dly_sclkrate[0] <= v_11Q10  ;
	u_11Q10_dly_sclkrate[0] <= u_11Q10  ;     // aligned with sof_PreStart_dly[21] 
end

assign v_actual_11Q10 = v_11Q10_dly_sclkrate[1] ;  // aligned with sof_PreStart_dly[22]
assign u_actual_11Q10 = u_11Q10_dly_sclkrate[1] ;  // 21bit - 16bit = extral expanding bits .... to be optimaized 

// 2. calculate the distance away from the expected coordinate (x_dest,y_dest) 
//    in streaming condition , (x_dest,y_dest) is cooresponding to the central of the matrix 
/*
    u_to_central = u_actual_11Q10 - x_dest 
    v_to_central = v_actual_11Q10 - y_dest 
*/
wire [11+10-1:0] expected_X_11Q10 = { x_dest_11Q0_dly_sclkrate[22 - (-1) - 1] , {10{1'b0}} }  ;
wire [11+10-1:0] expected_Y_11Q10 = { y_dest_11Q0_dly_sclkrate[22 - (-1) - 1] , {10{1'b0}} }  ;

wire signed [11+10-1:0] diff_of_actual_to_expected_X_11Q10 , diff_of_actual_to_expected_Y_11Q10 ;   // 1 sign bit , 10 integer bits , 10 fractional bits 
assign diff_of_actual_to_expected_X_11Q10 = $signed(expected_X_11Q10) - $signed(u_actual_11Q10)  ;   // aligned with sof_PreStart_dly[22] x_dest_11Q0 is aligned with sof_PreStart_dly[-1]
assign diff_of_actual_to_expected_Y_11Q10 = $signed(expected_Y_11Q10) - $signed(v_actual_11Q10)  ;   // aligned with sof_PreStart_dly[22] y_dest_11Q0 is aligned with sof_PreStart_dly[-1]
// 3. convert from iamge coordinate system to 13*13 matrix coordinate system
/*
    u_in_matrix_coord = u_to_central + 6 ;
    v_in_matrix_coord = v_to_central + 6 ;

	IMPORTANT NOTE : 
		finally locate the hidden error, the orgin of coordinate is not in the topleft of shifting register array matix , IS IN THE BOOTTOM RIGHT.

		orgin of matrix P00 at topleft
         _______________________________
   ---->|   P00    |  P01    |  P02     |  
		|(x+1,y+1) | (x,y+1) |(x-1,y+1) |
		|__________|_________|__________|
		|  P10     |  P11    |  P12     |
		|(x+1,y)   | (x,y)   | (x-1,y)  |
		|__________|_________|__________|
		|  P20     |  P21    |  P22     |
		|(x+1,y-1) |(x,y-1)  | (x-1,y-1)|-----------> stream flow 
		|__________|_________|__________| 

*/
wire  [11+10-1:0] uCoord_Inmatrix_Orgin_atbottomright_11Q10 , vCoord_Inmatrix_Orgin_atbottomright_11Q10 ;


assign uCoord_Inmatrix_Orgin_atbottomright_11Q10 = $signed(diff_of_actual_to_expected_X_11Q10) + $signed({1'b0,3'd6,{10{1'b0}}}) ; // aligned with sof_PreStart_dly[22]  
assign vCoord_Inmatrix_Orgin_atbottomright_11Q10 = $signed(diff_of_actual_to_expected_Y_11Q10) + $signed({1'b0,3'd6,{10{1'b0}}}) ; // aligned with sof_PreStart_dly[22]

// 4. find I(x,y) I(x+1,y) I(x,y+1) I(x+1,y+1) from u_in_matrix_coord and v_in_matrix_coord 
/*
    x   = u_in_matrix_coord[11+10-1:10] 
    y   = v_in_matrix_coord[11+10-1:10] 
    x+1 = u_in_matrix_coord[11+10-1:10] + 1'b1
    y+1 = v_in_matrix_coord[11+10-1:10] + 1'b1 

    du  = 1.0 - u_in_matrix_coord[9:0]
    dv  = 1.0 - v_in_matrix_coord[9:0]
*/
wire [3 :0] x_in_matrix_4Q0 , y_in_matrix_4Q0  ;
wire [3 :0] xPlus1_in_matrix_4Q0  , yPlus1_in_matrix_4Q0  ;
wire [10:0] delta_u_1Q10 , delta_v_1Q10 ;
wire [10:0] _1_minus_delta_u_1Q10 , _1_minus_delta_v_1Q10 ;

reg [10:0] delta_u_1Q10_dly_sclkrate [0:31] ;
reg [10:0] _1_minus_delta_u_1Q10_dly_sclkrate [0:31] ;
reg [10:0] delta_v_1Q10_dly_sclkrate [0:31] ;
reg [10:0] _1_minus_delta_v_1Q10_dly_sclkrate [0:31] ;

always @ (posedge clk)
if(en && pixelEN)
begin
	for(i=1;i<32;i=i+1)
		delta_u_1Q10_dly_sclkrate[i] <= delta_u_1Q10_dly_sclkrate[i-1] ;
	delta_u_1Q10_dly_sclkrate[0] <= delta_u_1Q10 ;

	for(i=1;i<32;i=i+1)
		_1_minus_delta_u_1Q10_dly_sclkrate[i] <= _1_minus_delta_u_1Q10_dly_sclkrate[i-1] ;
	_1_minus_delta_u_1Q10_dly_sclkrate[0] <= _1_minus_delta_u_1Q10  ;

	for(i=1;i<32;i=i+1)
		delta_v_1Q10_dly_sclkrate[i] <= delta_v_1Q10_dly_sclkrate[i-1] ;
	delta_v_1Q10_dly_sclkrate[0] <= delta_v_1Q10 ;

	for(i=1;i<32;i=i+1)
		_1_minus_delta_v_1Q10_dly_sclkrate[i] <= _1_minus_delta_v_1Q10_dly_sclkrate[i-1] ;
	_1_minus_delta_v_1Q10_dly_sclkrate[0] <= _1_minus_delta_v_1Q10  ;
end


assign x_in_matrix_4Q0 		= uCoord_Inmatrix_Orgin_atbottomright_11Q10[13:10];   // pass the integer part // aligned with sof_PreStart_dly[22]  
assign y_in_matrix_4Q0 		= vCoord_Inmatrix_Orgin_atbottomright_11Q10[13:10];   // pass the integer part // aligned with sof_PreStart_dly[22]  
assign xPlus1_in_matrix_4Q0 = x_in_matrix_4Q0 - 1'b1;   		   // pass the integer part // aligned with sof_PreStart_dly[22]  
assign yPlus1_in_matrix_4Q0 = y_in_matrix_4Q0 - 1'b1;   		   // pass the integer part // aligned with sof_PreStart_dly[22]  

wire x_below_bounds_warning  = (uCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1]==1'b1) ? 1'b1 : 1'b0 ;  // negative number 
wire x_exceed_bounds_warning = ( (uCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-2:10] > 12)  && 
							     (uCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1]==1'b0) ) ? 1'b1 : 1'b0 ;  // too big to fit in the matrix 
wire y_below_bounds_warning  = (vCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1]==1'b1) ? 1'b1 : 1'b0 ;  // negative number 
wire y_exceed_bounds_warning = ( (vCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-2:10] > 12)  && 
                                 (vCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1]==1'b0) ) ? 1'b1 : 1'b0 ;  // too big to fit in the matrix 

assign _1_minus_delta_u_1Q10 = {1'b0,uCoord_Inmatrix_Orgin_atbottomright_11Q10[9:0]} ; // the sign-bit should be 0 , other wise it is not in the 13*13 matrix range   // aligned with sof_PreStart_dly[22]  
assign _1_minus_delta_v_1Q10 = {1'b0,vCoord_Inmatrix_Orgin_atbottomright_11Q10[9:0]} ;
assign delta_u_1Q10 = {1'b0,{10{1'b1}}} - _1_minus_delta_u_1Q10 ;   // 1: {10{1'b1}}    // aligned with sof_PreStart_dly[22]  
assign delta_v_1Q10 = {1'b0,{10{1'b1}}} - _1_minus_delta_v_1Q10 ;   // aligned with sof_PreStart_dly[22]  



// 5. texture fetch according to x,y,x+1,y+1,du,dv 
reg [8:0] I_x_y_sclkrate ;
reg [8:0] I_xPlus1_y_sclkrate ;
reg [8:0] I_x_yPlus1_sclkrate ;
reg [8:0] I_xPlus1_yPlus1_sclkrate ;

/******************************************************************************************************************************
at this point matrixNbyNArray_wire should be aligned with the index below , ie. all of them are aligned with sof_PreStart_dly[22]
******************************************************************************************************************************/
always@(posedge clk)
if(en && pixelEN)    // matrixNbyNArray_wire[r][c] / [y][x]
begin
	if(x_below_bounds_warning || x_exceed_bounds_warning || y_below_bounds_warning || y_exceed_bounds_warning )
	begin 
		I_x_y_sclkrate 				<= 0 ;
		I_xPlus1_y_sclkrate 		<= 0 ;
		I_x_yPlus1_sclkrate 		<= 0 ;
		I_xPlus1_yPlus1_sclkrate 	<= 0 ;
	end
	else begin
    	I_x_y_sclkrate 				<= {1'b0 , matrixNbyNArray_wire [y_in_matrix_4Q0      ][x_in_matrix_4Q0      ][7:0]} ;    		//aligned with sof_PreStart_dly[23]
    	I_xPlus1_y_sclkrate 		<= {1'b0 , matrixNbyNArray_wire [y_in_matrix_4Q0      ][xPlus1_in_matrix_4Q0 ][7:0]} ;    	    //aligned with sof_PreStart_dly[23]
    	I_x_yPlus1_sclkrate 		<= {1'b0 , matrixNbyNArray_wire [yPlus1_in_matrix_4Q0 ][x_in_matrix_4Q0      ][7:0]} ;    	    //aligned with sof_PreStart_dly[23]
    	I_xPlus1_yPlus1_sclkrate 	<= {1'b0 , matrixNbyNArray_wire [yPlus1_in_matrix_4Q0 ][xPlus1_in_matrix_4Q0 ][7:0]} ;          //aligned with sof_PreStart_dly[23]
	end
end 

/*
	debug section , input data is counter , should match with the counter here. 
*/
`ifdef  debug 
	/*
		what are you looking for in modelsim waveform or from the printed txt files : 
		1) expected_X_11Q10 should be the same as the matrixNbyNArray_wire[6][6] output, when input stream is colcnt # ;
		2) the output UV txt files should be the same , float number can't be identical, but should be roughly the same.-
		    -----> this verifies that UV generation logic is right, and delay taps is right as well .(verified )
		3) check if U - expected_x right and V - expected_y are right ?
		4) if src_x_inMatrix = U - expected_x + 6 and and src_y_inMatrix = V - expected_y + 6 right ? these tells where in the matrix to fetch the actual source pixels ?
		5) if I[src_x_inMatrix][src_y_inMatrix] in the matrix kernel  == I[src_x][src_y] in the image ?? ------> this should be implemented by c 

		c++ side : 
		read in I[src_x_inMatrix][src_y_inMatrix] textfile , compared it with the I[src_x][src_y] in the image . 

		a) first do some simple waveform check, correct some visible logic timing error , if final outcome is good , no need further verification 
		b) then print the output to text file and use the c to do the mass checkout , this 
		helps reveal some hidden errors 
	*/

	reg [10:0] col_cnt = 0 ;
	always@(posedge clk)
	if(en && pixelEN)
	begin
		if( (sof_PreStart_dly[21] == 1'b1) || (col_cnt == IMAGE_WIDTH -1) )  
		begin
			col_cnt <= 0 ;   // aligned with 22 
		end
		else begin
			col_cnt <= col_cnt + 1'b1  ; 
		end
	end

	wire data_not_matched = (col_cnt[7:0] != matrixNbyNArray_wire[6][6][7:0]);   // this verify if the delay taps is correct or not ?

	integer fd_left_U , fd_left_V ;
	integer fd_right_U , fd_right_V ;
	reg start_print_UV = 0 ;

	generate  // check if UV is correct , comapred to opencv version
		if(LEFT_RIGHT == "L")
		begin
			initial
			begin
				fd_left_U = $fopen("left_U_cord.txt","w");
				fd_left_V = $fopen("left_V_cord.txt","w");
			end

			always @ (posedge clk)
			if(en && pixelEN)
			begin
				if(sof_PreStart_dly[19])   // aligned with 20 
					start_print_UV <= 1'b1 ;
				else 
					start_print_UV <= start_print_UV ;

				if(start_print_UV == 1'b1)
				begin
					$fwrite(fd_left_U,"%h\n", u_11Q10 );
					$fwrite(fd_left_V,"%h\n", v_11Q10 );
				end
			end
		end
		else if (LEFT_RIGHT == "R")
		begin
			initial begin
				fd_right_U = $fopen("right_U_cord.txt","w");
				fd_right_V = $fopen("right_V_cord.txt","w");
			end

			always @ (posedge clk)
			if(en && pixelEN)
			begin
				if(sof_PreStart_dly[19])   // aligned with 20 
					start_print_UV <= 1'b1 ;
				else 
					start_print_UV <= start_print_UV ;

				if(start_print_UV == 1'b1)
				begin
					$fwrite(fd_right_U,"%h\n", u_11Q10 );
					$fwrite(fd_right_V,"%h\n", v_11Q10 );
			    end
			end
		end

	endgenerate

`endif



// // I(x,y)*du            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [9+11-1:0] I_x_y_times_du_10Q10 ;  // 2 sign bits 
mult_8Q0By1Q10_one_pixel_clock U_I_x_y_times_du (
	 
	 .clk   	(clk) ,    // Clock
	 .clk_en	(1'b1) , // Clock Enable
	 .rst_n 	(rst_n) ,  // Asynchronous reset active low
	 .en    	(en) ,
	 .pixelEN 	(pixelEN) ,
	 .A_9Q0 	(I_x_y_sclkrate) ,               						 //aligned with sof_PreStart_dly[23]
	 .B_1Q10 	(delta_u_1Q10_dly_sclkrate[23-22-1]) ,  			     // delta_u_1Q10 is aligned with sof_PreStart_dly[22]
	 .O 		(I_x_y_times_du_10Q10)                                   //aligned with sof_PreStart_dly[24]
);


// I(x+1,y)*(1-du)            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [9+11-1:0] I_xPlus1_y_times_1Minus_du_10Q10 ;  // 2 sign bits 
mult_8Q0By1Q10_one_pixel_clock U_I_xPlus1_y_times_1Minus_du (
	 
	 .clk   	(clk) ,    // Clock
	 .clk_en	(1'b1) , // Clock Enable
	 .rst_n 	(rst_n) ,  // Asynchronous reset active low
	 .en    	(en) ,
	 .pixelEN 	(pixelEN) ,
	 .A_9Q0 	(I_xPlus1_y_sclkrate) ,               						     //aligned with sof_PreStart_dly[23]
	 .B_1Q10 	(_1_minus_delta_u_1Q10_dly_sclkrate[23-22-1]) ,  			     // _1_minus_delta_u_1Q10 is aligned with sof_PreStart_dly[22]
	 .O 		(I_xPlus1_y_times_1Minus_du_10Q10)                                   //aligned with sof_PreStart_dly[24]
);

// // I(x,y+1)*du            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [9+11-1:0] I_x_yPlus1_times_du_10Q10 ;  // 2 sign bits 
mult_8Q0By1Q10_one_pixel_clock U_I_x_yPlus1_times_du (
	 
	 .clk   	(clk) ,    // Clock
	 .clk_en	(1'b1) , // Clock Enable
	 .rst_n 	(rst_n) ,  // Asynchronous reset active low
	 .en    	(en) ,
	 .pixelEN 	(pixelEN) ,
	 .A_9Q0 	(I_x_yPlus1_sclkrate) ,               						 //aligned with sof_PreStart_dly[23]
	 .B_1Q10 	(delta_u_1Q10_dly_sclkrate[23-22-1]) ,  			     // _1_minus_delta_u_1Q10 is aligned with sof_PreStart_dly[22]
	 .O 		(I_x_yPlus1_times_du_10Q10)                                   //aligned with sof_PreStart_dly[24]
);

// // I(x+1,y+1)*(1-du)            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [9+11-1:0] I_xPlus1_yPlus1_times_1Minus_du_10Q10 ;  // 2 sign bits 
mult_8Q0By1Q10_one_pixel_clock U_I_xPlus1_yPlus1_times_1Minus_du (
	 
	 .clk   	(clk) ,    // Clock
	 .clk_en	(1'b1) , // Clock Enable
	 .rst_n 	(rst_n) ,  // Asynchronous reset active low
	 .en    	(en) ,
	 .pixelEN 	(pixelEN) ,
	 .A_9Q0 	(I_xPlus1_yPlus1_sclkrate) ,               						 //aligned with sof_PreStart_dly[23]
	 .B_1Q10 	(_1_minus_delta_u_1Q10_dly_sclkrate[23-22-1]) ,  			     // _1_minus_delta_u_1Q10 is aligned with sof_PreStart_dly[22]
	 .O 		(I_xPlus1_yPlus1_times_1Minus_du_10Q10)                                   //aligned with sof_PreStart_dly[24]
);

// I(x,y)*du + I(x+1,y)*(1-du)            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [8:0] weightedSum_of_top2_pixels_9Q0  ;  // 1 sign bits 
add_10Q10_one_pixel_clock U_top2Sum (
	.clk 		(clk)	,     
	.en    		(en)	,
	.pixelEN 	(pixelEN)	,
	.A_10Q10 	(I_x_y_times_du_10Q10)	,                              //aligned with sof_PreStart_dly[24] 
	.B_10Q10 	(I_xPlus1_y_times_1Minus_du_10Q10)	,                  //aligned with sof_PreStart_dly[24] 
	.O 			(weightedSum_of_top2_pixels_9Q0)	                   //aligned with sof_PreStart_dly[25] 
);


// // I(x,y+1)*du + I(x+1,y+1)*(1-du)            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [8:0] weightedSum_of_bottom2_pixels_9Q0  ;  // 1 sign bit
add_10Q10_one_pixel_clock U_bottom2Sum (
	.clk 		(clk)	,     
	.en    		(en)	,
	.pixelEN 	(pixelEN)	,
	.A_10Q10 	(I_x_yPlus1_times_du_10Q10)	,                              //aligned with sof_PreStart_dly[24] 
	.B_10Q10 	(I_xPlus1_yPlus1_times_1Minus_du_10Q10)	,                  //aligned with sof_PreStart_dly[24] 
	.O 			(weightedSum_of_bottom2_pixels_9Q0)	                       //aligned with sof_PreStart_dly[25] 
);

// [I(x,y)*du + I(x+1,y)*(1-du)] * dv            ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [9+11-1:0] top2_times_dv_10Q10 ;
mult_8Q0By1Q10_one_pixel_clock U_I_top2Sum_times_dv (
	 
	 .clk   	(clk) ,    // Clock
	 .clk_en	(1'b1) , // Clock Enable
	 .rst_n 	(rst_n) ,  // Asynchronous reset active low
	 .en    	(en) ,
	 .pixelEN 	(pixelEN) ,
	 .A_9Q0 	(weightedSum_of_top2_pixels_9Q0) ,               						 //aligned with sof_PreStart_dly[25]
	 .B_1Q10 	(delta_v_1Q10_dly_sclkrate[25-22-1]) ,  			     // delta_u_1Q10 is aligned with sof_PreStart_dly[22]
	 .O 		(top2_times_dv_10Q10)                                   //aligned with sof_PreStart_dly[26]
);

// // [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv)             ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [9+11-1:0] bottom2_times_1Minus_dv_10Q10 ;
mult_8Q0By1Q10_one_pixel_clock U_I_bottom2Sum_times_iMinus_dv (
	 
	 .clk   	(clk) ,    // Clock
	 .clk_en	(1'b1) , // Clock Enable
	 .rst_n 	(rst_n) ,  // Asynchronous reset active low
	 .en    	(en) ,
	 .pixelEN 	(pixelEN) ,
	 .A_9Q0 	(weightedSum_of_bottom2_pixels_9Q0) ,               						 //aligned with sof_PreStart_dly[25]
	 .B_1Q10 	(_1_minus_delta_v_1Q10_dly_sclkrate[25-22-1]) ,  			     // delta_u_1Q10 is aligned with sof_PreStart_dly[22]
	 .O 		(bottom2_times_1Minus_dv_10Q10)                                   //aligned with sof_PreStart_dly[26]
);
// [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv)              ----------------------->       I(x_dest,y_dest) = I(u,v)= [I(x,y)*du + I(x+1,y)*(1-du)] * dv + [I(x,y+1)*du + I(x+1,y+1)*(1-du)] * (1-dv) 
wire [8:0] weightedSum_of_bottom_and_top ; 
add_10Q10_one_pixel_clock U_sumOf_top_bottom (
	.clk 		(clk)	,     
	.en    		(en)	,
	.pixelEN 	(pixelEN)	,
	.A_10Q10 	(top2_times_dv_10Q10)	,                              //aligned with sof_PreStart_dly[26] 
	.B_10Q10 	(bottom2_times_1Minus_dv_10Q10)	,                  //aligned with sof_PreStart_dly[26] 
	.O 			(weightedSum_of_bottom_and_top)	                       //aligned with sof_PreStart_dly[27] 
);

wire [7:0] final_texture_pixel = weightedSum_of_bottom_and_top[7:0] ;

reg [8:0] I_x_y_dly_sclkrate [0:31] ;

always@(posedge clk)
if(en && pixelEN )
begin
	for(i=1; i<32; i=i+1)
	begin
		I_x_y_dly_sclkrate[i] <= I_x_y_dly_sclkrate[i-1] ;
	end
	I_x_y_dly_sclkrate[0] <= I_x_y_sclkrate ;
end

// assign rectified_stream = {sof_PreStart_dly[27],final_texture_pixel} ;
assign rectified_stream = {sof_PreStart_dly[27],I_x_y_dly_sclkrate[27-23-1][7:0]}  ;   // make it simple, don't use texture fetch method and save some resource 


/* 

	G =  (Rr * Mrect).inv  

	P_middle = G * P_dest ;
	P_src    = Mr.inv * Distortion(P_middle)        // Mr is camera matrix 3*3
	
	                       G
	|        |       |                 |   |      |
	|x_middle|       |ir[0] ir[1] ir[2]|   |x_dest|
	|y_middle|  =    |ir[3] ir[4] ir[5]| * |y_dest|
	|w_middle|       |ir[6] ir[7] ir[8]|   |w_dest|
	|        |       |                 |   |      | 



      keep in mind the process :
          1.  reverse rectify    P'' = (R * Mrect)^ P , ^ represent matrix inversion , R is the rotation matrix , Mrect is the rectified camera matrix 3x3
          2.  reverse undistort to the original sensor image  P= M^*F_inversDist(P'')   M is the camera matrix
          Mrect =
                        [
                            f_x , s     ,  c_x
                            0    , f_y  ,  c_y
                            0    , 0     ,   1   ]
           // radial distortion
           x_dest =  x_src(1 + k1*r^2 + k2*r^4 + k3*r^6)
           y_dest =  y_src(1 + k1*r^2 + k2*r^4 + k3*r^6)
           // tangential distortion
           x_dest = x_src + [2*p1*x_src * y_src + p2(r^2 + 2*x_src)]
           y_dest = y_src + [p1*(r^2 + 2*y^2) + 2*p2*x_src*y_src)]

           // reverse tangential distortion (x,y) dest , (_x,_y) src   ????
           >   _x = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + x0
           >   _y = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + y0

            iR = (R * Mrect)^ P
            A  is the camera metrix
            Ar is the new camera metrix

   
  C++ version , see the system diagram to read more 
 for( int i = 0; i < size.height; i++ )   // (i,j) is the destination coordinates,int type;  (u,v) is the source coordinate , float type
    {
        float* m1f = (float*)(map1.data + map1.step*i);   // pointer to the dest map1
        float* m2f = (float*)(map2.data + map2.step*i);   // pointer to the dest map2

        double _x = i*ir[1] + ir[2], _y = i*ir[4] + ir[5], _w = i*ir[7] + ir[8];    // clever!! saves a lot of redundant computation

        for( int j = 0; j < size.width; j++, _x += ir[0], _y += ir[3], _w += ir[6] )
        {
        	// P_middle = G * P_dest ;
            double w = 1./_w, x = _x*w, y = _y*w;   // (x,y,w)= ir * (j,i,1) ------ reverse rectified   ---Brian    

			// P_src    = Mr.inv * Distortion(P_middle)        // Mr is camera matrix 3*3            
            double x2 = x*x, y2 = y*y;
            double r2 = x2 + y2, _2xy = 2*x*y;
            double kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
            double u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
            double v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;

                m1f[j] = (float)u;
                m2f[j] = (float)v;
        }
    }
*/




/*      what about boundery condition    ?       
                                            __________                      _________
					                       |          |                    |         |
	    -------------------disp(x+1,y+1)-->|  Z-1     |--disp(x,y+1)------>|  Z-1    |-------------o disp(x-1,y+1) 
					|                      |__________|                    |_________|
					|
				  _\|/_
				 |     |
				 | N-2 |
				 |     |
				 |_____|                    __________                      _________
				 	|                      |          |                    |         |
				 	|--------disp(x+1,y)-->|  Z-1     |--disp(x,y)-------->|  Z-1    |-------------o disp(x-1,y)
				 	|                      |__________|                    |_________|
					|
				  _\|/_
				 |     |
				 | N-2 |
				 |     |
				 |_____|                    __________                      _________
				 	|                      |          |                    |         |
				 	 ------disp(x+1,y-1)-->|  Z-1     |--disp(x,y-1)------>|  Z-1    |-------------o disp(x-1,y-1)
				 	                       |__________|                    |_________|         

*/



// *****************  block ram fifo  **************************
reg[9:0] BlkRamAddressA , BlkRamAddressB ;
wire [10:0] BlkRamAddressB_pre ;
  

assign BlkRamAddressB_pre = BlkRamAddressA + 3 ;

always@(posedge clk)
if(~rst_n)
begin 
	BlkRamAddressA <= 0 ;
end 
else if(en && pixelEN)
begin
	if(BlkRamAddressA == IMAGE_WIDTH - 1 )
		BlkRamAddressA <= 0 ;
	else
		BlkRamAddressA <= BlkRamAddressA + 1;

	if(BlkRamAddressB_pre > IMAGE_WIDTH - 1) 
		BlkRamAddressB <= BlkRamAddressB_pre - IMAGE_WIDTH ;
	else
		BlkRamAddressB <= BlkRamAddressB_pre[9:0] ;
end



generate 
for(k=1; k<BLOCK_Y; k=k+1)
begin
 rectifyLineBuffer ulineBuffer
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[k-1])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[k])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );
end

 rectifyLineBuffer ulineBuffer0
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (input_delay[DELAY_TAP_LEN])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[0])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );

endgenerate
  
endmodule



module mult_11Q0_by_2Q16_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire  [11-1:0]     A , 
	input wire  [2+16-1:0]   B ,

	output wire [11+16-1:0]  P 
	
);
	reg [11+16-1:0] prod_reg_sclkrate ;
	// assign P = prod_reg_sclkrate ;

	// wire signed [18+11-1:0] prod ;   // 2 signed bits 

	// assign prod = $signed(A) * $signed(B) ;
	
	// wire overflow = (prod[16+11-1] != prod[18+11-1]); 

	wire [28:0]  p_out ;
	assign P =  prod_reg_sclkrate;

	mult_11Q0_by_2Q16 u
    (
       .CLK (clk) ,   //: IN STD_LOGIC;
       .A   (A) ,   //: IN STD_LOGIC_VECTOR(10 DOWNTO 0);
       .B   (B) ,   //: IN STD_LOGIC_VECTOR(17 DOWNTO 0);
       .P   (p_out)     //: OUT STD_LOGIC_VECTOR(28 DOWNTO 0)
    );

    always@(posedge clk)
	if(en && pixelEN)
	begin
		prod_reg_sclkrate <= p_out[11+16-1:0] ;   // 1 signed bit Q16
	end
	else begin
		prod_reg_sclkrate <= prod_reg_sclkrate ;
	end

endmodule


module mult_2Q16_by_2Q16_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [2+16-1:0] A , 
	input wire [2+16-1:0] B ,

	output wire [2+16-1:0] P 
	
);
	reg [2+16-1:0] prod_reg_sclkrate ;
	// assign P = prod_reg_sclkrate ;

	// wire signed [2+16 + 2+16-1:0] prod ;   // 2 signed bits  32 fractional bits    

	// assign prod = $signed(A) * $signed(B) ;
	
	// always@(posedge clk)
	// if(en && pixelEN)
	// begin
	// 	prod_reg_sclkrate <= prod[2+16 + 2+16-1 : 2+16 + 2+16-1 - 18 + 1] ;   // 2 signed bit Q16
	// end
	// else begin
	// 	prod_reg_sclkrate <= prod_reg_sclkrate ;
	// end

	wire [35:0] p_out ;
	assign P =  prod_reg_sclkrate ;

	mult_2Q16_by_2Q16 u
    (
       .CLK (clk) ,    
       .A   (A) ,    
       .B   (B) ,    
       .P   (p_out)      
    );

    always@(posedge clk)
	if(en && pixelEN)
	begin
		prod_reg_sclkrate <= p_out[16+16+2-1:16] ;   // 1 signed bit Q16
	end
	else begin
		prod_reg_sclkrate <= prod_reg_sclkrate ;
	end

endmodule


module mult_2Q16_by_11Q16_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [2+16-1:0] A , 
	input wire [11+16-1:0] B ,

	output wire [11+16-1:0] P 
	
);
	reg [11+16-1:0] prod_reg_sclkrate ;
	// assign P = prod_reg_sclkrate ;

	// wire signed [2+16 + 11+16-1:0] prod ;   // 2 signed bits  32 fractional bits 

	// assign prod = $signed(A) * $signed(B) ;
	
	// always@(posedge clk)
	// if(en && pixelEN)
	// begin
	// 	prod_reg_sclkrate <= prod[11+16 + 16 -1 : 16] ;   // 2 signed bit Q16
	// end
	// else begin
	// 	prod_reg_sclkrate <= prod_reg_sclkrate ;
	// end

	wire [18+27-1:0] p_out ;
	assign P =  prod_reg_sclkrate ;

	mult_2Q16_by_11Q16 u
    (
       .CLK (clk) ,    
       .A   (A) ,    
       .B   (B) ,    
       .P   (p_out)      
    );

    always@(posedge clk)
	if(en && pixelEN)
	begin
		prod_reg_sclkrate <= p_out[16+16+11-1:16] ;   // 1 signed bit Q16
	end
	else begin
		prod_reg_sclkrate <= prod_reg_sclkrate ;
	end

endmodule


module _11Q16_add_11Q16_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [11+16-1:0] A , 
	input wire [11+16-1:0] B ,

	output wire [11+16-1:0] SUM 
	
);
	reg [11+16-1:0] sum_ab_reg_sclkrate ;
	assign SUM = sum_ab_reg_sclkrate ;
	
	wire signed [11+16-1:0] sum_ab ; 

	assign sum_ab = $signed(A) + $signed(B) ;
	
	always@(posedge clk)
	if(en && pixelEN)
	begin
		sum_ab_reg_sclkrate <= sum_ab ;   // aligned with sof_PreStart_dly[11]
	end
	else begin
		sum_ab_reg_sclkrate <= sum_ab_reg_sclkrate ;
	end

endmodule


module _2Q16_add_2Q16_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [2+16-1:0] A , 
	input wire [2+16-1:0] B ,

	output wire [2+16-1:0] SUM 
	
);
	reg [2+16-1:0] sum_ab_reg_sclkrate ;
	assign SUM = sum_ab_reg_sclkrate ;
	
	wire signed [2+16-1:0] sum_ab ; 

	assign sum_ab = $signed(A) + $signed(B) ;
	
	always@(posedge clk)
	if(en && pixelEN)
	begin
		sum_ab_reg_sclkrate <= sum_ab ;    
	end
	else begin
		sum_ab_reg_sclkrate <= sum_ab_reg_sclkrate ;
	end

endmodule



// -------------------------------------------------------

module mult_8Q0By1Q10_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire  [8:0] A_9Q0 , 
	input wire  [10:0] B_1Q10 , 
	output wire [19:0] O 
	
);
	wire [19:0]  product_10Q10 ;
	reg  [19:0]  product_10Q10_sclkrate ;

	assign O = product_10Q10_sclkrate ;

	mult_8Q0By1Q10 u
	  (
	    .CLK    (clk),   
	    .A      (A_9Q0),   // IN STD_LOGIC_VECTOR(8 DOWNTO 0);                   
	    .B      (B_1Q10),  // IN STD_LOGIC_VECTOR(10 DOWNTO 0);         
	    .CE     (1'b1),   
	    .P      (product_10Q10)  
	  );

	always@(posedge clk)
	if(en && pixelEN) 
	begin
	    product_10Q10_sclkrate <= product_10Q10 ;   
	end
	else begin
		product_10Q10_sclkrate <= product_10Q10_sclkrate ;
	end

endmodule





module add_10Q10_one_pixel_clock (
	input wire  clk,     
	input wire  en    ,
	input wire  pixelEN ,
	input wire  [19:0] A_10Q10 , 
	input wire  [19:0] B_10Q10 , 
	output wire [8 :0] O 
	
);
	wire [19:0] sum = A_10Q10 + B_10Q10 ;
	reg  [7 :0] sum_reg  ; 
	assign O = sum_reg ;

	always@(posedge clk)
	if(en && pixelEN) 
	begin
	    sum_reg <= sum [18:10] + sum [9] ;    // 1 sign bit.  if bit[9] == 1, means fraction portion is greater than 0.5, round up to 1 ,otherwise round down to 0
	end
	else begin
		sum_reg <= sum_reg ;
	end

endmodule




module div_4_pixel_clock (
	input wire            clk,    // Clock
	input wire            en ,
	input wire            pixelEN ,

	input wire[17:0]      x_middle_p_2Q16 ,
    input wire[17:0]      w_middle_p_2Q16 , 

    output wire[17:0]     x_middle_2qQ16  
);


	wire[31:0] x_middle_hclkrate ;

	wire x_div_w_valid ;
	reg  x_div_w_valid_dly ;

	// wire s_axis_divisor_tready , s_axis_dividend_tready ; 

// ENTITY div_gen_0 IS
//   PORT (
//     aclk : IN STD_LOGIC;
//     aclken : IN STD_LOGIC;
//     aresetn : IN STD_LOGIC;
//     s_axis_divisor_tvalid : IN STD_LOGIC;
//     s_axis_divisor_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
//     s_axis_dividend_tvalid : IN STD_LOGIC;
//     s_axis_dividend_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
//     m_axis_dout_tvalid : OUT STD_LOGIC;
//     m_axis_dout_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
//   );

/*  
	 IMPORTANT :  READ THE DATASHEET !!!!!!  best to be 2^x bit width 

	    equal to divident width 
    |<---------integer -------------->|<-------- fraction ---------------->|
     _________________________________ ____________________________________
	|          |                      |          |                         |
	| sign-bit |                      | sign-bit |     FRACTION BIT FIELD  |
	|__________|______________________|__________|_________________________|
*/

	// both divident and divisor left shitf 2 bits , fractional point in D17
	wire [15:0] _0p5 = 16'b0010_0000_0000_0000;
    // wire [15:0] s_axis_divisor_tdata  =  _0p5 >> 1 ; //w_middle_p_2Q16[17:2] + w_middle_p_2Q16[1] ; //$signed(w_middle_p_2Q16) ;
    // wire [15:0] s_axis_dividend_tdata = ~_0p5 + 1'b1; //x_middle_p_2Q16[17:2] + x_middle_p_2Q16[1] ; //$signed(x_middle_p_2Q16) ;
    wire [15:0] s_axis_divisor_tdata  =   w_middle_p_2Q16[17:2] + w_middle_p_2Q16[1] ; //$signed(w_middle_p_2Q16) ;
    wire [15:0] s_axis_dividend_tdata =   x_middle_p_2Q16[17:2] + x_middle_p_2Q16[1] ; //$signed(x_middle_p_2Q16) ;

	div_gen_0 u_x_div_w
    (
	    .aclk 						(clk)  ,    //: IN STD_LOGIC;
	    .aclken 					(en)  ,    //	: IN STD_LOGIC;
	    .aresetn                    (1'b1) ,
	    .s_axis_divisor_tvalid 		(en & pixelEN)  ,    //: IN STD_LOGIC;
	    // .s_axis_divisor_tready 		(s_axis_divisor_tready)  ,    //: OUT STD_LOGIC;
	    .s_axis_divisor_tdata 		(s_axis_divisor_tdata) ,  //   ,    //: IN STD_LOGIC_VECTOR(15 DOWNTO 0);
	    .s_axis_dividend_tvalid 	(en & pixelEN)  ,    //	: IN STD_LOGIC;
	    // .s_axis_dividend_tready 	(s_axis_dividend_tready)  ,    //	: OUT STD_LOGIC;
	    .s_axis_dividend_tdata 		(s_axis_dividend_tdata  ) ,  //{{6{w_middle_p_2Q16[17]}},w_middle_p_2Q16})  ,    //: IN STD_LOGIC_VECTOR(15 DOWNTO 0);
	    .m_axis_dout_tvalid 		(x_div_w_valid)  ,    //	: OUT STD_LOGIC;
	    .m_axis_dout_tdata 			(x_middle_hclkrate)       //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );

	// using fifo to syn the two different clock domain , handle data from clk to pixel clock , when ip pipline is not handled by en signal 
	// the maximum data in fifo is determined by ip pipline cycle ,here is no more than 4 pixel clock cycles 

	// assign  x_div_w_write_fifo_en = (x_div_w_valid) & (~x_div_w_valid_dly) & (~x_div_w_fifo_full);  // rising edge and fifo is not full 

	// assign  x_div_w_read_fifo_en = en & pixelEN & (~x_div_w_fifo_empty) ;

	// the machanism determines than the delay is always 4 pixel clock cycles . ie. there are always 4 data left in the fifo , see the timing waveform below 
	/*
						  ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___      ___      ___     ___     ___     ___
		clk         _____|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |____|   |____|   |___|   |___|   |___|   |___
	                      _______                                                         _______                                                           ______
		pixelEN     _____|       |_______________________________________________________|       |_________________________________________________________|      |____
	                      _______                                                         _______                                                           _______
	divider_in_tvalid ___|       |_______________________________________________________|       |_________________________________________________________|       |_____
	                    _________ _______________________________________________________________ ________________________________________________________________ _____
		x_middle_p/w_p ____0_____X_______________________1_______________________________________X_______________________________2________________________________X_____  
	                                                                                                      ________                                                             ______
		divider output valid ____________________________________________________________________________|        |___________________________________________________________|      |____________
	                                                                                                      ____________________________________________________________________ _________________
		x_middle    ?????????????????????????????????????????????????????????????????????????????????????X_______________________0____________________________________________X___________1_____  
		                 |<----------divider pipline delay taps = 9 as an example----------------------->|
		                         					 start a new divider pipline here--->|<-------------------------------------9 clk cycle delay---------------------------->|
		               		_____________________________________________________________________________ ________________________________________________________ ___________ _________________
		# of data in fifo  ________________________________0_____________________________________________X_______________________1________________________________X____0______X___________1____
	             _________________________________________________________________________________________________________________________________________________ ____________________
		fifo_out _________________________________________________________________________________________________________________________________________________X___data0___________
					   |<----------------------------------- 2 pixel clock dealy -------------------------------------------------------------------------------->|


	*/

	integer n ;
  

	reg [17:0] x_div_w_reg_dly_sclkrate [0:3] ; 

	wire [15:0] Quatient ; 
	wire [15:0] Fraction ; // 2 sign bit 
	wire [1:0]  Quatient_2bit ; 

	assign Quatient = x_middle_hclkrate[31:16] ;   
	assign Fraction = x_middle_hclkrate[15:0] ;   //  1Q15  1 sign bit in fraction field 
	assign Quatient_2bit = (Quatient[1:0] == 2'b00) ?  {Fraction[15],Fraction[15]} : Quatient[1:0] ;

	always@(posedge clk)
	if(en && pixelEN)
	begin
		for(n=1; n < 4; n=n+1)
			x_div_w_reg_dly_sclkrate[n] <= x_div_w_reg_dly_sclkrate[n-1] ; 
		x_div_w_reg_dly_sclkrate[0] <=  {Quatient_2bit,{Fraction << 1}};  // note : need 2 sign bits , 2 interger , detect overflow 
	end 

	// always@(posedge clk)
	// if((x_div_w_valid && (~x_div_w_valid_dly) ) && en)
	// begin
	// 	x_middle_dly_hclkrate <= x_middle_hclkrate ;
	// end

	// always@(posedge clk)
	// begin
	// 	x_div_w_valid_dly <= x_div_w_valid ; 
	// end


	assign x_middle_2qQ16 = x_div_w_reg_dly_sclkrate[0] ;   // total design delay is 4 , the fix divider takes 25 clk cycle which is 3.xx pixel clock cycle
	                                                  // so we need a extral one clock delay to meet the delay requirement

endmodule


