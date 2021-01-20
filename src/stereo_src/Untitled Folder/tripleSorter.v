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

module tripleSorter (
	input wire[7:0]  A0 ,
	input wire[7:0]  A1 ,
	input wire[7:0]  A2 ,

	output wire[7:0] max ,
	output wire[7:0] med ,
	output wire[7:0] min 	
);

/*   
              _____
             | max |_____
       ______|     |
	A0       |     |
		     |     |
	   ______| min |_____
	A1	     |_____|

                                          _____
                                         | max |_____
                                   ______|     |
                            	A0       |     |
                            		     |     |
                            	   ______| min |_____
                            	A1	     |_____|
                            
	          _____
             | max |_____
       ______|     |
	A0       |     |
		     |     |
	   ______| min |_____
	A1	     |_____|
*/



reg[7:0] A0A1_max , A0A1_min ;
reg[7:0] A0A1minCmpA2_min , A0A1minCmpA2_max ;
reg[7:0] max_out, med_out ;

always@(*)
begin
	if(A0 > A1)
	begin
		A0A1_max = A0 ;
		A0A1_min = A1 ;
	end
	else begin
		A0A1_max = A1 ;
		A0A1_min = A0 ;
	end
end

always@(*)
begin
	if(A0A1_min > A2)
	begin
		A0A1minCmpA2_max = A0A1_min ;
		A0A1minCmpA2_min = A2 ;
	end
	else begin
		A0A1minCmpA2_max = A2 ;
		A0A1minCmpA2_min = A0A1_min ;
	end
end

always@(*)
begin
	if(A0A1minCmpA2_max > A0A1_max)
	begin
		max_out = A0A1minCmpA2_max ;
		med_out = A0A1_max ;
	end
	else begin
		max_out = A0A1_max ;
		med_out = A0A1minCmpA2_max  ;
	end
end

assign max = max_out ;
assign min = A0A1minCmpA2_min ;
assign med = med_out ;

endmodule