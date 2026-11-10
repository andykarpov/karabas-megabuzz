`timescale 1ns / 1ps
`default_nettype none
// Feeds audio_fir_vec.hex (left, right per line pair, one pair per 32 clocks) and dumps one output per 256 clocks.
// Driven by audio_fir_tb.py, which also checks the result against a bit-exact model.

module audio_fir_tb;
    parameter N = 1;

    reg clk = 0;
    always #17.857 clk = ~clk;

    reg [15:0] vec [0:2*N-1];
    reg signed [15:0] in_l = 0, in_r = 0;
    wire signed [15:0] out_l, out_r;

    // the second pair of channels gets the same data, swapped: it has to give the same results
    wire signed [15:0] out2_l, out2_r;
    audio_fir_decim dut(.clk(clk), .in_l(in_l), .in_r(in_r), .in2_l(in_r), .in2_r(in_l),
                        .out_l(out_l), .out_r(out_r), .out2_l(out2_l), .out2_r(out2_r));

    integer n = 0, c = 0, f;

    initial begin
        $readmemh("audio_fir_vec.hex", vec);
        f = $fopen("audio_fir_out.txt", "w");
    end

    always @(posedge clk) begin
        if (c % 32 == 0) begin
            if (n == N) begin
                $fclose(f);
                $finish;
            end
            in_l <= vec[2*n];
            in_r <= vec[2*n+1];
            n <= n + 1;
        end
        if (c % 256 == 200)
            $fdisplay(f, "%h %h %h %h", out_l, out_r, out2_l, out2_r);
        c <= c + 1;
    end
endmodule
