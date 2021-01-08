`timescale 1 ns / 1 ps
// `default_nettype none

module topModule 
#(
	parameter  CENSUS_TRANSFORM_WIDTH = 63 ,       // append sof in MSB 62+1
	parameter  MATCH_COST_OUTPUT_WID_1D = 385 ,    // 1(SOF)  + 6 * 64 
	parameter  LPDI_OUTPUTDATAWID_1D = 513 ,       // 8 * 64 + 1 
	parameter  INPUTDATAWIDTH  = 9 ,               // append sof in MSB 8+1
	parameter  DISPARITY_WIDTH = 9                 // append sof in MSB 8+1
	)
(
	input wire                                       MCLK						,    				// Clock
	input wire                                       RSTN 						,	  				// synchronous reset active low
	input wire                                       EN             	 		 ,    // golobal pipline enable signal 
	input wire                                       PIXEL_EN        	 		,    // pixel enalbe signal 


	input wire [INPUTDATAWIDTH-1:0]                  LEFT_IMAGE_IN       	 ,   //append sof in MSB
	input wire                                       LEFT_IMAGE_IN_VALID  	 ,
	input wire [INPUTDATAWIDTH-1:0]                  RIGHT_IMAGE_IN      	 ,   //append sof in MSB
	input wire                                       RIGHT_IMAGE_IN_VALID 	 ,

	output wire                                      dispOutput_left_valid   ,

	input wire                                       SHOW_COLOR_DEPTH        ,

	output wire[DISPARITY_WIDTH-1:0]                 DISPARITY_OUTPUT   ,  	//append sof in MSB

	input wire               enable_rectifty      ,

	input wire signed [31:0] LEFT_k1_32bit_wire   , 
	input wire signed [31:0] LEFT_k2_32bit_wire   , 
	input wire signed [31:0] LEFT_p1_32bit_wire   , 
	input wire signed [31:0] LEFT_p2_32bit_wire   , 
	input wire signed [31:0] LEFT_k3_32bit_wire   , 
	input wire signed [31:0] LEFT_k4_32bit_wire   , 
	input wire signed [31:0] LEFT_k5_32bit_wire   , 
	input wire signed [31:0] LEFT_k6_32bit_wire   , 
	input wire signed [31:0] LEFT_ir_32bit_0_wire , 
	input wire signed [31:0] LEFT_ir_32bit_1_wire , 
	input wire signed [31:0] LEFT_ir_32bit_2_wire , 
	input wire signed [31:0] LEFT_ir_32bit_3_wire , 
	input wire signed [31:0] LEFT_ir_32bit_4_wire , 
	input wire signed [31:0] LEFT_ir_32bit_5_wire , 
	input wire signed [31:0] LEFT_ir_32bit_6_wire , 
	input wire signed [31:0] LEFT_ir_32bit_7_wire , 
	input wire signed [31:0] LEFT_ir_32bit_8_wire ,
	input wire signed [31:0] LEFT_u0_32bit_wire   , 
	input wire signed [31:0] LEFT_v0_32bit_wire   , 
	input wire signed [31:0] LEFT_fx_32bit_wire   , 
	input wire signed [31:0] LEFT_fy_32bit_wire   , 

	input wire signed [31:0] RIGHT_k1_32bit_wire   , 
	input wire signed [31:0] RIGHT_k2_32bit_wire   , 
	input wire signed [31:0] RIGHT_p1_32bit_wire   , 
	input wire signed [31:0] RIGHT_p2_32bit_wire   , 
	input wire signed [31:0] RIGHT_k3_32bit_wire   , 
	input wire signed [31:0] RIGHT_k4_32bit_wire   , 
	input wire signed [31:0] RIGHT_k5_32bit_wire   , 
	input wire signed [31:0] RIGHT_k6_32bit_wire   , 
	input wire signed [31:0] RIGHT_ir_32bit_0_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_1_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_2_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_3_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_4_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_5_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_6_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_7_wire , 
	input wire signed [31:0] RIGHT_ir_32bit_8_wire ,
	input wire signed [31:0] RIGHT_u0_32bit_wire   , 
	input wire signed [31:0] RIGHT_v0_32bit_wire   , 
	input wire signed [31:0] RIGHT_fx_32bit_wire   , 
	input wire signed [31:0] RIGHT_fy_32bit_wire   

	
);

