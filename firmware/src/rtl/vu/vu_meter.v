module vu_meter (
    input wire clk,
    input wire sample_tick,                 
    input wire signed [15:0] audio_sample,  
    output wire [7:0] leds                  
);

    reg [15:0] audio_abs;

    always @(posedge clk) begin
        if (audio_sample < 0)
            audio_abs <= -audio_sample;
        else 
            audio_abs <= audio_sample;
    end

    reg [15:0] bar_val;
	 reg prev_sample_tick;
	 
	 localparam STEP = 16;

    always @(posedge clk) begin
		prev_sample_tick <= sample_tick;
		if (sample_tick && ~prev_sample_tick) begin
        if (audio_abs > bar_val)
            bar_val <= audio_abs;
        else if (bar_val >= STEP)
            bar_val <= bar_val - STEP;
		 end
    end

    function [7:0] to_leds(input [15:0] val);
        begin
            to_leds = (val > 10000) ? 8'b11111111 :
                      (val > 5000)  ? 8'b01111111 :
                      (val > 2000)  ? 8'b00111111 :
                      (val > 1000)  ? 8'b00011111 :
                      (val > 500)   ? 8'b00001111 :
                      (val > 200)   ? 8'b00000111 :
                      (val > 60)    ? 8'b00000011 :
                      (val > 20)    ? 8'b00000001 : 8'b00000000;
        end
    endfunction

    assign leds = ~to_leds(bar_val);

endmodule

