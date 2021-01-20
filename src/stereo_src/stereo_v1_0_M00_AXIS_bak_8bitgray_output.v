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



// `timescale 1 ns / 1 ps

// 	module stereo_v1_0_M00_AXIS #
// 	(
// 		// Users to add parameters here
// 		parameter STREAM_DATA_WIDTH = 9 ,
// 		// User parameters ends
// 		// Do not modify the parameters beyond this line
// 		parameter IMAGE_WIDTH = 11'd640 ,    // 640/4
// 		// Width of S_AXIS address bus. The slave accepts the read and write addresses of width C_M_AXIS_TDATA_WIDTH.
// 		parameter integer C_M_AXIS_TDATA_WIDTH	= 32,
// 		// Start count is the numeber of clock cycles the master will wait before initiating/issuing any transaction.
// 		parameter integer C_M_START_COUNT	= 32
// 	)
// 	(
// 		// Users to add ports here
// 		(* MARK_DEBUG="true" *) input  wire [STREAM_DATA_WIDTH-1:0]    INPUT_STREAM ,
// 		(* MARK_DEBUG="true" *) input  wire                            INPUT_STREAM_VALID ,  
// 		output wire                           WRITE_FIFO_FULL ,     // must stop pipline 
// 		input wire                            PIXEL_EN    ,   
// 		input wire                            EN          ,    // EN = 1'b1 if writingFIFO is not full && readingFIFO is not empty   
// 		input wire                            READ_PIXEL_EN ,                

// 		// User ports ends
// 		// Do not modify the ports beyond this line

// 		// Global ports
// 		input wire  M_AXIS_ACLK,
// 		// 
// 		input wire  M_AXIS_ARESETN,
// 		// Master Stream Ports. TVALID indicates that the master is driving a valid transfer, A transfer takes place when both TVALID and TREADY are asserted. 
// 		output wire  M_AXIS_TVALID,
// 		// TDATA is the primary payload that is used to provide the data that is passing across the interface from the master.
// 		output wire [C_M_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA,
// 		// TSTRB is the byte qualifier that indicates whether the content of the associated byte of TDATA is processed as a data byte or a position byte.
// 		output wire [0 : 0] M_AXIS_TUSER,
// 		// TLAST indicates the boundary of a packet.
// 		output wire [3:0] M_AXIS_TSTRB ,
// 		output wire  M_AXIS_TLAST,
// 		// TREADY indicates that the slave can accept a transfer in the current cycle.
// 		input wire  M_AXIS_TREADY
// 	);

       
// 	                                    __________________________
// 	INPUT_STREAM_VALID ________________|
// 	                ___________________ ______ ______ _______ _______
// 	INPUT_STREAM   ____////////////////X__0___X__1___X___2___X___3___  

//                                          _______
// 	write_fifo_is_full          ________|       |________________________________________________
// 	                            ________                  ________
// 	write_fifo_wren                     |________________|        |_________________
//                                          _______          ________
// 	PIXEL_EN                    ________|       |________|        |________________________________________

//                                     __    __    ___                             ___     ___     ___
// 	clk                         ___|  |__|  |__|   |___........................|   |___|   |___|   |___
//                                                                                 _______
// 	write_fifo_is_empty         ___ ___________________________________________|       |________________________________________________
//                                 ____________________________________________________________________         ________________________________________________
// 	M_AXIS_TREADY                                                                                   |_______|                                   (the slave is ready to accept data)
//                                 _______________________________________________         ____________         ____________________________________
// 	write_fifo_rd_en                                                           |_______|            |_______|                                     
//                                         _______________________________________________        _____________         _________________________  
// 	M_AXIS_TVALID                                                                      |______|             |_______|                          (1 clk delay)
//                                         _______________________________________________        _____________         _________________________  
// 	fifo_out                                                                           |______|             |_______|                          (1 clk delay)
//                                         _______________________________________________        _____________         _________________________  
// 	M_AXIS_TDATA                                                                       |______|             |_______|                          (1 clk delay)
//                                        ______                                    ______
// 	M_AXIS_TUSER                ______|      |__________________________________|      |_______________________________________________________
//                                 ______ ______ _____ _______ ___
// 	colCnt_reg                   _W-1_X__0___X__1__X___2___X___.........___W-1__X_____ 
//                                                                           ______
// 	M_AXIS_TLAST                _________________________________________|      |______________________







