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

`timescale 1 ns / 1 ps

	module stereo_v1_0_S00_AXIS #
	(
		// Users to add parameters here
		parameter integer STREAM_WIDTH = 18 ,
		// User parameters ends
		// Do not modify the parameters beyond this line

		// AXI4Stream sink: Data Width
		parameter integer C_S_AXIS_TDATA_WIDTH	= 32
	)
	(
		// Users to add ports here
		output  wire[STREAM_WIDTH-1:0]    READFIFO_OUTPUT ,    // {sof, 8_bit_image_data}
		output  wire         READ_FIFO_EMPTY          , 
		input   wire         PIXEL_EN                 ,    // pixel clock  en 
		input   wire         EN                       ,  
		output wire          READFIFO_OUTPUT_VALID    ,
		input   wire         WRITE_FIFO_FULL          ,

		input  	wire         MCLK                     ,
		input   wire         CORE_RSTN                ,

		// User ports ends
		// Do not modify the ports beyond this line

		// AXI4Stream sink: Clock
		input wire  S_AXIS_ACLK,
		// AXI4Stream sink: Reset
		input wire  S_AXIS_ARESETN,
		// Ready to accept data in
		output wire  S_AXIS_TREADY,
		// Data in
		input wire [C_S_AXIS_TDATA_WIDTH-1 : 0]     S_AXIS_TDATA,
		// Byte qualifier
		input wire [0 : 0] S_AXIS_TUSER,
		// Indicates boundary of last packet
		input wire  S_AXIS_TLAST,
		// Data is in valid
		input wire  S_AXIS_TVALID
	);


/*
                                       ___________
                                      |           |
	------4-byte-image-data-------->  | ReadFIFO  | ------- READFIFO_OUTPUT ----> 
                <--------- FIFO-FULL--|           | ------ FIFO-EMPTY---------------->  must stop pipline flow
                                      |           | 
                                      |           |
                                      |           |
                                      |           |
                                      |           |
                                      |           |
                                      |           |
                                      |           |
                                      |___________|

	in order to make things simple , left and right image syned by using data rearragement in cpu . ie 
     _______________ _________________
	|_____left______|_______right_____|
     _______________ _________________
	|_____left______|_______right_____|
	 _______________ _________________
	|_____left______|_______right_____|
                                                                                __________
prog_full		_______________________________________________________________|          |________________

                                     slave is ready to accept stream
                         								______________________            __________________________
S_AXIS_TREADY             _____________________________|                      |__________|
                                                            _____________________________                    __________________
S_AXIS_TVALID          ____________________________________|                             |__________________|
                                                            ______ _______ _______ _________________________ ______ _______ _____
S_AXIS_TDATA            ///////////////////////////////////X___0__X___1___X___2___X_________3_______________X__4___X___5___X_____
                                                            _____________________________                    ___________________
fifo_wren                 _________________________________|                             |__________________|
                                                            ______
S_AXIS_TUSER            ___________________________________|      |___________________________________________________
                                   _________________________________
fifo_rd_en              __________|
                                           _________________________
READFIFO_OUTPUT_VALID ____________________|
                                           ______ _____ _____ ____
READFIFO_OUTPUT       ////////////////////X___0__X__1__X__2__X____
*/

	wire    read_fifo_full ; 
	wire axis_tready ;

	wire   fifo_wren ;
	wire   fifo_rd_en ;

	wire [9:0] rd_data_count ;
	wire [8:0] wr_data_count ;
	wire  prog_full ;
	wire  prog_empty ;
	wire  empty ;
	reg fifo_output_data_valid_reg ;
	wire [35:0] fifo_out ;
	reg[17:0] mutex_fifo_out_data_reg [0:1] ;
	reg[17:0] stream_to_stereo_reg ;

	reg sel_cnt = 0;
	wire read_32bit_en  ;

	                                    
	assign S_AXIS_TREADY	= ~prog_full;
	// reg PIXEL_EN_div2 =0 ;

	// FIFO write enable generation
	assign fifo_wren = S_AXIS_TVALID   &  S_AXIS_TREADY ;  // input data clk enable = clk rate 

	/*  * write interface  (fifo is full , stop accepting new data, data is still valid after the rising edge of prog_full)
                                             _______________________
		prog_full     ______________________|                       |________________
	                  ______________________                         _________________
		axis_tready                         |______= ~prog_full_____|
                      _____ _____ _____ ____ ____________________________ ________ ______________ _______ _______ ____
		S_AXIS_TDATA  _____X_____X_____X____X____________________________X________X_/////////////X_______X_______X___
                      ____________________________________________________________                ____________________
		axis_tvalid                                                               |______________|
                      ______________________                         _____________                _______________________
		fifo_wren                           |_______________________|             |______________|




		* read interface  (fifo is empty, due to 1 clock cycle read of block ram, data is still valid after the rising edge of prog_empty, so EN signal should be delayed by 1 clock)
		                                 _________________
		prog_empty  ____________________|                 |____________________________________________________
                    ____________________                   ________________                   __________________
		fifo_rd_en                      |_________________|                |_________________|
                                                                            _________________
	write_fifo_is_full ____________________________________________________|		         |_______________
                     ___________________                   ________________                   _______________
	write_fifo_wr_en                    |_________________|                |_________________|
					_____ ____ ____ ____ _______________________ __________ ________________________ _______ _______
		fifo_out    _____X____X____X____X______________________X___________X________________________X_______X______
                    ____________________                   ________________                    ___________________
		EN                              |_________________|                |__________________|
	*/


	// Add user logic here


	// ------------ debug section --------
	(* MARK_DEBUG="true" *)wire read_fifo_in_not_match_data ;
	(* MARK_DEBUG="true" *)reg[7:0] fifo_in_data_cnt ; 
	always@(posedge S_AXIS_ACLK)
	if(S_AXIS_TUSER)
	begin
		fifo_in_data_cnt <= 2 ;
	end
	else if(S_AXIS_TVALID && S_AXIS_TREADY)   
	begin
		if(S_AXIS_TLAST)
			fifo_in_data_cnt <= 0 ;
		else 
			fifo_in_data_cnt <= fifo_in_data_cnt + 2 ;
	end

	assign read_fifo_in_not_match_data = (S_AXIS_TVALID && S_AXIS_TREADY 
										  && (fifo_in_data_cnt != 0)     
										  && (fifo_in_data_cnt != S_AXIS_TDATA[31:24]) ) ? 1'b1 : 1'b0 ;



	/*
		S_AXIS_TDATA[31:0] = {left[0],right[0],left[1],right[1]}
		stream2FIFO[35:0]  = {S_AXIS_TUSER,right[0],S_AXIS_TUSER,left[0],1'b0,right[1],1'b0,left[1]}
	*/
	wire [35:0] stream2FIFO ; 
	assign stream2FIFO[STREAM_WIDTH-1:0] = {1'b0,S_AXIS_TDATA[7:0],1'b0,S_AXIS_TDATA[15:8]}   ;
	assign stream2FIFO[2*STREAM_WIDTH-1:STREAM_WIDTH]   = {S_AXIS_TUSER,S_AXIS_TDATA[23:16],S_AXIS_TUSER,S_AXIS_TDATA[31:24]} ;


	// EN = (~readFIFO_is_empty_dly1) & (~write_fifo_is_full)
	assign fifo_rd_en  = PIXEL_EN & read_32bit_en & (~WRITE_FIFO_FULL) & (~prog_empty) ;  // 4byte per read , if write fifo is full do not read, that's why EN is here 

	assign READ_FIFO_EMPTY = prog_empty ;   

	/* generate fetch data from fifo pulse .
		initialize the counter to 0 at recieving sof from fifo. 
		increment 1 when EN is enabled at pixel_en clock rate , 
		when the counter eqs 1 , generate a pulse when enable reading another 2-16bit words from fifo 
	 */

	 wire sof_from_fifo = fifo_out[35] ;
	 reg sof_from_fifo_dly1 =0; 

	 always@(posedge MCLK)
	 if(EN && PIXEL_EN)
	 begin
	 	sof_from_fifo_dly1 <= sof_from_fifo ;

	 	if((~sof_from_fifo_dly1) && sof_from_fifo) // sof rising edge 
	 		sel_cnt <= 0 ;
	 	else 
	 		sel_cnt <= ~ sel_cnt ;
	 end
	 assign read_32bit_en = sel_cnt ;


	// move 4 byte data from fifo at the PIXEL_EN_div2 rate , move 2 byte at PIXEL_EN rate 
	always@(posedge MCLK)
	if(PIXEL_EN && EN )   // read fifo is no empty  and write fifo is not full
	begin
		if(read_32bit_en == 1'b1)
		begin
			mutex_fifo_out_data_reg[0] <= fifo_out[35:18] ;
			mutex_fifo_out_data_reg[1] <= fifo_out[17:0]  ;
		end
		else begin
			mutex_fifo_out_data_reg[0] <= mutex_fifo_out_data_reg[0] ;
			mutex_fifo_out_data_reg[1] <= mutex_fifo_out_data_reg[1]  ;
		end
	end

	(* MARK_DEBUG="true" *)wire[7:0] byte0 =  fifo_out[7:0] ;      // 0-8
	(* MARK_DEBUG="true" *)wire[7:0] byte1 =  fifo_out[16:9] ;    // 9-17
	(* MARK_DEBUG="true" *)wire[7:0] byte2 =  fifo_out[25:18] ;  // 18-26
	(* MARK_DEBUG="true" *)wire[7:0] byte3 =  fifo_out[34:27] ;  // 27-35   ------> [31:0] :  {image[0],image[1],image[2],image[3]}


	always@(posedge MCLK)  // mutiplexing data 
	if(EN && PIXEL_EN)
	begin
		stream_to_stereo_reg <= mutex_fifo_out_data_reg [sel_cnt] ;       
	end

	assign READFIFO_OUTPUT = stream_to_stereo_reg ;

	(* MARK_DEBUG="true" *)wire [7:0] left_img  = stream_to_stereo_reg[7:0] ;
	(* MARK_DEBUG="true" *)wire [7:0] right_img = stream_to_stereo_reg[16:9] ;


	readStreamFIFO  u_readFIFO 
	(
        .rd_clk         (MCLK           ) ,
        .wr_clk         (S_AXIS_ACLK    ) ,
        .rst    		(~S_AXIS_ARESETN) ,
        .din    		(stream2FIFO) ,
        .wr_en 			(fifo_wren) ,
        .rd_en 			(fifo_rd_en) ,
        .dout 			(fifo_out) ,
        .full 			() ,
        .empty 			() , 
        .prog_full   	(prog_full),
    	.prog_empty  	(prog_empty)
  	);

	// User logic ends

	endmodule
