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
// `default_nettype none

	module stereo_v1_0 #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 6,

		// Parameters of Axi Master Bus Interface M00_AXIS
		parameter integer C_M00_AXIS_TDATA_WIDTH	= 32,
		parameter integer C_M00_AXIS_START_COUNT	= 32,

		// Parameters of Axi Slave Bus Interface S00_AXIS
		parameter integer C_S00_AXIS_TDATA_WIDTH	= 32
	)
	(
		// Users to add ports here
		output wire     mm2s_fsync ,    //ready to start a frame signal ,  start the VDMA mm2s transform , this signal is accerted by cpu when data is ready to stream

		input  wire     MCLK       ,
		input  wire     CORE_RSTN  ,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready,

		// Ports of Axi Master Bus Interface M00_AXIS
		input wire  m00_axis_aclk,
		input wire  m00_axis_aresetn,
		output wire  m00_axis_tvalid,
		output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
		output wire [0 : 0] m00_axis_tuser,
		output wire  m00_axis_tlast,
		input wire  m00_axis_tready,
		output wire m00_axis_tstrb ,

		// Ports of Axi Slave Bus Interface S00_AXIS
		input wire  s00_axis_aclk,
		input wire  s00_axis_aresetn,
		output wire  s00_axis_tready,
		input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
		input wire [0 : 0] s00_axis_tuser,
		input wire  s00_axis_tlast,
		input wire  s00_axis_tvalid  ,

		// axis slave ports for left and right streams 
		input wire  								s00_axis_aclk_left		,
		input wire  								s00_axis_aresetn_left	,
		output wire  								s00_axis_tready_left	,
		input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] 	s00_axis_tdata_left		,
		input wire [0 : 0] 							s00_axis_tuser_left		,
		input wire  								s00_axis_tlast_left		,
		input wire  								s00_axis_tvalid_left  	, 

		input wire  								s00_axis_aclk_right 	,
		input wire  								s00_axis_aresetn_right	,
		output wire  								s00_axis_tready_right	,
		input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] 	s00_axis_tdata_right	,
		input wire [0 : 0] 							s00_axis_tuser_right	,
		input wire  								s00_axis_tlast_right	,
		input wire  								s00_axis_tvalid_right	   

	);

/*
	                 _____
mm2s_fsync  ________|	  |__________________  // start one frame of  memory to stream transform on the falling edge of this signal
                     _____
s2mm_tuser  ________|     |__________________  // start one frame of stream to memory transform on the falling edge of this signal 

*/

	wire wirte_fifo_full ;
	wire read_fifo_empty ;
	wire pixel_en  ;
	(* MARK_DEBUG="true" *) wire  en ;
	wire[17:0] right_left_image_stream ;
	wire read_fifo_output_valid;
	wire  read_pixel_en ;
	wire[8:0] disparity_left ;

	wire cpu_data_is_ready ;
	wire dispOutput_left_valid ;
	wire restn_stereoip_from_cpu ;
	wire soft_rstn ;
	wire  PIXEL_EN_div2 ;
	wire SHOW_COLOR_DEPTH ;

	wire inStreamIsSynedAndFifoIsNotEmpty ;


// Instantiation of Axi Bus Interface S00_AXI

	stereo_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) stereo_v1_0_S00_AXI_inst (


		.CPU_DATA_IS_READY(cpu_data_is_ready),  // used to generate mm2s_fsync falling edge 
		.RSTN_STEREOIP_FROM_CPU(restn_stereoip_from_cpu),
		.SHOW_COLOR_DEPTH (SHOW_COLOR_DEPTH) ,

		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);



	TimeGen    // generate pixel clock,  1/8 of s00_axis_aclk rate 
	#(
		.IMAGE_WIDTH  (640) ,
		.IMAGE_HEIGHT (480) 
	)
	uTimeGen
	(
		.clk                       (MCLK)      ,    // Clock
		.rst_n                     (CORE_RSTN ) ,  // reset active low
		.PIXEL_EN_div2             (PIXEL_EN_div2) ,
		.CPU_DATA_IS_READY         (cpu_data_is_ready) ,
		.wirte_fifo_full           (wirte_fifo_full)   ,
		.read_fifo_empty           (read_fifo_empty)   ,
		.inStreamIsSynedAndFifoIsNotEmpty (inStreamIsSynedAndFifoIsNotEmpty) ,
		.MM2S_FSYN                 (mm2s_fsync) ,
		.RSTN_STEREOIP_FROM_CPU    (restn_stereoip_from_cpu) ,
		.SYSTEM_RSTN               (soft_rstn) ,
		.EN_OUT                    (en)         ,
		.EN                        (pixel_en),           // must be pixel_en
		.pixelEN   	               (pixel_en) 
	);


