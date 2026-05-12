module vu_meter (
    input wire clk,
	 input wire reset,
    input wire sample_tick,                 
    input wire signed [15:0] audio_sample,  
    output wire [7:0] leds                  
);

    reg [15:0] audio_abs = 0;

    always @(posedge clk) begin
        if (audio_sample < 0)
            audio_abs <= -audio_sample;
        else 
            audio_abs <= audio_sample;
    end

    reg [15:0] bar_val = 0;
	 reg [15:0] dot_val = 0;
	 reg [1:0] dot_cnt = 0;
	 reg [2:0] sample_tick_r = 3'b000;
	 
	 localparam STEP = 1;

    always @(posedge clk or posedge reset) begin
		if (reset) begin
			bar_val <= {16{1'b1}};
			dot_val <= {16{1'b1}};
			sample_tick_r <= 3'b000;
			dot_cnt <= 0;
		end else begin
			sample_tick_r <= {sample_tick_r[1:0], sample_tick};
			if (sample_tick_r[2:1] == 2'b01) begin

				if (audio_abs > bar_val)
				  bar_val <= audio_abs;
				else if (bar_val >= STEP)
				  bar_val <= bar_val - STEP;

				if (audio_abs > dot_val) begin
					dot_val <= audio_abs;
					dot_cnt <= 0;
				end else if (dot_val >= STEP) begin
					if (dot_cnt == 3)
						dot_val <= dot_val - STEP;
					dot_cnt <= dot_cnt + 1;
				end
			end
		end
    end
	 
	 reg [7:0] bar_int = 0;
	 reg [7:0] dot_int = 0;
	 always @(posedge clk) begin
		bar_int <=   (bar_val > 10000) ? 8'b11111111 :
						 (bar_val > 5000)  ? 8'b01111111 :
						 (bar_val > 2000)  ? 8'b00111111 :
						 (bar_val > 1000)  ? 8'b00011111 :
						 (bar_val > 500)   ? 8'b00001111 :
						 (bar_val > 200)   ? 8'b00000111 :
						 (bar_val > 60)    ? 8'b00000011 :
						 (bar_val > 20)    ? 8'b00000001 : 
											      8'b00000000;

		dot_int <=   (dot_val > 10000) ? 8'b10000000 :
						 (dot_val > 5000)  ? 8'b01000000 :
						 (dot_val > 2000)  ? 8'b00100000 :
						 (dot_val > 1000)  ? 8'b00010000 :
						 (dot_val > 500)   ? 8'b00001000 :
						 (dot_val > 200)   ? 8'b00000100 :
						 (dot_val > 60)    ? 8'b00000010 :
						 (dot_val > 20)    ? 8'b00000001 : 
											      8'b00000000;
	 end

    assign leds = ~(bar_int | dot_int);

endmodule

