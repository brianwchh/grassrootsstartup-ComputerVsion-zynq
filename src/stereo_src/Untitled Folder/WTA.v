/*
	author : WuChengHe
	
	funtion discription : 
		

*/
`timescale 1 ns / 1 ps
module WTA
#(
	parameter  MAXDISPARITY = 64 ,
	parameter  LPDI_WIDTH = 8 ,
	parameter  INPUTDATAWID = 513,    // 8 * 64 + 1(SOF)
	parameter  OUTPUTDATAWID = 9
  )
(
	input wire                      clk                               ,         // 150 Clock
	input wire                      en                                ,
	input wire                      pixelEN                           , 
	input  wire[INPUTDATAWID-1:0]   LPDi                              ,         // W*H*D volumn     
	output wire[OUTPUTDATAWID-1:0]  disparity                         ,         // W*H               
	input 	wire						rst_n                                       // Asynchronous reset active low
	
);

wire [LPDI_WIDTH-1:0] LPDi_2dArray_wire [0:MAXDISPARITY-1] ;
wire SOF_atPxy_wire ;
reg SOF_atPxy_reg_dly_sclkrate [0:7] ;
integer i ;

assign SOF_atPxy_wire = LPDi[INPUTDATAWID-1] ;

genvar k ;
generate 
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin  
		assign LPDi_2dArray_wire[k] = LPDi[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH];
	end
endgenerate

// pipline min 
reg [LPDI_WIDTH-1:0] min_stg0_sclkrate [0:31] ;
reg [LPDI_WIDTH-1:0] min_stg1_sclkrate [0:15] ;
reg [LPDI_WIDTH-1:0] min_stg2_sclkrate [0:7] ;
reg [LPDI_WIDTH-1:0] min_stg3_sclkrate [0:3] ;
reg [LPDI_WIDTH-1:0] min_stg4_sclkrate [0:1] ;
reg [LPDI_WIDTH-1:0] min_stg5_sclkrate ;

reg [LPDI_WIDTH-1:0] min_Indx_stg0_sclkrate [0:31] ;
reg [LPDI_WIDTH-1:0] min_Indx_stg1_sclkrate [0:15] ;
reg [LPDI_WIDTH-1:0] min_Indx_stg2 [0:7] ;
reg [LPDI_WIDTH-1:0] min_Indx_stg3_sclkrate [0:3] ;
reg [LPDI_WIDTH-1:0] min_Indx_stg4_sclkrate [0:1] ;
reg [LPDI_WIDTH-1:0] min_Indx_stg5_sclkrate ;

always@(posedge clk)
if(en & pixelEN)
begin
	// stage0 
	for(i=0;i<32;i=i+1)
	begin
		if(LPDi_2dArray_wire[2*i] > LPDi_2dArray_wire[2*i+1])
		begin
			min_stg0_sclkrate[i]      <= LPDi_2dArray_wire[2*i+1] ; 
			min_Indx_stg0_sclkrate[i] <= 2*i+1 ;
		end
		else begin
			min_stg0_sclkrate[i]      <= LPDi_2dArray_wire[2*i] ;
			min_Indx_stg0_sclkrate[i] <= 2*i ;
		end
	end
	SOF_atPxy_reg_dly_sclkrate[0] <= SOF_atPxy_wire ;
	// stage1 
	for(i=0;i<16;i=i+1)
	begin
		if(min_stg0_sclkrate[2*i] > min_stg0_sclkrate[2*i+1])
		begin
			min_Indx_stg1_sclkrate[i] <= min_Indx_stg0_sclkrate[2*i+1] ;
			min_stg1_sclkrate[i]      <= min_stg0_sclkrate[2*i+1] ; 
		end
		else begin
			min_stg1_sclkrate[i]      <= min_stg0_sclkrate[2*i] ;
			min_Indx_stg1_sclkrate[i] <= min_Indx_stg0_sclkrate[2*i] ;
		end
	end
	SOF_atPxy_reg_dly_sclkrate[1] <= SOF_atPxy_reg_dly_sclkrate[0] ;
	// stage2 
	for(i=0;i<8;i=i+1)
	begin
		if(min_stg1_sclkrate[2*i] > min_stg1_sclkrate[2*i+1])
		begin
			min_stg2_sclkrate[i]   <= min_stg1_sclkrate[2*i+1] ; 
			min_Indx_stg2[i] <= min_Indx_stg1_sclkrate[2*i+1] ;
		end
		else begin
			min_stg2_sclkrate[i]   <= min_stg1_sclkrate[2*i] ;
			min_Indx_stg2[i] <= min_Indx_stg1_sclkrate[2*i] ;
		end
	end
	SOF_atPxy_reg_dly_sclkrate[2] <= SOF_atPxy_reg_dly_sclkrate[1] ;
	// stage3 
	for(i=0;i<4;i=i+1)
	begin
		if(min_stg2_sclkrate[2*i] > min_stg2_sclkrate[2*i+1])
		begin
			min_Indx_stg3_sclkrate[i]   <= min_Indx_stg2[2*i+1] ;
			min_stg3_sclkrate[i]     <= min_stg2_sclkrate[2*i+1] ; 
		end
		else begin
			min_stg3_sclkrate[i]    <= min_stg2_sclkrate[2*i] ;
			min_Indx_stg3_sclkrate[i]  <= min_Indx_stg2[2*i] ;
		end
	end
	SOF_atPxy_reg_dly_sclkrate[3] <= SOF_atPxy_reg_dly_sclkrate[2] ;
	// stage4 
	for(i=0;i<2;i=i+1)
	begin
		if(min_stg3_sclkrate[2*i] > min_stg3_sclkrate[2*i+1])
		begin
			min_Indx_stg4_sclkrate[i] <= min_Indx_stg3_sclkrate[2*i+1] ;
			min_stg4_sclkrate[i] <= min_stg3_sclkrate[2*i+1] ; 
		end
		else begin
			min_Indx_stg4_sclkrate[i] <= min_Indx_stg3_sclkrate[2*i] ;
			min_stg4_sclkrate[i] <= min_stg3_sclkrate[2*i] ;
		end
	end
	SOF_atPxy_reg_dly_sclkrate[4] <= SOF_atPxy_reg_dly_sclkrate[3] ;
	// stage5 
	for(i=0;i<1;i=i+1)
	begin
		if(min_stg4_sclkrate[2*i] > min_stg4_sclkrate[2*i+1])
		begin
			min_Indx_stg5_sclkrate <= min_Indx_stg4_sclkrate[2*i+1] ;
			min_stg5_sclkrate  <= min_stg4_sclkrate[2*i+1] ; 
		end 
		else begin
			min_Indx_stg5_sclkrate <= min_Indx_stg4_sclkrate[2*i] ;
			min_stg5_sclkrate  <= min_stg4_sclkrate[2*i] ;
		end
	end
	SOF_atPxy_reg_dly_sclkrate[5] <= SOF_atPxy_reg_dly_sclkrate[4] ;
end

assign disparity[7:0] = min_Indx_stg5_sclkrate;
assign disparity[8]   = SOF_atPxy_reg_dly_sclkrate[5] ;

(* MARK_DEBUG="true" *)wire sof_out_wta ;
assign sof_out_wta = disparity[8] ;

endmodule