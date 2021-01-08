module median3by3kernel (
	input wire         clk,    // Clock
	input wire         en , // Clock Enable
	input wire         rst_n,  // Asynchronous reset active low
	input wire [7:0]   A00  ,   // input data 
	input wire [7:0]   A01  ,
	input wire [7:0]   A02  ,
	input wire [7:0]   A10  ,
	input wire [7:0]   A11  ,
	input wire [7:0]   A12  ,
	input wire [7:0]   A20  ,
	input wire [7:0]   A21  ,
	input wire [7:0]   A22  ,
	input wire         pixelEN ,     // pixel clock rate 
	output wire [7:0]  final_output  
);

integer i ;

wire [7:0] taps [0:8] ;
wire [7:0] median_out ;

assign taps[0]  = A00     ; 
assign taps[1]  = A01     ; 
assign taps[2]  = A02     ; 
assign taps[3]  = A10     ; 
assign taps[4]  = A11     ; 
assign taps[5]  = A12     ; 
assign taps[6]  = A20     ;  
assign taps[7]  = A21     ;  
assign taps[8]  = A22     ;  


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
end

assign final_output = median_out_reg_sclkrate ;


endmodule