`define  __filter_resource 1 
`define  __rectify         1

wire [CENSUS_TRANSFORM_WIDTH-1:0] left_image_census_transform , right_image_census_transform ;

// matching cost part 
wire [MATCH_COST_OUTPUT_WID_1D-1:0] CPDi_1D ;

// ldpi left 
wire [LPDI_OUTPUTDATAWID_1D-1:0]  LPDi ;

// ldpi right 
wire [LPDI_OUTPUTDATAWID_1D-1:0] LPDiRight , LPDiLeft ;

// winner takes all 
wire [DISPARITY_WIDTH-1:0] disparity_left , disparity_right ;

// median filter 
wire [DISPARITY_WIDTH-1:0] disparity_left_filtered ;
wire [DISPARITY_WIDTH-1:0] disparity_right_filtered ;

// left right check 
wire [DISPARITY_WIDTH-1:0] dispOutput_left ;
wire [DISPARITY_WIDTH-1:0] dispOutput_left_filtered ;
wire [DISPARITY_WIDTH-1:0] dispOutput_left_filtered_pre;
wire [DISPARITY_WIDTH-1:0] dispOutput_left_fill_wholes ;
wire [DISPARITY_WIDTH-1:0] dispOutput_left_removed_noise ;

(* MARK_DEBUG="true" *)wire [8:0] rectified_stream_left ;
(* MARK_DEBUG="true" *)wire [8:0] rectified_stream_right ;

`ifdef __filter_resource
	assign DISPARITY_OUTPUT = dispOutput_left_filtered ;
`else 
	assign DISPARITY_OUTPUT = dispOutput_left ;   // dispOutput_left_filtered ;
`endif 


// `ifdef __rectify 

rectify
#(
	.LEFT_RIGHT    ("L") ,          
	.INPUTDATAWID  (9  ) ,    
	.IMAGE_WIDTH   (640) ,
	.IMAGE_HEIGHT  (480) ,
	.OUTPUTDATAWID (9  ) 
  )
U_rectify_left
(
	.clk                (MCLK)    ,         // 150 Clock   
	.en                 (EN)    ,     
	.pixelEN            (PIXEL_EN)    ,
	.image_stream       (LEFT_IMAGE_IN)       ,         // W*H       
	.rectified_stream   (rectified_stream_left)  ,            
	.rst_n              (RSTN)       ,       // Asynchronous reset active low
	.k1_32bit_wire 		(LEFT_k1_32bit_wire  ), 
	.k2_32bit_wire 		(LEFT_k2_32bit_wire  ), 
	.p1_32bit_wire 		(LEFT_p1_32bit_wire  ), 
	.p2_32bit_wire 		(LEFT_p2_32bit_wire  ), 
	.k3_32bit_wire 		(LEFT_k3_32bit_wire  ), 
	.k4_32bit_wire 		(LEFT_k4_32bit_wire  ), 
	.k5_32bit_wire 		(LEFT_k5_32bit_wire  ), 
	.k6_32bit_wire 		(LEFT_k6_32bit_wire  ), 
	.ir_32bit_0_wire 	(LEFT_ir_32bit_0_wire), 
	.ir_32bit_1_wire 	(LEFT_ir_32bit_1_wire), 
	.ir_32bit_2_wire 	(LEFT_ir_32bit_2_wire), 
	.ir_32bit_3_wire 	(LEFT_ir_32bit_3_wire), 
	.ir_32bit_4_wire 	(LEFT_ir_32bit_4_wire), 
	.ir_32bit_5_wire 	(LEFT_ir_32bit_5_wire), 
	.ir_32bit_6_wire 	(LEFT_ir_32bit_6_wire), 
	.ir_32bit_7_wire 	(LEFT_ir_32bit_7_wire), 
	.ir_32bit_8_wire 	(LEFT_ir_32bit_8_wire),
	.u0_32bit_wire 		(LEFT_u0_32bit_wire  ), 
	.v0_32bit_wire 		(LEFT_v0_32bit_wire  ), 
	.fx_32bit_wire 		(LEFT_fx_32bit_wire  ), 
	.fy_32bit_wire 		(LEFT_fy_32bit_wire  )
	
);