/*  !!!!!!! important there should be a disparity_left_valid signal to prevent 4-byte alignment problem in fifo
                                       _______
	SOF_FROM_DISPARITY_STREAM ________|       |_______________________________
                                       ________________________________________
	INPUT_STREAM_VALID         _______|
                              ________ _______ _______ _______ __
	INPUT_STREAM(disparity)   ////////X__0____X___1___X___2___X___
*/

// Instantiation of Axi Bus Interface M00_AXIS
	stereo_v1_0_M00_AXIS # ( 
		.C_M_AXIS_TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
		.C_M_START_COUNT(C_M00_AXIS_START_COUNT)
	) stereo_v1_0_M00_AXIS_inst (
		.M_AXIS_ACLK(m00_axis_aclk),
		.M_AXIS_ARESETN(m00_axis_aresetn),
		.M_AXIS_TVALID(m00_axis_tvalid),
		.M_AXIS_TDATA(m00_axis_tdata),
		.M_AXIS_TUSER(m00_axis_tuser),
		.M_AXIS_TLAST(m00_axis_tlast),
		.M_AXIS_TREADY(m00_axis_tready),
		.M_AXIS_TSTRB (m00_axis_tstrb),
		
                                                                       
		// .INPUT_STREAM_VALID (read_fifo_output_valid)        ,//
		// .INPUT_STREAM       (right_left_image_stream[8:0])  ,//  								
										
		// user interface 
		.SHOW_COLOR_DEPTH    (SHOW_COLOR_DEPTH),
		.INPUT_STREAM_VALID  (dispOutput_left_valid ),                 //   !!!!!!! important there should be a disparity_left_valid signal to prevent alignment problem in fifo
		.INPUT_STREAM        (disparity_left),     //9-bit {SOF,DATA} from stereo IP 
		.WRITE_FIFO_FULL    (wirte_fifo_full),            // must stop pipline 
		.PIXEL_EN           (pixel_en),   
		.MCLK                  (MCLK     ) ,
		.CORE_RSTN             (CORE_RSTN) ,
		.EN                 (en)                    // EN = 1'b1 if writingFIFO is not full && readingFIFO is not empty   
		
	);


