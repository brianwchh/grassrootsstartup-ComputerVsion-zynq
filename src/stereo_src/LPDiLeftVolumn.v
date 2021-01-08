/*
	author : WuChengHe
	
	funtion discription : 
		Lr0(p,Di) = C(p,Di) + min(Lr0(p-1,Di),Lr0(p-1,Di-1)+P1,Lr0(p-1,Di+1)+P1,min(Di+/-k) + P2) - min(Lr0(p-1,Dk)) 
		compute L(p,Di) = Lr0(p,Di) + Lr1(p,Di)+ Lr2(p,Di)+ Lr3(p,Di)

*/
`timescale 1 ns / 1 ps
module LPDiLeftVolumn
#(
	parameter  IMAGE_WIDTH = 640 ,
	parameter  IMAGE_HEIGHT = 480 ,
	parameter  MAXDISPARITY = 64 ,
	parameter  PENALTY1 = 10 ,
 	parameter  PENALTY2 = 60 ,
	parameter  CPDI_WIDTH = 6 ,
	parameter  LPDI_WIDTH = 8 ,
	parameter  INPUTDATAWID = 385,    // 6 * 64 + 1(SOF)
	parameter  OUTPUTDATAWID = 513    // 8 * 64 + 1 
  )
(
	input wire                      clk                               ,         // 150 Clock
	input wire                      en                                ,
	input wire                      pixelEN            	              ,         // clk / 8
	input wire                      sof_in                            , 
	input wire                   	eol_in                            ,
	output wire                  	sof_out                           ,
	output wire                  	eol_out                           ,
	input  wire[INPUTDATAWID-1:0]   CPDi_1D                           , 
	output wire[OUTPUTDATAWID-1:0]  LPDi                              ,         // W*H*D volumn                  
	input wire						rst_n                                       // Asynchronous reset active low
	
);


reg [LPDI_WIDTH-1:0] LPDi_2DArray_reg_sclkrate [0:MAXDISPARITY-1] ;
integer i,j,kk,r,c;


/*  note that : 
	no need buffer C(p,Di), need linebuffer Lr(p-1,Di) (r=1,2,3) , direction r=1,2,3 need 640 bytes of blockram
	direction r=0 , no need linebuffer
*/

/*
	 ________________________________________________________________
	|                   |                     |                      |
	|                   |                     |                      |
	|   P(x-1,y-1)      |    P(x,y-1)         |    P(x+1,y-1         | .............
	|                   |                     |                      |
	|___________________|_____________________|______________________|
	|         			|                     |                      |
	|                   |                     |                      |
	|   P(x-1,y)        |    P(x,y)           |                      | ..............
	|                   |                     |                      |
	|___________________|_____________________|______________________|

*/  

/*  ******************************************************************************************************************** 
	********************************************************************************************************************
							              compute  direction 0:   L0(p,Di) 
							              r0 = P(x-1,y) - P(x,y)   
	********************************************************************************************************************
	********************************************************************************************************************
 */
wire [OUTPUTDATAWID-2:0] Lr0PXminus1_YDi_1dArray_wire;  // Lr(P(x-1,y),Di)    
reg  [OUTPUTDATAWID-2:0] Lr0PXplus1_Yminus1Di_sclkrate ; // Lr(P(x+1,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr0PX_Yminus1Di_sclkrate ;   // Lr(P(x,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr0PXminus1_Yminus1Di_sclkrate ;   // Lr(P(x-1,y-1),Di)  
wire [OUTPUTDATAWID-2:0] Lr0LineBufferOut ;
wire  [LPDI_WIDTH-1:0]   Lr0PXminus1_YDi_min ;

reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2DArray_Reg_sclkrate [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] Lr0PX_YDi_2DArray_BeforeRegister_wire [0:MAXDISPARITY-1] ;   //Lr0(P(x,y),Di)  , wire 
wire [CPDI_WIDTH-1:0] CPDi [0:MAXDISPARITY-1] ; // current C(p,Di) from the stream 

reg[9:0] BlkRamAddressA , BlkRamAddressB ;
wire [10:0] BlkRamAddressB_pre ;

reg[9:0] colCnt_sclkrate, rowCnt_sclkrate ;

wire SOF_atPx_y_wire = CPDi_1D[INPUTDATAWID-1] ; // must be one pixel clk ahead of p(x,y), in order to compute Lr0(P(x,y),Di)
reg SOF_atPx_y_dly ; 

//*******  shift input and linebuffer  **************
/*                     Lr0PX_YDi_2DArray_BeforeRegister_wire
        _______________          |            ________
CPDi   |			   |        \|/          |        |
------>| compute_unit  |-Lr(P(x,y),Di)------>|  Z-1   |------Lr((x-1,y),Di)-----o
       |_______________|                     |________|                         |
          |                                                                     |
          |                                                                     |
                    _____________________________________________ ______________|
					|                
				  _\|/_
				 |     |
				 | N-2 |
				 |     |
				 |_____|                    __________                      _________
				 	|                      |          |                    |         |
				 	 --Lr(P(x+1,y-1),Di)-->|  Z-1     |--Lr(P(x,y-1),Di)-->|  Z-1    |-------------o Lr(P(x-1,y-1),Di)
				 	                       |__________|                    |_________|
         

*/
// shift register matrix 
always @(posedge clk )
if(en && pixelEN)
begin : shift_kernel
	Lr0PXplus1_Yminus1Di_sclkrate <= Lr0LineBufferOut ;       // from linebuffer output 
	Lr0PX_Yminus1Di_sclkrate <= Lr0PXplus1_Yminus1Di_sclkrate ;       // Lr0(P(x,y-1),Di) <= Lr0(P(x+1,y-1),Di)
	Lr0PXminus1_Yminus1Di_sclkrate <= Lr0PX_Yminus1Di_sclkrate ;      // Lr0(P(x-1,y-1),Di) <= Lr0(P(x,y-1),Di)
end

// linebuffer address gen

/*   
                     ________ ________ __________ _______
	BlkRamAddressA   ___0____X___1____X_____2____X____3___
                     ________ ________ __________ _______
BlkRamAddressB_pre   ___3____X___4____X_____5____X____6___
                     ________ ________ __________ _______
	BlkRamAddressB   ___2____X___3____X_____4____X____5___


*/

assign BlkRamAddressB_pre = BlkRamAddressA + 6 ;

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

genvar k;
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign CPDi[k] =  CPDi_1D[(k+1)*CPDI_WIDTH-1:k*CPDI_WIDTH]  ;
end
endgenerate

// compute current pixel coordinates P(x,y)
/* pixel coordinates counter, used for boundery detection and processing
  					  _____
SOF_atPx_y_wire _____|     |________________
               ______ _____ _____ ____
colCnt_sclkrate______X__0__X__1__x____
	           ______ ______________
rowCnt_sclkrate______X__0______
               ______ _____ _____ ____
	CPDi_1D    ______X__0__X__1__x____	P(x,y)_wire
                 ____ _____  _____ _____ _____ _____
Lr0(P(x-1,y),Di) ____X_638__X_639_x__0__X__1__X_____	
               ______ _____ _____ ______ ____
Lr0(P(x,y),Di) ______X_639_X__0__x__1___X____	P(x,y)_reg

 */
always@(posedge clk)
if(!rst_n)
begin
	colCnt_sclkrate<=0;
	rowCnt_sclkrate<=0;
end
else if(en && pixelEN) begin
	if(SOF_atPx_y_wire)
	begin
		colCnt_sclkrate <= 1 ;
		rowCnt_sclkrate <= 0 ;
	end
	else begin 
		if(colCnt_sclkrate == IMAGE_WIDTH -1)
			colCnt_sclkrate <= 0 ;
		else
			colCnt_sclkrate <= colCnt_sclkrate + 1'b1;
		if((rowCnt_sclkrate == IMAGE_HEIGHT-1) && (colCnt_sclkrate == IMAGE_WIDTH -1) )
		begin
			rowCnt_sclkrate <= 0 ;
		end
		else if(colCnt_sclkrate == IMAGE_WIDTH -1) begin
			rowCnt_sclkrate <= rowCnt_sclkrate + 1'b1 ;
		end
	end
end


// *******  compute Lr0(P(x,y),Di) core unit ************
/*
	input signals : 
							   ___________________
		C(P(x,y),Di) -------->|     compute unit  |
		Lr0(P(x-1,y),Di) ---->|                   |
 (start of line)SOL---------->|                   |-------------> Lr0(P(x,y),Di) 
 Lr0(P(x-1,y),Di)minIndx----->|                   |
                EOL---------->|___________________|

	if SOL asserted, Lr0(P(x,y),Di) = C(P(x,y),Di)
	else             Lr0(p(x,y),Di) = C(p(x,y),Di) + { min(Lr0(p(x-1,y),Di), Lr0(p(x-1,y),Di-1)+P1, Lr0(p(x-1,y),Di+1)+P1, min(Lr0(p(x-1,y),Di+/-jj) + P2) - min(Lr0(p(x-1,y),Dk)) }
					 jj>1 , Dk @(0,D)

           LookupTable(minIndx)       
         ____________________                                                                  
		|                    |                            _____________________                
		| Lr0PXminus1_YDi_min|---------->(+)---------->  |                     |              
	    |____________________|           /|\   ------->  |PiplineMin           |-------(+)-------------> Lr0(P(x,y),Di)
	                                      |    |  -----> |_____________________|       /|\
                                      PENALTY2 |  |            /|\                      |
         ____________________                  |  |             |                       |
		|                    |                 |  |             |                       |
		|  Lr0(P(x-1,y),Di-1)|---------->(+)---   |             |                       |
	    |____________________|           /|\      |             |                       |
                                          |       |             |                  C(P(x,y),Di)
                                          |       |             |
	     ____________________         PENALTY1    |             |
		|                    |                    |             |
		|  Lr0(P(x-1,y),Di+0)|---------->(+)------              |
	    |____________________|           /|\                    |
                                          |                     |
                                          |0                    |
         ____________________                                   |
		|                    |                                  |
		|  Lr0(P(x-1,y),Di+1)|---------->(+)--------------------
	    |____________________|	         /|\
                                          |
                                       PENALTY1
*/
wire [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_wire [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di)
wire [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di+1) + PENALTY1
wire [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_wire_DiAdd0    [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di+0) 
wire [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr0PDi_minTemp0_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr0PDi_minTemp1_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr0PDi_minTemp2_hclkrate [0:MAXDISPARITY-1];  



generate
	for (k = 0; k < MAXDISPARITY-1; k=k+1)   // exclude top  case , ie, d= MAXDISPARITY-1
	begin
		assign Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[k] = Lr0PXminus1_YDi_2dArray_wire[k+1] + PENALTY1 ;   // Lr0(P(x-1,y),Di+1) + PENALTY1
	end
	// assign Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[MAXDISPARITY-1] = 8'hBE ; // set non-exist-item to maximum , so that it does not affect the min operation
	
	for (k = 0; k < MAXDISPARITY; k=k+1)   
	begin
		assign Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k]       = Lr0PXminus1_YDi_2dArray_wire[k] ;         // Lr0(P(x-1,y),Di+0)  
	end
	
	for (k = 1; k < MAXDISPARITY; k=k+1)   // exclude bottom case , ie, d=0 
	begin
		assign Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1[k]  = Lr0PXminus1_YDi_2dArray_wire[k-1] + PENALTY1 ;   // Lr0(P(x-1,y),Di-1) + PENALTY1 
	end
	// assign Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1[0]  = 8'hBE ;  // set non-exist-item to maximum , so that it does not affect the min operation

endgenerate

/*   pipline min
	 _____
    |     |
    |di-1_| \
             \               
	 _____    \              _____                  ______                           ______
    |     |----(min)------->|     |                |      |                         |      |
    |_di__|                 |temp0| --(min)------> |temp1 |------->(min)----------> |temp2 |------>  minOut
                            |_____|  /             |______|         /|\             |______|
	 _____                   ______ /                                |
    |     |---------------->|dly1  |                                 |
    |_di+1|                 |______|                       Lr0PXminus1_YDi_min + PENALTY2

*/

wire  r0_boundery_pulse = (colCnt_sclkrate==0);

// always @(posedge clk ) 
// if(en)
// begin : neighborConstrain   // compute at clk clock rate ~= 140M 
// 	for (i = 0; i < MAXDISPARITY; i=i+1) // must be finished in one piexEN cycle
// 	begin
// 		Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[i] <= Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1[i] ;
// 		if(Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[i] > Lr0PXminus1_YDi_2dArray_wire_DiAdd0[i] )  //Pipeline Min
// 			Lr0PDi_minTemp0_hclkrate[i] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd0[i] ;
// 		else
// 			Lr0PDi_minTemp0_hclkrate[i] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[i] ;
// 		if(Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[i] < Lr0PDi_minTemp0_hclkrate[i])
// 			Lr0PDi_minTemp1_hclkrate[i] <= Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[i] ;
// 		else
// 			Lr0PDi_minTemp1_hclkrate[i] <= Lr0PDi_minTemp0_hclkrate[i] ;
// 		// Lr0PXminus1_YDi_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
// 		if(Lr0PXminus1_YDi_min + PENALTY2 > Lr0PDi_minTemp1_hclkrate[i])
// 			Lr0PDi_minTemp2_hclkrate[i] <= Lr0PDi_minTemp1_hclkrate[i] - Lr0PXminus1_YDi_min ;
// 		else 
// 			Lr0PDi_minTemp2_hclkrate[i] <= PENALTY2 ;
// 	end
// end


generate 

	for (k = 1; k < MAXDISPARITY - 1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin : neighborConstrain   // compute at clk clock rate ~= 140M 
			begin
				Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1[k] ;
				if(Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr0PDi_minTemp0_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k] ;
				else
					Lr0PDi_minTemp0_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[k] ;

				if(Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] < Lr0PDi_minTemp0_hclkrate[k])
					Lr0PDi_minTemp1_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] ;
				else
					Lr0PDi_minTemp1_hclkrate[k] <= Lr0PDi_minTemp0_hclkrate[k] ;

				// Lr0PXminus1_YDi_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr0PXminus1_YDi_min + PENALTY2 > Lr0PDi_minTemp1_hclkrate[k])
					Lr0PDi_minTemp2_hclkrate[k] <= Lr0PDi_minTemp1_hclkrate[k] - Lr0PXminus1_YDi_min ;
				else 
					Lr0PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	for (k = 0; k < 1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin : neighborConstrain   // compute at clk clock rate ~= 140M 
			begin
				if(Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr0PDi_minTemp0_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k] ;
				else
					Lr0PDi_minTemp0_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd1_plusPENALTY1[k] ;
				// Lr0PXminus1_YDi_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr0PXminus1_YDi_min + PENALTY2 > Lr0PDi_minTemp0_hclkrate[k])
					Lr0PDi_minTemp2_hclkrate[k] <= Lr0PDi_minTemp0_hclkrate[k] - Lr0PXminus1_YDi_min ;
				else 
					Lr0PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	for (k = MAXDISPARITY-1; k < MAXDISPARITY; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin : neighborConstrain   // compute at clk clock rate ~= 140M 
			begin
				if(Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1[k] < Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k])
					Lr0PDi_minTemp1_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiMinus1_plusPENALTY1[k] ;
				else
					Lr0PDi_minTemp1_hclkrate[k] <= Lr0PXminus1_YDi_2dArray_wire_DiAdd0[k] ;
				// Lr0PXminus1_YDi_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr0PXminus1_YDi_min + PENALTY2 > Lr0PDi_minTemp1_hclkrate[k])
					Lr0PDi_minTemp2_hclkrate[k] <= Lr0PDi_minTemp1_hclkrate[k] - Lr0PXminus1_YDi_min ;
				else 
					Lr0PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

endgenerate



wire [LPDI_WIDTH:0] PreventAddOverFlow [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] neighborConstrainOutPut [0:MAXDISPARITY-1] ;

// always@(posedge clk)
// if(en && pixelEN)
// begin
// 	for (i = 0; i < MAXDISPARITY; i=i+1) 
// 	begin
// 		Lr0PXminus1_YDi_2DArray_Reg_sclkrate[i] <= Lr0PX_YDi_2DArray_BeforeRegister_wire[i] ; 
// 	end
// end


// boundery , the first column of each row 
generate
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			Lr0PXminus1_YDi_2DArray_Reg_sclkrate[k] <= Lr0PX_YDi_2DArray_BeforeRegister_wire[k] ; 
		end
	end

	for (k = 0; k < MAXDISPARITY; k=k+1) begin  : boundery_condition
		assign PreventAddOverFlow[k] = {3'b0,CPDi[k]} + {1'b0,Lr0PDi_minTemp2_hclkrate[k]};
		assign neighborConstrainOutPut[k] = (PreventAddOverFlow[k] > 8'hFF ) ?  8'hFF : PreventAddOverFlow[k][LPDI_WIDTH-1:0] ;   // never overflow, onless logic is wrong.  Lr0PDi_minTemp2_hclkrate <= PENALTY2   CPDi < 63
		assign Lr0PX_YDi_2DArray_BeforeRegister_wire[k] = (colCnt_sclkrate==0 || SOF_atPx_y_wire)? {2'b0,CPDi[k]} : neighborConstrainOutPut[k][LPDI_WIDTH-1:0]  ; // if boundery  assign CPDi
	end
endgenerate

always@(posedge clk)
if(en && pixelEN)
begin
	SOF_atPx_y_dly <= SOF_atPx_y_wire ;
end

// expand to 1d wires 
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr0PXminus1_YDi_1dArray_wire[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] = Lr0PXminus1_YDi_2DArray_Reg_sclkrate[k] ;
end
endgenerate

generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr0PXminus1_YDi_2dArray_wire[k] = Lr0PXminus1_YDi_2DArray_Reg_sclkrate[k] ;
end
endgenerate


// assign Lr0PXminus1_YDi_1dArray_wire[OUTPUTDATAWID-1] = SOF_atPx_y_dly ;


// ********  compute  min(Lr(P(x-1,y),Di))   **********
/*
	input signal :    Lr0(P(x,y),Di)
	output signal :   minVale 

                                __________________
		Lr0(P(x-1,y),Di)-----> |  PipelineMin     | -------> MinVale
		                       |__________________| 

    clk  ~  150M 
	pixelEN  ~  clk / 8  (2^8= 128) , maximum PipelineMin cycle = 6 if MAXDISPARITY = 64 , 7 if MAXDISPARITY= 128; 8 if MAXDISPARITY = 256
                                    ___     ____      ____      ____
	                      clk  ____|   |___|    |____|    |____|
                                            _________
	                      pixelEN  ________|         |________________________________________
                                _____________________ _________________
Lr0PXminus1_YDi_2dArray_wire	_____________________X_________________
                                         ____________ _________ _________ __________ __________
Lr0PXminus1_YDi_2dArray_computeMin_temp______________X_________X_________X__________X__________
                                       ______________ _________________________
Lr0PXminus1_YDi_min                    ______________X_________________________
*/
// reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp [0:MAXDISPARITY/2-1][0:MAXDISPARITY/2-1];    // Lr0(P(x-1,y),Di)

reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0 [0:31] ;
reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1 [0:15] ;
reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2 [0:7] ;
reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3 [0:3] ;
reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4 [0:1] ;
reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp_stg5 ;

// always@(posedge clk)
// if(en)
// begin
// 	// stage0 
// 	for(i=0;i<32;i=i+1)
// 	begin
// 		if(Lr0PXminus1_YDi_2dArray_wire[2*i] > Lr0PXminus1_YDi_2dArray_wire[2*i+1])
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[i] <= Lr0PXminus1_YDi_2dArray_wire[2*i+1] ; 
// 		else
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[i] <= Lr0PXminus1_YDi_2dArray_wire[2*i] ;
// 	end
// 	// stage1 
// 	for(i=0;i<16;i=i+1)
// 	begin
// 		if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*i] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*i+1])
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*i+1] ; 
// 		else
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*i] ;
// 	end
// 	// stage2 
// 	for(i=0;i<8;i=i+1)
// 	begin
// 		if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*i] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*i+1])
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*i+1] ; 
// 		else
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*i] ;
// 	end
// 	// stage3 
// 	for(i=0;i<4;i=i+1)
// 	begin
// 		if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*i] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*i+1])
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*i+1] ; 
// 		else
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*i] ;
// 	end
// 	// stage4 
// 	for(i=0;i<2;i=i+1)
// 	begin
// 		if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*i] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*i+1])
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*i+1] ; 
// 		else
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[i] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*i] ;
// 	end
// 	// stage5 
// 	for(i=0;i<1;i=i+1)
// 	begin
// 		if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*i] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*i+1])
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg5  <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*i+1] ; 
// 		else
// 			Lr0PXminus1_YDi_2dArray_computeMin_temp_stg5  <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*i] ;
// 	end
// end


generate

	// stage0 
	for(k=0;k<32;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr0PXminus1_YDi_2dArray_wire[2*k] > Lr0PXminus1_YDi_2dArray_wire[2*k+1])
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[k] <= Lr0PXminus1_YDi_2dArray_wire[2*k+1] ; 
			else
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[k] <= Lr0PXminus1_YDi_2dArray_wire[2*k] ;
		end
	end
	// stage1 
	for(k=0;k<16;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*k] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*k+1])
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*k+1] ; 
			else
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg0[2*k] ;
		end
	end
	// stage2 
	for(k=0;k<8;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*k] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*k+1])
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*k+1] ; 
			else
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg1[2*k] ;
		end
	end
	// stage3 
	for(k=0;k<4;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*k] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*k+1])
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*k+1] ; 
			else
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg2[2*k] ;
		end
	end
	// stage4 
	for(k=0;k<2;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*k] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*k+1])
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*k+1] ; 
			else
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[k] <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg3[2*k] ;
		end
	end
	// stage5 
	for(k=0;k<1;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*k] > Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*k+1])
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg5  <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*k+1] ; 
			else
				Lr0PXminus1_YDi_2dArray_computeMin_temp_stg5  <= Lr0PXminus1_YDi_2dArray_computeMin_temp_stg4[2*k] ;
		end
	end

endgenerate

assign Lr0PXminus1_YDi_min = Lr0PXminus1_YDi_2dArray_computeMin_temp_stg5;




/* ************  LineBuffers   *****************  */


pathAggLineBuffer  uR0   
		(
		    .clka  (clk),
		    .ena   (en & pixelEN),
		    .wea   (en & pixelEN),
		    .addra (BlkRamAddressA),
		    .dina  (Lr0PXminus1_YDi_1dArray_wire[511:0]),
		    .clkb  (clk),
		    .enb   (en & pixelEN),
		    .addrb (BlkRamAddressB),
		    .doutb (Lr0LineBufferOut[511:0])
		);









/*************************************************************************************************************************************************
**************************************************************************************************************************************************
**************************************************************************************************************************************************

  										compute  direction 1:   L1(p,Di) 
							            r1 = P(x-1,y-1) - P(x,y)    

**************************************************************************************************************************************************
**************************************************************************************************************************************************
**************************************************************************************************************************************************/

/*
	 ________________________________________________________________
	|                   |                     |                      |
	|                   |                     |                      |
	|   P(x-1,y-1)      |    P(x,y-1)         |    P(x+1,y-1         | .............
	|                   |                     |                      |
	|___________________|_____________________|______________________|
	|         			|                     |                      |
	|                   |                     |                      |
	|   P(x-1,y)        |    P(x,y)           |                      | ..............
	|                   |                     |                      |
	|___________________|_____________________|______________________|

*/  


wire [OUTPUTDATAWID-2:0] Lr1PXminus1_YDi_1dArray_wire;  // Lr(P(x-1,y),Di)    
reg  [OUTPUTDATAWID-2:0] Lr1PXplus1_Yminus1Di_sclkrate ; // Lr(P(x+1,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr1PX_Yminus1Di_sclkrate ;   // Lr(P(x,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr1PXminus1_Yminus1Di_sclkrate ;   // Lr(P(x-1,y-1),Di)  
wire [OUTPUTDATAWID-2:0] Lr1LineBufferOut ;
wire  [LPDI_WIDTH-1:0]   Lr1PXminus1_Yminus1Di_min ;

reg [LPDI_WIDTH-1:0]  Lr1PXminus1_YDi_2DArray_Reg_sclkrate [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] Lr1PX_YDi_2DArray_BeforeRegister_wire [0:MAXDISPARITY-1] ;   //Lr0(P(x,y),Di)  , wire 


//*******  shift input and linebuffer  **************
/*                     Lr1PX_YDi_2DArray_BeforeRegister_wire
        _______________          |            ________
CPDi   |			   |        \|/          |        |
------>| compute_unit  |-Lr(P(x,y),Di)------>|  Z-1   |------Lr((x-1,y),Di)-----o
       |_______________|                     |________|                         |
          |                                                                     |
          |                                                                     |
                    _____________________________________________ ______________|
					|                
				  _\|/_
				 |     |
				 | N-2 |
				 |     |
				 |_____|                    __________                      _________
				 	|                      |          |                    |         |
				 	 --Lr(P(x+1,y-1),Di)-->|  Z-1     |--Lr(P(x,y-1),Di)-->|  Z-1    |-------------o Lr(P(x-1,y-1),Di)
				 	                       |__________|                    |_________|
         

*/
// shift register matrix 
always @(posedge clk )
if(en && pixelEN)
begin : shift_kernel_r1
	Lr1PXplus1_Yminus1Di_sclkrate <= Lr1LineBufferOut ;       // from linebuffer output 
	Lr1PX_Yminus1Di_sclkrate <= Lr1PXplus1_Yminus1Di_sclkrate ;       // Lr0(P(x,y-1),Di) <= Lr0(P(x+1,y-1),Di)
	Lr1PXminus1_Yminus1Di_sclkrate <= Lr1PX_Yminus1Di_sclkrate ;      // Lr0(P(x-1,y-1),Di) <= Lr0(P(x,y-1),Di)
end

// linebuffer address gen

/*   
                     ________ ________ __________ _______
	BlkRamAddressA   ___0____X___1____X_____2____X____3___
                     ________ ________ __________ _______
BlkRamAddressB_pre   ___3____X___4____X_____5____X____6___
                     ________ ________ __________ _______
	BlkRamAddressB   ___2____X___3____X_____4____X____5___


*/



// compute current pixel coordinates P(x,y)
/* pixel coordinates counter, used for boundery detection and processing
  					          _____
		SOF_atPx_y_wire _____|     |________________
		               ______ _____ _____ ____
		colCnt_sclkrate______X__0__X__1__x____
			           ______ ______________
		rowCnt_sclkrate______X__0______
		               ______ _____ _____ ____
			CPDi_1D    ______X__0__X__1__x____	P(x,y)_wire
		                 ____ _____  _____ _____ _____ _____
		Lr0(P(x-1,y),Di) ____X_638__X_639_x__0__X__1__X_____	
		               ______ _____ _____ ______ ____
		Lr0(P(x,y),Di) ______X_639_X__0__x__1___X____	P(x,y)_reg

 */



// *******  compute Lr0(P(x,y),Di) core unit ************
/*
	input signals : 
							   ___________________
		C(P(x,y),Di) -------->|     compute unit  |
		Lr0(P(x-1,y),Di) ---->|                   |
 (start of line)SOL---------->|                   |-------------> Lr0(P(x,y),Di) 
 Lr0(P(x-1,y),Di)minIndx----->|                   |
                EOL---------->|___________________|

	if SOL asserted, Lr0(P(x,y),Di) = C(P(x,y),Di)
	else             Lr0(p(x,y),Di) = C(p(x,y),Di) + { min(Lr0(p(x-1,y),Di), Lr0(p(x-1,y),Di-1)+P1, Lr0(p(x-1,y),Di+1)+P1, min(Lr0(p(x-1,y),Di+/-jj) + P2) - min(Lr0(p(x-1,y),Dk)) }
					 jj>1 , Dk @(0,D)

           LookupTable(minIndx)       
         ____________________                                                                  
		|                    |                            _____________________                
    Lr1PXminus1_Yminus1Di_min|---------->(+)---------->  |                     |              
	    |____________________|           /|\   ------->  |PiplineMin           |-------(+)-------------> Lr0(P(x,y),Di)
	                                      |    |  -----> |_____________________|       /|\
                                      PENALTY2 |  |            /|\                      |
         ____________________                  |  |             |                       |
		|                    |                 |  |             |                       |
		|  Lr0(P(x-1,y),Di-1)|---------->(+)---   |             |                       |
	    |____________________|           /|\      |             |                       |
                                          |       |             |                  C(P(x,y),Di)
                                          |       |             |
	     ____________________         PENALTY1    |             |
		|                    |                    |             |
		|  Lr0(P(x-1,y),Di+0)|---------->(+)------              |
	    |____________________|           /|\                    |
                                          |                     |
                                          |0                    |
         ____________________                                   |
		|                    |                                  |
		|  Lr0(P(x-1,y),Di+1)|---------->(+)--------------------
	    |____________________|	         /|\
                                          |
                                       PENALTY1
*/
wire [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_wire [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di)
wire [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di+1) + PENALTY1
wire [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0    [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di+0) 
wire [LPDI_WIDTH-1:0] Lr1PXminus1_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr1PDi_minTemp0_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr1PDi_minTemp1_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr1PDi_minTemp2_hclkrate [0:MAXDISPARITY-1];  



generate
	for (k = 0; k < MAXDISPARITY-1; k=k+1)   // exclude top  case , ie, d= MAXDISPARITY-1
	begin
		assign Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] = Lr1PXminus1_Yminus1Di_2dArray_wire[k+1] + PENALTY1 ;   // Lr0(P(x-1,y),Di+1) + PENALTY1
	end
	assign Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[MAXDISPARITY-1] = 8'hBE ; // set non-exist-item to maximum , so that it does not affect the min operation
	
	for (k = 0; k < MAXDISPARITY; k=k+1)   
	begin
		assign Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k]       = Lr1PXminus1_Yminus1Di_2dArray_wire[k] ;         // Lr0(P(x-1,y),Di+0)  
	end
	
	for (k = 1; k < MAXDISPARITY; k=k+1)   // exclude bottom case , ie, d=0 
	begin
		assign Lr1PXminus1_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k]  = Lr1PXminus1_Yminus1Di_2dArray_wire[k-1] + PENALTY1 ;   // Lr0(P(x-1,y),Di-1) + PENALTY1 
	end
	assign Lr1PXminus1_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[0]  = 8'hBE ;  // set non-exist-item to maximum , so that it does not affect the min operation

endgenerate

/*   pipline min
	 _____
    |     |
    |di-1_| \
             \               
	 _____    \              _____                  ______                           ______
    |     |----(min)------->|     |                |      |                         |      |
    |_di__|                 |temp0| --(min)------> |temp1 |------->(min)----------> |temp2 |------>  minOut
                            |_____|  /             |______|         /|\             |______|
	 _____                   ______ /                                |
    |     |---------------->|dly1  |                                 |
    |_di+1|                 |______|                       Lr1PXminus1_Yminus1Di_min + PENALTY2

*/

wire  r1_boundery_pulse = (colCnt_sclkrate==0);   // ???????  not used 


generate 

	for (k = 1; k < MAXDISPARITY-1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin      // compute at clk clock rate ~= 140M 
			begin
				Lr1PXminus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] <= Lr1PXminus1_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k] ;

				if(Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr1PDi_minTemp0_hclkrate[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr1PDi_minTemp0_hclkrate[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] ;

				if(Lr1PXminus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] < Lr1PDi_minTemp0_hclkrate[k])
					Lr1PDi_minTemp1_hclkrate[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] ;
				else
					Lr1PDi_minTemp1_hclkrate[k] <= Lr1PDi_minTemp0_hclkrate[k] ;

				// Lr1PXminus1_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr1PXminus1_Yminus1Di_min + PENALTY2 > Lr1PDi_minTemp1_hclkrate[k])
					Lr1PDi_minTemp2_hclkrate[k] <= Lr1PDi_minTemp1_hclkrate[k] - Lr1PXminus1_Yminus1Di_min ;
				else 
					Lr1PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	for (k = 0; k < 1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin      // compute at clk clock rate ~= 140M 
			begin
				if(Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr1PDi_minTemp0_hclkrate[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr1PDi_minTemp0_hclkrate[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] ;

				// Lr1PXminus1_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr1PXminus1_Yminus1Di_min + PENALTY2 > Lr1PDi_minTemp0_hclkrate[k])
					Lr1PDi_minTemp2_hclkrate[k] <= Lr1PDi_minTemp0_hclkrate[k] - Lr1PXminus1_Yminus1Di_min ;
				else 
					Lr1PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	for (k = MAXDISPARITY - 1; k < MAXDISPARITY; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin      // compute at clk clock rate ~= 140M 
			begin
				if(Lr1PXminus1_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k] > Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr1PDi_minTemp0_hclkrate[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr1PDi_minTemp0_hclkrate[k] <= Lr1PXminus1_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k] ;

				// Lr1PXminus1_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr1PXminus1_Yminus1Di_min + PENALTY2 > Lr1PDi_minTemp0_hclkrate[k])
					Lr1PDi_minTemp2_hclkrate[k] <= Lr1PDi_minTemp0_hclkrate[k] - Lr1PXminus1_Yminus1Di_min ;
				else 
					Lr1PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

endgenerate



wire [LPDI_WIDTH:0] r1_PreventAddOverFlow [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] r1_neighborConstrainOutPut [0:MAXDISPARITY-1] ;

// always@(posedge clk)
// if(en && pixelEN)
// begin
// 	for (i = 0; i < MAXDISPARITY; i=i+1) 
// 	begin
// 		Lr1PXminus1_YDi_2DArray_Reg_sclkrate[i] <= Lr1PX_YDi_2DArray_BeforeRegister_wire[i] ; 
// 	end
// end



 /******** debug linebuffer  , assume Lr1(p(x,y),Di) == counter, then Lr1(p(x,y-1),Di), should be eq. ****** 

    reg[10:0] debug_dataCnt = 0 ; 
	always@(posedge clk)
	if(en && pixelEN)
	begin
		if(debug_dataCnt == 11'd639)
			debug_dataCnt <= 0 ;
		else 
			debug_dataCnt <= debug_dataCnt + 1'b1 ;
	end
 *********************************************************************************************/


// boundery , the first column of each row 
generate
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			Lr1PXminus1_YDi_2DArray_Reg_sclkrate[k] <= Lr1PX_YDi_2DArray_BeforeRegister_wire[k] ; 
		end
	end

	/* *******  for debuging line buffer ************* 
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			Lr1PXminus1_YDi_2DArray_Reg_sclkrate[k] <= debug_dataCnt ;  // debug_dataCnt = Lr1(p(x,y),Di)
		end
	end
	*/

	for (k = 0; k < MAXDISPARITY; k=k+1) begin  : boundery_condition_r1
		assign r1_PreventAddOverFlow[k] = {3'b0,CPDi[k]} + {1'b0,Lr1PDi_minTemp2_hclkrate[k]};
		// assign r1_neighborConstrainOutPut[k] = (r1_PreventAddOverFlow[k] > 8'hFF ) ?  8'hFF : r1_PreventAddOverFlow[k][LPDI_WIDTH-1:0] ;   // never overflow, onless logic is wrong.  Lr1PDi_minTemp2_hclkrate <= PENALTY2   CPDi < 63
		assign Lr1PX_YDi_2DArray_BeforeRegister_wire[k] = ((colCnt_sclkrate==0) || (SOF_atPx_y_wire == 1'b1) || (rowCnt_sclkrate) == 0)? {2'b0,CPDi[k]} : r1_PreventAddOverFlow[k][LPDI_WIDTH-1:0]  ;
	end
endgenerate



// expand to 1d wires , and port to line buffer
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr1PXminus1_YDi_1dArray_wire[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] = Lr1PXminus1_YDi_2DArray_Reg_sclkrate[k] ;
end
endgenerate


// tap Lr1(p(x-1,y-1),Di) from the kernel shift register array 
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr1PXminus1_Yminus1Di_2dArray_wire[k] = Lr1PXminus1_Yminus1Di_sclkrate[k] ;
end
endgenerate


// assign Lr1PXminus1_YDi_1dArray_wire[OUTPUTDATAWID-1] = SOF_atPx_y_dly ;


// ********  compute  min(Lr(P(x-1,y),Di))   **********
/*
	input signal :    Lr0(P(x,y),Di)
	output signal :   minVale 

                                __________________
		Lr0(P(x-1,y),Di)-----> |  PipelineMin     | -------> MinVale
		                       |__________________| 

    clk  ~  150M 
	pixelEN  ~  clk / 8  (2^8= 128) , maximum PipelineMin cycle = 6 if MAXDISPARITY = 64 , 7 if MAXDISPARITY= 128; 8 if MAXDISPARITY = 256
                                    ___     ____      ____      ____
	                      clk  ____|   |___|    |____|    |____|
                                            _________
	                      pixelEN  ________|         |________________________________________
                                _____________________ _________________
Lr1PXminus1_Yminus1Di_2dArray_wire	_________________X_________________
                                         ____________ _________ _________ __________ __________
Lr0PXminus1_YDi_2dArray_computeMin_temp______________X_________X_________X__________X__________
                                       ______________ _________________________
Lr1PXminus1_Yminus1Di_min                    ______________X_________________________
*/
// reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp [0:MAXDISPARITY/2-1][0:MAXDISPARITY/2-1];    // Lr0(P(x-1,y),Di)

reg [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0 [0:31] ;
reg [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1 [0:15] ;
reg [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2 [0:7] ;
reg [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3 [0:3] ;
reg [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4 [0:1] ;
reg [LPDI_WIDTH-1:0] Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg5       ;



generate

	// stage0 
	for(k=0;k<32;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr1PXminus1_Yminus1Di_2dArray_wire[2*k] > Lr1PXminus1_Yminus1Di_2dArray_wire[2*k+1])
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire[2*k+1] ; 
			else
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0[k] <= Lr1PXminus1_Yminus1Di_2dArray_wire[2*k] ;
		end
	end
	// stage1 
	for(k=0;k<16;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k] > Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k+1])
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k+1] ; 
			else
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k] ;
		end
	end
	// stage2 
	for(k=0;k<8;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k] > Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k+1])
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k+1] ; 
			else
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k] ;
		end
	end
	// stage3 
	for(k=0;k<4;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k] > Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k+1])
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k+1] ; 
			else
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k] ;
		end
	end
	// stage4 
	for(k=0;k<2;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k] > Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k+1])
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k+1] ; 
			else
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4[k] <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k] ;
		end
	end
	// stage5 
	for(k=0;k<1;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k] > Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k+1])
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg5  <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k+1] ; 
			else
				Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg5  <= Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k] ;
		end
	end

endgenerate

assign Lr1PXminus1_Yminus1Di_min = Lr1PXminus1_Yminus1Di_2dArray_computeMin_temp_stg5;



/* ************  LineBuffers   *****************  */


pathAggLineBuffer  uR1   
		(
		    .clka  (clk),
		    .ena   (en & pixelEN),
		    .wea   (en & pixelEN),
		    .addra (BlkRamAddressA),
		    .dina  (Lr1PXminus1_YDi_1dArray_wire[511:0]),
		    .clkb  (clk),
		    .enb   (en & pixelEN),
		    .addrb (BlkRamAddressB),
		    .doutb (Lr1LineBufferOut[511:0])
		);




/*************************************************************************************************************************************************
**************************************************************************************************************************************************
**************************************************************************************************************************************************

  										compute  direction 1:   L2(p,Di) 
							            r2 = P(x,y-1) - P(x,y)    

**************************************************************************************************************************************************
**************************************************************************************************************************************************
**************************************************************************************************************************************************/

/*
	 ________________________________________________________________
	|                   |                     |                      |
	|                   |                     |                      |
	|   P(x-1,y-1)      |    P(x,y-1)         |    P(x+1,y-1         | .............
	|                   |                     |                      |
	|___________________|_____________________|______________________|
	|         			|                     |                      |
	|                   |                     |                      |
	|   P(x-1,y)        |    P(x,y)           |                      | ..............
	|                   |                     |                      |
	|___________________|_____________________|______________________|

*/  


wire [OUTPUTDATAWID-2:0] Lr2PXminus1_YDi_1dArray_wire;  // Lr(P(x-1,y),Di)    
reg  [OUTPUTDATAWID-2:0] Lr2PXplus1_Yminus1Di_sclkrate ; // Lr(P(x+1,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr2PX_Yminus1Di_sclkrate ;   // Lr(P(x,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr2PXminus1_Yminus1Di_sclkrate ;   // Lr(P(x-1,y-1),Di)  
wire [OUTPUTDATAWID-2:0] Lr2LineBufferOut ;
wire  [LPDI_WIDTH-1:0]   Lr2PX_Yminus1Di_min ;

reg [LPDI_WIDTH-1:0]  Lr2PXminus1_YDi_2DArray_Reg_sclkrate [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] Lr2PX_YDi_2DArray_BeforeRegister_wire [0:MAXDISPARITY-1] ;   //Lr0(P(x,y),Di)  , wire 


//*******  shift input and linebuffer  **************
/*                     Lr2PX_YDi_2DArray_BeforeRegister_wire
        _______________          |            ________
CPDi   |			   |        \|/          |        |
------>| compute_unit  |-Lr(P(x,y),Di)------>|  Z-1   |------Lr((x-1,y),Di)-----o
       |_______________|                     |________|                         |
          |                                                                     |
          |                                                                     |
                    _____________________________________________ ______________|
					|                
				  _\|/_
				 |     |
				 | N-2 |
				 |     |
				 |_____|                    __________                      _________
				 	|                      |          |                    |         |
				 	 --Lr(P(x+1,y-1),Di)-->|  Z-1     |--Lr(P(x,y-1),Di)-->|  Z-1    |-------------o Lr(P(x-1,y-1),Di)
				 	                       |__________|                    |_________|
         

*/
// shift register matrix 
always @(posedge clk )
if(en && pixelEN)
begin : shift_kernel_r2
	Lr2PXplus1_Yminus1Di_sclkrate <= Lr2LineBufferOut ;       // from linebuffer output 
	Lr2PX_Yminus1Di_sclkrate <= Lr2PXplus1_Yminus1Di_sclkrate ;       // Lr0(P(x,y-1),Di) <= Lr0(P(x+1,y-1),Di)
	Lr2PXminus1_Yminus1Di_sclkrate <= Lr2PX_Yminus1Di_sclkrate ;      // Lr0(P(x-1,y-1),Di) <= Lr0(P(x,y-1),Di)
end

// linebuffer address gen

/*   
                     ________ ________ __________ _______
	BlkRamAddressA   ___0____X___1____X_____2____X____3___
                     ________ ________ __________ _______
BlkRamAddressB_pre   ___3____X___4____X_____5____X____6___
                     ________ ________ __________ _______
	BlkRamAddressB   ___2____X___3____X_____4____X____5___


*/



// compute current pixel coordinates P(x,y)
/* pixel coordinates counter, used for boundery detection and processing
  					  _____
		SOF_atPx_y_wire _____|     |________________
		               ______ _____ _____ ____
		colCnt_sclkrate______X__0__X__1__x____
			           ______ ______________
		rowCnt_sclkrate______X__0______
		               ______ _____ _____ ____
			CPDi_1D    ______X__0__X__1__x____	P(x,y)_wire
		                 ____ _____  _____ _____ _____ _____
		Lr0(P(x-1,y),Di) ____X_638__X_639_x__0__X__1__X_____	
		               ______ _____ _____ ______ ____
		Lr0(P(x,y),Di) ______X_639_X__0__x__1___X____	P(x,y)_reg

 */



// *******  compute Lr0(P(x,y),Di) core unit ************
/*
	input signals : 
							   ___________________
		C(P(x,y),Di) -------->|     compute unit  |
		Lr0(P(x-1,y),Di) ---->|                   |
 (start of line)SOL---------->|                   |-------------> Lr0(P(x,y),Di) 
 Lr0(P(x-1,y),Di)minIndx----->|                   |
                EOL---------->|___________________|

	if SOL asserted, Lr0(P(x,y),Di) = C(P(x,y),Di)
	else             Lr0(p(x,y),Di) = C(p(x,y),Di) + { min(Lr0(p(x-1,y),Di), Lr0(p(x-1,y),Di-1)+P1, Lr0(p(x-1,y),Di+1)+P1, min(Lr0(p(x-1,y),Di+/-jj) + P2) - min(Lr0(p(x-1,y),Dk)) }
					 jj>1 , Dk @(0,D)

           LookupTable(minIndx)       
         ____________________                                                                  
		|                    |                            _____________________                
		| Lr2PX_Yminus1Di_min|---------->(+)---------->  |                     |              
	    |____________________|           /|\   ------->  |PiplineMin           |-------(+)-------------> Lr0(P(x,y),Di)
	                                      |    |  -----> |_____________________|       /|\
                                      PENALTY2 |  |            /|\                      |
         ____________________                  |  |             |                       |
		|                    |                 |  |             |                       |
		|  Lr0(P(x-1,y),Di-1)|---------->(+)---   |             |                       |
	    |____________________|           /|\      |             |                       |
                                          |       |             |                  C(P(x,y),Di)
                                          |       |             |
	     ____________________         PENALTY1    |             |
		|                    |                    |             |
		|  Lr0(P(x-1,y),Di+0)|---------->(+)------              |
	    |____________________|           /|\                    |
                                          |                     |
                                          |0                    |
         ____________________                                   |
		|                    |                                  |
		|  Lr0(P(x-1,y),Di+1)|---------->(+)--------------------
	    |____________________|	         /|\
                                          |
                                       PENALTY1
*/
wire [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_wire [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di)
wire [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di+1) + PENALTY1
wire [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_wire_DiAdd0    [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di+0) 
wire [LPDI_WIDTH-1:0] Lr2PX_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr2PDi_minTemp0_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr2PDi_minTemp1_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr2PDi_minTemp2_hclkrate [0:MAXDISPARITY-1];  



generate
	for (k = 0; k < MAXDISPARITY-1; k=k+1)   // exclude top  case , ie, d= MAXDISPARITY-1
	begin
		assign Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] = Lr2PX_Yminus1Di_2dArray_wire[k+1] + PENALTY1 ;   // Lr0(P(x-1,y),Di+1) + PENALTY1
	end
	assign Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[MAXDISPARITY-1] = 8'hBE ; // set non-exist-item to maximum , so that it does not affect the min operation
	
	for (k = 0; k < MAXDISPARITY; k=k+1)   
	begin
		assign Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k]       = Lr2PX_Yminus1Di_2dArray_wire[k] ;         // Lr0(P(x-1,y),Di+0)  
	end
	
	for (k = 1; k < MAXDISPARITY; k=k+1)   // exclude bottom case , ie, d=0 
	begin
		assign Lr2PX_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k]  = Lr2PX_Yminus1Di_2dArray_wire[k-1] + PENALTY1 ;   // Lr0(P(x-1,y),Di-1) + PENALTY1 
	end
	assign Lr2PX_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[0]  = 8'hBE ;  // set non-exist-item to maximum , so that it does not affect the min operation

endgenerate

/*   pipline min
	 _____
    |     |
    |di-1_| \
             \               
	 _____    \              _____                  ______                           ______
    |     |----(min)------->|     |                |      |                         |      |
    |_di__|                 |temp0| --(min)------> |temp1 |------->(min)----------> |temp2 |------>  minOut
                            |_____|  /             |______|         /|\             |______|
	 _____                   ______ /                                |
    |     |---------------->|dly1  |                                 |
    |_di+1|                 |______|                       Lr2PX_Yminus1Di_min + PENALTY2

*/

wire  r2_boundery_pulse = (colCnt_sclkrate==0);   // ???????  not used 


generate 

	for (k = 1; k < MAXDISPARITY-1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin : neighborConstrain   // compute at clk clock rate ~= 140M 
			begin
				Lr2PX_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] <= Lr2PX_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k] ;
				if(Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr2PDi_minTemp0_hclkrate[k] <= Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr2PDi_minTemp0_hclkrate[k] <= Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] ;
				if(Lr2PX_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] < Lr2PDi_minTemp0_hclkrate[k])
					Lr2PDi_minTemp1_hclkrate[k] <= Lr2PX_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] ;
				else
					Lr2PDi_minTemp1_hclkrate[k] <= Lr2PDi_minTemp0_hclkrate[k] ;
				// Lr2PX_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr2PX_Yminus1Di_min + PENALTY2 > Lr2PDi_minTemp1_hclkrate[k])
					Lr2PDi_minTemp2_hclkrate[k] <= Lr2PDi_minTemp1_hclkrate[k] - Lr2PX_Yminus1Di_min ;
				else 
					Lr2PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	for (k = 0; k < 1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin : neighborConstrain   // compute at clk clock rate ~= 140M 
			begin
				if(Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr2PDi_minTemp0_hclkrate[k] <= Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr2PDi_minTemp0_hclkrate[k] <= Lr2PX_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] ;

				// Lr2PX_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr2PX_Yminus1Di_min + PENALTY2 > Lr2PDi_minTemp0_hclkrate[k])
					Lr2PDi_minTemp2_hclkrate[k] <= Lr2PDi_minTemp0_hclkrate[k] - Lr2PX_Yminus1Di_min ;
				else 
					Lr2PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	for (k = MAXDISPARITY-1; k < MAXDISPARITY ; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin : neighborConstrain   // compute at clk clock rate ~= 140M 
			begin
				if(Lr2PX_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k] > Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr2PDi_minTemp0_hclkrate[k] <= Lr2PX_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr2PDi_minTemp0_hclkrate[k] <= Lr2PX_YminusDi_2dArray_wire_DiMinus1_plusPENALTY1[k] ;

				// Lr2PX_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr2PX_Yminus1Di_min + PENALTY2 > Lr2PDi_minTemp0_hclkrate[k])
					Lr2PDi_minTemp2_hclkrate[k] <= Lr2PDi_minTemp0_hclkrate[k] - Lr2PX_Yminus1Di_min ;
				else 
					Lr2PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

endgenerate



wire [LPDI_WIDTH:0] r2_PreventAddOverFlow [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] r2_neighborConstrainOutPut [0:MAXDISPARITY-1] ;

// always@(posedge clk)
// if(en && pixelEN)
// begin
// 	for (i = 0; i < MAXDISPARITY; i=i+1) 
// 	begin
// 		Lr2PXminus1_YDi_2DArray_Reg_sclkrate[i] <= Lr2PX_YDi_2DArray_BeforeRegister_wire[i] ; 
// 	end
// end


// boundery , the first column of each row 
generate
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			Lr2PXminus1_YDi_2DArray_Reg_sclkrate[k] <= Lr2PX_YDi_2DArray_BeforeRegister_wire[k] ; 
		end
	end

	/******** for debuging line buffer   ************************
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			Lr2PXminus1_YDi_2DArray_Reg_sclkrate[k] <= debug_dataCnt ; 
		end
	end
	***************************************/	

	for (k = 0; k < MAXDISPARITY; k=k+1) begin  : boundery_condition_r2
		assign r2_PreventAddOverFlow[k] = {3'b0,CPDi[k]} + {1'b0,Lr2PDi_minTemp2_hclkrate[k]};
		// assign r2_neighborConstrainOutPut[k] = (r2_PreventAddOverFlow[k] > 8'hFF ) ?  8'hFF : r2_PreventAddOverFlow[k][LPDI_WIDTH-1:0] ;   // never overflow, onless logic is wrong.  Lr2PDi_minTemp2_hclkrate <= PENALTY2   CPDi < 63
		assign Lr2PX_YDi_2DArray_BeforeRegister_wire[k] = ((colCnt_sclkrate==0) || (SOF_atPx_y_wire == 1'b1) || (rowCnt_sclkrate) == 0)? {2'b0,CPDi[k]} : r2_PreventAddOverFlow[k][LPDI_WIDTH-1:0]  ;
	end
endgenerate


// expand to 1d wires , and port to line buffer
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr2PXminus1_YDi_1dArray_wire[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] = Lr2PXminus1_YDi_2DArray_Reg_sclkrate[k] ;
end
endgenerate


// tap Lr1(p(x-1,y-1),Di) from the kernel shift register array , tap location is different in each direction
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr2PX_Yminus1Di_2dArray_wire[k] = Lr2PX_Yminus1Di_sclkrate[k] ;
end
endgenerate


// assign Lr2PXminus1_YDi_1dArray_wire[OUTPUTDATAWID-1] = SOF_atPx_y_dly ;


// ********  compute  min(Lr(P(x-1,y),Di))   **********
/*
	input signal :    Lr0(P(x,y),Di)
	output signal :   minVale 

                                __________________
		Lr0(P(x-1,y),Di)-----> |  PipelineMin     | -------> MinVale
		                       |__________________| 

    clk  ~  150M 
	pixelEN  ~  clk / 8  (2^8= 128) , maximum PipelineMin cycle = 6 if MAXDISPARITY = 64 , 7 if MAXDISPARITY= 128; 8 if MAXDISPARITY = 256
                                    ___     ____      ____      ____
	                      clk  ____|   |___|    |____|    |____|
                                            _________
	                      pixelEN  ________|         |________________________________________
                                _____________________ _________________
Lr2PX_Yminus1Di_2dArray_wire	    _________________X_________________
                                         ____________ _________ _________ __________ __________
Lr0PXminus1_YDi_2dArray_computeMin_temp______________X_________X_________X__________X__________
                                       ______________ _________________________
Lr2PX_Yminus1Di_min              ______________X_________________________
*/
// reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp [0:MAXDISPARITY/2-1][0:MAXDISPARITY/2-1];    // Lr0(P(x-1,y),Di)

reg [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0 [0:31] ;
reg [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1 [0:15] ;
reg [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2 [0:7] ;
reg [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3 [0:3] ;
reg [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4 [0:1] ;
reg [LPDI_WIDTH-1:0] Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg5       ;



generate

	// stage0 
	for(k=0;k<32;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr2PX_Yminus1Di_2dArray_wire[2*k] > Lr2PX_Yminus1Di_2dArray_wire[2*k+1])
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0[k] <= Lr2PX_Yminus1Di_2dArray_wire[2*k+1] ; 
			else
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0[k] <= Lr2PX_Yminus1Di_2dArray_wire[2*k] ;
		end
	end
	// stage1 
	for(k=0;k<16;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0[2*k] > Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0[2*k+1])
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0[2*k+1] ; 
			else
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg0[2*k] ;
		end
	end
	// stage2 
	for(k=0;k<8;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1[2*k] > Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1[2*k+1])
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1[2*k+1] ; 
			else
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg1[2*k] ;
		end
	end
	// stage3 
	for(k=0;k<4;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2[2*k] > Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2[2*k+1])
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2[2*k+1] ; 
			else
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg2[2*k] ;
		end
	end
	// stage4 
	for(k=0;k<2;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3[2*k] > Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3[2*k+1])
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3[2*k+1] ; 
			else
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4[k] <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg3[2*k] ;
		end
	end
	// stage5 
	for(k=0;k<1;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4[2*k] > Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4[2*k+1])
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg5  <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4[2*k+1] ; 
			else
				Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg5  <= Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg4[2*k] ;
		end
	end

endgenerate

assign Lr2PX_Yminus1Di_min = Lr2PX_Yminus1Di_2dArray_computeMin_temp_stg5;



/* ************  LineBuffers   *****************  */


pathAggLineBuffer  uR2   
		(
		    .clka  (clk),
		    .ena   (en & pixelEN),
		    .wea   (en & pixelEN),
		    .addra (BlkRamAddressA),
		    .dina  (Lr2PXminus1_YDi_1dArray_wire[511:0]),
		    .clkb  (clk),
		    .enb   (en & pixelEN),
		    .addrb (BlkRamAddressB),
		    .doutb (Lr2LineBufferOut[511:0])
		);




/*************************************************************************************************************************************************
**************************************************************************************************************************************************
**************************************************************************************************************************************************

  										compute  direction 1:   L2(p,Di) 
							            r3 = P(x+1,y-1) - P(x,y)    

**************************************************************************************************************************************************
**************************************************************************************************************************************************
**************************************************************************************************************************************************/

/*
	 ________________________________________________________________
	|                   |                     |                      |
	|                   |                     |                      |
	|   P(x-1,y-1)      |    P(x,y-1)         |    P(x+1,y-1         | .............
	|                   |                     |                      |
	|___________________|_____________________|______________________|
	|         			|                     |                      |
	|                   |                     |                      |
	|   P(x-1,y)        |    P(x,y)           |                      | ..............
	|                   |                     |                      |
	|___________________|_____________________|______________________|

*/  


wire [OUTPUTDATAWID-2:0] Lr3PXminus1_YDi_1dArray_wire;  // Lr(P(x-1,y),Di)    
reg  [OUTPUTDATAWID-2:0] Lr3PXplus1_Yminus1Di_sclkrate ; // Lr(P(x+1,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr3PX_Yminus1Di_sclkrate ;   // Lr(P(x,y-1),Di)  
reg  [OUTPUTDATAWID-2:0] Lr3PXminus1_Yminus1Di_sclkrate ;   // Lr(P(x-1,y-1),Di)  
wire [OUTPUTDATAWID-2:0] Lr3LineBufferOut ;
wire  [LPDI_WIDTH-1:0]   Lr3PXplus1_Yminus1Di_min ;

reg [LPDI_WIDTH-1:0]  Lr3PXminus1_YDi_2DArray_Reg_sclkrate [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] Lr3PX_YDi_2DArray_BeforeRegister_wire [0:MAXDISPARITY-1] ;   //Lr0(P(x,y),Di)  , wire 


//*******  shift input and linebuffer  **************
/*                     Lr3PX_YDi_2DArray_BeforeRegister_wire
        _______________          |            ________
CPDi   |			   |        \|/          |        |
------>| compute_unit  |-Lr(P(x,y),Di)------>|  Z-1   |------Lr((x-1,y),Di)-----o
       |_______________|                     |________|                         |
          |                                                                     |
          |                                                                     |
                    _____________________________________________ ______________|
					|                
				  _\|/_
				 |     |
				 | N-2 |
				 |     |
				 |_____|                    __________                      _________
				 	|                      |          |                    |         |
				 	 --Lr(P(x+1,y-1),Di)-->|  Z-1     |--Lr(P(x,y-1),Di)-->|  Z-1    |-------------o Lr(P(x-1,y-1),Di)
				 	                       |__________|                    |_________|
         

*/
// shift register matrix 
always @(posedge clk )
if(en && pixelEN)
begin : shift_kernel_r3
	Lr3PXplus1_Yminus1Di_sclkrate <= Lr3LineBufferOut ;       // from linebuffer output 
	Lr3PX_Yminus1Di_sclkrate <= Lr3PXplus1_Yminus1Di_sclkrate ;       // Lr0(P(x,y-1),Di) <= Lr0(P(x+1,y-1),Di)
	Lr3PXminus1_Yminus1Di_sclkrate <= Lr3PX_Yminus1Di_sclkrate ;      // Lr0(P(x-1,y-1),Di) <= Lr0(P(x,y-1),Di)
end

// linebuffer address gen

/*   
                     ________ ________ __________ _______
	BlkRamAddressA   ___0____X___1____X_____2____X____3___
                     ________ ________ __________ _______
BlkRamAddressB_pre   ___3____X___4____X_____5____X____6___
                     ________ ________ __________ _______
	BlkRamAddressB   ___2____X___3____X_____4____X____5___


*/



// compute current pixel coordinates P(x,y)
/* pixel coordinates counter, used for boundery detection and processing
  					  _____
		SOF_atPx_y_wire _____|     |________________
		               ______ _____ _____ ____
		colCnt_sclkrate______X__0__X__1__x____
			           ______ ______________
		rowCnt_sclkrate______X__0______
		               ______ _____ _____ ____
			CPDi_1D    ______X__0__X__1__x____	P(x,y)_wire
		                 ____ _____  _____ _____ _____ _____
		Lr0(P(x-1,y),Di) ____X_638__X_639_x__0__X__1__X_____	
		               ______ _____ _____ ______ ____
		Lr0(P(x,y),Di) ______X_639_X__0__x__1___X____	P(x,y)_reg

 */



// *******  compute Lr0(P(x,y),Di) core unit ************
/*
	input signals : 
							   ___________________
		C(P(x,y),Di) -------->|     compute unit  |
		Lr0(P(x-1,y),Di) ---->|                   |
 (start of line)SOL---------->|                   |-------------> Lr0(P(x,y),Di) 
 Lr0(P(x-1,y),Di)minIndx----->|                   |
                EOL---------->|___________________|

	if SOL asserted, Lr0(P(x,y),Di) = C(P(x,y),Di)
	else             Lr0(p(x,y),Di) = C(p(x,y),Di) + { min(Lr0(p(x-1,y),Di), Lr0(p(x-1,y),Di-1)+P1, Lr0(p(x-1,y),Di+1)+P1, min(Lr0(p(x-1,y),Di+/-jj) + P2) - min(Lr0(p(x-1,y),Dk)) }
					 jj>1 , Dk @(0,D)

           LookupTable(minIndx)       
         ____________________                                                                  
		|                    |                            _____________________                
		| Lr3PXplus1_Yminus1Di_min|---------->(+)---------->  |                     |              
	    |____________________|           /|\   ------->  |PiplineMin           |-------(+)-------------> Lr0(P(x,y),Di)
	                                      |    |  -----> |_____________________|       /|\
                                      PENALTY2 |  |            /|\                      |
         ____________________                  |  |             |                       |
		|                    |                 |  |             |                       |
		|  Lr0(P(x-1,y),Di-1)|---------->(+)---   |             |                       |
	    |____________________|           /|\      |             |                       |
                                          |       |             |                  C(P(x,y),Di)
                                          |       |             |
	     ____________________         PENALTY1    |             |
		|                    |                    |             |
		|  Lr0(P(x-1,y),Di+0)|---------->(+)------              |
	    |____________________|           /|\                    |
                                          |                     |
                                          |0                    |
         ____________________                                   |
		|                    |                                  |
		|  Lr0(P(x-1,y),Di+1)|---------->(+)--------------------
	    |____________________|	         /|\
                                          |
                                       PENALTY1
*/
wire [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_wire [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di)
wire [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di+1) + PENALTY1
wire [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0    [0:MAXDISPARITY-1];    // Lr0(P(x-1,y),Di+0) 
wire [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1 [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate [0:MAXDISPARITY-1];  // Lr0(P(x-1,y),Di-1) + PENALTY1
reg  [LPDI_WIDTH-1:0] Lr3PDi_minTemp0_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr3PDi_minTemp1_hclkrate [0:MAXDISPARITY-1];    
reg  [LPDI_WIDTH-1:0] Lr3PDi_minTemp2_hclkrate [0:MAXDISPARITY-1];  



generate
	for (k = 0; k < MAXDISPARITY-1; k=k+1)   // exclude top  case , ie, d= MAXDISPARITY-1
	begin
		assign Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] = Lr3PXplus1_Yminus1Di_2dArray_wire[k+1] + PENALTY1 ;   // Lr0(P(x-1,y),Di+1) + PENALTY1
	end
	// assign Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[MAXDISPARITY-1] = 8'hBE ; // set non-exist-item to maximum , so that it does not affect the min operation
	
	for (k = 0; k < MAXDISPARITY; k=k+1)   
	begin
		assign Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[k]       = Lr3PXplus1_Yminus1Di_2dArray_wire[k] ;         // Lr0(P(x-1,y),Di+0)  
	end
	
	for (k = 1; k < MAXDISPARITY; k=k+1)   // exclude bottom case , ie, d=0 
	begin
		assign Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1[k]  = Lr3PXplus1_Yminus1Di_2dArray_wire[k-1] + PENALTY1 ;   // Lr0(P(x-1,y),Di-1) + PENALTY1 
	end
	// assign Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1[0]  = 8'hBE ;  // set non-exist-item to maximum , so that it does not affect the min operation

endgenerate

/*   pipline min
	 _____
    |     |
    |di-1_| \
             \               
	 _____    \              _____                  ______                           ______
    |     |----(min)------->|     |                |      |                         |      |
    |_di__|                 |temp0| --(min)------> |temp1 |------->(min)----------> |temp2 |------>  minOut
                            |_____|  /             |______|         /|\             |______|
	 _____                   ______ /                                |
    |     |---------------->|dly1  |                                 |
    |_di+1|                 |______|                       Lr3PXplus1_Yminus1Di_min + PENALTY2

*/

wire  r3_boundery_pulse = (colCnt_sclkrate==0);   // ???????  not used 


generate 

	// for (k = 0; k < MAXDISPARITY; k=k+1) // must be finished in one piexEN cycle
	// begin
	// 	always @(posedge clk ) 
	// 	if(en)
	// 	begin : neighborConstrain   // compute at clk clock rate ~= 140M 
	// 		begin
	// 			Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1[k] ;
	// 			if(Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
	// 				Lr3PDi_minTemp0_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[k] ;
	// 			else
	// 				Lr3PDi_minTemp0_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] ;
	// 			if(Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] < Lr3PDi_minTemp0_hclkrate[k])
	// 				Lr3PDi_minTemp1_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] ;
	// 			else
	// 				Lr3PDi_minTemp1_hclkrate[k] <= Lr3PDi_minTemp0_hclkrate[k] ;
	// 			// Lr3PXplus1_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
	// 			if(Lr3PXplus1_Yminus1Di_min + PENALTY2 > Lr3PDi_minTemp1_hclkrate[k])
	// 				Lr3PDi_minTemp2_hclkrate[k] <= Lr3PDi_minTemp1_hclkrate[k] - Lr3PXplus1_Yminus1Di_min ;
	// 			else 
	// 				Lr3PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
	// 		end
	// 	end
	// end


	for (k = 1; k < MAXDISPARITY - 1; k=k+1) // must be finished in one piexEN cycle
	begin
		always @(posedge clk ) 
		if(en)
		begin    // compute at clk clock rate ~= 140M 
			begin
				Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1[k] ;
				if(Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] > Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[k] )  //Pipeline Min
					Lr3PDi_minTemp0_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[k] ;
				else
					Lr3PDi_minTemp0_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[k] ;
				if(Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] < Lr3PDi_minTemp0_hclkrate[k])
					Lr3PDi_minTemp1_hclkrate[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1_dly1_hclkrate[k] ;
				else
					Lr3PDi_minTemp1_hclkrate[k] <= Lr3PDi_minTemp0_hclkrate[k] ;
				// Lr3PXplus1_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
				if(Lr3PXplus1_Yminus1Di_min + PENALTY2 > Lr3PDi_minTemp1_hclkrate[k])
					Lr3PDi_minTemp2_hclkrate[k] <= Lr3PDi_minTemp1_hclkrate[k] - Lr3PXplus1_Yminus1Di_min ;
				else 
					Lr3PDi_minTemp2_hclkrate[k] <= PENALTY2 ;
			end
		end
	end

	// for k=0; Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1 does not exist 
	always @(posedge clk ) 
	if(en)
	begin     // compute at clk clock rate ~= 140M 
		if(Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[0] > Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[0] )  //Pipeline Min
			Lr3PDi_minTemp0_hclkrate[0] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[0] ;
		else
			Lr3PDi_minTemp0_hclkrate[0] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd1_plusPENALTY1[0] ;

			Lr3PDi_minTemp1_hclkrate[0] <= Lr3PDi_minTemp0_hclkrate[0] ;

		if(Lr3PXplus1_Yminus1Di_min + PENALTY2 > Lr3PDi_minTemp1_hclkrate[0])
			Lr3PDi_minTemp2_hclkrate[0] <= Lr3PDi_minTemp1_hclkrate[0] - Lr3PXplus1_Yminus1Di_min ;
		else 
			Lr3PDi_minTemp2_hclkrate[0] <= PENALTY2 ;
	end

	// for k=D-1; Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1 does not exist 
	always @(posedge clk ) 
	if(en)
	begin    // compute at clk clock rate ~= 140M 
		if(Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1[MAXDISPARITY-1] < Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[MAXDISPARITY-1])
			Lr3PDi_minTemp1_hclkrate[MAXDISPARITY-1] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiMinus1_plusPENALTY1[MAXDISPARITY-1] ;
		else
			Lr3PDi_minTemp1_hclkrate[MAXDISPARITY-1] <= Lr3PXplus1_Yminus1Di_2dArray_wire_DiAdd0[MAXDISPARITY-1] ;
		// Lr3PXplus1_Yminus1Di_min should be stable within one pixel clock cycle , here clk is 8 times of pixel clock
		if(Lr3PXplus1_Yminus1Di_min + PENALTY2 > Lr3PDi_minTemp1_hclkrate[0])
			Lr3PDi_minTemp2_hclkrate[0] <= Lr3PDi_minTemp1_hclkrate[0] - Lr3PXplus1_Yminus1Di_min ;
		else 
			Lr3PDi_minTemp2_hclkrate[0] <= PENALTY2 ;
	end

endgenerate



wire [LPDI_WIDTH:0] r3_PreventAddOverFlow [0:MAXDISPARITY-1] ;
wire [LPDI_WIDTH-1:0] r3_neighborConstrainOutPut [0:MAXDISPARITY-1] ;

// always@(posedge clk)
// if(en && pixelEN)
// begin
// 	for (i = 0; i < MAXDISPARITY; i=i+1) 
// 	begin
// 		Lr3PXminus1_YDi_2DArray_Reg_sclkrate[i] <= Lr3PX_YDi_2DArray_BeforeRegister_wire[i] ; 
// 	end
// end


// boundery , the first column of each row 
generate
	for (k = 0; k < MAXDISPARITY; k=k+1) 
	begin
		always@(posedge clk)
		if(en && pixelEN)
		begin
			Lr3PXminus1_YDi_2DArray_Reg_sclkrate[k] <= Lr3PX_YDi_2DArray_BeforeRegister_wire[k] ; 
		end
	end

	for (k = 0; k < MAXDISPARITY; k=k+1) begin  : boundery_condition_r3
		assign r3_PreventAddOverFlow[k] = {3'b0,CPDi[k]} + {1'b0,Lr3PDi_minTemp2_hclkrate[k]};
		// assign r3_neighborConstrainOutPut[k] = (r3_PreventAddOverFlow[k] > 8'hFF ) ?  8'hFF : r3_PreventAddOverFlow[k][LPDI_WIDTH-1:0] ;   // never overflow, onless logic is wrong.  Lr3PDi_minTemp2_hclkrate <= PENALTY2   CPDi < 63
		assign Lr3PX_YDi_2DArray_BeforeRegister_wire[k] = ((colCnt_sclkrate==IMAGE_WIDTH-1) || (SOF_atPx_y_wire == 1'b1) || (rowCnt_sclkrate) == 0)? {2'b0,CPDi[k]} : r3_PreventAddOverFlow[k][LPDI_WIDTH-1:0]  ;
	end
endgenerate


// expand to 1d wires , and port to line buffer
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr3PXminus1_YDi_1dArray_wire[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] = Lr3PXminus1_YDi_2DArray_Reg_sclkrate[k] ;
end
endgenerate


// tap Lr1(p(x-1,y-1),Di) from the kernel shift register array , tap location is different in each direction
generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign Lr3PXplus1_Yminus1Di_2dArray_wire[k] = Lr3PXplus1_Yminus1Di_sclkrate[k] ;
end
endgenerate


// assign Lr3PXminus1_YDi_1dArray_wire[OUTPUTDATAWID-1] = SOF_atPx_y_dly ;


// ********  compute  min(Lr(P(x-1,y),Di))   **********
/*
	input signal :    Lr0(P(x,y),Di)
	output signal :   minVale 

                                __________________
		Lr0(P(x-1,y),Di)-----> |  PipelineMin     | -------> MinVale
		                       |__________________| 

    clk  ~  150M 
	pixelEN  ~  clk / 8  (2^8= 128) , maximum PipelineMin cycle = 6 if MAXDISPARITY = 64 , 7 if MAXDISPARITY= 128; 8 if MAXDISPARITY = 256
                                    ___     ____      ____      ____
	                      clk  ____|   |___|    |____|    |____|
                                            _________
	                      pixelEN  ________|         |________________________________________
                                _____________________ _________________
Lr3PXplus1_Yminus1Di_2dArray_wire	    _________________X_________________
                                         ____________ _________ _________ __________ __________
Lr0PXminus1_YDi_2dArray_computeMin_temp______________X_________X_________X__________X__________
                                       ______________ _________________________
Lr3PXplus1_Yminus1Di_min              ______________X_________________________
*/
// reg [LPDI_WIDTH-1:0] Lr0PXminus1_YDi_2dArray_computeMin_temp [0:MAXDISPARITY/2-1][0:MAXDISPARITY/2-1];    // Lr0(P(x-1,y),Di)

reg [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0 [0:31] ;
reg [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1 [0:15] ;
reg [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2 [0:7] ;
reg [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3 [0:3] ;
reg [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4 [0:1] ;
reg [LPDI_WIDTH-1:0] Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg5       ;



generate

	// stage0 
	for(k=0;k<32;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr3PXplus1_Yminus1Di_2dArray_wire[2*k] > Lr3PXplus1_Yminus1Di_2dArray_wire[2*k+1])
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire[2*k+1] ; 
			else
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0[k] <= Lr3PXplus1_Yminus1Di_2dArray_wire[2*k] ;
		end
	end
	// stage1 
	for(k=0;k<16;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k] > Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k+1])
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k+1] ; 
			else
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg0[2*k] ;
		end
	end
	// stage2 
	for(k=0;k<8;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k] > Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k+1])
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k+1] ; 
			else
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg1[2*k] ;
		end
	end
	// stage3 
	for(k=0;k<4;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k] > Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k+1])
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k+1] ; 
			else
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg2[2*k] ;
		end
	end
	// stage4 
	for(k=0;k<2;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k] > Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k+1])
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k+1] ; 
			else
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4[k] <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg3[2*k] ;
		end
	end
	// stage5 
	for(k=0;k<1;k=k+1)
	begin
		always@(posedge clk)
		if(en)
		begin
			if(Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k] > Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k+1])
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg5  <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k+1] ; 
			else
				Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg5  <= Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg4[2*k] ;
		end
	end

endgenerate

assign Lr3PXplus1_Yminus1Di_min = Lr3PXplus1_Yminus1Di_2dArray_computeMin_temp_stg5;



/* ************  LineBuffers   *****************  */


pathAggLineBuffer  uR3   
		(
		    .clka  (clk),
		    .ena   (en & pixelEN),
		    .wea   (en & pixelEN),
		    .addra (BlkRamAddressA),
		    .dina  (Lr3PXminus1_YDi_1dArray_wire[511:0]),
		    .clkb  (clk),
		    .enb   (en & pixelEN),
		    .addrb (BlkRamAddressB),
		    .doutb (Lr3LineBufferOut[511:0])
		);









/**********************************************************************************************************
***********************************************************************************************************
						 Add 4 direction Lr0(P,Di) to get L(P,Di)
***********************************************************************************************************
************************************************************************************************************/
reg SOF_atPx_y_dly2_sclkrate ;
wire [8+2-1:0] add4Path [0:MAXDISPARITY-1] ;
always @(posedge clk )    // multicycle constrain , for 640*480 60frame/sec pixelEN ~= 20M 
if(en && pixelEN)
begin 
	for(i = 0 ; i < MAXDISPARITY ; i= i + 1)
	begin 
		LPDi_2DArray_reg_sclkrate[i] <=   add4Path[i][9:2] ;  // /2 
										  // + Lr2PXminus1_YDi_2DArray_Reg_sclkrate[i];  // add 4 direction , output Lr(p(x-1,y),Di), delay one clock to better meet timing , not output Lr(p(x,y),Di)
	end
	SOF_atPx_y_dly2_sclkrate <= SOF_atPx_y_dly;
end

generate 
for (k = 0; k < MAXDISPARITY; k=k+1) begin
	assign LPDi[(k+1)*LPDI_WIDTH-1:k*LPDI_WIDTH] = LPDi_2DArray_reg_sclkrate[k] ;
	assign add4Path[k] = Lr0PXminus1_YDi_2DArray_Reg_sclkrate[k] + Lr1PXminus1_YDi_2DArray_Reg_sclkrate[k] + 
					     Lr2PXminus1_YDi_2DArray_Reg_sclkrate[k] + Lr3PXminus1_YDi_2DArray_Reg_sclkrate[k] ;
end
endgenerate

assign LPDi[OUTPUTDATAWID-1] = SOF_atPx_y_dly2_sclkrate ;



endmodule