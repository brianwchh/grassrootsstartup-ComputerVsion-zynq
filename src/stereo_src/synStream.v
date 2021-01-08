module synStream #
(
	// Users to add parameters here
	// User parameters ends
	// Do not modify the parameters beyond this line

	// AXI4Stream sink: Data Width
	parameter IMAGE_WIDTH = 640    ,
	parameter  IMAGE_HEIGHT  = 480 ,
	parameter integer C_S_AXIS_TDATA_WIDTH	= 32
)
(
	// Users to add ports here
	input   wire         PIXEL_EN                 ,    // pixel clock  en 
	input   wire         EN                       ,  


	input  	wire         MCLK                     ,
	input   wire         CORE_RSTN                ,
	input   wire         WRITE_FIFO_FULL          ,
	output  wire         inStreamIsSynedAndFifoIsNotEmpty ,

	// User ports ends
	// Do not modify the ports beyond this line

	/*********** left stream interface *****************/
	// AXI4Stream sink: Clock
	input wire  S_AXIS_ACLK_LEFT,
	// AXI4Stream sink: Reset
	input wire  S_AXIS_ARESETN_LEFT,
	// Ready to accept data in
	output wire  S_AXIS_TREADY_LEFT,
	// Data in
	input wire [C_S_AXIS_TDATA_WIDTH-1 : 0]     S_AXIS_TDATA_LEFT,
	// Byte qualifier
	input wire [0 : 0] S_AXIS_TUSER_LEFT,
	// Indicates boundary of last packet
	input wire  S_AXIS_TLAST_LEFT,
	// Data is in valid
	input wire  S_AXIS_TVALID_LEFT ,


	/***************** right stream interface *************/
	// AXI4Stream sink: Clock
	input wire  S_AXIS_ACLK_RIGHT,
	// AXI4Stream sink: Reset
	input wire  S_AXIS_ARESETN_RIGHT,
	// Ready to accept data in
	output wire  S_AXIS_TREADY_RIGHT,
	// Data in
	input wire [C_S_AXIS_TDATA_WIDTH-1 : 0]     S_AXIS_TDATA_RIGHT,
	// Byte qualifier
	input wire [0 : 0] S_AXIS_TUSER_RIGHT,
	// Indicates boundary of last packet
	input wire  S_AXIS_TLAST_RIGHT,
	// Data is in valid
	input wire  S_AXIS_TVALID_RIGHT ,

	/******************output stream *********************************/

	output wire  stream_not_syn_wire   , 

	output reg[24+1-1:0] left_stream_sofRGB ,
	output reg[24+1-1:0] right_stream_sofRGB 

);

initial begin
	left_stream_sofRGB  = 0 ;
	right_stream_sofRGB = 0 ;
end

/*

	camera stream data to DDR should be minimal delay, so it should be directly stored to frame buffers . 
	then we fetech data from frame buffers and synchronize them with 2 deep fifos . this is the method for the time being, 
	in the next updated version, I should rewrite the capture module and try to synchronize the input data stream at that level , so that 
	I can remove the frame buffers in DDR, and directly stream the sychronized video streams to stereo IP . 


	data flow for the time being : 
     ____           ____________
    |    |         |            |               ___________
	|ISP0|-------> |            |              |           |
    |____|         |            | -----------> |           |
                   |            |              |           |
     ____          | DDR        |              | synStream |
    |    |         |            |              |           |
	|ISP1|-------> |            | -----------> |           |
    |____|         |            |              |___________|
                   |____________|


	data flow for next version : 

     ____           ____________
    |    |         |            |  
	|ISP0|-------> |            |  
    |____|         |            |  
                   |            |  
     ____          | synStream  |  
    |    |         |            |  
	|ISP1|-------> |            |  
    |____|         |            |  
                   |____________|

	


	state machine : 
	                                                          _________________________________both sof detected simultanously _________________
                                                             |                                                                                  |
                                                             |                                                                                 \|/
     ________                                                |        ________________________                                        __________________
	|        |                                               |       |                        |                                      |                  |
	|state 0 |-------------------receive sof from stream0/1--------->| wait for the other sof |--------- the other sof arrived ----->|start transmiting |
	|Idle    |                                                       |                        |                                      |                  |
	|________|                                                       |________________________|                                      |__________________|
        /|\                                                                                                                                    |
         |                                                                                                                                     |
         |                                                                                                                                      |
	     ----------------------------------------------------------lose syn -------------------------------------------------------------------


                         ________
						|        |
	  fifo_ren	------- |        |-------- fifo_wen 
	  fifo_rData -----	| FIFO_0 |-------- fifo_wData
	  fifo_is_empty---- |        |-------- fifo_is_full 
						|________|


                         ________
						|        |
	  fifo_ren	------- |        |-------- fifo_wen 
	  fifo_rData -----	| FIFO_1 |-------- fifo_wData
	  fifo_is_empty---- |        |-------- fifo_is_full 
						|________|

	
	fifo_ren  : 
			if in state idle :   fifo_en = 1'b1 
			in state waitforothersof : fifo read is pended , if the corresponding channel has detected the sof signal . otherwise fifo read is enabled 
			in state transimiting  :   fifo read is disabled if either of the fifo is empty . 

*/