// 	//Total number of output data.
// 	// Total number of output data                                                 
// 	localparam NUMBER_OF_OUTPUT_WORDS = 8;                                               
	                                                                                     
// 	// function called clogb2 that returns an integer which has the                      
// 	// value of the ceiling of the log base 2.                                           
// 	function integer clogb2 (input integer bit_depth);                                   
// 	  begin                                                                              
// 	    for(clogb2=0; bit_depth>0; clogb2=clogb2+1)                                      
// 	      bit_depth = bit_depth >> 1;                                                    
// 	  end                                                                                
// 	endfunction                                                                          

// 	//streaming data valid
// 	wire  	axis_tvalid;
// 	//streaming data valid delayed by one clock cycle
// 	reg  	axis_tvalid_delay1;
// 	//Last of the streaming data 
// 	wire  	axis_tlast;
// 	//Last of the streaming data delayed by one clock cycle
// 	reg  	axis_tlast_delay;
// 	//FIFO implementation signals
// 	wire [C_M_AXIS_TDATA_WIDTH-1 : 0] 	stream_data_out;

// 	wire write_fifo_rd_en ;
// 	(* MARK_DEBUG="true" *)wire write_fifo_wren ;
// 	wire write_fifo_is_full ; 
// 	wire write_fifo_is_empty ;

// 	// I/O Connections assignments

// 	assign M_AXIS_TVALID	= axis_tvalid_delay1;
// 	assign M_AXIS_TSTRB	    = {(C_M_AXIS_TDATA_WIDTH/8){1'b1}};

// 	assign WRITE_FIFO_FULL = write_fifo_is_full ;

// 	// Add user logic here

// 	wire [35:0] fifo_out ; 
// 	wire [31:0] stream_data_to_ddr ; 
// 	(* MARK_DEBUG="true" *)reg [10:0]  colCnt_reg ; 

// 	// assign stream_data_to_ddr[7:0] =    fifo_out[7:0] ;      // 0-8
// 	// assign stream_data_to_ddr[15:8] =   fifo_out[16:9] ;    // 9-17
// 	// assign stream_data_to_ddr[23:16] =  fifo_out[25:18] ;  // 18-26
// 	// assign stream_data_to_ddr[31:24] =  fifo_out[34:27] ;  // 27-35   ------> [31:0] :  {image[0],image[1],image[2],image[3]}

// 	wire [7:0] image_data_0 , image_data_1, image_data_2, image_data_3;
// 	assign image_data_0 = fifo_out[7:0] ;
// 	assign image_data_1 = fifo_out[16:9] ;
// 	assign image_data_2 = fifo_out[25:18] ;
// 	assign image_data_3 = fifo_out[34:27] ;

// 	assign stream_data_to_ddr[7:0] =    image_data_0 ;      // 0-8
// 	assign stream_data_to_ddr[15:8] =   image_data_1 ;    // 9-17
// 	assign stream_data_to_ddr[23:16] =  image_data_2 ;  // 18-26
// 	assign stream_data_to_ddr[31:24] =  image_data_3 ;  // 27-35

// 	assign M_AXIS_TUSER = ( fifo_out[35] && M_AXIS_TVALID && READ_PIXEL_EN );   // this assumes image stride is multiple of 32-bits 

// 	assign M_AXIS_TDATA = stream_data_to_ddr ;
// 	assign M_AXIS_TLAST = ((colCnt_reg==IMAGE_WIDTH/4-1) && M_AXIS_TVALID && READ_PIXEL_EN ) ;


// 	wire [10:0] colCnt_reg_wire ; 

// 	assign colCnt_reg_wire = (M_AXIS_TUSER )? 11'd1 : (colCnt_reg==IMAGE_WIDTH/4-1) ? 11'd0 : colCnt_reg + 1'b1 ;

// 	always@(posedge M_AXIS_ACLK)
// 	if(write_fifo_rd_en == 1'b1)
// 	begin
// 		colCnt_reg <= colCnt_reg_wire ;
// 	end

// 	// always@(posedge M_AXIS_ACLK)
// 	// begin
// 	// 	if(M_AXIS_TUSER == 1'b1)  // start of frame 
// 	// 	begin  
// 	// 		colCnt_reg <= 1 ; 
// 	// 	end
// 	// 	else if(M_AXIS_TVALID) begin
// 	// 		if(colCnt_reg==IMAGE_WIDTH/4-1)
// 	// 			colCnt_reg <= 0 ;
// 	// 		else 
// 	// 			colCnt_reg <= colCnt_reg + 1'b1 ;
// 	// 	end
// 	// end

