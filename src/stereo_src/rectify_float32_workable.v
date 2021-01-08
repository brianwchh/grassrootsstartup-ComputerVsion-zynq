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
 
*/

`define  debug

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

wire [31:0] one_float16 = {1'b0,8'h7F,23'd0} ;    // 1.0*2^(15-15) = 1.0
wire [31:0] _2_float16 =  {1'b0,8'h80,23'd0} ;    // 1.0*2^(16-15) = 2.0
wire [31:0] zero_float16 =  {1'b0,8'h00,23'd0} ;    // 1.0*2^(16-15) = 2.0

wire[31:0] ir_float32[0:8] ;
wire [9:0] linebufferout [0:BLOCK_Y-1] ; 
reg [9:0] input_delay [0:31] ;
wire sof_PreStart ;


wire[31:0] k1_float32 ;
wire[31:0] k2_float32 ;
wire[31:0] p1_float32 ;
wire[31:0] p2_float32 ;
wire[31:0] k3_float32 ;
wire[31:0] k4_float32 ;
wire[31:0] k5_float32 ;
wire[31:0] k6_float32 ;
      
wire[31:0] u0_float32 ;
wire[31:0] v0_float32 ;
wire[31:0] fx_float32 ;
wire[31:0] fy_float32 ;

generate 
	if(LEFT_RIGHT  == "L") 
	begin
		assign k1_float32         = 32'h3CA9D9AE ;       // DistortCoefArray[0]  =  0.020734      :     
		assign k2_float32         = 32'h3CFFAAFD ;       // DistortCoefArray[1]  =  0.031209      :     
		assign p1_float32         = 32'h00000000 ;       // DistortCoefArray[2]  =  0.000000      :     
		assign p2_float32         = 32'h00000000 ;       // DistortCoefArray[3]  =  0.000000      :     
		assign k3_float32         = 32'hBE869FB5 ;       // DistortCoefArray[4]  = -0.262937      :     
		assign k4_float32         = 32'h00000000 ;       // DistortCoefArray[5]  =  0.000000      :     
		assign k5_float32         = 32'h00000000 ;       // DistortCoefArray[6]  =  0.000000      :     
		assign k6_float32         = 32'h00000000 ;       // DistortCoefArray[7]  =  0.000000      :     
		assign u0_float32    	  = 32'h43A5EC8A ;       // AcameraMatrix[0]  =  331.847961      :     
		assign v0_float32    	  = 32'h432EC7FE ;       // AcameraMatrix[1]  =  174.781219      :     
		assign fx_float32    	  = 32'h4409B76A ;       // AcameraMatrix[2]  =  550.865845      :     
		assign fy_float32    	  = 32'h4409B76A ;       // AcameraMatrix[3]  =  550.865845      :     
		assign ir_float32[0] 	  = 32'h3AEDEF73 ;    	 // iRMatrix[0]  =  0.001815      :     
		assign ir_float32[1] 	  = 32'h36C3D269 ;    	 // iRMatrix[1]  =  0.000006      :     
		assign ir_float32[2] 	  = 32'hBF1B5B3E ;    	 // iRMatrix[2]  = -0.606861      :     
		assign ir_float32[3] 	  = 32'hB6C32EB1 ;    	 // iRMatrix[3]  = -0.000006      :     
		assign ir_float32[4] 	  = 32'h3AEDEF99 ;    	 // iRMatrix[4]  =  0.001815      :     
		assign ir_float32[5] 	  = 32'hBEA3E773 ;    	 // iRMatrix[5]  = -0.320125      :     
		assign ir_float32[6] 	  = 32'hB6DD8204 ;    	 // iRMatrix[6]  = -0.000007      :     
		assign ir_float32[7] 	  = 32'h36AFBBCA ;    	 // iRMatrix[7]  =  0.000005      :     
		assign ir_float32[8] 	  = 32'h3F802A19 ;    	 // iRMatrix[8]  =  1.001285      :   
	end 
	else if (LEFT_RIGHT  == "R")
	begin
		assign k1_float32         = 32'h3D30E8DB ;       // DistortCoefArray[0]  =  0.043191      :      
		assign k2_float32         = 32'hBE448173 ;       // DistortCoefArray[1]  =  -0.191900      :     
		assign p1_float32         = 32'h00000000 ;       // DistortCoefArray[2]  =  0.000000      :      
		assign p2_float32         = 32'h00000000 ;       // DistortCoefArray[3]  =  0.000000      :      
		assign k3_float32         = 32'h3E529DDB ;       // DistortCoefArray[4]  =  0.205680      :      
		assign k4_float32         = 32'h00000000 ;       // DistortCoefArray[5]  =  0.000000      :      
		assign k5_float32         = 32'h00000000 ;       // DistortCoefArray[6]  =  0.000000      :      
		assign k6_float32         = 32'h00000000 ;       // DistortCoefArray[7]  =  0.000000      :      		           
		assign u0_float32         = 32'h43ADAA26 ;       // AcameraMatrix[0]  =  347.329285      :   
		assign v0_float32         = 32'h4330E809 ;       // AcameraMatrix[1]  =  176.906387      :   
		assign fx_float32         = 32'h4409B76A ;       // AcameraMatrix[2]  =  550.865845      :   
		assign fy_float32         = 32'h4409B76A ;       // AcameraMatrix[3]  =  550.865845      :   		 
		assign ir_float32[0] 	  = 32'h3AEDE90B ;    	 // iRMatrix[0]  =  0.001815      :    
		assign ir_float32[1] 	  = 32'h370AD439 ;    	 // iRMatrix[1]  =  0.000008      :    
		assign ir_float32[2] 	  = 32'hBF208CB9 ;    	 // iRMatrix[2]  =  -0.627147      :   
		assign ir_float32[3] 	  = 32'hB7098B0B ;    	 // iRMatrix[3]  =  -0.000008      :   
		assign ir_float32[4] 	  = 32'h3AEDEF49 ;    	 // iRMatrix[4]  =  0.001815      :    
		assign ir_float32[5] 	  = 32'hBEA08285 ;    	 // iRMatrix[5]  =  -0.313496      :   
		assign ir_float32[6] 	  = 32'h37DE7DD6 ;    	 // iRMatrix[6]  =  0.000027      :    
		assign ir_float32[7] 	  = 32'hB6AE10D4 ;    	 // iRMatrix[7]  =  -0.000005      :   
		assign ir_float32[8] 	  = 32'h3F7DEB4F ;    	 // iRMatrix[8]  =  0.991872      :    
	end
endgenerate

/*
	construct the following condition to test the timing 

        double kr = 1 + ((k3(0)*r2 + k2(0))*r2 + k1(0))*r2 
        double u = fx(1)*(x*kr + p1(0)*_2xy + p2(0)*(r2 + 2*x)) + u0(0);
        double v = fy(1)*(y*kr + p1(0)*(r2 + 2*y) + p2(0)*_2xy) + v0(0);

        expected u,v output is : x, y 
*/

// wire[31:0] k1_float32    = zero_float16 ;  //32'h3CA9D9AE ;       // DistortCoefArray[0]  =  0.020734      :     
// wire[31:0] k2_float32    = zero_float16 ;  //32'h3CFFAAFD ;       // DistortCoefArray[1]  =  0.031209      :     
// wire[31:0] p1_float32    = zero_float16 ;  //32'h00000000 ;       // DistortCoefArray[2]  =  0.000000      :     
// wire[31:0] p2_float32    = zero_float16 ;  //32'h00000000 ;       // DistortCoefArray[3]  =  0.000000      :     
// wire[31:0] k3_float32    = zero_float16 ;  //32'hBE869FB5 ;       // DistortCoefArray[4]  = -0.262937      :     
// wire[31:0] k4_float32    = 32'h00000000 ;       // DistortCoefArray[5]  =  0.000000      :     
// wire[31:0] k5_float32    = 32'h00000000 ;       // DistortCoefArray[6]  =  0.000000      :     
// wire[31:0] k6_float32    = 32'h00000000 ;       // DistortCoefArray[7]  =  0.000000      :     
      
// wire[31:0] u0_float32    = zero_float16 ;  //32'h43A5EC8A ;       // AcameraMatrix[0]  =  331.847961      :     
// wire[31:0] v0_float32    = zero_float16 ;  //32'h432EC7FE ;       // AcameraMatrix[1]  =  174.781219      :     
// wire[31:0] fx_float32    = one_float16  ;  //32'h4409B76A ;       // AcameraMatrix[2]  =  550.865845      :     
// wire[31:0] fy_float32    = one_float16  ;  //32'h4409B76A ;       // AcameraMatrix[3]  =  550.865845      :     
 
// assign ir_float32[0] 	 = one_float16  ;    // 32'h3AEDEF73 ;    	// iRMatrix[0]  =  0.001815      :     
// assign ir_float32[1] 	 = zero_float16 ;    // 32'h36C3D269 ;    	// iRMatrix[1]  =  0.000006      :     
// assign ir_float32[2] 	 = zero_float16 ;    // 32'hBF1B5B3E ;    	// iRMatrix[2]  = -0.606861      :     
// assign ir_float32[3] 	 = zero_float16  ;  // 32'hB6C32EB1 ;    	// iRMatrix[3]  = -0.000006      :     
// assign ir_float32[4] 	 = one_float16 ;  // 32'h3AEDEF99 ;    	// iRMatrix[4]  =  0.001815      :     
// assign ir_float32[5] 	 = zero_float16 ;  // 32'hBEA3E773 ;    	// iRMatrix[5]  = -0.320125      :     
// assign ir_float32[6] 	 = zero_float16 ;  //32'hB6DD8204 ;    	// iRMatrix[6]  = -0.000007      :     
// assign ir_float32[7] 	 = zero_float16 ;  //32'h36AFBBCA ;    	// iRMatrix[7]  =  0.000005      :     
// assign ir_float32[8] 	 = one_float16  ;  //32'h3F802A19 ;    	// iRMatrix[8]  =  1.001285      :   




wire[31:0] k1_float16  = k1_float32 ;  
wire[31:0] k2_float16  = k2_float32 ;  
wire[31:0] p1_float16  = p1_float32 ;  
wire[31:0] p2_float16  = p2_float32 ;  
wire[31:0] k3_float16  = k3_float32 ;  
wire[31:0] k4_float16  = k4_float32 ;  
wire[31:0] k5_float16  = k5_float32 ;  
wire[31:0] k6_float16  = k6_float32 ;  
      
wire[31:0] u0_float16  = u0_float32 ;  
wire[31:0] v0_float16  = v0_float32 ;  
wire[31:0] fx_float16  = fx_float32 ;  
wire[31:0] fy_float16  = fy_float32 ;  
 
wire[31:0] ir_float16[0:8]  ;  

assign ir_float16[0] = ir_float32[0] ;
assign ir_float16[1] = ir_float32[1] ;
assign ir_float16[2] = ir_float32[2] ;
assign ir_float16[3] = ir_float32[3] ;
assign ir_float16[4] = ir_float32[4] ;
assign ir_float16[5] = ir_float32[5] ;
assign ir_float16[6] = ir_float32[6] ;
assign ir_float16[7] = ir_float32[7] ;
assign ir_float16[8] = ir_float32[8] ; 

// convert from float32 to float16  mantissa exponent 
/*
    float16 :  
     _______
    |_bit15_|  sign-bit 
             ________________________
            |_bit14____________bit10_|  Exponent width : 5 
                                 ____ __________________________
                                |_1.0|__________________________| Fraction bit width : 11 . there is a hidden bit in bit10 which is always eq. to 1'b1
*/
//  exponent_16 = exponent_32 - 8'h7F + 5'h0F

// wire signed [8:0] k1_exponent_value = $signed({1'b0,k1_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] k2_exponent_value = $signed({1'b0,k2_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] p1_exponent_value = $signed({1'b0,p1_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] p2_exponent_value = $signed({1'b0,p2_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] k3_exponent_value = $signed({1'b0,k3_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] k4_exponent_value = $signed({1'b0,k4_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] k5_exponent_value = $signed({1'b0,k5_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ;  
// wire signed [8:0] k6_exponent_value = $signed({1'b0,k6_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b0000, 5'b01111}) ; 

// wire [4:0] k1_exponent_float16 = (k1_exponent_value[8] == 1'b1) ? 5'd0 : (k1_exponent_value < 6'b100000) ? k1_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] k2_exponent_float16 = (k2_exponent_value[8] == 1'b1) ? 5'd0 : (k2_exponent_value < 6'b100000) ? k2_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] p1_exponent_float16 = (p1_exponent_value[8] == 1'b1) ? 5'd0 : (p1_exponent_value < 6'b100000) ? p1_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] p2_exponent_float16 = (p2_exponent_value[8] == 1'b1) ? 5'd0 : (p2_exponent_value < 6'b100000) ? p2_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] k3_exponent_float16 = (k3_exponent_value[8] == 1'b1) ? 5'd0 : (k3_exponent_value < 6'b100000) ? k3_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] k4_exponent_float16 = (k4_exponent_value[8] == 1'b1) ? 5'd0 : (k4_exponent_value < 6'b100000) ? k4_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] k5_exponent_float16 = (k5_exponent_value[8] == 1'b1) ? 5'd0 : (k5_exponent_value < 6'b100000) ? k5_exponent_value[4:0] : 5'b11111 ;
// wire [4:0] k6_exponent_float16 = (k6_exponent_value[8] == 1'b1) ? 5'd0 : (k6_exponent_value < 6'b100000) ? k6_exponent_value[4:0] : 5'b11111 ;


// assign k1_float16 = {k1_float32[31],k1_exponent_float16 , k1_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign k2_float16 = {k2_float32[31],k2_exponent_float16 , k2_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign p1_float16 = {p1_float32[31],p1_exponent_float16 , p1_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign p2_float16 = {p2_float32[31],p2_exponent_float16 , p2_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign k3_float16 = {k3_float32[31],k3_exponent_float16 , k3_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign k4_float16 = {k4_float32[31],k4_exponent_float16 , k4_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign k5_float16 = {k5_float32[31],k5_exponent_float16 , k5_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign k6_float16 = {k6_float32[31],k6_exponent_float16 , k6_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  

// wire signed [8:0] u0_exponent_value = $signed({1'b0,u0_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// wire signed [8:0] v0_exponent_value = $signed({1'b0,v0_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// wire signed [8:0] fx_exponent_value = $signed({1'b0,fx_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// wire signed [8:0] fy_exponent_value = $signed({1'b0,fy_float32[30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  

// wire signed [4:0] u0_exponent_float16 = (u0_exponent_value[8]==1'b1)? 5'd0 : (u0_exponent_value < 6'b100000) ? u0_exponent_value[4:0] : 5'b11111 ;
// wire signed [4:0] v0_exponent_float16 = (v0_exponent_value[8]==1'b1)? 5'd0 : (v0_exponent_value < 6'b100000) ? v0_exponent_value[4:0] : 5'b11111 ;
// wire signed [4:0] fx_exponent_float16 = (fx_exponent_value[8]==1'b1)? 5'd0 : (fx_exponent_value < 6'b100000) ? fx_exponent_value[4:0] : 5'b11111 ;
// wire signed [4:0] fy_exponent_float16 = (fy_exponent_value[8]==1'b1)? 5'd0 : (fy_exponent_value < 6'b100000) ? fy_exponent_value[4:0] : 5'b11111 ;

// assign u0_float16 = {u0_float32[31],u0_exponent_float16,u0_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign v0_float16 = {v0_float32[31],v0_exponent_float16,v0_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign fx_float16 = {fx_float32[31],fx_exponent_float16,fx_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  
// assign fy_float16 = {fy_float32[31],fy_exponent_float16,fy_float32[22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits 

// wire signed [8:0] ir_exponent_value[0:7] ;
// assign ir_exponent_value[0] = $signed({1'b0,ir_float32[0][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[1] = $signed({1'b0,ir_float32[1][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[2] = $signed({1'b0,ir_float32[2][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[3] = $signed({1'b0,ir_float32[3][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[4] = $signed({1'b0,ir_float32[4][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[5] = $signed({1'b0,ir_float32[5][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[6] = $signed({1'b0,ir_float32[6][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ;  
// assign ir_exponent_value[7] = $signed({1'b0,ir_float32[7][30:23]}) - $signed({1'b0,8'H7F})  + $signed({4'b000, 5'b01111}) ; 

// wire [4:0] ir_exponent_float16 [0:7] ;

// assign ir_exponent_float16[0] = (ir_exponent_value[0][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[0] < 6'b100000 ) ? ir_exponent_value[0][4:0] : 5'b11111 ;  // if less than the range , set to 0 
// assign ir_exponent_float16[1] = (ir_exponent_value[1][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[1] < 6'b100000 ) ? ir_exponent_value[1][4:0] : 5'b11111 ;
// assign ir_exponent_float16[2] = (ir_exponent_value[2][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[2] < 6'b100000 ) ? ir_exponent_value[2][4:0] : 5'b11111 ;
// assign ir_exponent_float16[3] = (ir_exponent_value[3][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[3] < 6'b100000 ) ? ir_exponent_value[3][4:0] : 5'b11111 ;
// assign ir_exponent_float16[4] = (ir_exponent_value[4][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[4] < 6'b100000 ) ? ir_exponent_value[4][4:0] : 5'b11111 ;
// assign ir_exponent_float16[5] = (ir_exponent_value[5][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[5] < 6'b100000 ) ? ir_exponent_value[5][4:0] : 5'b11111 ;
// assign ir_exponent_float16[6] = (ir_exponent_value[6][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[6] < 6'b100000 ) ? ir_exponent_value[6][4:0] : 5'b11111 ;
// assign ir_exponent_float16[7] = (ir_exponent_value[7][8] == 1'b1)  ? 5'd0 : (ir_exponent_value[7] < 6'b100000 ) ? ir_exponent_value[7][4:0] : 5'b11111 ;


// assign ir_float16[0] = {ir_float32[0][31],ir_exponent_float16[0],ir_float32[0][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[1] = {ir_float32[1][31],ir_exponent_float16[1],ir_float32[1][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[2] = {ir_float32[2][31],ir_exponent_float16[2],ir_float32[2][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[3] = {ir_float32[3][31],ir_exponent_float16[3],ir_float32[3][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[4] = {ir_float32[4][31],ir_exponent_float16[4],ir_float32[4][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[5] = {ir_float32[5][31],ir_exponent_float16[5],ir_float32[5][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[6] = {ir_float32[6][31],ir_exponent_float16[6],ir_float32[6][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits   
// assign ir_float16[7] = {ir_float32[7][31],ir_exponent_float16[7],ir_float32[7][22:22-9]} ;  // truncate mantissa bits , discards the last 22-10 bits  


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
reg signed [10:0] colCnt_Q0_sclkrate = 0 ;
reg signed [10:0] rowCnt_Q0_sclkrate = 0;

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
		if((sof_PreStart == 1'b1) && (colCnt_Q0_sclkrate != 0))
			colCnt_Q0_sclkrate <= 1 ;
		else if(colCnt_Q0_sclkrate == IMAGE_WIDTH -1)
			colCnt_Q0_sclkrate <= 0 ;
		else
			colCnt_Q0_sclkrate <= colCnt_Q0_sclkrate + 1'b1;

		if((rowCnt_Q0_sclkrate == IMAGE_HEIGHT-1 && colCnt_Q0_sclkrate == IMAGE_WIDTH -1) || sof_PreStart)
		begin
			rowCnt_Q0_sclkrate <= 0 ;
		end
		else if(colCnt_Q0_sclkrate == IMAGE_WIDTH -1) begin
			rowCnt_Q0_sclkrate <= rowCnt_Q0_sclkrate + 1'b1 ;
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
wire [10:0] x_dest_Q0  =  colCnt_Q0_sclkrate ;
wire [10:0] y_dest_Q0  =  rowCnt_Q0_sclkrate ;
wire  x_to_float_vld , y_to_float_vld;
wire [31:0] x_dest_float16 ; 
wire [31:0] y_dest_float16 ;

fix_to_float u_x_dest   // 6 clk cycle still less then one pixelen clock 
(
.aclk 					(clk) ,
.s_axis_a_tvalid 		(en & pixelEN) 	,
.s_axis_a_tdata 		({5'b0,x_dest_Q0}   )  ,
.m_axis_result_tvalid	(x_to_float_vld) ,
.m_axis_result_tdata 	(x_dest_float16) 
);

fix_to_float u_y_dest   // 6 clk cycle still less then one pixelen clock 
(
.aclk 					(clk) ,
.s_axis_a_tvalid 		(en & pixelEN) 	 ,
.s_axis_a_tdata 		({5'b0,y_dest_Q0}   )   ,
.m_axis_result_tvalid	(y_to_float_vld) ,
.m_axis_result_tdata 	(y_dest_float16) 
);

reg [31:0] x_dest_float16_sclkrate ;
reg [31:0] y_dest_float16_sclkrate ;

// make sure y_dest_float16_at_valid is stable when pixelEN arrives 
always@(posedge clk)      // aligned with sof_PreStart_dly[0] , 1 pixelEN clock delay 
if(en && pixelEN)
begin
	x_dest_float16_sclkrate <= x_dest_float16 ;   // aligned with sof_PreStart_dly[0]
	y_dest_float16_sclkrate <= y_dest_float16 ;
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

wire [31:0] ir0_xDest_float16 ;   
wire [31:0] ir1_yDest_float16 ;   
wire [31:0] ir2_wDest_float16_const ;   
wire [31:0] ir3_xDest_float16 ;   
wire [31:0] ir4_yDest_float16 ;   
wire [31:0] ir5_wDest_float16_const ;   
wire [31:0] ir6_xDest_float16 ;   
wire [31:0] ir7_yDest_float16 ;   
wire [31:0] ir8_wDest_float16_const ;   


/* *************************** row 0 ***********************************************************/
// aligned with sof_PreStart_dly[1] , 2 pixelEN clock delay 
mult_one_pixel_clock ir0_time_xDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_dest_float16_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_float16[0])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir0_xDest_float16)      			// aligned with sof_PreStart_dly[1] 
);

mult_one_pixel_clock ir1_time_yDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_dest_float16_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_float16[1])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir1_yDest_float16)      			// aligned with sof_PreStart_dly[1] 
);

/* *************************** row 1 ***********************************************************/
mult_one_pixel_clock ir3_time_xDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_dest_float16_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_float16[3])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir3_xDest_float16)      			// aligned with sof_PreStart_dly[1] 
);

mult_one_pixel_clock ir4_time_yDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_dest_float16_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_float16[4])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir4_yDest_float16)      			// aligned with sof_PreStart_dly[1] 
);

/* *************************** row 2 ***********************************************************/
mult_one_pixel_clock ir6_time_xDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_dest_float16_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_float16[6])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir6_xDest_float16)      			// aligned with sof_PreStart_dly[1] 
);

mult_one_pixel_clock ir7_time_yDest
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_dest_float16_sclkrate)		,   // aligned with sof_PreStart_dly[0]
	  .B 			(ir_float16[7])		,   			//  aligned with sof_PreStart_dly[0] 
	  .P 			(ir7_yDest_float16)      			// aligned with sof_PreStart_dly[1] 
);

wire [31:0] x_middle_p ;
wire [31:0] y_middle_p ;
wire [31:0] w_middle_p ;
wire [31:0] x_middle_temp ;
wire [31:0] y_middle_temp ;
wire [31:0] w_middle_temp ;

wire [31:0] x_middle ;
wire [31:0] y_middle ;

assign ir2_wDest_float16_const = ir_float16[2] ;     // constant 
assign ir5_wDest_float16_const = ir_float16[5] ;     // constant 
assign ir8_wDest_float16_const = ir_float16[8] ;     // constant 




/************************************ compute x *************************************************************/
//  ir[0] * x_dest + ir[1] * y_dest
add_one_pixel_clock u_x_middle_p_tmp
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(ir0_xDest_float16)     ,    // aligned with sof_PreStart_dly[1]
	  .B 			(ir1_yDest_float16)     ,    // aligned with sof_PreStart_dly[1]
	  .SUM 			(x_middle_temp)      			// aligned with sof_PreStart_dly[2] 
);
// ir[0] * x_dest + ir[1] * y_dest + ir[2] * w_dest
add_one_pixel_clock u_x_middle_p
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(x_middle_temp)     ,    // aligned with sof_PreStart_dly[2]
	  .B 			(ir2_wDest_float16_const)     ,    // constant
	  .SUM 			(x_middle_p)      			// aligned with sof_PreStart_dly[3] 
);
/************************************ compute y *************************************************************/
//  ir[3] * x_dest + ir[4] * y_dest
add_one_pixel_clock u_y_middle_p_tmp
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(ir3_xDest_float16)     ,   // aligned with sof_PreStart_dly[1]
	  .B 			(ir4_yDest_float16)     	,  // aligned with sof_PreStart_dly[1]
	  .SUM 			(y_middle_temp)      			// aligned with sof_PreStart_dly[2] 
);
// ir[3] * x_dest + ir[4] * y_dest + ir[5] * w_dest
add_one_pixel_clock u_y_middle_p
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(y_middle_temp)     ,    // aligned with sof_PreStart_dly[2]
	  .B 			(ir5_wDest_float16_const)     ,    // constant
	  .SUM 			(y_middle_p)      			// aligned with sof_PreStart_dly[3] 
);

/************************************ compute w *************************************************************/
//  ir[6] * x_dest + ir[7] * y_dest
add_one_pixel_clock u_w_middle_p_tmp
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(ir6_xDest_float16)     ,   // aligned with sof_PreStart_dly[1]
	  .B 			(ir7_yDest_float16)     	,  // aligned with sof_PreStart_dly[1]
	  .SUM 			(w_middle_temp)      			// aligned with sof_PreStart_dly[2] 
);
// ir[6] * x_dest + ir[7] * y_dest + ir[8]
add_one_pixel_clock u_w_middle_p
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(w_middle_temp)     ,    // aligned with sof_PreStart_dly[2]
	  .B 			(ir8_wDest_float16_const)     ,    // constant
	  .SUM 			(w_middle_p)      			// aligned with sof_PreStart_dly[3] 
);


// 3. compute x_middle , y_middle 
/*
    x_middle  = x_middle_p / w_middle_p ;     
    y_middle  = y_middle_p / w_middle_p ;
*/
div_float_4_pixel_clock U_x_div_w (
	.clk        (clk) 	,    // Clock
	.en 		(en)	,
	.pixelEN 	(pixelEN)	,
	.x_middle_p (x_middle_p)	,   // aligned with sof_PreStart_dly[3] 
    .w_middle_p (w_middle_p) ,      // aligned with sof_PreStart_dly[3] 
    .x_middle   (x_middle)          // aligned with sof_PreStart_dly[7]
);

div_float_4_pixel_clock U_y_div_w (
	.clk        (clk) 	,    // Clock
	.en 		(en)	,
	.pixelEN 	(pixelEN)	,
	.x_middle_p (y_middle_p)	,   // aligned with sof_PreStart_dly[3] 
    .w_middle_p (w_middle_p) ,      // aligned with sof_PreStart_dly[3] 
    .x_middle   (y_middle)          // aligned with sof_PreStart_dly[7]
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
            double u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x)) + u0;
            double v = fy*(y*kr + p1*(r2 + 2*y) + p2*_2xy) + v0;

            note : here x , y is x_middle and y_middle 
*/
wire [31:0] r2 ;
wire [31:0] _xy ;
wire [31:0] _2xy ;

wire [31:0] k3r2 ;
wire [31:0] k3r2_k2 ;
wire [31:0] k3r2_k2_r2 ;
wire [31:0] k3r2_k2_r2_k1 ;
wire [31:0] k3r2_k2_r2_k1_r2 ;
wire [31:0] _1_k3r2_k2_r2_k1_r2 ;


wire [31:0] kr ;
wire [31:0] p1_2xy ;
wire [31:0] x_kr ;
wire [31:0] _xx ;
wire [31:0] _2xx ;
wire [31:0] _yy ;
wire [31:0] _2yy ;
wire [31:0] r2_2xx ;
wire [31:0] p2_r2_2xx ;
wire [31:0] add_terms_0 ; 
wire [31:0] add_terms_0_0 ;
wire [31:0] fx_add_terms_0_0 ;
wire [31:0] fx_add_terms_0_0_u0 ;

wire[31:0] y_kr ;
wire[31:0] r2_2yy ;
wire[31:0] p1_r2_2yy ;
wire[31:0] p2_2xy ; 
wire[31:0] add_terms_1 ;
wire[31:0] add_terms_1_1 ;
wire[31:0] fy_add_terms_1_1 ;
wire[31:0] fy_add_terms_1_1_v0 ;

wire[31:0] u , v ;

reg [31:0] r2_dly_sclkrate [0:31]; 
reg [31:0] x_middle_dly_sclkrate [0:31] ;
reg [31:0] _2xx_dly_sclkrate [0:31] ;
reg [31:0] p1_2xy_dly_sclkrate [0:31] ;
reg [31:0] p2_r2_2xx_dly_sclkrate [0:31] ;
reg [31:0] y_middle_dly_sclkrate [0:31] ;
reg [31:0] _2yy_dly_sclkrate [0:31] ;
reg [31:0] p1_r2_2yy_dly_sclkrate [0:31] ;
reg [31:0] p2_2xy_dly_sclkrate [0:31] ;
reg [10:0] x_dest_11Q0_dly_sclkrate [0:31] ;
reg [10:0] y_dest_11Q0_dly_sclkrate [0:31] ;  //x_dest_Q0

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
	x_dest_11Q0_dly_sclkrate[0] <= x_dest_Q0 ;

	for(i=1; i<32 ; i=i+1)
	begin
		y_dest_11Q0_dly_sclkrate[i] <= y_dest_11Q0_dly_sclkrate[i-1] ;
	end
	y_dest_11Q0_dly_sclkrate[0] <= y_dest_Q0  ;

end

// compute x^2, y^2 xy
mult_one_pixel_clock u_xx
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

mult_one_pixel_clock u_yy
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

mult_one_pixel_clock u_xy
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


/*
    float16 :  
     _______
    |_bit15_|  sign-bit 
             ________________________
            |_bit14____________bit10_|  Exponent width : 5 
                                 ____ __________________________
                                |_1.0|__________________________| Fraction bit width : 10+1 . there is a hidden bit in bit10 which is always eq. to 1'b1
*/

assign _2xx = {_xx[31],_xx[30:23]+1'b1,_xx[22:0]} ; // matissa unchanged , exponent + 1  // aligned with sof_PreStart_dly[8]
assign _2yy = {_yy[31],_yy[30:23]+1'b1,_yy[22:0]} ; // matissa unchanged , exponent + 1  // aligned with sof_PreStart_dly[8]
assign _2xy = {_xy[31],_xy[30:23]+1'b1,_xy[22:0]} ; // matissa unchanged , exponent + 1  // aligned with sof_PreStart_dly[8]

// r2 = xx + yy 
add_one_pixel_clock u_r2
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
mult_one_pixel_clock u_k3r2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(r2)     ,            // aligned with sof_PreStart_dly[9]
	  .B 			(k3_float16)     		,  // constant
	  .P 			(k3r2)      			// aligned with sof_PreStart_dly[10] 
);

// k3*r2 + k2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
add_one_pixel_clock u_k3r2_k2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(k3r2)     ,            // aligned with sof_PreStart_dly[10]
	  .B 			(k2_float16)       ,         // constant
	  .SUM 			(k3r2_k2)      			   // aligned with sof_PreStart_dly[11] 
);

// (k3*r2 + k2)*r2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
mult_one_pixel_clock u_k3r2_k2_r2
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
add_one_pixel_clock u_k3r2_k2_r2_k1
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(k3r2_k2_r2)     ,            // aligned with sof_PreStart_dly[12]
	  .B 			(k1_float16)       ,         // constant
	  .SUM 			(k3r2_k2_r2_k1)      			   // aligned with sof_PreStart_dly[13] 
);

// ((k3*r2 + k2)*r2 + k1)*r2   -------> kr = (1 + ((k3*r2 + k2)*r2 + k1)*r2)/(1 + ((k6*r2 + k5)*r2 + k4)*r2);
mult_one_pixel_clock u_k3r2_k2_r2_k1_r2
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
add_one_pixel_clock u_1_k3r2_k2_r2_k1_r2
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(k3r2_k2_r2_k1_r2)     ,            // aligned with sof_PreStart_dly[14]
	  .B 			(one_float16)       ,         // constant
	  .SUM 			(_1_k3r2_k2_r2_k1_r2)      			   // aligned with sof_PreStart_dly[15] 
);

assign kr = _1_k3r2_k2_r2_k1_r2 ;    // aligned with sof_PreStart_dly[15]

// x*kr           -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
mult_one_pixel_clock u_x_kr
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
mult_one_pixel_clock u_p1_2xy
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(_2xy)     ,            				// aligned with sof_PreStart_dly[8]
	  .B 			(p1_float16)       ,         // constant
	  .P 			(p1_2xy)      								// aligned with sof_PreStart_dly[9] 
);

// r2 + 2*x2      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
add_one_pixel_clock u_r2_2xx
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
mult_one_pixel_clock u_p2_r2_2xx
(
	  .clk 			(clk)										,    	 
	  .clk_en		(1'b1)										, 		 
	  .rst_n		(rst_n)										,  		 
	  .en    		(en)										,
	  .pixelEN 		(pixelEN)	    							,
	  .A 			(r2_2xx )     ,            // aligned with sof_PreStart_dly[10]
	  .B 			(p2_float16)       ,         // constant
	  .P 			(p2_r2_2xx)      								// aligned with sof_PreStart_dly[11] 
);

// x*kr + p1*_2xy       -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
add_one_pixel_clock u_add_terms_0 
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
add_one_pixel_clock u_add_terms_0_0 
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
mult_one_pixel_clock u_fx_add_terms_0_0
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(add_terms_0_0)		,   // aligned with sof_PreStart_dly[18] 
	  .B 			(fx_float16)		,   // constant
	  .P 			(fx_add_terms_0_0)      // aligned with sof_PreStart_dly[19] 
);

// u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0      -------------------->   u = fx*(x*kr + p1*_2xy + p2*(r2 + 2*x2)) + u0;
add_one_pixel_clock u_fx_add_terms_0_0_u0 
(
	 .clk 		(clk)	,  
	 .clk_en	(1'b1)	,  
	 .rst_n		(rst_n)	,  
	 .en    	(en)	,
	 .pixelEN 	(pixelEN)	,
	 .A 		(u0_float16)	,     // constant
	 .B 		(fx_add_terms_0_0)       ,        // aligned with sof_PreStart_dly[19] 
	 .SUM 		(fx_add_terms_0_0_u0 )            // aligned with sof_PreStart_dly[20] -------------> u 
);

// y*kr          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
mult_one_pixel_clock u_y_kr
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
add_one_pixel_clock u_r2_2yy
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
mult_one_pixel_clock u_p1_r2_2yy
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(r2_2yy)			,       // aligned with sof_PreStart_dly[10] 
	  .B 			(p1_float16)       ,        // constant
	  .P 			(p1_r2_2yy)      			// aligned with sof_PreStart_dly[11] 
);

// p2*_2xy          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
mult_one_pixel_clock u_p2_2xy
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(_2xy)			    ,       // aligned with sof_PreStart_dly[8]
	  .B 			(p2_float16)        ,       // constant
	  .P 			(p2_2xy)      			    // aligned with sof_PreStart_dly[9] 
);

// y*kr + p1*(r2 + 2*y2)          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
add_one_pixel_clock u_add_terms_1
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
add_one_pixel_clock u_add_terms_1_1
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
mult_one_pixel_clock u_fy_add_terms_1_1
(
	  .clk 			(clk)				,    	 
	  .clk_en		(1'b1)				, 		 
	  .rst_n		(rst_n)				,  		 
	  .en    		(en)				,
	  .pixelEN 		(pixelEN)	    	,
	  .A 			(add_terms_1_1)			,       // aligned with sof_PreStart_dly[18]
	  .B 			(fy_float16)       ,    		// constant
	  .P 			(fy_add_terms_1_1)      			// aligned with sof_PreStart_dly[19] 
);

// v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0          ---------------------------->   v = fy*(y*kr + p1*(r2 + 2*y2) + p2*_2xy) + v0;
add_one_pixel_clock u_fy_add_terms_1_1_v0
(
	  .clk 			(clk)				        ,    	 
	  .clk_en		(1'b1)				        , 		 
	  .rst_n		(rst_n)				        ,  		 
	  .en    		(en)				        ,
	  .pixelEN 		(pixelEN)	    	        ,
	  .A 			(fy_add_terms_1_1 )          	,   		// aligned with sof_PreStart_dly[19] 		
	  .B 			(v0_float16             )  ,        			    // constant
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


// 1. convert u,v from float16 to fix-Q10 
wire [31:0] u_float16 , v_float16 ;   // aligned with sof_PreStart_dly[20]  
reg [31:0] u_float32_sclkrate , v_float32_sclkrate ;   // aligned with sof_PreStart_dly[21] 
wire [11+10-1:0] u_actual_11Q10, v_actual_11Q10 ;
wire [14+10-1:0] u_14Q10, v_14Q10 ;

assign  u_float16 = fx_add_terms_0_0_u0 ;     // aligned with sof_PreStart_dly[20] 
assign  v_float16 = fy_add_terms_1_1_v0 ;     // aligned with sof_PreStart_dly[20] 

// float16_to_float32 U_u_float32(         
//     .aclk                 (clk),
//     .aclken               (1'b1)
//     .s_axis_a_tvalid      (),
//     .s_axis_a_tdata       (u_float16),   // aligned with sof_PreStart_dly[20]
//     .m_axis_result_tvalid (),
//     .m_axis_result_tdata  (u_float32)    // aligned with sof_PreStart_dly[21]
//   );

// float16_to_float32 U_v_float32(
//     .aclk                 (clk),
//     .aclken               (1'b1)
//     .s_axis_a_tvalid      (),
//     .s_axis_a_tdata       (v_float16),  // aligned with sof_PreStart_dly[20]
//     .m_axis_result_tvalid (),
//     .m_axis_result_tdata  (v_float32)   // aligned with sof_PreStart_dly[21]
//   );

always@(posedge clk)
if(en && pixelEN)
begin
	u_float32_sclkrate <= u_float16 ;    // aligned with sof_PreStart_dly[21]
	v_float32_sclkrate <= v_float16 ;    // aligned with sof_PreStart_dly[21]
end 
else begin
	u_float32_sclkrate <= u_float32_sclkrate ;   
	v_float32_sclkrate <= v_float32_sclkrate ;
end


float_to_11Q10_one_pixel_clock U_u_11Q10(
	
	.clk 		(clk),    // Clock
	.clk_en 	(1'b1), // Clock Enable
	.rst_n		(rst_n),  // Asynchronous reset active low
	.en   		(en) ,
	.pixelEN 	(pixelEN),
	.A_float	(u_float32_sclkrate),   // aligned with sof_PreStart_dly[21]
	.O_14Q10	(u_14Q10)				// aligned with sof_PreStart_dly[22]
);

float_to_11Q10_one_pixel_clock U_v_11Q10(
	
	.clk 		(clk),    // Clock
	.clk_en 	(1'b1), // Clock Enable
	.rst_n		(rst_n),  // Asynchronous reset active low
	.en   		(en) ,
	.pixelEN 	(pixelEN),
	.A_float	(v_float32_sclkrate),   // aligned with sof_PreStart_dly[21]
	.O_14Q10	(v_14Q10)				// aligned with sof_PreStart_dly[22]
);

assign v_actual_11Q10 = v_14Q10[11+10-1:0] ;
assign u_actual_11Q10 = u_14Q10[11+10-1:0] ;

// 2. calculate the distance away from the expected coordinate (x_dest,y_dest) 
//    in streaming condition , (x_dest,y_dest) is cooresponding to the central of the matrix 
/*
    u_to_central = u_actual_11Q10 - x_dest 
    v_to_central = v_actual_11Q10 - y_dest 
*/
wire [11+10-1:0] expected_X_11Q10 = { x_dest_11Q0_dly_sclkrate[22 - (-1) - 1] , {10{1'b0}} }  ;
wire [11+10-1:0] expected_Y_11Q10 = { y_dest_11Q0_dly_sclkrate[22 - (-1) - 1] , {10{1'b0}} }  ;

wire signed [11+10-1:0] diff_of_actual_to_expected_X_11Q10 , diff_of_actual_to_expected_Y_11Q10 ;   // 1 sign bit , 10 integer bits , 10 fractional bits 
assign diff_of_actual_to_expected_X_11Q10 = $signed(expected_X_11Q10) - $signed(u_actual_11Q10)  ;   // aligned with sof_PreStart_dly[22] x_dest_Q0 is aligned with sof_PreStart_dly[-1]
assign diff_of_actual_to_expected_Y_11Q10 = $signed(expected_Y_11Q10) - $signed(v_actual_11Q10)  ;   // aligned with sof_PreStart_dly[22] y_dest_Q0 is aligned with sof_PreStart_dly[-1]
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
wire x_exceed_bounds_warning = (uCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1:10] > 12) ? 1'b1 : 1'b0 ;  // too big to fit in the matrix 
wire y_below_bounds_warning  = (vCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1]==1'b1) ? 1'b1 : 1'b0 ;  // negative number 
wire y_exceed_bounds_warning = (vCoord_Inmatrix_Orgin_atbottomright_11Q10[11+10-1:10] > 12) ? 1'b1 : 1'b0 ;  // too big to fit in the matrix 

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
					$fwrite(fd_left_U,"%h\n", u_float16 );
					$fwrite(fd_left_V,"%h\n", v_float16 );
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
					$fwrite(fd_right_U,"%h\n", u_float16 );
					$fwrite(fd_right_V,"%h\n", v_float16 );
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

assign rectified_stream = {sof_PreStart_dly[27],final_texture_pixel} ;
// assign rectified_stream = {sof_PreStart_dly[27],I_x_y_dly_sclkrate[27-23-1][7:0]}  ;


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





module mult_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [31:0] A , 
	input wire [31:0] B ,

	output wire [31:0] P 
	
);
	reg [31:0] prod_reg_sclkrate ;
	assign P = prod_reg_sclkrate ;

	wire [31:0] prod ; 

	mul_float32 u (              // 6 clock cycle delay = pixelEN clock rate 
	    .aclk                   (clk)     ,
	    .s_axis_a_tvalid        (en & pixelEN)      ,
	    .s_axis_a_tdata         (A)     ,            
	    .s_axis_b_tvalid        (en & pixelEN)     ,
	    .s_axis_b_tdata         (B)       ,         
	    .m_axis_result_tvalid   ()     ,              
	    .m_axis_result_tdata    (prod)          
	  );
	
	always@(posedge clk)
	if(en && pixelEN)
	begin
		prod_reg_sclkrate <= prod ;   // aligned with sof_PreStart_dly[11]
	end
	else begin
		prod_reg_sclkrate <= prod_reg_sclkrate ;
	end

endmodule


module add_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [31:0] A , 
	input wire [31:0] B ,

	output wire [31:0] SUM 
	
);
	reg [31:0] sum_ab_reg_sclkrate ;
	assign SUM = sum_ab_reg_sclkrate ;
	
	wire [31:0] sum_ab ; 

	add_float32 u (              // 6 clock cycle delay = pixelEN clock rate 
	    .aclk                   (clk)     ,
	    .s_axis_a_tvalid        (en & pixelEN)      ,
	    .s_axis_a_tdata         (A)     ,            
	    .s_axis_b_tvalid        (en & pixelEN)     ,
	    .s_axis_b_tdata         (B)       ,         
	    .m_axis_result_tvalid   ()     ,              
	    .m_axis_result_tdata    (sum_ab)          
	  );
	
	always@(posedge clk)
	if(en && pixelEN)
	begin
		sum_ab_reg_sclkrate <= sum_ab ;   // aligned with sof_PreStart_dly[11]
	end
	else begin
		sum_ab_reg_sclkrate <= sum_ab_reg_sclkrate ;
	end

endmodule






module float_to_11Q10_one_pixel_clock (
	input wire  clk,    // Clock
	input wire  clk_en, // Clock Enable
	input wire  rst_n,  // Asynchronous reset active low
	input wire  en    ,
	input wire  pixelEN ,
	input wire [31:0] A_float , 

	output wire [14+10-1:0] O_14Q10 
	
);
	reg [14+10-1:0] D_14Q10_sclkrate ;
	
	wire [14+10-1:0] D_14Q10 ; 

	assign O_14Q10 = D_14Q10_sclkrate ;


	float32_to_11Q10 u(
    .aclk                 (clk),
    .s_axis_a_tvalid      (en & pixelEN),
    .s_axis_a_tdata       (A_float),    
    .m_axis_result_tvalid (),
    .m_axis_result_tdata  (D_14Q10)     
  );
	
	always@(posedge clk)
	if(en && pixelEN)
	begin
		D_14Q10_sclkrate <= D_14Q10 ;   // aligned with sof_PreStart_dly[11]
	end
	else begin
		D_14Q10_sclkrate <= D_14Q10_sclkrate ;
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




module div_float_4_pixel_clock (
	input wire            clk,    // Clock
	input wire            en ,
	input wire            pixelEN ,

	input wire[31:0]      x_middle_p ,
    input wire[31:0]      w_middle_p , 

    output wire[31:0]     x_middle  
);


	wire[31:0] x_middle_hclkrate ;

	wire x_div_w_valid ;
	reg  x_div_w_valid_dly ;
	wire x_div_w_write_fifo_en ;
	wire x_div_w_read_fifo_en ;

	wire x_div_w_fifo_full ;
	wire x_div_w_fifo_empty ;

	wire[31:0] x_div_w_fifo_out ;


	div_float32 u_x_div_w (              // 28 clock cycle delay  
	    .aclk 					(clk)     			,
	    .aclken 				(en)     			,
	    .s_axis_a_tvalid		(en & pixelEN)     	,
	    .s_axis_a_tdata			(x_middle_p)     	, // aligned with sof_PreStart_dly[3]
	    .s_axis_b_tvalid 		(en & pixelEN)     	,
	    .s_axis_b_tdata 		(w_middle_p)     	, // aligned with sof_PreStart_dly[3]
	    .m_axis_result_tvalid 	(x_div_w_valid)     ,             // don't care , as long as it matches pixelEN
	    .m_axis_result_tdata 	(x_middle_hclkrate)    
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
	// small_fifo U_x_div_w_fifo
	// (
	//     .clk 	(clk) , //: IN STD_LOGIC;
	//     .srst 	(~rst_n) , //: IN STD_LOGIC;
	//     .din 	(x_middle_hclkrate) , //: IN STD_LOGIC_VECTOR(31 DOWNTO 0);
	//     .wr_en 	(x_div_w_write_fifo_en) , //: IN STD_LOGIC;
	//     .rd_en 	(x_div_w_read_fifo_en ) , //: IN STD_LOGIC;
	//     .dout 	(x_div_w_fifo_out) , //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
	//     .full 	(x_div_w_fifo_full) , //: OUT STD_LOGIC;
	//     .empty 	(x_div_w_fifo_empty)  //: OUT STD_LOGIC
	//  );

	// always@(posedge clk)
	// begin
	// 	x_div_w_valid_dly <= x_div_w_valid ;
	// end

	// assign x_middle = x_div_w_fifo_out ;  // aligned with sof_PreStart_dly[7]   

	reg [31:0] x_div_w_reg_dly_sclkrate [0:3] ; 
	integer n ; 

	always@(posedge clk)
	if(en && pixelEN)
	begin
		for(n=1; n < 4; n=n+1)
			x_div_w_reg_dly_sclkrate[n] <= x_div_w_reg_dly_sclkrate[n-1] ; 
		x_div_w_reg_dly_sclkrate[0] <= x_middle_hclkrate ;
	end 

	assign x_middle = x_div_w_reg_dly_sclkrate[0] ;

endmodule
