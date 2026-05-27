module resetter (
	input wire clk,
	input wire areset,
	input wire reset_in,
	output wire reset_out
);

// reset
reg reset = 0;
reg [8:0] cnt_reset = 0; // initial reset counter
always @(posedge clk, posedge areset) begin
	 if (areset) begin
		reset <= 1;
		cnt_reset <= 0;
	 end
	 else begin
		 if (reset_in) begin
			reset <= 1;
			cnt_reset <= 0;
		 end else if (cnt_reset != 9'h1FF) begin
			reset <= 1;
			cnt_reset <= cnt_reset + 1;
		 end
		 else
			  reset <= 0;
	 end
end

assign reset_out = reset;

endmodule