localparam idle            = 2'b00 ;
localparam waitforothersof = 2'b01 ;
localparam transimiting  = 2'b10 ;

reg [1:0] state = 0; 
reg [1:0] NxtState ;
reg left_stream_first_arrive = 0;
reg right_stream_first_arrive = 0;


 wire [25-1:0] left_stream_fifo_out ;
 wire [24  :0] right_stream_fifo_out;
 wire sof_left_from_fifo;
 wire sof_right_from_fifo ;
reg [25-1:0] left_stream_fifo_out_dly1_sclkrate ;
reg [25-1:0] left_stream_fifo_out_dly2_sclkrate ;
reg [24:0] right_stream_fifo_out_dly1_sclkrate;
reg [24:0] right_stream_fifo_out_dly2_sclkrate;
reg sof_left_dly1 , sof_right_dly1 ;
 wire left_fifo_is_full ;
 wire right_fifo_is_full ;
 wire left_fifo_is_empty ;
 wire right_fifo_is_empty ;

reg [10:0] left_pixel_cnt_sclkrate ;
reg [10:0] right_pixel_cnt_sclkrate ;
reg pixelCntNotMatched ;
(* MARK_DEBUG="true" *)reg stream_not_syn = 0;

(* MARK_DEBUG="true" *)reg stream_timing_wrong_left ;
(* MARK_DEBUG="true" *)reg stream_timing_wrong_right ;

/*
	fifo interface with axis 
*/
wire [24+1-1:0] left_fifo_data_in_wire , right_fifo_data_in_wire ;   // {sof,RGB}
wire left_fifo_wen , right_fifo_wen ;

wire rd_en_l ;
wire rd_en_r ;

assign S_AXIS_TREADY_LEFT  = ~left_fifo_is_full  ;
assign S_AXIS_TREADY_RIGHT = ~right_fifo_is_full ;
/*
	remember the timing :
                       _______________________
	tready  __________|            
                           ____________________
	tvalid  ______________|

	the slaver side assert tready, the master side take this signal as ready to accept signal, then assert tvalid when 
	transimitting data is ready and valid .
	data is valid only if tready and tvalid signals are both high 

*/

assign left_fifo_data_in_wire  = {S_AXIS_TUSER_LEFT, S_AXIS_TDATA_LEFT[23:0] } ;
assign right_fifo_data_in_wire = {S_AXIS_TUSER_RIGHT,S_AXIS_TDATA_RIGHT[23:0]} ;

assign left_fifo_wen =  (~left_fifo_is_full)   & S_AXIS_TVALID_LEFT ;      // fifo is not full and tvalid is assertec
assign right_fifo_wen  = (~right_fifo_is_full) & S_AXIS_TVALID_RIGHT ;

assign sof_left_from_fifo  = left_stream_fifo_out[24]  ;
assign sof_right_from_fifo = right_stream_fifo_out[24] ;

always@(posedge MCLK)
if(PIXEL_EN)
begin
	state <= NxtState ;
end

