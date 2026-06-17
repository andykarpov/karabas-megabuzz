module resetter (
	input wire clk,
	input wire areset,
	input wire reset_in,
	output wire reset_out,
	output wire reset_short
);

// reset
reg reset = 0;
reg reset2 = 0;
reg [10:0] cnt_reset = 0; // initial reset counter
always @(posedge clk, posedge areset) begin
	 if (areset) begin
		reset <= 1;
		reset2 <= 1;
		cnt_reset <= 0;
	 end
	 else begin
		 reset2 <= 0;
		 if (reset_in) begin
			reset <= 1;
			reset2 <= 1;
			cnt_reset <= 0;
		 end else if (cnt_reset != 11'h7FF) begin
			reset <= 1;
			cnt_reset <= cnt_reset + 1;
		 end
		 else
			  reset <= 0;
	 end
end

assign reset_out = reset;
assign reset_short = reset2;

endmodule