// 	// assign axis_tvalid = write_fifo_rd_en ;
// 	assign write_fifo_rd_en = M_AXIS_TREADY & (~write_fifo_is_empty) & READ_PIXEL_EN  ;   // when slave side is ready to revcieve data and fifo is not empty
// 																				      // start streaming data 
//     assign write_fifo_wren =  PIXEL_EN &  EN  & (~write_fifo_is_full) & INPUT_STREAM_VALID;


// 	always@(posedge M_AXIS_ACLK)
// 	if(READ_PIXEL_EN && M_AXIS_TREADY)
// 	begin
// 		axis_tvalid_delay1 <= write_fifo_rd_en ;
// 	end


// 	writeStreamFIFO u_writeFIFO  // read output delay 1 clock cycle 
//    (
//     	.clk 	(M_AXIS_ACLK),
//     	.srst 	(~M_AXIS_ARESETN),
//     	.din 	(INPUT_STREAM),
//     	.wr_en 	(write_fifo_wren),
//     	.rd_en 	(write_fifo_rd_en),
//     	.dout 	(fifo_out),
//     	.prog_full  (write_fifo_is_full ) ,
//     	.prog_empty (write_fifo_is_empty) ,
//     	.full 	(),
//     	.empty 	()
//    );





//	// /******************************** fifo part********************************************/
//
//	// // generate fifo address 
//	// reg[8:0] read_address ;
//	// wire [9:0] read_address_pre , read_address_wire ;
//	// reg[10:0] write_address ;
//	// wire[11:0] write_address_pre , write_address_wire; 
//	// reg readRunCnt , writeRunCnt ;
//	// wire  readRunCnt_wire , writeRunCnt_wire ;
//
//
//	// wire [11:0] write_address_pre_minus_fifoLEN = write_address_pre - 2048 ;
//	// assign write_address_pre = (write_fifo_is_full)? write_address : write_address + 1'b1 ;
//	// assign write_address_wire = (write_address_pre_minus_fifoLEN[11]==1'b0) ? write_address_pre_minus_fifoLEN : write_address_pre ;  // if write_address_pre >= 2048
//
//	// wire [9:0] read_address_pre_minus_fifoLEN = read_address_pre - 512 ;
//	// assign read_address_pre = (write_fifo_is_empty)? read_address : read_address + 1'b1 ;
//	// assign read_address_wire = (read_address_pre_minus_fifoLEN == 1'b0) ? read_address_pre_minus_fifoLEN : read_address_pre ;
//
//	// assign readRunCnt_wire = (read_address_pre_minus_fifoLEN == 1'b0) ? ~readRunCnt  : readRunCnt ;
//	// assign writeRunCnt_wire = (write_address_pre_minus_fifoLEN == 1'b0) ? ~writeRunCnt  : writeRunCnt ;
//
//	// // fifo full and fifo empty genreation 
//	// always@(posedge M_AXIS_ACLK)
//	// if(!M_AXIS_ARESETN)
//	// begin
//	// 	readRunCnt <= 0 ;
//	// end
//	// else if (PIXEL_EN) 
//	// begin
//	// 	readRunCnt <= readRunCnt_wire ;
//	// end
//
//	// always@(posedge M_AXIS_ACLK)
//	// if(!M_AXIS_ARESETN)
//	// begin
//	// 	writeRunCnt <= 0 ;
//	// end
//	// else if (READ_PIXEL_EN) 
//	// begin
//	// 	writeRunCnt <= writeRunCnt_wire ;
//	// end
//
//
//	// assign write_fifo_is_empty = ((readRunCnt  == writeRunCnt ) && (read_address == write_address[10:2]));  // read catch up write in the same run 
//	// assign write_fifo_is_full =  ((readRunCnt  != writeRunCnt ) && (read_address == write_address[10:2]));   // write catch up read , ahead of 1 run
//
//
//	// always@(posedge M_AXIS_ACLK)  // write address 
//	// if(!M_AXIS_ARESETN)
//	// begin
//	// 	write_address <= 0 ;
//	// end
//	// else if(PIXEL_EN)
//	// begin
//	// 	write_address <= write_address_wire[10:0] ;
//	// end
//
//
//	// always@(posedge M_AXIS_ACLK)  // read address 
//	// if(!M_AXIS_ARESETN) 
//	// begin
//	// 	read_address <= 0 ;
//	// end
//	// else if(READ_PIXEL_EN) 
//	// begin
//	// 	read_address <= read_address_wire[9:0] ;
//	// end
//
//
//	// writeStreamFIFO u_writeFIFO  // read latency = 2 clock cycles 
//	// (
//	//     .clka 	(M_AXIS_ACLK),
//	//     .ena 	(1'b1),
//	//     .wea 	(write_fifo_wren),
//	//     .addra 	(write_address),
//	//     .dina 	(INPUT_STREAM),
//	//     .clkb 	(M_AXIS_ACLK),
//	//     .enb 	(write_fifo_rd_en),
//	//     .addrb 	(read_address),
//	//     .doutb 	(fifo_out)
// //  	);

	// endmodule