rectify
#(
	.LEFT_RIGHT    ("R") ,          
	.INPUTDATAWID  (9  ) ,    
	.IMAGE_WIDTH   (640) ,
	.IMAGE_HEIGHT  (480) ,
	.OUTPUTDATAWID (9  ) 
  )
U_rectify_right
(
	.clk                (MCLK)    ,         // 150 Clock   
	.en                 (EN)    ,     
	.pixelEN            (PIXEL_EN)    ,
	.image_stream       (RIGHT_IMAGE_IN)       ,         // W*H       
	.rectified_stream   (rectified_stream_right)  ,            
	.rst_n              (RSTN)  ,            // Asynchronous reset active low
	.k1_32bit_wire 		(RIGHT_k1_32bit_wire  ),
	.k2_32bit_wire 		(RIGHT_k2_32bit_wire  ),
	.p1_32bit_wire 		(RIGHT_p1_32bit_wire  ),
	.p2_32bit_wire 		(RIGHT_p2_32bit_wire  ),
	.k3_32bit_wire 		(RIGHT_k3_32bit_wire  ),
	.k4_32bit_wire 		(RIGHT_k4_32bit_wire  ),
	.k5_32bit_wire 		(RIGHT_k5_32bit_wire  ),
	.k6_32bit_wire 		(RIGHT_k6_32bit_wire  ),
	.ir_32bit_0_wire 	(RIGHT_ir_32bit_0_wire),
	.ir_32bit_1_wire 	(RIGHT_ir_32bit_1_wire),
	.ir_32bit_2_wire 	(RIGHT_ir_32bit_2_wire),
	.ir_32bit_3_wire 	(RIGHT_ir_32bit_3_wire),
	.ir_32bit_4_wire 	(RIGHT_ir_32bit_4_wire),
	.ir_32bit_5_wire 	(RIGHT_ir_32bit_5_wire),
	.ir_32bit_6_wire 	(RIGHT_ir_32bit_6_wire),
	.ir_32bit_7_wire 	(RIGHT_ir_32bit_7_wire),
	.ir_32bit_8_wire 	(RIGHT_ir_32bit_8_wire),
	.u0_32bit_wire 		(RIGHT_u0_32bit_wire  ),
	.v0_32bit_wire 		(RIGHT_v0_32bit_wire  ),
	.fx_32bit_wire 		(RIGHT_fx_32bit_wire  ),
	.fy_32bit_wire 		(RIGHT_fy_32bit_wire  )
	
);
// `else 
// 	assign rectified_stream_left  = LEFT_IMAGE_IN  ;
// 	assign rectified_stream_right = RIGHT_IMAGE_IN ;

wire [8:0] data_to_census_left, data_to_census_right ;

assign data_to_census_left  = (enable_rectifty == 1'b1) ? rectified_stream_left   : LEFT_IMAGE_IN  ;
assign data_to_census_right = (enable_rectifty == 1'b1) ? rectified_stream_right  : RIGHT_IMAGE_IN ;


// `endif  // __rectify

census_transform 
#(
	 .BUSDATAWID       (9   ),         // MSB = SOF
	 .LINEBUFFERLEN    (640 ),         // 640 byte
	 .OUTPUTDATAWID    (63  )          // MSB = SOF 
  )
uCensusTransform_left
(
	.clk      (MCLK)          ,   // 150 Clock
	.en       (EN & PIXEL_EN)          ,
	.data_in  (data_to_census_left)          ,
	.data_out (left_image_census_transform)          ,   //  
	.rst_n    (RSTN)              // Asynchronous reset active low
);

census_transform 
#(
	 .BUSDATAWID       (9   ),         // MSB = SOF
	 .LINEBUFFERLEN    (640 ),         // 640 byte
	 .OUTPUTDATAWID    (63  )          // MSB = SOF 
  )
uCensusTransform_right
(
	.clk      (MCLK)          ,   // 150 Clock
	.en       (EN & PIXEL_EN )          ,
	.data_in  (data_to_census_right)          ,
	.data_out (right_image_census_transform)          ,   //  
	.rst_n    (RSTN)              // Asynchronous reset active low
);