// Instantiation of Axi Bus Interface S00_AXIS
`define  __synStreamModule 1


`ifdef __synStreamModule


	(* MARK_DEBUG="true" *)wire [24:0] left_stream_sofRGB ;
	(* MARK_DEBUG="true" *)wire [24:0] right_stream_sofRGB ; 
	(* MARK_DEBUG="true" *)wire [8:0]  gray_stream_out_left ;
	(* MARK_DEBUG="true" *)wire [8:0 ] gray_stream_out_right ;

	synStream #
	(
		.IMAGE_WIDTH  (640) ,
		.IMAGE_HEIGHT (480) ,
		.C_S_AXIS_TDATA_WIDTH	(32)
	)
	U_synStream
	(
		.PIXEL_EN 					(pixel_en) 				  ,    // pixel clock  en 
		.EN       					(en) 					  ,  
		.MCLK     					(MCLK) 					  ,
		.CORE_RSTN					(CORE_RSTN) 			  ,
		.WRITE_FIFO_FULL      		(wirte_fifo_full)		  ,
		.inStreamIsSynedAndFifoIsNotEmpty (inStreamIsSynedAndFifoIsNotEmpty) ,


		/*********** left stream interface *****************/
		.S_AXIS_ACLK_LEFT    		(s00_axis_aclk_left		) ,
		.S_AXIS_ARESETN_LEFT 		(s00_axis_aresetn_left	) ,
		.S_AXIS_TREADY_LEFT  		(s00_axis_tready_left	) ,
		.S_AXIS_TDATA_LEFT   		(s00_axis_tdata_left	) ,
		.S_AXIS_TUSER_LEFT   		(s00_axis_tuser_left	) ,
		.S_AXIS_TLAST_LEFT   		(s00_axis_tlast_left	) ,
		.S_AXIS_TVALID_LEFT  		(s00_axis_tvalid_left  	) ,

		/***************** right stream interface *************/
		.S_AXIS_ACLK_RIGHT			(s00_axis_aclk_right 	) ,
		.S_AXIS_ARESETN_RIGHT		(s00_axis_aresetn_right	) ,
		.S_AXIS_TREADY_RIGHT		(s00_axis_tready_right	) ,
		.S_AXIS_TDATA_RIGHT			(s00_axis_tdata_right	) ,
		.S_AXIS_TUSER_RIGHT			(s00_axis_tuser_right	) ,
		.S_AXIS_TLAST_RIGHT			(s00_axis_tlast_right	) ,
		.S_AXIS_TVALID_RIGHT 		(s00_axis_tvalid_right	) ,

		/******************output stream *********************************/
		.left_stream_sofRGB     	(left_stream_sofRGB		) ,
		.right_stream_sofRGB    	(right_stream_sofRGB	) 

	);

	color2gray 
	#(         
		.INPUTDATAWID  (25),    
		.OUTPUTDATAWID ( 9)
	  )
	U_color2gray_left
	(
		.clk          (MCLK) 					,         // 150 Clock   
		.en           (en) 						,     
		.pixelEN      (pixel_en) 				,
		.stream_in    (left_stream_sofRGB) 		,         // {sof,rgb}       
		.stream_out   (gray_stream_out_left) 	,         // {sof,gray}
		.rst_n        (CORE_RSTN)           
	);

	color2gray 
	#(         
		.INPUTDATAWID  (25),    
		.OUTPUTDATAWID (9 )
	  )
	U_color2gray_right
	(
		.clk          (MCLK) 					,         // 150 Clock   
		.en           (en) 						,     
		.pixelEN      (pixel_en) 				,
		.stream_in    (right_stream_sofRGB) 		,         // {sof,rgb}       
		.stream_out   (gray_stream_out_right) 	,         // {sof,gray}
		.rst_n        (CORE_RSTN)           
	);

	topModule 
	#(
		.INPUTDATAWIDTH (9) ,
		.DISPARITY_WIDTH (9)
		)
	u_stereoIP_top
	(
		.MCLK				  (MCLK                  ),             										
		.RSTN 				  (CORE_RSTN & soft_rstn ),          										
		.EN             	  (en),           										
		.PIXEL_EN        	  (pixel_en),           										
		.LEFT_IMAGE_IN        (gray_stream_out_left),           										
		.LEFT_IMAGE_IN_VALID  (read_fifo_output_valid),             										
		.RIGHT_IMAGE_IN       (gray_stream_out_right),           										
		.RIGHT_IMAGE_IN_VALID (read_fifo_output_valid),  
		.dispOutput_left_valid (dispOutput_left_valid) ,  
		.SHOW_COLOR_DEPTH     (SHOW_COLOR_DEPTH) ,         										
		.DISPARITY_OUTPUT     (disparity_left)             										
	);

	

`else


	stereo_v1_0_S00_AXIS # ( 
		.C_S_AXIS_TDATA_WIDTH(C_S00_AXIS_TDATA_WIDTH)
	) stereo_v1_0_S00_AXIS_inst (
		.S_AXIS_ACLK(s00_axis_aclk),
		.S_AXIS_ARESETN(s00_axis_aresetn ),
		.S_AXIS_TREADY(s00_axis_tready),
		.S_AXIS_TDATA(s00_axis_tdata),
		.S_AXIS_TUSER(s00_axis_tuser),
		.S_AXIS_TLAST(s00_axis_tlast),
		.S_AXIS_TVALID(s00_axis_tvalid),

		// Add user logic here
		.MCLK                 (MCLK     ) ,
		.CORE_RSTN            (CORE_RSTN) ,
		.PIXEL_EN             (pixel_en),
		.WRITE_FIFO_FULL      (wirte_fifo_full),
		.READFIFO_OUTPUT      (right_left_image_stream),     //{sof,right,sof,left}    
		.READ_FIFO_EMPTY      (read_fifo_empty),            // must stop pipline 
		.EN                   (en)            ,        // EN = 1'b1 if writingFIFO is not full && readingFIFO is not empty   
		.READFIFO_OUTPUT_VALID    (read_fifo_output_valid)
	// User logic ends
	);



	topModule 
	#(
		.INPUTDATAWIDTH (9) ,
		.DISPARITY_WIDTH (9)
		)
	u_stereoIP_top
	(
		.MCLK				  (MCLK                  ),             										
		.RSTN 				  (CORE_RSTN & soft_rstn ),          										
		.EN             	  (en),           										
		.PIXEL_EN        	  (pixel_en),           										
		.LEFT_IMAGE_IN        (right_left_image_stream[8:0]),           										
		.LEFT_IMAGE_IN_VALID  (read_fifo_output_valid),             										
		.RIGHT_IMAGE_IN       (right_left_image_stream[17:9]),           										
		.RIGHT_IMAGE_IN_VALID (read_fifo_output_valid),  
		.dispOutput_left_valid (dispOutput_left_valid) ,           										
		.DISPARITY_OUTPUT     (disparity_left)             										
	);

`endif 


	endmodule