`timescale 1 ns / 1 ps

	module stereo_v1_0_M00_AXIS #
	(
		// Users to add parameters here
		parameter STREAM_DATA_WIDTH = 9 ,
		// User parameters ends
		// Do not modify the parameters beyond this line
		parameter IMAGE_WIDTH = 11'd640 ,    // 640/4
		// Width of S_AXIS address bus. The slave accepts the read and write addresses of width C_M_AXIS_TDATA_WIDTH.
		parameter integer C_M_AXIS_TDATA_WIDTH	= 32,
		// Start count is the numeber of clock cycles the master will wait before initiating/issuing any transaction.
		parameter integer C_M_START_COUNT	= 32
	)
	(
		// Users to add ports here
		(* MARK_DEBUG="true" *) input  wire [STREAM_DATA_WIDTH-1:0]    INPUT_STREAM ,
		(* MARK_DEBUG="true" *) input  wire                            INPUT_STREAM_VALID ,  
		output wire                           WRITE_FIFO_FULL ,     // must stop pipline 
		input wire                            PIXEL_EN    ,   
		input wire                            EN          ,    // EN = 1'b1 if writingFIFO is not full && readingFIFO is not empty   
		input wire                            READ_PIXEL_EN ,                

		// User ports ends
		// Do not modify the ports beyond this line

		// Global ports
		input wire  M_AXIS_ACLK,
		// 
		input wire  M_AXIS_ARESETN,
		// Master Stream Ports. TVALID indicates that the master is driving a valid transfer, A transfer takes place when both TVALID and TREADY are asserted. 
		output wire  M_AXIS_TVALID,
		// TDATA is the primary payload that is used to provide the data that is passing across the interface from the master.
		output wire [C_M_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA,
		// TSTRB is the byte qualifier that indicates whether the content of the associated byte of TDATA is processed as a data byte or a position byte.
		output wire [0 : 0] M_AXIS_TUSER,
		// TLAST indicates the boundary of a packet.
		output wire [3:0] M_AXIS_TSTRB ,
		output wire  M_AXIS_TLAST,
		// TREADY indicates that the slave can accept a transfer in the current cycle.
		input wire  M_AXIS_TREADY
	);

/*       
	                                    __________________________
	INPUT_STREAM_VALID ________________|
	                ___________________ ______ ______ _______ _______
	INPUT_STREAM   ____////////////////X__0___X__1___X___2___X___3___  

                                         _______
	write_fifo_is_full          ________|       |________________________________________________
	                            ________                  ________
	write_fifo_wren                     |________________|        |_________________
                                         _______          ________
	PIXEL_EN                    ________|       |________|        |________________________________________

                                    __    __    ___                             ___     ___     ___
	clk                         ___|  |__|  |__|   |___........................|   |___|   |___|   |___
                                                                                _______
	write_fifo_is_empty         ___ ___________________________________________|       |________________________________________________
                                ____________________________________________________________________         ________________________________________________
	M_AXIS_TREADY                                                                                   |_______|                                   (the slave is ready to accept data)
                                _______________________________________________         ____________         ____________________________________
	write_fifo_rd_en                                                           |_______|            |_______|                                     
                                        _______________________________________________        _____________         _________________________  
	M_AXIS_TVALID                                                                      |______|             |_______|                          (1 clk delay)
                                        _______________________________________________        _____________         _________________________  
	fifo_out                                                                           |______|             |_______|                          (1 clk delay)
                                        _______________________________________________        _____________         _________________________  
	M_AXIS_TDATA                                                                       |______|             |_______|                          (1 clk delay)
                                       ______                                    ______
	M_AXIS_TUSER                ______|      |__________________________________|      |_______________________________________________________
                                ______ ______ _____ _______ ___
	colCnt_reg                   _W-1_X__0___X__1__X___2___X___.........___W-1__X_____ 
                                                                          ______
	M_AXIS_TLAST                _________________________________________|      |______________________

*/

                                                                    

	//streaming data valid
	wire  	axis_tvalid;
	//streaming data valid delayed by one clock cycle
	reg  	axis_tvalid_delay1;
	//Last of the streaming data 
	wire  	axis_tlast;
	//Last of the streaming data delayed by one clock cycle
	reg  	axis_tlast_delay;
	//FIFO implementation signals
	wire [C_M_AXIS_TDATA_WIDTH-1 : 0] 	stream_data_out;

	wire write_fifo_rd_en ;
	(* MARK_DEBUG="true" *)wire write_fifo_wren ;
	wire write_fifo_is_full ; 
	wire write_fifo_is_empty ;

	(* MARK_DEBUG="true" *)reg[1:0] pixel_en_div4_cnt = 0;
	wire sof_in_input_stream  ;

	// I/O Connections assignments

	assign M_AXIS_TSTRB	    = {(C_M_AXIS_TDATA_WIDTH/8){1'b1}};

	assign WRITE_FIFO_FULL = write_fifo_is_full ;

	// Add user logic here

	(* MARK_DEBUG="true" *)wire [32:0] fifo_out ; 
	(* MARK_DEBUG="true" *)reg [10:0]  colCnt_reg ; 

	// assign stream_data_to_ddr[7:0] =    fifo_out[7:0] ;      // 0-8
	// assign stream_data_to_ddr[15:8] =   fifo_out[16:9] ;    // 9-17
	// assign stream_data_to_ddr[23:16] =  fifo_out[25:18] ;  // 18-26
	// assign stream_data_to_ddr[31:24] =  fifo_out[34:27] ;  // 27-35   ------> [31:0] :  {image[0],image[1],image[2],image[3]}


	// always@(posedge M_AXIS_ACLK)
	// begin
	// 	if(M_AXIS_TUSER == 1'b1)  // start of frame 
	// 	begin  
	// 		colCnt_reg <= 1 ; 
	// 	end
	// 	else if(M_AXIS_TVALID) begin
	// 		if(colCnt_reg==IMAGE_WIDTH/4-1)
	// 			colCnt_reg <= 0 ;
	// 		else 
	// 			colCnt_reg <= colCnt_reg + 1'b1 ;
	// 	end
	// end

																				      // start streaming data

	/*
		* output interface :  
		when tready == 0 , keep tvalid unchaged , and keep data unchanged, so when tready is asserted , the slave can 
		take the value immediately .  if(ready == 1'b1) begin valid <= 1'b1; data <= data + 1; end else begin valid <= valid; data <= data; end 
		when fifo is empty , set tvalid for one more clock 
                                               __________________________
		write_fifo_is_empty  _________________|                          |_____________________
                            __________________                                    _________
		write_fifo_rd_en                      |__________________________________|
							______ ____ ___ __ _______________________________________ _______ ______ _______
		fifo_out             _____X____X___X__X____________keep unchaged______________X_______X______X______
							________________________                                   _______________________________
		M_AXIS_TVALID                               |_________________________________|  keep unchanged when tready is low
							_____________________all 1_______________              _____________
		M_AXIS_TREADY                                                |____________|
	*/

	wire tvalid_wire ;
	reg  tvalid_reg ;
	// generate tvalid signal 
	always@(posedge M_AXIS_ACLK)   // at clk rate , keep in mind fifo is 1 clock cycle read delay
	begin
		if((~write_fifo_is_empty) &&  M_AXIS_TREADY )
		begin
			tvalid_reg <= 1'b1 ;   
		end
		else if (write_fifo_is_empty) begin
			tvalid_reg <= 1'b0 ;   // when fifo is empty , should never sent data later , data keep unchanged
		end
		else begin
			tvalid_reg <= tvalid_reg ;
		end
	end

	assign M_AXIS_TVALID = tvalid_reg ;   // valid signal can stay high even when tready is low , 
										  // but write_fifo_rd_en must stay low , when tready stay low 
	//generate fifo read signal 
	assign write_fifo_rd_en = M_AXIS_TREADY & (~write_fifo_is_empty)   ;   // when slave side is ready to revcieve data and fifo is not empty


	// start counter at recieving sof , match sof with counter , if not match ,report system timing error 
	wire [10:0] colCnt_reg_wire ; 

	assign colCnt_reg_wire = (M_AXIS_TUSER )? 11'd1 : (colCnt_reg==IMAGE_WIDTH/4-1) ? 11'd0 : colCnt_reg + 1'b1 ;

	always@(posedge M_AXIS_ACLK)
	if(write_fifo_rd_en == 1'b1)   // counting the pulse of write_fifo_rd_en not tvalid
	begin
		colCnt_reg <= colCnt_reg_wire ;
	end
	else begin
		colCnt_reg <= colCnt_reg ;
	end

	// generate M_AXIS_TLAST  M_AXIS_TUSER  M_AXIS_TDATA signal from the counter 
	assign M_AXIS_TUSER =  fifo_out[32] ;   // this assumes image stride is multiple of 32-bits 
	assign M_AXIS_TDATA = fifo_out[31:0] ;
	assign M_AXIS_TLAST = (colCnt_reg==IMAGE_WIDTH/4-1) ;   // keep high if colCnt_reg don't count , so it is not a pixecl clock wide pulse 

	/*
		* input interface 
		start the write counter at recieving sof in the data stream . collect 4 byte data , make sure sof is at the MSB , if not 
		left shift to make so ,and campare to cnter to make sure the whole word count matches , if not pad zeros at the end , to avoid 
		system timging error , meanwhile , generate a interupt to notify system error in image timing .

	*/

	//1. generate 4byte clock 
	(* MARK_DEBUG="true" *)wire pixel_en_div4_wire ; 
	always@(posedge M_AXIS_ACLK)
	if(~M_AXIS_ARESETN)
	begin
		pixel_en_div4_cnt <= 0 ;
	end
	else if(PIXEL_EN && EN ) begin
		if(sof_in_input_stream==1'b1)
			pixel_en_div4_cnt <= 0 ;		
		else 
			pixel_en_div4_cnt <= pixel_en_div4_cnt + 1'b1 ;		
	end
	assign pixel_en_div4_wire = ((pixel_en_div4_cnt == 2'b00) && EN) ;


	// detect sof from input stream , collect 4 byte-stream data to form a word-stream , with sof-data in MSB 
	assign sof_in_input_stream = INPUT_STREAM[8] ;
	(* MARK_DEBUG="true" *)reg [7:0] data_collect [0:3] ; 
	reg [8:0] stream_dely1 ;
	reg sof_delay1;
	(* MARK_DEBUG="true" *)reg [32:0] data_to_fifo_reg ;
	always@(posedge M_AXIS_ACLK)
	if(PIXEL_EN && EN )
	begin
		stream_dely1 <= INPUT_STREAM ;     // data delay 1 clock to align with pixel_en_div4_cnt
		data_collect[pixel_en_div4_cnt] <= stream_dely1[7:0] ;
		if(pixel_en_div4_wire)
		begin
			data_to_fifo_reg <= {sof_delay1,data_collect[0],data_collect[1],data_collect[2],data_collect[3]} ;
		end
		else begin
			data_to_fifo_reg <=  data_to_fifo_reg ;
		end

		if(pixel_en_div4_wire == 1'b1) // pixel_en_div4_wire is alined with pixel_en_div4_cnt
		begin
			sof_delay1 <= stream_dely1[8] ;   // keep sof_delay1 for 1 pixel_en_div4_wire cycle, passing it from PIXEL_EN domain to pixel_en_div4_wire domain
		end
		else begin
			sof_delay1 <= sof_delay1 ;
		end
	end

	assign write_fifo_wren =  pixel_en_div4_wire & PIXEL_EN;   // EN signal only controlls write , do not controlls read interface 

	writeStreamFIFO u_writeFIFO  // read output delay 1 clock cycle 
   (
    	.clk 	(M_AXIS_ACLK),
    	.rst 	(~M_AXIS_ARESETN),
    	.din 	(data_to_fifo_reg),
    	.wr_en 	(write_fifo_wren),
    	.rd_en 	(write_fifo_rd_en),
    	.dout 	(fifo_out),
    	.prog_full  (write_fifo_is_full ) ,
    	.prog_empty (write_fifo_is_empty) ,
    	.full 	(),
    	.empty 	()
   );


endmodule