module vu_meter (
    input wire clk,
	 input wire reset,
    input wire sample_tick,                 
    input wire signed [15:0] audio_sample,  
    output wire [7:0] leds                  
);

   parameter DIR = 0;

	// vu_level (0..8 from signed audio sample)
	wire [3:0] level;
	vu_level vu_level(.clk(clk), .audio_sample(audio_sample), .level(level));

	// falling bar value (0..8)
	wire [3:0] bar_val;
	vu_falling #(.DELAY(3000)) vu_falling_bar(.clk(clk), .reset(reset), .sample_tick(sample_tick), .level(level), .out(bar_val));

	// falling dot value (0..8)
	wire [3:0] dot_val;
	vu_falling #(.DELAY(10000)) vu_falling_dot(.clk(clk), .reset(reset), .sample_tick(sample_tick), .level(level), .out(dot_val));

	// bar led data
	wire [7:0] bar_int;
	vu_leds #(.MODE(1), .DIR(DIR)) vu_leds_bar (.clk(clk), .level(bar_val), .out(bar_int));

	// dot led data
	wire [7:0] dot_int;
	vu_leds #(.MODE(2), .DIR(DIR)) vu_dots_bar (.clk(clk), .level(dot_val), .out(dot_int));

	// inverting the result value for our leds
	assign leds = ~(bar_int | dot_int);

endmodule

///////////////////////////////////////////////////////////////////////////

module vu_level (
	input wire clk,
	input wire signed [15:0] audio_sample,
	output reg [3:0] level
);

// absolute value 0..65535
reg [15:0] audio_abs = 0;
always @(posedge clk) begin
	if (audio_sample < 0)
		audio_abs <= -audio_sample;
	else 
		audio_abs <= audio_sample;
end
 
// level value 0-8
always @(posedge clk) begin
	level <= 
		(audio_abs > 10000) ? 8 :
		(audio_abs > 5000)  ? 7 :
		(audio_abs > 2000)  ? 6 :
		(audio_abs > 1000)  ? 5 :
		(audio_abs > 500)   ? 4 :
		(audio_abs > 200)   ? 3 :
		(audio_abs > 60)    ? 2 :
		(audio_abs > 20)    ? 1 : 
									 0;
end

endmodule

///////////////////////////////////////////////////////////////////////////

module vu_falling (
	input wire clk,
	input wire reset,
	input wire sample_tick,
	input wire [3:0] level,
	output reg [3:0] out
);

parameter DELAY = 3000;

reg [15:0] cnt = 0;
reg [2:0] sample_tick_r = 3'b000;

always @(posedge clk or posedge reset) begin
	if (reset) begin
		out <= 8;
		sample_tick_r <= 0;
		cnt <= 0;
	end else begin
		sample_tick_r <= {sample_tick_r[1:0], sample_tick};
		if (sample_tick_r[2:1] == 2'b01) begin
			if (level > out) begin
			  out <= level;
			  cnt <= 0;
			end else if (out > 0) begin
				if (cnt == DELAY) begin
					out <= out - 1;
					cnt <= 0;
				end else
					cnt <= cnt + 1;
			end
		end
	end
end

endmodule

///////////////////////////////////////////////////////////////////////////

module vu_leds (
	input wire clk,
	input wire [3:0] level,
	output reg [7:0] out
);

localparam MODE_BAR = 1;
localparam MODE_DOT = 2;
parameter MODE = MODE_BAR;

localparam DIR_NORMAL = 0;
localparam DIR_REVERSE = 1;
parameter DIR = DIR_NORMAL;

always @(posedge clk) begin
	if (DIR == DIR_NORMAL)
			case (level)
				8: out <= (MODE == MODE_BAR) ? 8'b11111111 : 8'b10000000;
				7: out <= (MODE == MODE_BAR) ? 8'b01111111 : 8'b01000000;
				6: out <= (MODE == MODE_BAR) ? 8'b00111111 : 8'b00100000;
				5: out <= (MODE == MODE_BAR) ? 8'b00011111 : 8'b00010000;
				4: out <= (MODE == MODE_BAR) ? 8'b00001111 : 8'b00001000;
				3: out <= (MODE == MODE_BAR) ? 8'b00000111 : 8'b00000100;
				2: out <= (MODE == MODE_BAR) ? 8'b00000011 : 8'b00000010;
				1: out <= (MODE == MODE_BAR) ? 8'b00000001 : 8'b00000001;
				default: out <= 8'b00000000;
			endcase
	else
			case (level)
				8: out <= (MODE == MODE_BAR) ? 8'b11111111 : 8'b00000001;
				7: out <= (MODE == MODE_BAR) ? 8'b11111110 : 8'b00000010;
				6: out <= (MODE == MODE_BAR) ? 8'b11111100 : 8'b00000100;
				5: out <= (MODE == MODE_BAR) ? 8'b11111000 : 8'b00001000;
				4: out <= (MODE == MODE_BAR) ? 8'b11110000 : 8'b00010000;
				3: out <= (MODE == MODE_BAR) ? 8'b11100000 : 8'b00100000;
				2: out <= (MODE == MODE_BAR) ? 8'b11000000 : 8'b01000000;
				1: out <= (MODE == MODE_BAR) ? 8'b10000000 : 8'b10000000;
				default: out <= 8'b00000000;
			endcase
end

endmodule
