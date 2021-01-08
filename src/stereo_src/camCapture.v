/*
	VGA 30 帧/秒
	YUV VGA 30fps, night mode 5fps
	Input Clock = 24Mhz, PCLK = 56MHz
*/

`timescale 1 ns / 1 ps
`default_nettype none

module camCapture (
	input  wire       								    aclk    			   ,       // 150 MCLK 

	// Ports of Axi Master Bus Interface M00_AXIS
	// input wire  m00_axis_aclk,
	// input wire  m00_axis_aresetn,
	output wire  m00_axis_tvalid,
	output wire [31 : 0] m00_axis_tdata,
	output wire [0 : 0] m00_axis_tuser,
	output wire  m00_axis_tlast,
	input wire  m00_axis_tready,
	output wire[3:0] m00_axis_tkeep ,

	// Ports of Axi Slave Bus Interface S00_AXIS
	// input wire  s00_axis_aclk,
	// input wire  m01_axis_aresetn,
	output wire  m01_axis_tvalid,
	output wire [31 : 0] m01_axis_tdata,
	output wire [0 : 0] m01_axis_tuser,
	output wire  m01_axis_tlast,
	input wire  m01_axis_tready,
	output wire[3:0] m01_axis_tkeep ,

	//cmos1 interface
	input wire                                       sys_clk_50m,
	inout wire                                       cmos1_scl,         //cmos i2c clock
	inout wire                                       cmos1_sda,         //cmos i2c data
	input wire                                       cmos1_vsync,       //cmos vsync
	input wire                                       cmos1_href,        //cmos hsync refrence
	input wire                                       cmos1_pclk,        //cmos pxiel clock      640*480 : 56M
	
	input  wire [9:0]                                cmos1_d,           //cmos data
	output wire                                      cmos1_reset,       //cmos reset


	//cmos2 interface
	output wire                                      cmos2_scl,         //cmos i2c clock
	inout  wire                                      cmos2_sda,         //cmos i2c data
	input  wire                                      cmos2_vsync,       //cmos vsync
	input  wire                                      cmos2_href,        //cmos hsync refrence
	input  wire                                      cmos2_pclk,        //cmos pxiel clock
	
	input  wire [9:0]                                cmos2_d,          //cmos data
	output wire                                      cmos2_reset       //cmos reset

);

assign m00_axis_tkeep = 4'b1111;
assign m01_axis_tkeep = 4'b1111;

