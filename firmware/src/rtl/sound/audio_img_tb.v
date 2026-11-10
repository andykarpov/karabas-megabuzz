`timescale 1ns / 1ps
`default_nettype none
// Feeds audio_img_vec.hex (left, right per line pair, one pair per 256 clocks) and dumps one output pair per
// 256 clocks. Driven by audio_img_tb.py, which checks the result against a bit-exact model.

module audio_img_tb;
    parameter N = 1;

    reg clk = 0;
    always #17.857 clk = ~clk;

    reg [15:0] vec [0:2*N-1];
    reg signed [15:0] in_l = 0, in_r = 0;
    wire signed [15:0] out_l, out_r;

    audio_img_lpf dut(.clk(clk), .in_l(in_l), .in_r(in_r), .out_l(out_l), .out_r(out_r));

    integer n = 0, c = 0, f;

    initial begin
        $readmemh("audio_img_vec.hex", vec);
        f = $fopen("audio_img_out.txt", "w");
    end

    always @(posedge clk) begin
        if (c % 256 == 100) begin
            if (n == N) begin
                $fclose(f);
                $finish;
            end
            in_l <= vec[2*n];
            in_r <= vec[2*n+1];
            n <= n + 1;
        end
        if (c % 256 == 230)
            $fdisplay(f, "%h %h", out_l, out_r);
        c <= c + 1;
    end
endmodule