matching_cost
#(
	.MAXDISPARITY (64)  ,
	.MATCHINGCOSTBITWID (6) ,
	.INPUTDATAWID (63),     // 62bit + 1 (SOF)
	.OUTPUTDATAWID (385)    // 6 * 64 + 1(SOF) 

  )
uMatchingCTcost 
(
	.clk              (MCLK)                 ,                   // 150 Clock
	.en               (EN & PIXEL_EN )               ,         
	.leftCTstream     (left_image_census_transform )                      ,
	.rightCTstream    (right_image_census_transform)                      ,
	.MatchingCost     (CPDi_1D)                    ,   
	.rst_n            (RSTN)                                     // Asynchronous reset active low
	
);


LPDiLeftVolumn
#(
	.IMAGE_WIDTH    (640) ,
	.IMAGE_HEIGHT   (480) ,
	.MAXDISPARITY   (64) ,
	.PENALTY1       (10) ,
 	.PENALTY2       (60) ,
	.CPDI_WIDTH     (6) ,
	.LPDI_WIDTH     (8) ,
	.INPUTDATAWID   (385) , // 6 * 64 + 1(SOF)
	.OUTPUTDATAWID  (513)   // 8 * 64  
  )
U_LPDiLeftVolumn
(
	.clk       (MCLK)                     ,         // 150 Clock
	.en        (EN)                      ,
	.pixelEN   (PIXEL_EN)         	     ,         // clk / 8
	.CPDi_1D   (CPDi_1D  )               ,  // (CPDi_DataGen_1D_wire)    , 
	.LPDi      (LPDi)                        ,         // W*H*D volumn                  
	.rst_n     (RSTN)                                  // Asynchronous reset active low
	
) ;


LPDiRightVolumn
#(
	.MAXDISPARITY    (64  ) ,
	.INPUTDATAWID    (513 ) ,    // 8 * 64 + 1(SOF)
	.LPDI_WIDTH      (8   ),
	.OUTPUTDATAWID   (513 )
  )
u_LPDiRightVolumn
(
	.clk          (MCLK)                  ,         // 150 Clock
	.en           (EN)                   ,
	.pixelEN      (PIXEL_EN)              ,
	.LPDiLeft_in  (LPDi)                 ,         // W*H*D volumn     
	.LPDiRight    (LPDiRight)            ,         // W*H*D volumn   
	.LPDiLeft     (LPDiLeft)             ,         // W*H*D volumn               
	.rst_n        (RSTN)                          // Asynchronous reset active low
);


// winner takes all 
WTA
#(
	.MAXDISPARITY  (64 ) ,
	.LPDI_WIDTH    (8  ) ,
	.INPUTDATAWID  (513) ,    // 8 * 64 + 1(SOF)
	.OUTPUTDATAWID (9  )
  )
u_wta_left 
(
	.clk          (MCLK)       ,        
	.en           (EN)       ,
	.pixelEN      (PIXEL_EN)       , 
	.LPDi         (LPDiLeft)       ,        
	.disparity    (disparity_left)       ,        
	.rst_n        (RSTN)                
	
);

WTA
#(
	.MAXDISPARITY  (64 ) ,
	.LPDI_WIDTH    (8  ) ,
	.INPUTDATAWID  (513) ,    // 8 * 64 + 1(SOF)
	.OUTPUTDATAWID (9  )
  )
u_wta_right 
(
	.clk          (MCLK)       ,        
	.en           (EN)       ,
	.pixelEN      (PIXEL_EN)       , 
	.LPDi         (LPDiRight)       ,        
	.disparity    (disparity_right)       ,        
	.rst_n        (RSTN)                
	
);


medianFilter
#(
	.INPUTDATAWID   (9   ),    
	.IMAGE_WIDTH    (640 ),
	.OUTPUTDATAWID  (9   )
 )
 median_left
(
	.clk                    (MCLK)          ,         // 150 Clock   
	.en                     (EN)          ,     
	.pixelEN                (PIXEL_EN)          ,
	.disparity              (disparity_left)          ,         // W*H       
	.disparity_filtered     (disparity_left_filtered)          ,            
	.rst_n                  (RSTN)                    // Asynchronous reset active low
	
);