wire clk_camera;
wire locked;
sys_clock sys_clock_m0
 (
 // Clock in ports
	.clk_in1(sys_clk_50m),
  // Clock out ports
	.clk_out1(clk_camera),           // 24MHz
  // Status and control signals
	.reset(1'b0),
	.locked(locked)
 );	

//CMOS OV5640上电延迟部分
wire initial_en;                       //OV5640 register configure enable
power_on_delay	power_on_delay_inst(
	.clk_50M                 (clk_camera),
	.reset_n                 (1'b1),	
	.camera1_rstn            (cmos1_reset),
	.camera2_rstn            (cmos2_reset),	
	.camera_pwnd             (),
	.initial_en              (initial_en)		
);
 
//-------------------------------------
//CMOS1 Camera初始化部�?
wire Cmos1_Config_Done;
reg_config	reg_config_inst1(
	.clk_25M                 (clk_camera),
	.camera_rstn             (cmos1_reset),
	.initial_en              (initial_en),		
	.i2c_sclk                (cmos1_scl),
	.i2c_sdat                (cmos1_sda),
	.reg_conf_done           (Cmos1_Config_Done),
	.reg_index               (),
	.clock_20k               ()

);

//-------------------------------------
//CMOS2 Camera初始化部�?
wire Cmos2_Config_Done;
reg_config	reg_config_inst2(
	.clk_25M                 (clk_camera),
	.camera_rstn             (cmos2_reset),
	.initial_en              (initial_en),		
	.i2c_sclk                (cmos2_scl),
	.i2c_sdat                (cmos2_sda),
	.reg_conf_done           (Cmos2_Config_Done),
	.reg_index               (),
	.clock_20k               ()

);

wire[15:0] cmos1_d_16bit;
wire cmos1_href_16bit;
reg[7:0] cmos1_d_d0;
reg cmos1_href_d0;
reg cmos1_vsync_d0;
wire cmos1_hblank;

wire[15:0] cmos2_d_16bit;
wire cmos2_href_16bit;
reg[7:0] cmos2_d_d0;
reg cmos2_href_d0;
reg cmos2_vsync_d0;
wire cmos2_hblank;
always@(posedge cmos1_pclk)
begin
    cmos1_d_d0 <= cmos1_d[9:2];
    cmos1_href_d0 <= cmos1_href;
    cmos1_vsync_d0 <= cmos1_vsync;
end

always@(posedge cmos2_pclk)
begin
    cmos2_d_d0 <= cmos2_d[9:2];
    cmos2_href_d0 <= cmos2_href;
    cmos2_vsync_d0 <= cmos2_vsync;
end

cmos_8_16bit cmos_8_16bit_m0(
	.rst(1'b0),
	.pclk(cmos1_pclk),
	.pdata_i(cmos1_d_d0),
	.de_i(cmos1_href_d0),
	
	.pdata_o(cmos1_d_16bit),
	.hblank(cmos1_hblank),
	.de_o(cmos1_href_16bit)
);

cmos_8_16bit cmos_8_16bit_m1(
	.rst(1'b0),
	.pclk(cmos2_pclk),
	.pdata_i(cmos2_d_d0),
	.de_i(cmos2_href_d0),
	
	.pdata_o(cmos2_d_16bit),
	.hblank(cmos2_hblank),
	.de_o(cmos2_href_16bit)
);


wire vid_io_in_active_video;
wire vid_io_in_clk;
wire[31:0] vid_io_in_data;
wire vid_io_in_hsync;
wire vid_io_in_vsync;
assign vid_io_in_clk = cmos1_pclk;
assign vid_io_in_active_video = cmos1_href_16bit;
assign vid_io_in_data = {8'd0,cmos1_d_16bit[4:0],3'd0,cmos1_d_16bit[10:5],2'd0,cmos1_d_16bit[15:11],3'd0};
assign vid_io_in_hsync = cmos1_href_d0;
assign vid_io_in_vsync = cmos1_vsync_d0;


wire vid1_io_in_active_video;
wire vid1_io_in_clk;
wire[31:0] vid1_io_in_data;
wire vid1_io_in_hsync;
wire vid1_io_in_vsync;
assign vid1_io_in_clk = cmos2_pclk;
assign vid1_io_in_active_video = cmos2_href_16bit;
assign vid1_io_in_data = {8'd0,cmos2_d_16bit[4:0],3'd0,cmos2_d_16bit[10:5],2'd0,cmos2_d_16bit[15:11],3'd0};
assign vid1_io_in_hsync = cmos2_href_d0;
assign vid1_io_in_vsync = cmos2_vsync_d0;


cmos_in_axi4s cmos_in_axi4s_m0
  (
  // Native video signals
  .vid_io_in_clk           (vid_io_in_clk              ), // Native video clock
  .vid_io_in_ce            (1'b1                       ), // Native video clock enable
  .vid_io_in_reset         (1'b0                       ), // Native video reset active high
  .vid_active_video        (vid_io_in_active_video     ), // Native video data enable
  .vid_vblank              (1'b0                       ), // Native video vertical blank
  .vid_hblank              (cmos1_hblank      ), // Native video horizontal blank
  .vid_vsync               (vid_io_in_vsync            ), // Native video vertical sync
  .vid_hsync               (vid_io_in_hsync            ), // Native video horizontal sync
  .vid_field_id            (1'b0                       ), // Native video field-id
  .vid_data                (vid_io_in_data             ), // Native video data 
  
  // AXI4-Stream signals
  .aclk                    (aclk                 ), // AXI4-Stream clock
  .aclken                  (1'b1               ), // AXI4-Stream clock enable
  .aresetn                 (1'b1              ), // AXI4-Stream reset active low 
  .m_axis_video_tdata      (m00_axis_tdata   ), // AXI4-Stream data
  .m_axis_video_tvalid     (m00_axis_tvalid  ), // AXI4-Stream valid 
  .m_axis_video_tready     (m00_axis_tready  ), // AXI4-Stream ready 
  .m_axis_video_tuser      (m00_axis_tuser   ), // AXI4-Stream tuser (SOF)
  .m_axis_video_tlast      (m00_axis_tlast   ), // AXI4-Stream tlast (EOL)
  .fid                     (                     ), // Field-id output


  // Video timing detector locked
	.axis_enable(1'b1)
);

cmos_in_axi4s cmos_in_axi4s_m1
  (
  // Native video signals
  .vid_io_in_clk           (vid1_io_in_clk              ), // Native video clock
  .vid_io_in_ce            (1'b1                       ), // Native video clock enable
  .vid_io_in_reset         (1'b0                       ), // Native video reset active high
  .vid_active_video        (vid1_io_in_active_video     ), // Native video data enable
  .vid_vblank              (1'b0                       ), // Native video vertical blank
  .vid_hblank              (cmos2_hblank      ), // Native video horizontal blank
  .vid_vsync               (vid1_io_in_vsync            ), // Native video vertical sync
  .vid_hsync               (vid1_io_in_hsync            ), // Native video horizontal sync
  .vid_field_id            (1'b0                       ), // Native video field-id
  .vid_data                (vid1_io_in_data             ), // Native video data 
  
  // AXI4-Stream signals
  .aclk                    (aclk                 ), // AXI4-Stream clock
  .aclken                  (1'b1               ), // AXI4-Stream clock enable
  .aresetn                 (1'b1              ), // AXI4-Stream reset active low 
  .m_axis_video_tdata      (m01_axis_tdata   ), // AXI4-Stream data
  .m_axis_video_tvalid     (m01_axis_tvalid  ), // AXI4-Stream valid 
  .m_axis_video_tready     (m01_axis_tready  ), // AXI4-Stream ready 
  .m_axis_video_tuser      (m01_axis_tuser   ), // AXI4-Stream tuser (SOF)
  .m_axis_video_tlast      (m01_axis_tlast   ), // AXI4-Stream tlast (EOL)
  .fid                     (                     ), // Field-id output

  // Video timing detector locked
	.axis_enable(1'b1)
);



/*
	camera input stream timing : 
                  ___     ___     ___     ___     ___     ___
	pclk    _____|   |___|   |___|   |___|   |___|   |___|   |___
				_ _______ _______ _______ _______ _______ _______
	pixelData  __X__Y____X___U___X__Y____X___V___X___Y___X___U___
            _____                                                      _____
	eol   _|     |____________________________________________________|     |____

			     |<----------640*2 pclk------------------------------------>|
*/
// sampling image data according to the stream timing sequence   , YUV , only use Y signal as the grayscale 





// synchronouzation FIFO  , at the output side detect the vsyn signal , to make sure left and right image are syned .






// interleave the left and right image stream  




// packed into axis (M_axis_s2mm for left image and right image stream respectively)





endmodule