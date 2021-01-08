/*
	author : WuChengHe
	
	funtion discription : 
		derive Lr(P,Di) from Ll(P,Di)

*/
`timescale 1 ns / 1 ps
module fillinHoles
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
	input 							rst_n                                       // Asynchronous reset active low
	
);

integer i ;
reg [8:0] data_tapArray_reg_sclkrate [0:7] ; 
reg [8:0] data_filled_sclkrate ;
reg [10:0] colCnt_sclkrate = 0 ;
wire sof = disparity[8] ;

always@(posedge clk)
if(en && pixelEN)
begin
	data_tapArray_reg_sclkrate[0] <= disparity ;
	for(i=1; i < 4 ; i=i+1)
		data_tapArray_reg_sclkrate[i] <= data_tapArray_reg_sclkrate [i-1] ;
end

// wire nonHoleElements = ((data_tapArray_reg_sclkrate[0][7:0] != 0) && 
// 						(data_tapArray_reg_sclkrate[1][7:0] != 0) && 
// 						(data_tapArray_reg_sclkrate[2][7:0] != 0) && 
// 						(data_tapArray_reg_sclkrate[3][7:0] != 0) ) ? 1'b1 : 1'b0 ;

wire [3+8-1:0] sumTap =   data_tapArray_reg_sclkrate[0][7:0] + data_tapArray_reg_sclkrate[1][7:0] + data_tapArray_reg_sclkrate[2][7:0]
						+ data_tapArray_reg_sclkrate[3][7:0] + data_tapArray_reg_sclkrate[4][7:0] + data_tapArray_reg_sclkrate[5][7:0]
						+ data_tapArray_reg_sclkrate[6][7:0] + data_tapArray_reg_sclkrate[7][7:0] ;

always@(posedge clk )
if(en && pixelEN)
begin
	// if(nonHoleElements && (disparity[7:0] == 0) && (colCnt_sclkrate > 10) && (colCnt_sclkrate < IMAGE_WIDTH-10))
	// if(((disparity[7:0] == 0)  ) && (colCnt_sclkrate > 10) && (colCnt_sclkrate < IMAGE_WIDTH-10))
		data_filled_sclkrate <= {disparity[8],sumTap[10:3]} ;
	// else 
	// 	data_filled_sclkrate <= disparity ;
end

assign disparity_filtered = data_filled_sclkrate ;


always@(posedge clk)
if(en && pixelEN) begin
	if(sof)
	begin
		colCnt_sclkrate <= 1 ;
	end
	else begin 
		if(colCnt_sclkrate == IMAGE_WIDTH -1)
			colCnt_sclkrate <= 0 ;
		else
			colCnt_sclkrate <= colCnt_sclkrate + 1'b1;
	end
end

















`ifdef  thisone 

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
wire [8:0] fill_in_data ;


reg is_similiar_color_region_sclkrate ;

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
	shift2DArray_sclkrate[0][0] <= fill_in_data       ;
	shift2DArray_sclkrate[0][1] <= linebuffer0_out ;
	shift2DArray_sclkrate[0][2] <= linebuffer1_out ;
end

endgenerate

wire sof = disparity[8] ;

assign fill_in_data = ((disparity[7:0] == 0) && (is_similiar_color_region_sclkrate==1'b1)) ? {sof,taps[4]} : disparity ;  // if similiar region fill in previous color
// assign fill_in_data = disparity ;

assign taps[0]  = fill_in_data ;
assign taps[1]  = shift2DArray_sclkrate[0][0][7:0]     ; 
assign taps[2]  = shift2DArray_sclkrate[1][0][7:0]     ; 
assign taps[3]  = linebuffer0_out[7:0]                 ; 
assign taps[4]  = shift2DArray_sclkrate[0][1][7:0]     ; 
assign taps[5]  = shift2DArray_sclkrate[1][1][7:0]     ; 
assign taps[6]  = linebuffer1_out[7:0]                 ;  
assign taps[7]  = shift2DArray_sclkrate[0][2][7:0]     ;  
assign taps[8]  = shift2DArray_sclkrate[1][2][7:0]     ;  

assign disparity_filtered = shift2DArray_sclkrate[0][1] ; 


wire signed [8:0] sub12 = $signed({1'b0,taps[1]}) - $signed({1'b0,taps[2]}) ;
wire [8:0]       abs_sub12 = (sub12[8]==1'b1) ? ~sub12 + 1'b1 : sub12 ;

wire signed [8:0] sub23 = $signed({1'b0,taps[2]}) - $signed({1'b0,taps[3]}) ;
wire [8:0]       abs_sub23 = (sub23[8]==1'b1) ? ~sub23 + 1'b1 : sub23 ;

wire signed [8:0] sub34 = $signed({1'b0,taps[3]}) - $signed({1'b0,taps[4]}) ;
wire [8:0]       abs_sub34 = (sub34[8]==1'b1) ? ~sub34 + 1'b1 : sub34 ;

wire signed [8:0] sub45 = $signed({1'b0,taps[5]}) - $signed({1'b0,taps[4]}) ;
wire [8:0]       abs_sub45 = (sub45[8]==1'b1) ? ~sub45 + 1'b1 : sub45 ;


reg [10:0] colCnt_sclkrate = 0 ;
always@(posedge clk)
if(en && pixelEN) begin
	if(sof)
	begin
		colCnt_sclkrate <= 1 ;
	end
	else begin 
		if(colCnt_sclkrate == IMAGE_WIDTH -1)
			colCnt_sclkrate <= 0 ;
		else
			colCnt_sclkrate <= colCnt_sclkrate + 1'b1;
	end
end

always@(posedge clk)
if(en && pixelEN)
begin
	is_similiar_color_region_sclkrate <= ((abs_sub12 < 4) && (abs_sub23 < 4) && (abs_sub34 < 4) && (abs_sub45 < 4) 
										  && (colCnt_sclkrate > 15) && (colCnt_sclkrate < ( IMAGE_WIDTH-15)) );  // similiar color region 
end




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
    .dina  (fill_in_data)      , //: IN STD_LOGIC_VECTOR(8 DOWNTO 0);
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


`endif


endmodule