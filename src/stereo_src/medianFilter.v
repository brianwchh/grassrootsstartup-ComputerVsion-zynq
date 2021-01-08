/*
	author : WuChengHe
	
	funtion discription : 
		derive Lr(P,Di) from Ll(P,Di)

*/
`timescale 1 ns / 1 ps
module medianFilter
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
	input 	wire						rst_n                                       // Asynchronous reset active low
	
);

// Triple Input Sorter Optimization Algorithm of Median Filter Based on FPGA

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

reg [INPUTDATAWID-1:0] shift2DArray_sclkrate [0:1][0:2] ;
reg[9:0] BlkRamAddressA , BlkRamAddressB ;
wire [10:0] BlkRamAddressB_pre ;
wire [INPUTDATAWID-1:0] linebuffer0_out, linebuffer1_out ;
wire [7:0] taps [0:8] ;
wire SOF_at_central ;

reg [7:0] taps_d1 [0:8] ;
reg [7:0] taps_d2 [0:8] ;
integer i ;

genvar r, c,k ; 

generate 

for(r=0;r<3;r=r+1)
	for(c=1;c<2;c=c+1)
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			shift2DArray_sclkrate[c][r] <=  shift2DArray_sclkrate[c-1][r] ;
		end
	end

always@(posedge clk)
if(en && pixelEN)
begin
	shift2DArray_sclkrate[0][0] <= disparity       ;
	shift2DArray_sclkrate[0][1] <= linebuffer0_out ;
	shift2DArray_sclkrate[0][2] <= linebuffer1_out ;
end

endgenerate

assign taps[0]  = disparity[7:0]                       ; 
assign taps[1]  = shift2DArray_sclkrate[0][0][7:0]     ; 
assign taps[2]  = shift2DArray_sclkrate[1][0][7:0]     ; 
assign taps[3]  = linebuffer0_out[7:0]                 ; 
assign taps[4]  = shift2DArray_sclkrate[0][1][7:0]     ; 
assign taps[5]  = shift2DArray_sclkrate[1][1][7:0]     ; 
assign taps[6]  = linebuffer1_out[7:0]                 ;  
assign taps[7]  = shift2DArray_sclkrate[0][2][7:0]     ;  
assign taps[8]  = shift2DArray_sclkrate[1][2][7:0]     ;  

assign SOF_at_central = shift2DArray_sclkrate[0][1][8] ; 

wire [7:0] max_u[0:2] ;
wire [7:0] med_u[0:2] ;
wire [7:0] min_u[0:2] ;

reg [7:0] max_u_reg_sclkrate[0:2] ;
reg [7:0] med_u_reg_sclkrate[0:2] ;
reg [7:0] min_u_reg_sclkrate[0:2] ;

wire [7:0] stage2_max_o ;
wire [7:0] stage2_med_o ;
wire [7:0] stage2_min_o ;

reg [7:0] stage2_max_o_reg_sclkrate ;
reg [7:0] stage2_med_o_reg_sclkrate ;
reg [7:0] stage2_min_o_reg_sclkrate ;

reg sof_dly1,sof_dly2,sof_dly3 ;

tripleSorter u0 (
   .A0  (taps[0] ) ,
   .A1  (taps[1] ) ,
   .A2  (taps[2] ) ,
   .max (max_u[0]) ,
   .med (med_u[0]) ,
   .min (min_u[0])
);

tripleSorter u1 (
   .A0  (taps[3] ) ,
   .A1  (taps[4] ) ,
   .A2  (taps[5] ) ,
   .max (max_u[1]) ,
   .med (med_u[1]) ,
   .min (min_u[1])
);

tripleSorter u2 (
   .A0  (taps[6] ) ,
   .A1  (taps[7] ) ,
   .A2  (taps[8] ) ,
   .max (max_u[2]) ,
   .med (med_u[2]) ,
   .min (min_u[2])
);

always@(posedge clk)
if(en && pixelEN)      // aligned with sof_dly1
begin
	for(i=0;i<3;i=i+1)
	begin
		max_u_reg_sclkrate[i] <= max_u[i] ; 
		med_u_reg_sclkrate[i] <= med_u[i] ; 
		min_u_reg_sclkrate[i] <= min_u[i] ; 
	end
end

tripleSorter u00 (
   .A0  (max_u_reg_sclkrate[0] ) ,
   .A1  (max_u_reg_sclkrate[1] ) ,
   .A2  (max_u_reg_sclkrate[2] ) ,
   .max () ,
   .med () ,
   .min (stage2_min_o)
);

tripleSorter u10 (
   .A0  (med_u_reg_sclkrate[0] ) ,
   .A1  (med_u_reg_sclkrate[1] ) ,
   .A2  (med_u_reg_sclkrate[2] ) ,
   .max ( ) ,
   .med (stage2_med_o ) ,
   .min ( )
);

tripleSorter u20 (
   .A0  (min_u_reg_sclkrate[0] ) ,
   .A1  (min_u_reg_sclkrate[1] ) ,
   .A2  (min_u_reg_sclkrate[2] ) ,
   .max (stage2_max_o          ) ,
   .med () ,
   .min ()
);

always@(posedge clk)
if(en && pixelEN)      // aligned with sof_dly2
begin
	stage2_max_o_reg_sclkrate <= stage2_max_o ; 
	stage2_med_o_reg_sclkrate <= stage2_med_o ; 
	stage2_min_o_reg_sclkrate <= stage2_min_o ; 
end

wire [7:0] median_out ;
reg [7:0] median_out_reg_sclkrate ;

tripleSorter u30 (
   .A0  (stage2_max_o_reg_sclkrate ) ,
   .A1  (stage2_med_o_reg_sclkrate ) ,
   .A2  (stage2_min_o_reg_sclkrate ) ,
   .max () ,
   .med (median_out) ,
   .min ()
);

always@(posedge clk)
if(en && pixelEN)     // aligned with sof_dly3
begin
	median_out_reg_sclkrate <= median_out ;
	{sof_dly3,sof_dly2,sof_dly1} <= {sof_dly2,sof_dly1,SOF_at_central} ;
end

assign disparity_filtered = {sof_dly3,median_out_reg_sclkrate} ;

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
    .doutb (linebuffer0_out)        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );

 median_filter_linebuffer ulineBuffer1
 (
    .clka  (clk)      , //: IN STD_LOGIC;
    .ena   (1'b1)      , //: IN STD_LOGIC;
    .wea   (en & pixelEN)      , //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    .addra (BlkRamAddressA)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .dina  (linebuffer0_out)      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    .clkb  (clk)      , //: IN STD_LOGIC;
    .enb   (en & pixelEN)      , //: IN STD_LOGIC;
    .addrb (BlkRamAddressB)      , //: IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    .doutb (linebuffer1_out)        //: OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );





endmodule