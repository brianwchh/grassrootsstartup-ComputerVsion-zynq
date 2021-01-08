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