// state transition logic 
always@(*)
begin
	case (state)
		idle : 	
			begin
				case ({sof_left_from_fifo , sof_right_from_fifo})
					2'b11 		:  NxtState = transimiting ;
					2'b10,2'b01 :  NxtState = waitforothersof ;
					default : NxtState = idle ;
				endcase
			end

		waitforothersof :
			begin
				case ({left_stream_first_arrive,right_stream_first_arrive})
					2'b10 :   
						/*                                _________________________________________
						sof_of_second_stream ____________|                                         |__________
		                                                                                         __
						rd_en_of_second_fifo ___________________________________________________|  |___________
                                        ___________________________________________________________ _____________
						state           ______________________________1____________________________X________2____

						*/
							begin   // left first , waiting for right sof 
								if(sof_right_from_fifo && rd_en_r)   // in case sof stays several pixel_en clock width, due to fifo rd_en is low 
									NxtState = transimiting ;
								else 
									NxtState = waitforothersof ;
							end
					2'b10 :   
							begin
								if(sof_left_from_fifo && rd_en_l)
									NxtState = transimiting ;
								else 
									NxtState = waitforothersof ;
							end
					2'b00 :   
							begin  // something is wrong in this case ,return to idel state 
									NxtState = idle ;
							end
					2'b11 : NxtState = idle ;    // this state is wrong, should not in this branch, should be in state start_stransmit 

				endcase
			end

		transimiting :
			begin
				if(pixelCntNotMatched || stream_timing_wrong_left || stream_timing_wrong_right )   // lose synchronization 
					NxtState = idle ;
				else 
					NxtState = transimiting ;
			end

		default :
			begin
				NxtState = idle ;
			end
	endcase // state
end


// jobs to do at each stage ;  output logic 
/*
	              ________
	sof _________|        |________________
              ___ ________ _______ _______
    axis_data ___X________X_______X_______

*/


reg left_fifo_ren_sclkrate ;
reg right_fifo_ren_sclkrate ;

// when fifo is full(stillhave several position open) , it can write at the current time step, but write enable is deassertted at the next time step 
// when fifi is empty(still have several left) , it can still read at the current time step, but read enable is deasserted at the next time step 
// EN signal is only controlled by write_fifo_wen  &  read_fifo_ren & transmitting_state

wire left_fifo_not_empty_and_write_fifo_is_not_full_wire  = (~left_fifo_is_empty) &  ( ~WRITE_FIFO_FULL) ;
wire right_fifo_not_empty_and_write_fifo_is_not_full_wire = (~right_fifo_is_empty) &  ( ~WRITE_FIFO_FULL) ;
wire neither_fifo_is_empty_and_write_fifo_is_not_full_wire = (~right_fifo_is_empty) &  ( ~WRITE_FIFO_FULL) & (~right_fifo_is_empty);