medianFilter 
#(
	.INPUTDATAWID   (9   ),    
	.IMAGE_WIDTH    (640 ),
	.OUTPUTDATAWID  (9   )
 )
median_right
(
	.clk                    (MCLK)          ,         // 150 Clock   
	.en                     (EN)          ,     
	.pixelEN                (PIXEL_EN)          ,
	.disparity              (disparity_right)          ,         // W*H       
	.disparity_filtered     (disparity_right_filtered)          ,            
	.rst_n                  (RSTN)                    // Asynchronous reset active low
	
); 


LeftRightCheck
#(
	.MAXDISPARITY  ( 64 ),
	.INPUTDATAWID  ( 9  ),    // 8   + 1(SOF)
	.DISP_WIDTH    ( 8  ),
	.OUTPUTDATAWID ( 9  )
  )
u_LeftRifhtCheck
(
	.clk                (MCLK)            ,         // 150 Clock
	.en                 (EN)            ,
	.pixelEN            (PIXEL_EN)            ,
	.Disparity_Left     (disparity_left_filtered)            ,         
	.Disparity_Right    (disparity_right_filtered)            ,         
	.dispOutput_left    (dispOutput_left)            ,
	.dispOutput_left_valid ()   ,
	.rst_n              (RSTN)                       
);



 // // debug linebuffer in median filter

 //    reg[10:0] debug_dataCnt = 0 ; 
	// always@(posedge MCLK)
	// if(EN && PIXEL_EN)
	// begin
	// 	if(debug_dataCnt == 11'd639)
	// 		debug_dataCnt <= 0 ;
	// 	else 
	// 		debug_dataCnt <= debug_dataCnt + 1'b1 ;
	// end



// fillinHoles
// #(
// 	.INPUTDATAWID   (9   ),    
// 	.IMAGE_WIDTH    (640 ),
// 	.OUTPUTDATAWID  (9   )
//  )
// fillinwholes_output
// (
// 	.clk                    (MCLK)          ,         // 150 Clock   
// 	.en                     (EN)          ,     
// 	.pixelEN                (PIXEL_EN)          ,
// 	.disparity              (dispOutput_left)          ,         
// 	.disparity_filtered     (dispOutput_left_fill_wholes)          ,            
// 	.rst_n                  (RSTN)                    // Asynchronous reset active low
	
// );

`ifdef  __filter_resource 


remove_noise
#(
	.INPUTDATAWID   (9   ),    
	.IMAGE_WIDTH    (640 ),
	.OUTPUTDATAWID  (9   )
 )
remove_noise_output
(
	.clk                    (MCLK)          ,         // 150 Clock   
	.en                     (EN)          ,     
	.pixelEN                (PIXEL_EN)          ,
	.disparity              (dispOutput_left)          ,         
	.disparity_filtered     (dispOutput_left_removed_noise)          ,            
	.rst_n                  (RSTN)                    // Asynchronous reset active low
	
);

medianFilter
#(
	.INPUTDATAWID   (9   ),    
	.IMAGE_WIDTH    (640 ),
	.OUTPUTDATAWID  (9   )
 )
median_output_pre
(
	.clk                    (MCLK)          ,         // 150 Clock   
	.en                     (EN)          ,     
	.pixelEN                (PIXEL_EN)          ,
	.disparity              ( dispOutput_left_removed_noise)          ,         // W*H       
	.disparity_filtered     ( dispOutput_left_filtered_pre)          ,            
	.rst_n                  (RSTN)                    // Asynchronous reset active low
	
);





medianFilter
#(
	.INPUTDATAWID   (9   ),    
	.IMAGE_WIDTH    (640 ),
	.OUTPUTDATAWID  (9   )
 )
median_output
(
	.clk                    (MCLK)          ,         // 150 Clock   
	.en                     (EN)          ,     
	.pixelEN                (PIXEL_EN)          ,
	.disparity              ( dispOutput_left_filtered_pre)          ,         // W*H       
	.disparity_filtered     ( dispOutput_left_filtered)          ,            
	.rst_n                  (RSTN)                    // Asynchronous reset active low
	
);

`endif  // __filter_resource

endmodule