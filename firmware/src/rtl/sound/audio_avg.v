`default_nettype none
/*
  The FIR takes its input every 32 clocks. A sample changing between two of those would have its edge moved
  by up to 1.14 us, a large signal dependent noise at high frequencies: average instead, so that the position
  of the edge within the 32 clocks is kept in the value.
*/

module audio_avg (
    input wire clk,                     // 28 MHz
    input wire signed [15:0] in_l,
    input wire signed [15:0] in_r,
    output reg signed [15:0] out_l = 0,
    output reg signed [15:0] out_r = 0
);

    reg [4:0] cnt = 0;
    reg signed [20:0] acc_l = 0, acc_r = 0;

    wire signed [20:0] sum_l = acc_l + in_l;
    wire signed [20:0] sum_r = acc_r + in_r;

    always @(posedge clk) begin
        cnt <= cnt + 1'b1;
        if (cnt == 5'd31) begin
            out_l <= sum_l >>> 5;
            out_r <= sum_r >>> 5;
            acc_l <= 0;
            acc_r <= 0;
        end else begin
            acc_l <= sum_l;
            acc_r <= sum_r;
        end
    end

endmodule