always@(posedge MCLK)
if (PIXEL_EN)
begin
	case (state)
		idle : 	
			begin
				case ({sof_left_from_fifo,sof_right_from_fifo})
						2'b10 : 
								begin   // left stream sof detected 
									left_stream_first_arrive <= 1'b1 ;
									right_stream_first_arrive <= 1'b0 ;

									// in this case stop reading left fifo , right fifo continue reading 
									left_fifo_ren_sclkrate  <= 0  ;   
									right_fifo_ren_sclkrate <= right_fifo_not_empty_and_write_fifo_is_not_full_wire;
								end
						2'b01 : 
								begin   // right stream sof detected 
									left_stream_first_arrive <= 1'b0 ;
									right_stream_first_arrive <= 1'b1 ;

									// in this case stop reading right fifo , left fifo continue reading 
									left_fifo_ren_sclkrate  <= left_fifo_not_empty_and_write_fifo_is_not_full_wire  ;   
									right_fifo_ren_sclkrate <= 0 ;
								end
						2'b11 : 
								begin   // 2 stream sofs have beed detected simutanously 
									left_stream_first_arrive <= 1'b1 ;
									right_stream_first_arrive <= 1'b1 ;

									// in this case ,both fifos continue reading  
									left_fifo_ren_sclkrate  <= neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;
									right_fifo_ren_sclkrate <= neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;

								end
						2'b00 : 
								begin  // none of the sof has been detected, all signals keep as it was
									left_stream_first_arrive  <= left_stream_first_arrive  ;
									right_stream_first_arrive <= right_stream_first_arrive ;
									left_fifo_ren_sclkrate  <= left_fifo_not_empty_and_write_fifo_is_not_full_wire ;
									right_fifo_ren_sclkrate <= right_fifo_not_empty_and_write_fifo_is_not_full_wire ;
								end
				endcase
			end

		waitforothersof :
			begin
						/*
							be careful about the timing between the two streams .  

							always@(posedge MCLK)
							if(pixen)
							begin
								if(fifo_left_ren && fifo_right_ren && state == transmiting)
									EN <= 1'b1
							end
                                                                                       ______________________
							EN _______________________________________________________|
                                                   
                                                     ____
							sof_of_first_stream ____|    |__________________________________________________
                                   ______________________ ______________________ ___________________________
							state  ______idle____________X___waitforothersof____X___transimiting___________

                                                           _______________________________________________________  asserted 
                            fifo_ren_from_the_other_stream 
                                                                           _____
							sof_from_the_other_stream   __________________|     |_____________________
                                                        __________________ _____ ____ ____ ____
							data_of_other_stream       ...................X__0__X__1_X__2_X__3_
                                              ___________                        __________
                            fifo_ren_of_waiting_stream   |______________________|
                            
                                  __________________ ____ ___________________________ ____ ____
							data_of_first_stream ...X__0_X__1____waiting_____________X__2_X___
                                                                                  ________________________
							syn_detected ________________________________________|

								             ____________ ___________________________ ____ _________
							data_of_first_stream_dly1 ...X___0_______________________X__1_X__2______   output stream with synchronization
                                                        _________________________ ___ ____ ______
							data_of_other_stream_dly1 ...........................X_0_X_1__X__2__       output stream with synchronization 

							data_of_first_stream_dly2 ...X___________________________X__0_X__1______   sof aligned with EN
                                                        _________________________ ___ ____ ______
							data_of_other_stream_dly2 ...........................X_?_X_0__X__1__        						


							in this state, waiting for the other sof to appear, once detected, the fifo in waiting state starts reading , in such case, 
							both streams are synchronized 
						*/
				case ({left_stream_first_arrive,right_stream_first_arrive})
					2'b10 :   
							begin   // left first , waiting for right sof 
								if(sof_right_from_fifo && rd_en_r)  // right sof arrived
								begin
									left_fifo_ren_sclkrate  <=  neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;  
									right_fifo_ren_sclkrate <=  neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;
								end
								else begin
									left_fifo_ren_sclkrate  <=  1'b0 ;  //left fifo keep waiting 
									right_fifo_ren_sclkrate <=  right_fifo_not_empty_and_write_fifo_is_not_full_wire ;  // right fifo keeps reading 
								end
							end
					2'b01 :   
							begin
								if(sof_left_from_fifo && rd_en_l)  // left sof arrived
								begin
									left_fifo_ren_sclkrate  <=  neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;  
									right_fifo_ren_sclkrate <=  neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;
								end
								else begin
									left_fifo_ren_sclkrate  <=  left_fifo_not_empty_and_write_fifo_is_not_full_wire ;  //left fifo keep reading 
									right_fifo_ren_sclkrate <=  1'b0 ;  // left fifo keeps waiting 
								end
							end
					default :   
							begin  
								left_fifo_ren_sclkrate  <=  left_fifo_not_empty_and_write_fifo_is_not_full_wire   ;  
								right_fifo_ren_sclkrate <=  right_fifo_not_empty_and_write_fifo_is_not_full_wire ;	   
							end
				endcase

			end

		transimiting :
			begin
						/*
							in this state it monitors whether the two streams are kept synchronized, by means of counting the pixel numbers , and either of the 
							fifo is emty , the other fifo should stop reading as well 
							
							this is quite simply realized by only this : left_fifo_ren_sclkrate_from_fsm <= (1'b1) & (1'b1) ;  

							theoretically they should be algined from here on, otherwise there must be something wrong with the logic , trigger debug signal .
						*/
						
						// if((sof_left_from_fifo && (!sof_right_from_fifo)) || ((!sof_left_from_fifo) && sof_right_from_fifo)) // the two sofs did not match, syn lost 
						/*
                          // (sof_left_from_fifo != sof_right_from_fifo) these 2 signal are not aligned at the begining,because the first stream is waiting for the second one, so 
                          at the begining the timing should look like this 
							       ____
							______|    |___________
                            ___________ ____________________________ ______ _______
 							_____0_____X___1________________________X__2___X_____
                                                       ______
							__________________________|      |________
                                                       ______ ______ _______ _____
							________........__........X__0___X___1__X___2___X___

						*/

						if(pixelCntNotMatched || stream_timing_wrong_left || stream_timing_wrong_right ) 
						begin
							left_fifo_ren_sclkrate  <= left_fifo_not_empty_and_write_fifo_is_not_full_wire ;  
							right_fifo_ren_sclkrate <= right_fifo_not_empty_and_write_fifo_is_not_full_wire ;
						end
						else begin
							left_fifo_ren_sclkrate  <= neither_fifo_is_empty_and_write_fifo_is_not_full_wire ; 
							right_fifo_ren_sclkrate <= neither_fifo_is_empty_and_write_fifo_is_not_full_wire ;		 					
						end

			end

		default :
			begin
				        /*
							in default state , the two fifos should be in reading state .
				        */
				        left_fifo_ren_sclkrate  <=  left_fifo_not_empty_and_write_fifo_is_not_full_wire  ;
						right_fifo_ren_sclkrate <=  right_fifo_not_empty_and_write_fifo_is_not_full_wire ;
			end
	endcase // state
