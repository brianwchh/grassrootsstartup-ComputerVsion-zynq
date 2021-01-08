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
		 input  wire [STREAM_DATA_WIDTH-1:0]    INPUT_STREAM ,
		 input  wire                            INPUT_STREAM_VALID ,  
		output wire                           WRITE_FIFO_FULL ,     // must stop pipline 
		input wire                            PIXEL_EN    ,   
		input wire                            EN          ,    // EN = 1'b1 if writingFIFO is not full && readingFIFO is not empty   
		input wire                            READ_PIXEL_EN ,   
		input wire                            MCLK ,
		input wire                            CORE_RSTN ,         
		input wire                            SHOW_COLOR_DEPTH ,    

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
	wire write_fifo_wren ;
	wire write_fifo_is_full ; 
	wire write_fifo_is_empty ;

	reg[1:0] pixel_en_div4_cnt = 0;
	wire sof_in_input_stream  ;

	// I/O Connections assignments

	assign M_AXIS_TSTRB	    = {(C_M_AXIS_TDATA_WIDTH/8){1'b1}};

	assign WRITE_FIFO_FULL = write_fifo_is_full ;

	// Add user logic here

	wire [32:0] fifo_out ; 
	reg [10:0]  colCnt_reg ; 

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
		write_fifo_is_empty  _________________|                          |___________________________________________
                            __________________                            ______________________                   _______________________
		write_fifo_rd_en                      |__________________________|                      |_________________|
							______ ____ ___ __ __________________________________ _______ ______ _______________________ _______ _______ ______
		fifo_out             _____X____X___X__X____________keep unchaged_________X_______X______X_______________________X_______X_______X______
							________________________                              _____________________________________________________________
		M_AXIS_TVALID                               |____________________________|                               
							_____________________all 1___________________________________________                  __________
		M_AXIS_TREADY                                                                            |________________|
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


	/*
		                      ________
		SOF    ______________|        |_________________________________
                              __________________________________
M_AXIS_TVALID  ///___________|
                      ______________________________________
M_AXIS_TREADY  ///___|
                              ________ __________ _______
colCnt_reg      /////////////X___0____X____1_____X______

	*/

	// start counter at recieving sof , match sof with counter , if not match ,report system timing error 
	wire [10:0] colCnt_reg_wire ; 

	assign colCnt_reg_wire = (M_AXIS_TUSER )? 11'd1 : (colCnt_reg==IMAGE_WIDTH-1) ? 11'd0 : colCnt_reg + 1'b1 ;

	always@(posedge M_AXIS_ACLK)
	if(M_AXIS_TVALID && M_AXIS_TREADY)   
	begin
		colCnt_reg <= colCnt_reg_wire ;
	end
	else begin
		colCnt_reg <= colCnt_reg ;
	end

	// ------------ debug section --------
	wire write_fifo_out_not_match_data ;
	reg write_fifo_out_not_match_data_reg ;
	reg[7:0] fifo_out_data_cnt ; 
	always@(posedge M_AXIS_ACLK)
	if(M_AXIS_TUSER)
	begin
		fifo_out_data_cnt <= 1 ;
	end
	else if(M_AXIS_TVALID && M_AXIS_TREADY)   
	begin
		if(M_AXIS_TLAST)
			fifo_out_data_cnt <= 0 ;
		else 
			fifo_out_data_cnt <= fifo_out_data_cnt + 1'b1 ;
	end

	always@(posedge M_AXIS_ACLK)
	begin
		write_fifo_out_not_match_data_reg <= (M_AXIS_TVALID && M_AXIS_TREADY && (fifo_out_data_cnt != 0) && (fifo_out_data_cnt != M_AXIS_TDATA[7:0]) ) ? 1'b1 : 1'b0 ;
	end
	assign write_fifo_out_not_match_data = write_fifo_out_not_match_data_reg ;

	// generate M_AXIS_TLAST  M_AXIS_TUSER  M_AXIS_TDATA signal from the counter 
	assign M_AXIS_TUSER =  fifo_out[32] ;   // this assumes image stride is multiple of 32-bits 
	assign M_AXIS_TDATA = fifo_out[31:0] ;
	assign M_AXIS_TLAST = (colCnt_reg==IMAGE_WIDTH-1) ;   // keep high if colCnt_reg don't count , so it is not a pixecl clock wide pulse 

	/*
		* input interface 
		start the write counter at recieving sof in the data stream . collect 4 byte data , make sure sof is at the MSB , if not 
		left shift to make so ,and campare to cnter to make sure the whole word count matches , if not pad zeros at the end , to avoid 
		system timging error , meanwhile , generate a interupt to notify system error in image timing .

	*/

	(* MARK_DEBUG="true" *)reg [10:0] col_cnt = 0 ;
	(* MARK_DEBUG="true" *)reg [10:0] row_cnt = 0 ;
	(* MARK_DEBUG="true" *)reg stream_timing_wrong = 0 ;
	
    always@(posedge MCLK)
    if(PIXEL_EN && EN && write_fifo_wren)
    begin
        if(sof_in_input_stream)  // start of frame 
        begin  
            col_cnt <= 1 ; 
            row_cnt <= 0 ;
        end
        else begin
            if(col_cnt== 640 -1 )
            begin
                col_cnt <= 0 ;

                if(row_cnt == 480 - 1)
                    row_cnt <= 0 ;
                else 
                    row_cnt <= row_cnt + 1'b1 ;
            end
            else 
                col_cnt <= col_cnt + 1'b1 ;
        end
    end

	always@(posedge MCLK)
	if(PIXEL_EN && EN && write_fifo_wren)
	begin 
		if((col_cnt == 0) && (row_cnt == 0) && (sof_in_input_stream ==0))
			stream_timing_wrong <= 1'b1 ;
		else 
			stream_timing_wrong <= 1'b0 ;
	end


	// detect sof from input stream , collect 4 byte-stream data to form a word-stream , with sof-data in MSB 
	assign sof_in_input_stream = INPUT_STREAM[8] ;
	reg [7:0] data_collect [0:3] ; 
	reg [8:0] stream_dely1 ;
	reg sof_delay1;
	wire [23:0] colorMapValueOut ;
	(* MARK_DEBUG="true" *)wire [32:0] data_to_fifo_wire ;
	assign data_to_fifo_wire[32] = sof_in_input_stream ;
	assign data_to_fifo_wire[31:0] = (SHOW_COLOR_DEPTH == 1'b1) ? {8'h00,colorMapValueOut} 
																: {8'h0,{INPUT_STREAM[5:0],2'b0},{INPUT_STREAM[5:0],2'b0},{INPUT_STREAM[5:0],2'b0}} ; 
	
	// assign data_to_fifo_wire[31:0] = {8'h0,{INPUT_STREAM[7:0]},{INPUT_STREAM[7:0]},{INPUT_STREAM[7:0]}} ; 


	/*
                             __            __
	pix_en           _______|  |__________|  |_________
                                ____________________
	fifo_is_full     __________|
                             __
	write_en         _______|  |_________________


	write_en = (~fifo_is_ful) & pix_en ;

	en = (~wirte_fifo_is_full) & (~read_fifo_is_empty) ;
		
	*/

	/*
                                       _______________________________________
	write_fifo_is_full _______________|                 read_fifo_is_empty    |_________________________
              _____ ______ ______ ____ _____ ________________________________________________ _______ ______ ___________
	data     ______X______X______X____X_____X________________________________________________X_______X______X___......
                       _____________________                                           ___________________
	EN                                      |_________________________________________|
                       _____________________                                           ___________________
	write_fifo_wen                          |_________________________________________|
                       _____________________                                           ___________________
	read_fifo_ren                           |_________________________________________|

*/


	assign write_fifo_wren =  EN & PIXEL_EN;   // EN signal only controlls write , do not controlls read interface 

	writeStreamFIFO u_writeFIFO  // read output delay 1 clock cycle 
   (
    	.rd_clk (M_AXIS_ACLK),
    	.wr_clk (MCLK) ,
    	.rst 	(~M_AXIS_ARESETN),
    	.din 	(data_to_fifo_wire),
    	.wr_en 	(write_fifo_wren),
    	.rd_en 	(write_fifo_rd_en),
    	.dout 	(fifo_out),
    	.full 	(),
    	.empty 	() ,
    	.prog_full   (write_fifo_is_full),
    	.prog_empty  (write_fifo_is_empty)
   );

// settle down within one pixel clock cycle , when pxiel_en is asserted , ramout is stable and is the current pixel vale
// MCLK is 8 times faster than pixel clock

// colorMapLut uColor
//   (
//     .clka 	(MCLK),  //: IN STD_LOGIC;
//     .ena 	(EN),  //: IN STD_LOGIC;
//     .wea 	(1'b0),  //: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
//     .addra 	({INPUT_STREAM[5:0],2'b0}),  //: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
//     .dina 	(),  //: IN STD_LOGIC_VECTOR(23 DOWNTO 0);
//     .douta 	(colorMapValueOut)   //: OUT STD_LOGIC_VECTOR(23 DOWNTO 0)
//   );
 
endmodule 