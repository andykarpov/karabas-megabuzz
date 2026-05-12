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

    always @(posedge clk) begin
        if (audio_abs > bar_val) 
            bar_val <= audio_abs;
        else if (sample_tick && (bar_val >= 1024))
            bar_val <= bar_val - 1024;
    end

    function [7:0] to_leds(input [15:0] val);
        begin
            to_leds = (val > 56000) ? 8'b11111111 :
                      (val > 48000) ? 8'b01111111 :
                      (val > 40000) ? 8'b00111111 :
                      (val > 32000) ? 8'b00011111 :
                      (val > 24000) ? 8'b00001111 :
                      (val > 16000) ? 8'b00000111 :
                      (val > 8000)  ? 8'b00000011 :
                      (val > 4000)  ? 8'b00000001 : 8'b00000000;
        end
    endfunction

    function [7:0] to_dot_bit(input [15:0] val);
        begin
            to_dot_bit = (val > 56000) ? 8'b10000000 :
                         (val > 48000) ? 8'b01000000 :
                         (val > 40000) ? 8'b00100000 :
                         (val > 32000) ? 8'b00010000 :
                         (val > 24000) ? 8'b00001000 :
                         (val > 16000) ? 8'b00000100 :
                         (val > 8000)  ? 8'b00000010 :
                         (val > 4000)  ? 8'b00000001 : 8'b00000000;
        end
    endfunction

    assign leds = ~to_leds(bar_val);

endmodule