end


/*
                             _____
	sof_first_stream _______|     |___________________
                     _____________ ____________
	state          _______0_______X____1_______
                     _____________
	fifo_ren_first                |_____________________ 




	output timing : 

		                        _____________________________
	syn_detected     __________|
	                  _________ ____ ____ ______
	output stream    __________X_0__X_1__X___ 
*/
always@(posedge MCLK)
if(PIXEL_EN)
begin
	if(left_fifo_ren_sclkrate)
	begin
		left_stream_fifo_out_dly1_sclkrate  <= left_stream_fifo_out      ;
		left_stream_fifo_out_dly2_sclkrate  <= left_stream_fifo_out_dly1_sclkrate ;
	end
	// sof_left_dly1 <= sof_left_from_fifo ;
	if(right_fifo_ren_sclkrate)
	begin
		right_stream_fifo_out_dly1_sclkrate <= right_stream_fifo_out      ;
		right_stream_fifo_out_dly2_sclkrate <= right_stream_fifo_out_dly1_sclkrate ;
	end
	// sof_right_dly1 <= sof_right_from_fifo ;
end


/* inStreamIsSyned 
	global enable signal EN : 
	1) inStreamIsSynedAndFifoIsNotEmpty == 1'b1  (syned, both read fifo is not empty)
	2) write fifo is not full 

*/

assign inStreamIsSynedAndFifoIsNotEmpty = ( (state == transimiting) && (~left_fifo_is_empty) && (~right_fifo_is_empty) ) ;


always@(posedge MCLK)
if(PIXEL_EN && EN)
begin
	left_stream_sofRGB  <= left_stream_fifo_out_dly2_sclkrate  ;
	right_stream_sofRGB <= right_stream_fifo_out_dly2_sclkrate ;
end



// checking sync logic
always@(posedge MCLK)
if(PIXEL_EN && EN )
begin
	if(left_stream_sofRGB[24]) // sof detected
		left_pixel_cnt_sclkrate <= 1 ;
	else 
		left_pixel_cnt_sclkrate <= left_pixel_cnt_sclkrate + 1'b1 ;

	if(right_stream_sofRGB[24]) // sof detected
		right_pixel_cnt_sclkrate <= 1 ;
	else 
		right_pixel_cnt_sclkrate <= right_pixel_cnt_sclkrate + 1'b1 ;

	if(left_pixel_cnt_sclkrate != right_pixel_cnt_sclkrate)
		pixelCntNotMatched <= 1'b1 ;
	else 
		pixelCntNotMatched <= 1'b0 ;
end 


