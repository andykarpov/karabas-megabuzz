`timescale 1ns / 1ps
`default_nettype wire

/*
 kg_pcm5102.v

 I2S transmitter for the PCM5102 DAC, 16 bits per channel, 32 bck per frame (the DAC detects the
 format from the clocks, no MCLK): the replacement of pcm5102.v with the same clocks.
 - bck = clk / 2^(DIV_BITS+2), lrck = bck / 32 (DIV_BITS 1, clk 28 MHz: 7 MHz bck, 218 kHz),
   lrck low = left; lrck and din change with the falling bck;
 - left and right are taken together at the start of the left word, all 16 bits of both go out,
   MSB first, one bck after the lrck edge (bit 0 of a word is in the first slot after it).
 pcm5102.v sent bits 15..1: bit 0 came from index 16 of a 16-bit register (X in simulation,
 bit 0 of the wrong channel after XST, changing with the rising bck).
*/

module kg_pcm5102 #(
	parameter DIV_BITS = 1
) (
	input wire clk,
	input wire reset,
	input wire [15:0] left,  // two's complement
	input wire [15:0] right,
	output reg din = 1'b0,
	output reg bck = 1'b0,
	output reg lrck = 1'b0
);

reg [DIV_BITS:0] div = 0;
reg [5:0] step = 6'd0;   // bit 0 = bck, bits 5..1 = slot of the frame
reg [30:0] sr = 31'd0;   // the bits of the frame still to send, MSB next

always @(posedge clk) begin
	if (reset) begin
		div <= 0;
		step <= 6'd0;
	end
	else begin
		div <= div + 1'b1;
		if (div == 0) begin
			step <= step + 6'd1;
			bck <= step[0];
			lrck <= step[5];
			// a new bit with the falling bck: slot 1 starts the frame with the MSB of left,
			// slot 0 sends bit 0 of right of the frame before
			if (!step[0]) begin
				if (step[5:1] == 5'd1) begin
					din <= left[15];
					sr <= { left[14:0], right };
				end
				else begin
					din <= sr[30];
					sr <= { sr[29:0], 1'b0 };
				end
			end
		end
	end
end

endmodule
