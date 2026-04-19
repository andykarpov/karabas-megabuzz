module beeper(
	input wire clk,
	input wire reset,
	input wire cs,
	input wire [15:0] a,
	input wire [7:0] d,
	input wire ioreq_wr,
	output reg out_beeper
);

wire port_xxfe = ~a[0] && cs;
always @(posedge clk or posedge reset) begin
	if (reset || ~cs)
		out_beeper <= 0;
	else if (port_xxfe && ioreq_wr)
		out_beeper <= d[4];
end

endmodule