// debug 
(* MARK_DEBUG="true" *)reg [10:0] col_cnt_left =1;
(* MARK_DEBUG="true" *)reg [10:0] row_cnt_left ;
(* MARK_DEBUG="true" *)reg [10:0] col_cnt_right =1;
(* MARK_DEBUG="true" *)reg [10:0] row_cnt_right ;

always@(posedge MCLK)
if(PIXEL_EN && EN  )
begin
	if(left_stream_sofRGB[24])  // start of frame 
	begin  
		col_cnt_left <= 1 ; 
		row_cnt_left <= 0 ;
	end
	else begin
		if(col_cnt_left== IMAGE_WIDTH -1 )
		begin
			col_cnt_left <= 0 ;
			
			if(row_cnt_left == IMAGE_HEIGHT - 1)
                row_cnt_left <= 0 ;
			else 
			    row_cnt_left <= row_cnt_left + 1'b1 ;
		end
		else 
			col_cnt_left <= col_cnt_left + 1'b1 ;
	end
end

always@(posedge MCLK)
if(PIXEL_EN && EN  )
begin
    if(right_stream_sofRGB[24])  // start of frame 
    begin  
        col_cnt_right <= 1 ; 
        row_cnt_right <= 0 ;
    end
    else begin
        if(col_cnt_right== IMAGE_WIDTH -1 )
        begin
            col_cnt_right <= 0 ;

            if(row_cnt_right == IMAGE_HEIGHT - 1)
            	row_cnt_right <= 0 ;
            else 
            	row_cnt_right <= row_cnt_right + 1'b1 ;
        end
        else 
            col_cnt_right <= col_cnt_right + 1'b1 ;
    end
end

always@(posedge MCLK)
if(PIXEL_EN && EN  )
begin 
	if((col_cnt_right == 0) && (row_cnt_right == 0) && (right_stream_sofRGB[24]==0))
		stream_timing_wrong_left <= 1'b1 ;
	else 
		stream_timing_wrong_left <= 1'b0 ;
end

always@(posedge MCLK)
if(PIXEL_EN && EN  )
begin 
    if((col_cnt_right == 0) && (row_cnt_right == 0) && (right_stream_sofRGB[24]==0))
        stream_timing_wrong_right <= 1'b1 ;
    else 
        stream_timing_wrong_right <= 1'b0 ;
end

always@(posedge MCLK)
if(PIXEL_EN && EN)
begin
	if( (col_cnt_left[7:0] != left_stream_sofRGB[7:0]) || (col_cnt_right[7:0] != right_stream_sofRGB[7:0]) || (left_stream_sofRGB != right_stream_sofRGB) )
		stream_not_syn <= 1'b1 ;
	else 
		stream_not_syn <= 1'b0 ;
end


/*
                                             /
                                            /   
		left_stream_sofRGB  <---------------    ----------- left_stream_sofRGB 

*/

assign rd_en_l = left_fifo_ren_sclkrate & PIXEL_EN ;
assign rd_en_r = right_fifo_ren_sclkrate & PIXEL_EN ;

synStreamFIFO  u_left_fifo 
	(
        .rd_clk         (MCLK           ) ,
        .wr_clk         (S_AXIS_ACLK_LEFT    ) ,
        .rst    		(~S_AXIS_ARESETN_LEFT) ,
        .din    		(left_fifo_data_in_wire) ,
        .wr_en 			(left_fifo_wen) ,
        .rd_en 			(rd_en_l) ,
        .dout 			(left_stream_fifo_out) ,
        .full 			() ,
        .empty 			() ,
        .prog_full      (left_fifo_is_full ) ,
    	.prog_empty     (left_fifo_is_empty)
  	);


synStreamFIFO  u_right_fifo 
	(
        .rd_clk         (MCLK           ) ,
        .wr_clk         (S_AXIS_ACLK_RIGHT    ) ,
        .rst    		(~S_AXIS_ARESETN_RIGHT) ,
        .din    		(right_fifo_data_in_wire) ,
        .wr_en 			(right_fifo_wen) ,
        .rd_en 			(rd_en_r) ,
        .dout 			(right_stream_fifo_out) ,
        .full 			() ,
        .empty 			() ,
        .prog_full      (right_fifo_is_full ) ,
    	.prog_empty     (right_fifo_is_empty)
  	);

endmodule



