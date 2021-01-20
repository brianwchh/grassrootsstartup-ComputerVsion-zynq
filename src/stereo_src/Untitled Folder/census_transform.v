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
	input data : 32bit , image format 8-bit grayscale 
*/
`timescale 1 ns / 1 ps
module census_transform
#(
	parameter  IMAGE_WIDTH = 640 ,
	parameter  IMAGE_HEIGHT = 480 ,
	parameter  BUSDATAWID = 9 ,         // MSB = SOF
	parameter  LINEBUFFERLEN =  640 ,   // 640 byte
	parameter  OUTPUTDATAWID = 63       // MSB = SOF 
  )
(
	input wire                   clk                ,   // 150 Clock
	input wire                   en                 ,
	input wire[BUSDATAWID-1:0]   data_in            ,
	input wire                   sof_in             , 
	input wire                   eol_in             ,
	output wire                  sof_out            ,
	output wire                  eol_out            ,
	output wire[OUTPUTDATAWID-1:0]  data_out        ,   //  
	input  wire                  rst_n                  // Asynchronous reset active low
	
);



/*
	embed SOF_in in data_in flow, so that we do not need counting the delay mannually to sync the SOF pulse in every pipline stage  .
	during the streaming process, if we need access the pixel coordinates we can use the piplined version of the SOF to generate the coordinate-counter
  signal timing :                                                                the flow must not move here,otherwise timing will be incorrect !
            ______________________________________________________________________                             _______________
	EN  ___|                                                                      |______PIPLINE_PAUSE________|
            ______                                                 _______
 SOF_in ___|      |_______________________________________________|       |_____________________________________________________
                                                            ______
 EOL_in ___________________________________________________|      |___________________________
            ______ ______ ______ ______                     ______ _______ ___________________________________ ________ _______
data_in ....__D0__X__D1__X__D2__X______....................X_Deol_X__D0___X__D1_______________________________X__D2____X___D3__


                                 ______                                                                                      _______
SOF_out ________________________|      |____________________________________________________________________________________|       |_____________________________________________________
                                                                                                                      ______
EOL_out _____________________________________________________________________________________________________________|      |___________________________
                                 ______ ______ ______ ______              __________________________________________________ _______ ________ _______
data_out.._____________________..__D0__X__D1__X__D2__X______..............__Deol____________________________________________X__D1___X__D2____X___D3__

*/

                                     
/*
                                               ____                 ____        
                                              |    |               |    |       
	image_stream-----------------I(x+1,y+1)---|z-1 |---I(x,y+1)--->|z-1 |----o I(x-1,y+1) 
	               |                          |____|               |____|       
	               |
                  _|_ 
	             |   | 
	             | N |
	             |___|
				   |  LineBufferOutput[k-1]
				   |
                   |  matrixInput[k]          ____               ____       
                   |                         |    |             |    |       
                   |-------------I(x+1,y)----|z-1 |---I(x,y)--->|z-1 |----o I(x-1,y) 
                   |                         |____|             |____|       
                   |
                  _|_  LineBufferInput[k]
	             |   | 
	             | N |
	             |___|
				   |
				   |
                   |                           ____                 ____        
                   |                          |    |               |    |       
                   |-------------I(x+1,y-1)---|z-1 |---I(x,y-1)--->|z-1 |----o I(x-1,y-1) 
                   |                          |____|               |____|       
                   |

*/


// /******************  construct 9*7 census transform kernel    *****************************/
wire[BUSDATAWID-1:0] matrixInput [0:6]      ;   // relace this register array with dualport block ram 
wire[BUSDATAWID-1:0] LineBufferInput [0:6]      ;   // relace this register array with dualport block ram 
wire[BUSDATAWID-1:0] LineBufferOutput [0:6]      ;   // relace this register array with dualport block ram 
reg[9:0] BlkRamAddressA_sclkrate , BlkRamAddressB_sclkrate; 
reg[BUSDATAWID-1:0]  RegShiftArray9X7_sclkrate [0:6][0:8]  ;   // [row][col]
integer r , c , i, j; 

//  generate simple dualport block ram address 
wire[10:0] BlkRamAddressB_pre ;
assign BlkRamAddressB_pre = BlkRamAddressA_sclkrate +  3 ;   // the total read output delay is 2 clock cycles 
// porta address 
always @(posedge clk ) 
begin : BlockRamAddress
	if(~rst_n) begin
			BlkRamAddressA_sclkrate <= 0 ;
	end 
	else if(en) 
	begin
		if(BlkRamAddressA_sclkrate == LINEBUFFERLEN-1)
			BlkRamAddressA_sclkrate <= 0 ;
		else 
		 BlkRamAddressA_sclkrate <= BlkRamAddressA_sclkrate + 1'b1 ;

		if(BlkRamAddressB_pre > LINEBUFFERLEN -1) 
			BlkRamAddressB_sclkrate <= BlkRamAddressB_pre - LINEBUFFERLEN ;
		else 
			BlkRamAddressB_sclkrate <= BlkRamAddressB_pre[9:0] ;
	end
end
// // portb address 
// always@(*)
// begin
// 	BlkRamAddressB_pre = BlkRamAddressA_sclkrate +  2 ;   // the total read output delay is 2 clock cycles 
// 	if(BlkRamAddressB_pre >= LINEBUFFERLEN) 
// 		BlkRamAddressB_sclkrate = BlkRamAddressB_pre - LINEBUFFERLEN ;
// 	else 
// 		BlkRamAddressB_sclkrate = BlkRamAddressB_pre[9:0] ;
// end

/*   
                     ________ ________ __________ _______
	BlkRamAddressA_sclkrate   ___0____X___1____X_____2____X____3___
                     ________ ________ __________ _______
BlkRamAddressB_pre   ___3____X___4____X_____5____X____6___
                     ________ ________ __________ _______
	BlkRamAddressB_sclkrate   ___2____X___3____X_____4____X____5___


*/



//assign kernel matrix input 
assign LineBufferInput[0] = data_in ;
assign matrixInput[0] = data_in ;

genvar k;

generate
	for (k = 1; k < 6; k=k+1) 
		begin
			assign LineBufferInput[k] = LineBufferOutput[k-1] ;
		end

		for (k = 1; k < 7; k=k+1) 
		begin
			assign matrixInput[k] = LineBufferOutput[k-1] ;
		end
endgenerate

// linebuffers 
generate
  for (k = 0; k < 6; k = k + 1)
    begin
    	lineBuffer_censusTF  uLineBuffer
		(
		    .clka  (clk),
		    .ena   (en),
		    .wea   (en),
		    .addra (BlkRamAddressA_sclkrate),
		    .dina  (LineBufferInput[k]),
		    .clkb  (clk),
		    .enb   (en),
		    .addrb (BlkRamAddressB_sclkrate),
		    .doutb (LineBufferOutput[k])
		);
    end
endgenerate 

// shift data in matrix 
always@(posedge clk ) 
begin : kernel9x7_shift
	if(!rst_n)begin : reset 
		for(r=0; r<7; r=r+1)begin: rest_0
			RegShiftArray9X7_sclkrate[r][0] <= 0;
			for(c=1;c<9;c=c+1)begin    
				RegShiftArray9X7_sclkrate[r][c] <= 0 ;
			end
		end
	end
	else if(en) begin
		for(r=0; r<7; r=r+1)begin
			RegShiftArray9X7_sclkrate[r][0] <= matrixInput[r];   // first col of each row,  shift register array input 
			for(c=1;c<9;c=c+1)begin   // shift the registers by 1 
				RegShiftArray9X7_sclkrate[r][c] <= RegShiftArray9X7_sclkrate[r][c-1] ;
			end
		end
	end
end

/******************************  core process  **************************************************/
wire [7:0] CentralVal  ;   // P[4][2]
reg  CompareValue_sclkrate [0:63] ;    
reg  CentralBit_SOF_dly_sclkrate,SofOut_reg_sclkrate ;
reg[0:61] CensusTF_sclkrate;
wire CentralBit_SOF ;

assign CentralVal = RegShiftArray9X7_sclkrate[3][4][BUSDATAWID-1:0];  // exclude the SOF bit 
assign CentralBit_SOF = RegShiftArray9X7_sclkrate[3][4][BUSDATAWID-1];  //  the SOF bit 


// /* pixel coordinates counter, used for boundery detection and processing
//   					 _____
// CentralBit_SOF ______|     |________________
//                ______ _____ _____ ____
// 	colCnt     ______X__0__X__1__x____
// 	           ______ ______________
// 	rowCnt     ______X__0______

//  */
// reg[9:0] colCnt, rowCnt;
// always@(posedge clk)
// if(!rst_n)
// begin
// 	colCnt<=0;
// 	rowCnt<=0;
// end
// else if(en) begin
// 	if(CentralBit_SOF)
// 	begin
// 		colCnt <= 1 ;
// 		rowCnt <= 0 ;
// 	end
// 	else begin 
// 		if(colCnt == IMAGE_WIDTH -1)
// 			colCnt <= 0 ;
// 		else
// 			colCnt <= colCnt + 1'b1;
// 		if(rowCnt == IMAGE_HEIGHT-1 && colCnt == IMAGE_WIDTH -1) 
// 		begin
// 			rowCnt <= 0 ;
// 		end
// 		else if(colCnt == IMAGE_WIDTH -1) begin
// 			rowCnt <= rowCnt + 1'b1 ;
// 		end
// 	end
// end

/*                    _____
	SofOut_reg_sclkrate ______|     |________________
               ______ _____ _____ ____
	CensusTF_sclkrate   ______X__0__X__1__x____
*/


// parallel compare to the central value to caculate the census transform output 
genvar row , col ;
generate
	for (row = 0; row < 7; row=row+1) begin
		for (col = 0; col < 9; col=col+1) begin
			// if(r!=3 && c !=4 )  // this is problematic , pay attention to it ,should be if((r!=3)&&(c!=4))
			always@(posedge clk)
			if(en)
			begin : parallel_compare_to_central_value
				if(CentralVal > RegShiftArray9X7_sclkrate[row][col][BUSDATAWID-1:0])    // campare to sorrounding values
					CompareValue_sclkrate[row*9+col] <= 1'b1 ;
				else 
					CompareValue_sclkrate[row*9+col] <= 1'b0 ;
			end
		end
	end
endgenerate

generate 
	for(k=0; k<64; k=k+1)
	begin
		if(k<31)
		begin
			always@(posedge clk)
			if(en)
			begin
				CensusTF_sclkrate[k] <= CompareValue_sclkrate[k];
			end
		end
		else begin
			always@(posedge clk)
			if(en)
			begin
				CensusTF_sclkrate[k] <= CompareValue_sclkrate[k+1];
			end
		end
	end
endgenerate



always@(posedge clk)
if(en)
begin
	CentralBit_SOF_dly_sclkrate <= CentralBit_SOF ;   // it must be the SOF in the current central position
	SofOut_reg_sclkrate         <= CentralBit_SOF_dly_sclkrate ; 	
end


// always@(posedge clk)
// if(en)  // en controls the pipline flow
// begin:parallel_compare_to_central_value
	// for (r = 0; r < 7; r=r+1) begin
	// 	for (c = 0; c < 9; c=c+1) begin
	// 		// if(r!=3 && c !=4 )  // this is problematic , pay attention to it ,should be if((r!=3)&&(c!=4))
	// 		begin
	// 			if(CentralVal > RegShiftArray9X7_sclkrate[r][c][BUSDATAWID-1:0])    // campare to sorrounding values
	// 				CompareValue_sclkrate[r*9+c] <= 1'b1 ;
	// 			else 
	// 				CompareValue_sclkrate[r*9+c] <= 1'b0 ;
	// 		end
	// 	end
	// end
	// CentralBit_SOF_dly_sclkrate <= CentralBit_SOF ;   // it must be the SOF in the current central position
	// SofOut_reg_sclkrate <= CentralBit_SOF_dly_sclkrate ; 
	// asign comapred value to census transform, do not include the central point, which is P[3][4]
	// for(i=0;i<62;i=i+1)
	// begin
	// 	if(i<31)
	// 	begin
 // 			CensusTF_sclkrate[i] <= CompareValue_sclkrate[i];
	// 	end
	// 	else begin
	// 		CensusTF_sclkrate[i] <= CompareValue_sclkrate[i+1];
	// 	end
	// end
// end 

// endgenerate

// TODO : take boundery condition into account 


assign data_out = {SofOut_reg_sclkrate,CensusTF_sclkrate} ; 
assign sof_out  = SofOut_reg_sclkrate ;


endmodule