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

module color2gray 
#(         
	parameter  INPUTDATAWID  = 25,    
	parameter  OUTPUTDATAWID = 9
  )
(
	input wire                      clk                               ,         // 150 Clock   
	input wire                      en                                ,     
	input wire                      pixelEN                           ,
	input  wire[INPUTDATAWID-1:0]   stream_in                         ,         // {sof,rgb}       
	output wire[OUTPUTDATAWID-1:0]  stream_out                        ,         // {sof,gray}
	input wire						rst_n                                       
);



/*  

	RGB to grayscale G =  B*0.07 + G*0.72 + R* 0.21
                         ____________
                        |            |
	  ----rgb---------->  | color2gray |-------gray------->
	  -----sof--------->  |            |-------sof-------->
                        |____________|  



      B --------(x)--------------
                 |                \
      0.07 ------                  \
                                    \
	    G --------(x)------------------(+)------------>  gray 
                 |                  /
      0.72 ------                  /
                                  /
      R --------(x)---------------
                 |
      0.21 ------

	the whole process takes 2 pixel clock cycles 

*/  

wire [7:0] R = stream_in[23:16] ;
wire [7:0] G = stream_in[15:8 ] ;
wire [7:0] B = stream_in[7 :0 ] ;
wire  sof_in = stream_in[24]    ;

wire [15:0] B_coef  = 16'd4587    ;    // Q16  0.07 * (2**16-1)  unsigned
wire [15:0] G_coef  = 16'd47185   ;    // Q16  0.72
wire [15:0] R_coef  = 16'd13762   ;    // Q16  0.21

wire [16+8-1:0] B_prod , G_prod, R_prod ;   // unsigned 24Q16
wire [7:0] B_prod_trun, G_prod_trun, R_prod_trun ;   // unsigned 


// aQb : total a bits, fractional bit at bth location

mult_16Q16x8Q0 u_R
  (
    .CLK    (clk   ) ,   
    .A      (R_coef ) ,   // IN STD_LOGIC_VECTOR(8 DOWNTO 0);                   
    .B      (R) ,  // IN STD_LOGIC_VECTOR(10 DOWNTO 0);         
    .CE     (pixelEN & en ) ,   
    .P      (R_prod)  
  );

mult_16Q16x8Q0 u_G
  (
    .CLK    (clk   ) ,   
    .A      (G_coef ) ,   // IN STD_LOGIC_VECTOR(8 DOWNTO 0);                   
    .B      (G) ,  // IN STD_LOGIC_VECTOR(10 DOWNTO 0);         
    .CE     (pixelEN & en ) ,   
    .P      (G_prod)  
  );

mult_16Q16x8Q0 u_B
  (
    .CLK    (clk   ) ,   
    .A      (B_coef ) ,   // IN STD_LOGIC_VECTOR(8 DOWNTO 0);                   
    .B      (B) ,  // IN STD_LOGIC_VECTOR(10 DOWNTO 0);         
    .CE     (pixelEN & en ) ,   
    .P      (B_prod)  
  );

assign B_prod_trun = B_prod[23:16] + B_prod[15];
assign G_prod_trun = G_prod[23:16] + G_prod[15];
assign R_prod_trun = R_prod[23:16] + R_prod[15];

// add up 
reg [7:0] grayV ;
reg [1:0] sof_delay ;

always@(posedge clk)
if(en && pixelEN)
begin
	{sof_delay[1],sof_delay[0]} <= {sof_delay[0],sof_in} ;
	grayV <= B_prod_trun + R_prod_trun + G_prod_trun ;   // I swear to God, it won't overflow ^_^, because it is averaging ..... 
end

assign stream_out = {sof_delay[1],grayV} ;  // aligned with sof_delay[2-1]

endmodule