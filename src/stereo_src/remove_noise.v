/*
	author : WuChengHe
	
	funtion discription : 
		derive Lr(P,Di) from Ll(P,Di)

*/
`timescale 1 ns / 1 ps
module remove_noise
#(
	parameter  INPUTDATAWID  = 9,    
	parameter  IMAGE_WIDTH   = 640 ,
	parameter  OUTPUTDATAWID = 9
  )
(
	input wire                      clk                               ,         // 150 Clock   
	input wire                      en                                ,     
	input wire                      pixelEN                           ,
	input  wire[INPUTDATAWID-1:0]   disparity                         ,         // W*H       
	output wire[OUTPUTDATAWID-1:0]  disparity_filtered                ,            
	input wire						rst_n                                       // Asynchronous reset active low
	
);


integer i ;




 // shift array 
 //*******  shift input and linebuffer  **************
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


reg[9:0] BlkRamAddressA , BlkRamAddressB ;
wire [10:0] BlkRamAddressB_pre ;
wire [INPUTDATAWID-1:0] linebufferout [0:7] ; 
wire [7:0] stage1_out [0:2][0:2] ;
wire [7:0] final_stage_out ;

reg [8:0] shiftRegArray_sclkrate [0:8][0:8] ;   


/* ----------------------- stage1 : find median for each block----------------------------- */ 
// --------------------  lane 1------------------------------------

median3by3kernel u00 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0][0][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0][1][7:0]),     
	.A02         (shiftRegArray_sclkrate[0][2][7:0]),     
	.A10         (shiftRegArray_sclkrate[1][0][7:0]),     
	.A11         (shiftRegArray_sclkrate[1][1][7:0]),     
	.A12         (shiftRegArray_sclkrate[1][2][7:0]),     
	.A20         (shiftRegArray_sclkrate[2][0][7:0]),     
	.A21         (shiftRegArray_sclkrate[2][1][7:0]),     
	.A22         (shiftRegArray_sclkrate[2][2][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[0][0])  
);

median3by3kernel u01 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0][0+3][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0][1+3][7:0]),     
	.A02         (shiftRegArray_sclkrate[0][2+3][7:0]),     
	.A10         (shiftRegArray_sclkrate[1][0+3][7:0]),     
	.A11         (shiftRegArray_sclkrate[1][1+3][7:0]),     
	.A12         (shiftRegArray_sclkrate[1][2+3][7:0]),     
	.A20         (shiftRegArray_sclkrate[2][0+3][7:0]),     
	.A21         (shiftRegArray_sclkrate[2][1+3][7:0]),     
	.A22         (shiftRegArray_sclkrate[2][2+3][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[0][1])  
);

median3by3kernel u02 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0][0+6][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0][1+6][7:0]),     
	.A02         (shiftRegArray_sclkrate[0][2+6][7:0]),     
	.A10         (shiftRegArray_sclkrate[1][0+6][7:0]),     
	.A11         (shiftRegArray_sclkrate[1][1+6][7:0]),     
	.A12         (shiftRegArray_sclkrate[1][2+6][7:0]),     
	.A20         (shiftRegArray_sclkrate[2][0+6][7:0]),     
	.A21         (shiftRegArray_sclkrate[2][1+6][7:0]),     
	.A22         (shiftRegArray_sclkrate[2][2+6][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[0][2])  
);

// --------------------  lane 2------------------------------------

median3by3kernel u10 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0+3][0][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0+3][1][7:0]),     
	.A02         (shiftRegArray_sclkrate[0+3][2][7:0]),     
	.A10         (shiftRegArray_sclkrate[1+3][0][7:0]),     
	.A11         (shiftRegArray_sclkrate[1+3][1][7:0]),     
	.A12         (shiftRegArray_sclkrate[1+3][2][7:0]),     
	.A20         (shiftRegArray_sclkrate[2+3][0][7:0]),     
	.A21         (shiftRegArray_sclkrate[2+3][1][7:0]),     
	.A22         (shiftRegArray_sclkrate[2+3][2][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[1][0])  
);

median3by3kernel u11 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0+3][0+3][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0+3][1+3][7:0]),     
	.A02         (shiftRegArray_sclkrate[0+3][2+3][7:0]),     
	.A10         (shiftRegArray_sclkrate[1+3][0+3][7:0]),     
	.A11         (shiftRegArray_sclkrate[1+3][1+3][7:0]),     
	.A12         (shiftRegArray_sclkrate[1+3][2+3][7:0]),     
	.A20         (shiftRegArray_sclkrate[2+3][0+3][7:0]),     
	.A21         (shiftRegArray_sclkrate[2+3][1+3][7:0]),     
	.A22         (shiftRegArray_sclkrate[2+3][2+3][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[1][1])  
);

median3by3kernel u12 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0+3][0+6][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0+3][1+6][7:0]),     
	.A02         (shiftRegArray_sclkrate[0+3][2+6][7:0]),     
	.A10         (shiftRegArray_sclkrate[1+3][0+6][7:0]),     
	.A11         (shiftRegArray_sclkrate[1+3][1+6][7:0]),     
	.A12         (shiftRegArray_sclkrate[1+3][2+6][7:0]),     
	.A20         (shiftRegArray_sclkrate[2+3][0+6][7:0]),     
	.A21         (shiftRegArray_sclkrate[2+3][1+6][7:0]),     
	.A22         (shiftRegArray_sclkrate[2+3][2+6][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[1][2])  
);


// --------------------  lane 3------------------------------------

median3by3kernel u20 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0+6][0][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0+6][1][7:0]),     
	.A02         (shiftRegArray_sclkrate[0+6][2][7:0]),     
	.A10         (shiftRegArray_sclkrate[1+6][0][7:0]),     
	.A11         (shiftRegArray_sclkrate[1+6][1][7:0]),     
	.A12         (shiftRegArray_sclkrate[1+6][2][7:0]),     
	.A20         (shiftRegArray_sclkrate[2+6][0][7:0]),     
	.A21         (shiftRegArray_sclkrate[2+6][1][7:0]),     
	.A22         (shiftRegArray_sclkrate[2+6][2][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[2][0])  
);

median3by3kernel u21 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0+6][0+3][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0+6][1+3][7:0]),     
	.A02         (shiftRegArray_sclkrate[0+6][2+3][7:0]),     
	.A10         (shiftRegArray_sclkrate[1+6][0+3][7:0]),     
	.A11         (shiftRegArray_sclkrate[1+6][1+3][7:0]),     
	.A12         (shiftRegArray_sclkrate[1+6][2+3][7:0]),     
	.A20         (shiftRegArray_sclkrate[2+6][0+3][7:0]),     
	.A21         (shiftRegArray_sclkrate[2+6][1+3][7:0]),     
	.A22         (shiftRegArray_sclkrate[2+6][2+3][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[2][1])  
);

median3by3kernel u22 (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (shiftRegArray_sclkrate[0+6][0+6][7:0]),       // input data 
	.A01         (shiftRegArray_sclkrate[0+6][1+6][7:0]),     
	.A02         (shiftRegArray_sclkrate[0+6][2+6][7:0]),     
	.A10         (shiftRegArray_sclkrate[1+6][0+6][7:0]),     
	.A11         (shiftRegArray_sclkrate[1+6][1+6][7:0]),     
	.A12         (shiftRegArray_sclkrate[1+6][2+6][7:0]),     
	.A20         (shiftRegArray_sclkrate[2+6][0+6][7:0]),     
	.A21         (shiftRegArray_sclkrate[2+6][1+6][7:0]),     
	.A22         (shiftRegArray_sclkrate[2+6][2+6][7:0]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(stage1_out[2][2])                      // aligned with sof_dly3
);

/* ----------------------- final stage : find median from the above 9 block----------------------------- */ 
median3by3kernel u_final_median (
	.clk         (clk),      // Clock
	.en          (en), 	     // Clock Enable
	.rst_n       (rst_n),    // Asynchronous reset active low
	.A00         (stage1_out[0][0]),       // input data 
	.A01         (stage1_out[0][1]),     
	.A02         (stage1_out[0][2]),     
	.A10         (stage1_out[1][0]),     
	.A11         (stage1_out[1][1]),     
	.A12         (stage1_out[1][2]),     
	.A20         (stage1_out[2][0]),     
	.A21         (stage1_out[2][1]),     
	.A22         (stage1_out[2][2]),     
	.pixelEN     (pixelEN),      // pixel clock rate 
	.final_output(final_stage_out)                   // aligned with sof_dly6 sof_dly[4]
);

wire  sof = shiftRegArray_sclkrate[4][4][8] ; 
reg [7:0] central_data_shift_sclkrate [0:5] ;
reg sof_dly [0:5] ;
reg[8:0] noise_removed_output ;

always@(posedge clk)
if(en && pixelEN)
begin
	for(i=1; i<5 ; i=i+1)
	begin
		sof_dly[i] <= sof_dly[i-1] ;
		central_data_shift_sclkrate[i] <= central_data_shift_sclkrate[i-1] ;
	end
	sof_dly[0] <= sof;
	central_data_shift_sclkrate[0] <= shiftRegArray_sclkrate[4][4][7:0] ; 
end

always@(posedge clk)
if(en && pixelEN)
begin
	if(((central_data_shift_sclkrate[4]) < 3 ) || (central_data_shift_sclkrate[4] > 60)) // aligned with final_stage_out 
	begin
		noise_removed_output[7:0] <= final_stage_out ;
		noise_removed_output[8]  <= sof_dly[4] ;
	end
	else begin
		noise_removed_output <= {sof_dly[4] , central_data_shift_sclkrate[4]} ;
	end

	// noise_removed_output[7:0] <= final_stage_out ;
	// noise_removed_output[8]  <= sof_dly[4] ;
end

assign disparity_filtered = noise_removed_output ;

// *********** shift array structure **********************

genvar r, c ; 
generate 
	for(r=0; r<9; r=r+1)
		for(c=1; c<9; c=c+1)
		begin
			always@(posedge clk)
			if(en && pixelEN)
			begin
				shiftRegArray_sclkrate[r][c] <= shiftRegArray_sclkrate[r][c-1] ;
			end
		end

	for(r=1; r<9; r=r+1)
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
		shiftRegArray_sclkrate[0][0]     <=  disparity ;
	end
endgenerate


// *****************  block ram fifo  **************************

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

 median_filter_linebuffer ulineBuffer0
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (disparity)      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[0])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );

 median_filter_linebuffer ulineBuffer1
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[0])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[1])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );


 median_filter_linebuffer ulineBuffer2
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[1])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[2])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );


 median_filter_linebuffer ulineBuffer3
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[2])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[3])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );

  median_filter_linebuffer ulineBuffer4
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[3])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[4])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );

   median_filter_linebuffer ulineBuffer5
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[4])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[5])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );


   median_filter_linebuffer ulineBuffer6
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[5])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[6])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );

    median_filter_linebuffer ulineBuffer7
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebufferout[6])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebufferout[7])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );


endmodule



































// module remove_noise
// #(
// 	parameter  INPUTDATAWID  = 9,    
// 	parameter  IMAGE_WIDTH   = 640 ,
// 	parameter  OUTPUTDATAWID = 9
//   )
// (
// 	input wire                      clk                               ,         // 150 Clock   
// 	input wire                      en                                ,     
// 	input wire                      pixelEN                           ,
// 	input  wire[INPUTDATAWID-1:0]   disparity                         ,         // W*H       
// 	output wire[OUTPUTDATAWID-1:0]  disparity_filtered                ,            
// 	input 							rst_n                                       // Asynchronous reset active low
	
// );


// integer i ;




//  // shift array 
//  //*******  shift input and linebuffer  **************
// /*      what about boundery condition    ?       
//                                             __________                      _________
// 					                       |          |                    |         |
// 	    -------------------disp(x+1,y+1)-->|  Z-1     |--disp(x,y+1)------>|  Z-1    |-------------o disp(x-1,y+1) 
// 					|                      |__________|                    |_________|
// 					|
// 				  _\|/_
// 				 |     |
// 				 | N-2 |
// 				 |     |
// 				 |_____|                    __________                      _________
// 				 	|                      |          |                    |         |
// 				 	|--------disp(x+1,y)-->|  Z-1     |--disp(x,y)-------->|  Z-1    |-------------o disp(x-1,y)
// 				 	|                      |__________|                    |_________|
// 					|
// 				  _\|/_
// 				 |     |
// 				 | N-2 |
// 				 |     |
// 				 |_____|                    __________                      _________
// 				 	|                      |          |                    |         |
// 				 	 ------disp(x+1,y-1)-->|  Z-1     |--disp(x,y-1)------>|  Z-1    |-------------o disp(x-1,y-1)
// 				 	                       |__________|                    |_________|         

// */


// reg[9:0] BlkRamAddressA , BlkRamAddressB ;
// wire [10:0] BlkRamAddressB_pre ;
// wire [INPUTDATAWID-1:0] linebufferout [0:7] ; 

// wire [8+6-1:0] sum_wire ;
// wire[7:0] mean_of_neighbours ;

// reg [8:0] filtered_out_reg_sclkrate ;

// reg [8:0] shiftRegArray_sclkrate [0:7][0:3] ;  // 32

// genvar r, c ; 
// generate 
// 	for(r=0; r<4; r=r+1)
// 		for(c=1; c<8; c=c+1)
// 		begin
// 			always@(posedge clk)
// 			if(en && pixelEN)
// 			begin
// 				shiftRegArray_sclkrate[r][c] <= shiftRegArray_sclkrate[r][c-1] ;
// 			end
// 		end

// 	for(r=1; r<8; r=r+1)
// 	begin
// 		always@(posedge clk)
// 		if(en && pixelEN)
// 		begin
// 			shiftRegArray_sclkrate[r][0] <= linebufferout[r-1] ;
// 		end
// 	end
// 	always@(posedge clk)
// 	if(en && pixelEN)
// 	begin
// 		shiftRegArray_sclkrate[0][0]     <=  disparity ;
// 	end


// endgenerate

// assign sum_wire = shiftRegArray_sclkrate[0][0][7:0]  +  shiftRegArray_sclkrate[0][1][7:0] + shiftRegArray_sclkrate[0][2][7:0] + shiftRegArray_sclkrate[0][3][7:0] +  
// 				  shiftRegArray_sclkrate[1][0][7:0]  +  shiftRegArray_sclkrate[1][1][7:0] + shiftRegArray_sclkrate[1][2][7:0] + shiftRegArray_sclkrate[1][3][7:0] +  
// 				  shiftRegArray_sclkrate[2][0][7:0]  +  shiftRegArray_sclkrate[2][1][7:0] + shiftRegArray_sclkrate[2][2][7:0] + shiftRegArray_sclkrate[2][3][7:0] +  
// 				  shiftRegArray_sclkrate[3][0][7:0]  +  shiftRegArray_sclkrate[3][1][7:0] + shiftRegArray_sclkrate[3][2][7:0] + shiftRegArray_sclkrate[3][3][7:0] +  
// 				  shiftRegArray_sclkrate[4][0][7:0]  +  shiftRegArray_sclkrate[4][1][7:0] + shiftRegArray_sclkrate[4][2][7:0] + shiftRegArray_sclkrate[4][3][7:0] +  
// 				  shiftRegArray_sclkrate[5][0][7:0]  +  shiftRegArray_sclkrate[5][1][7:0] + shiftRegArray_sclkrate[5][2][7:0] + shiftRegArray_sclkrate[5][3][7:0] +  
// 				  shiftRegArray_sclkrate[6][0][7:0]  +  shiftRegArray_sclkrate[6][1][7:0] + shiftRegArray_sclkrate[6][2][7:0] + shiftRegArray_sclkrate[6][3][7:0] + 
// 				  shiftRegArray_sclkrate[7][0][7:0]  +  shiftRegArray_sclkrate[7][1][7:0] + shiftRegArray_sclkrate[7][2][7:0] + shiftRegArray_sclkrate[7][3][7:0]  ; 

// assign mean_of_neighbours = sum_wire[12:5] ;   // sum / 32

// always@(posedge clk)
// if(en && pixelEN)
// begin
// 	filtered_out_reg_sclkrate <= {shiftRegArray_sclkrate[3][1][8],mean_of_neighbours};
// end

// assign disparity_filtered = filtered_out_reg_sclkrate ;


// // *****************  block ram fifo  **************************

// assign BlkRamAddressB_pre = BlkRamAddressA + 3 ;

// always@(posedge clk)
// if(~rst_n)
// begin 
// 	BlkRamAddressA <= 0 ;
// end 
// else if(en && pixelEN)
// begin
// 	if(BlkRamAddressA == IMAGE_WIDTH - 1 )
// 		BlkRamAddressA <= 0 ;
// 	else
// 		BlkRamAddressA <= BlkRamAddressA + 1;

// 	if(BlkRamAddressB_pre > IMAGE_WIDTH - 1) 
// 		BlkRamAddressB <= BlkRamAddressB_pre - IMAGE_WIDTH ;
// 	else
// 		BlkRamAddressB <= BlkRamAddressB_pre[9:0] ;
// end

//  median_filter_linebuffer ulineBuffer0
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (disparity)      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[0])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );

//  median_filter_linebuffer ulineBuffer1
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (linebufferout[0])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[1])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );


//  median_filter_linebuffer ulineBuffer2
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (linebufferout[1])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[2])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );


//  median_filter_linebuffer ulineBuffer3
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (linebufferout[2])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[3])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );

//   median_filter_linebuffer ulineBuffer4
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (linebufferout[3])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[4])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );

//    median_filter_linebuffer ulineBuffer5
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (linebufferout[4])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[5])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );


//    median_filter_linebuffer ulineBuffer6
//  (
//     .clka  (clk)      , //: IN STD_LOGIC;
//     .ena   (1'b1)      , //: IN STD_LOGIC;
//     .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .dina  (linebufferout[5])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//     .clkb  (clk)      , //: IN STD_LOGIC;
//     .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//     .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//     .doutb (linebufferout[6])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//   );

//  //    median_filter_linebuffer ulineBuffer7
//  // (
//  //    .clka  (clk)      , //: IN STD_LOGIC;
//  //    .ena   (1'b1)      , //: IN STD_LOGIC;
//  //    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//  //    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//  //    .dina  (linebufferout[6])      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
//  //    .clkb  (clk)      , //: IN STD_LOGIC;
//  //    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
//  //    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
//  //    .doutb (linebufferout[7])        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
//  //  );


// endmodule