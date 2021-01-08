/*
	author : WuChengHe
	input data : 32bit , image format 8-bit grayscale 
*/
`timescale 1 ns / 1 ps
module matching_cost
#(
	parameter  MAXDISPARITY = 64 ,
	parameter  MATCHINGCOSTBITWID = 6 ,
	parameter  INPUTDATAWID = 63,     // 62bit + 1 (SOF)
	parameter  OUTPUTDATAWID = 385    // 6 * 64 + 1(SOF) 

  )
(
	input wire                      clk                               ,                   // 150 Clock
	input wire                      en                                ,
	input wire                      sof_in                            , 
	input wire                   	eol_in                            ,
	output wire                  	sof_out                           ,
	output wire                  	eol_out                           ,
	input wire[INPUTDATAWID-1:0]    leftCTstream                      ,
	input wire[INPUTDATAWID-1:0]    rightCTstream                     ,
	output wire[OUTPUTDATAWID-1:0]  MatchingCost                      ,   
	input  wire                     rst_n                                                 // Asynchronous reset active low
	
);

reg[INPUTDATAWID-1:0] rightShiftReg_sclkrate [0:MAXDISPARITY-1] ;
reg[INPUTDATAWID-1:0] leftShiftReg_sclkrate [0:MAXDISPARITY-1] ;
wire [INPUTDATAWID-2:0] ComparedBase ;
integer i ;
integer DispIndx, AddPiplineIndx ;

wire SOF_atCompareBase ;

// integer r,c,i,j;


/*
	                      ____ ______ ______________________________
	leftCTstream ------->|__x_|__x-1_|______________________________|  leftShiftReg_sclkrate
													
                                                         
	                      ____________________________ _____ _______
   rightCTstream ------->|____________________________|_____|_x-D+1_|  rightShiftReg_sclkrate
*/


/*  
	the stereo processing block need not worry about the synchronization of left and right image stream timing , 
	because input streams are syncronized before feeding to the block 
 */

 // ----------- shift data in  ----------
always@(posedge clk )
if(!rst_n)
begin
	rightShiftReg_sclkrate[0] <= 0;
	for(i=1;i<64;i=i+1)
	begin
		rightShiftReg_sclkrate[i] <= 0;
	end 
end
else if(en) begin  
	rightShiftReg_sclkrate[0] <= rightCTstream;   // SOF emmbeded in MSB
	for(i=1;i<MAXDISPARITY;i=i+1)
	begin
		rightShiftReg_sclkrate[i] <= rightShiftReg_sclkrate[i-1];
	end 
end

always@(posedge clk )
if(!rst_n)
begin
	leftShiftReg_sclkrate[0] <= 0;
	for(i=1;i<64;i=i+1)
	begin
		leftShiftReg_sclkrate[i] <= 0;
	end 
end
else if(en) begin  
	leftShiftReg_sclkrate[0] <= leftCTstream;   // SOF emmbeded in MSB
	for(i=1;i<MAXDISPARITY;i=i+1)
	begin
		leftShiftReg_sclkrate[i] <= leftShiftReg_sclkrate[i-1];
	end 
end

assign SOF_atCompareBase = leftShiftReg_sclkrate[0][62] ;
assign ComparedBase = leftShiftReg_sclkrate[0][61:0] ;

// parallel comparasion 
reg [INPUTDATAWID-2:0] LeftvsRightXorValue_sclkrate [0:MAXDISPARITY-1] ;  
reg sof_dely_sclkrate [0:7] ; 
always@(posedge clk)
if(en)
begin
	for (i = 0; i < MAXDISPARITY; i=i+1) begin
		LeftvsRightXorValue_sclkrate[i] <= ComparedBase ^ rightShiftReg_sclkrate[i][61:0] ;   // sof delay by 1 
	end
end

// ****** parallel add *********
reg[1:0] PiplineAddStg0_sclkrate [0:MAXDISPARITY-1] [0:30] ; // 62/2 = 31
reg[2:0] PiplineAddStg1_sclkrate [0:MAXDISPARITY-1] [0:15] ; //  (31+1)/2 = 16 
reg[3:0] PiplineAddStg2_sclkrate [0:MAXDISPARITY-1] [0:7]  ; //  16/2 = 8 
reg[4:0] PiplineAddStg3_sclkrate [0:MAXDISPARITY-1] [0:3]  ; //  4 
reg[5:0] PiplineAddStg4_sclkrate [0:MAXDISPARITY-1] [0:1]  ; //  2 
reg[5:0] PiplineAddOut_sclkrate [0:MAXDISPARITY-1]        ; //  1    maximum add = 62bit * 1 = 62

always@(posedge clk)
if(en)
begin : parallel_add
	sof_dely_sclkrate[0] <= SOF_atCompareBase ;
	//stage0
	for(DispIndx=0;DispIndx<MAXDISPARITY;DispIndx=DispIndx+1)
	begin 
		for(AddPiplineIndx=0;AddPiplineIndx<31;AddPiplineIndx=AddPiplineIndx+1)
		begin
			PiplineAddStg0_sclkrate[DispIndx][AddPiplineIndx] <= LeftvsRightXorValue_sclkrate[DispIndx][AddPiplineIndx*2] + LeftvsRightXorValue_sclkrate[DispIndx][AddPiplineIndx*2 + 1];
		end
	end
	sof_dely_sclkrate[1] <= sof_dely_sclkrate[0] ;
	//stage1
	for(DispIndx=0;DispIndx<MAXDISPARITY;DispIndx=DispIndx+1)
	begin 
		for(AddPiplineIndx=0;AddPiplineIndx<15;AddPiplineIndx=AddPiplineIndx+1)
		begin
			PiplineAddStg1_sclkrate[DispIndx][AddPiplineIndx] <= PiplineAddStg0_sclkrate[DispIndx][AddPiplineIndx*2] + PiplineAddStg0_sclkrate[DispIndx][AddPiplineIndx*2 + 1];
		end
		PiplineAddStg1_sclkrate[DispIndx][15] <=  PiplineAddStg0_sclkrate[DispIndx][30];
	end
	sof_dely_sclkrate[2] <= sof_dely_sclkrate[1] ;
	//stage2
	for(DispIndx=0;DispIndx<MAXDISPARITY;DispIndx=DispIndx+1)
	begin 
		for(AddPiplineIndx=0;AddPiplineIndx<8;AddPiplineIndx=AddPiplineIndx+1)
		begin
			PiplineAddStg2_sclkrate[DispIndx][AddPiplineIndx] <= PiplineAddStg1_sclkrate[DispIndx][AddPiplineIndx*2] + PiplineAddStg1_sclkrate[DispIndx][AddPiplineIndx*2 + 1];
		end
	end
	sof_dely_sclkrate[3] <= sof_dely_sclkrate[2] ;
	//stage3
	for(DispIndx=0;DispIndx<MAXDISPARITY;DispIndx=DispIndx+1)
	begin 
		for(AddPiplineIndx=0;AddPiplineIndx<4;AddPiplineIndx=AddPiplineIndx+1)
		begin
			PiplineAddStg3_sclkrate[DispIndx][AddPiplineIndx] <= PiplineAddStg2_sclkrate[DispIndx][AddPiplineIndx*2] + PiplineAddStg2_sclkrate[DispIndx][AddPiplineIndx*2 + 1];
		end
	end
	sof_dely_sclkrate[4] <= sof_dely_sclkrate[3] ;
	//stage4
	for(DispIndx=0;DispIndx<MAXDISPARITY;DispIndx=DispIndx+1)
	begin 
		for(AddPiplineIndx=0;AddPiplineIndx<2;AddPiplineIndx=AddPiplineIndx+1)
		begin
			PiplineAddStg4_sclkrate[DispIndx][AddPiplineIndx] <= PiplineAddStg3_sclkrate[DispIndx][AddPiplineIndx*2] + PiplineAddStg3_sclkrate[DispIndx][AddPiplineIndx*2 + 1];
		end
	end
	sof_dely_sclkrate[5] <= sof_dely_sclkrate[4] ;
	//stage5
	for(DispIndx=0;DispIndx<MAXDISPARITY;DispIndx=DispIndx+1)
	begin 
		for(AddPiplineIndx=0;AddPiplineIndx<1;AddPiplineIndx=AddPiplineIndx+1)
		begin
			PiplineAddOut_sclkrate[DispIndx] <= PiplineAddStg4_sclkrate[DispIndx][AddPiplineIndx*2] + PiplineAddStg4_sclkrate[DispIndx][AddPiplineIndx*2 + 1];
		end
	end
	sof_dely_sclkrate[6] <= sof_dely_sclkrate[5] ;
end


// expand matching cost register array to 1d wires 
genvar k;
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign MatchingCost[(k+1)*MATCHINGCOSTBITWID-1:k*MATCHINGCOSTBITWID] = PiplineAddOut_sclkrate[k] ;
end
endgenerate

assign MatchingCost[OUTPUTDATAWID-1]  =  sof_dely_sclkrate[6] ;
assign sof_out = sof_dely_sclkrate[6] ;

(* MARK_DEBUG="true" *)wire matching_cost_sof_out ;
assign matching_cost_sof_out = sof_out ;
 
endmodule