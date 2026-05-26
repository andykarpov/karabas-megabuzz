/*-------------------------------------------------------------------------------
 Soundrive + Covox FB
 -------------------------------------------------------------------------------*/

module soundrive(
	input wire clk,
	input wire reset,
	input wire cs,
	
	input wire [15:0] a,
	input wire [7:0] d,
	input wire ioreq_wr,
	input wire rom_m1_access,
	
	output reg [7:0] out_a,
	output reg [7:0] out_b,
	output reg [7:0] out_c,
	output reg [7:0] out_d,
	output reg [7:0] out_fb	
);

always @(posedge clk or posedge reset) begin
	if (reset || ~cs) begin
		out_a <= 0;
		out_b <= 0;
		out_c <= 0;
		out_d <= 0;
		out_fb <= 0;
	end
	else if (cs && ioreq_wr && ~rom_m1_access) begin
		case (a[7:0])
			8'h0F: out_a <= d;
			8'h1F: out_b <= d;
			8'h3F: out_b <= d;
			8'h4F: out_c <= d;
			8'h5F: out_d <= d;
			8'hFB: out_fb <= d;
		endcase
	end
end

endmodule
