`timescale 1ns/100ps
`default_nettype none
// Random accesses of GS and of the host against a model of the SRAM with its real timing. Every value read
// is compared with a shadow copy; a read of a location in the middle of an access gives X and fails.
// Run: ./sram_arbiter_tb.sh

module sram_arbiter_tb;
    parameter integer RUN_US = 20000;
    parameter real PAD_OUT = 10.0;      // clock to pad, FPGA
    parameter real PAD_IN = 6.0;        // pad to input, FPGA
    parameter real T_AA = 45.0;
    parameter real T_WP = 35.0;
    parameter real T_OE = 22.0;

    reg clk_mem = 0, clk_bus = 0;
    always #3.5714 clk_mem = ~clk_mem;
    always #17.857 clk_bus = ~clk_bus;

    // ---------------------------------------------------------------- SRAM model
    wire [20:0] sram_a;
    wire [7:0] sram_d;
    wire sram_wr_n, sram_rd_n;
    wire [20:0] #(PAD_OUT) a_pad = sram_a;
    wire #(PAD_OUT) wr_pad = sram_wr_n;
    wire #(PAD_OUT) rd_pad = sram_rd_n;
    wire [7:0] #(PAD_OUT) d_pad = sram_d;

    reg [7:0] mem [0:2097151];
    integer i;
    initial for (i = 0; i < 2097152; i = i + 1) mem[i] = i ^ (i >> 8);

    real valid_at = 0, wr_fell = 0;
    always @(a_pad) valid_at = $realtime + T_AA;
    always @(negedge rd_pad) if ($realtime + T_OE > valid_at) valid_at = $realtime + T_OE;
    always @(negedge wr_pad) wr_fell = $realtime;
    always @(posedge wr_pad)
        if ($realtime < 100) ; // outputs settling after time 0
        else if ($realtime - wr_fell >= T_WP) mem[a_pad] = d_pad;
        else mem[a_pad] = 8'hxx;

    reg [7:0] q = 8'hzz;
    always #1 q = rd_pad ? 8'hzz : ($realtime >= valid_at) ? mem[a_pad] : 8'hxx;
    assign #(PAD_IN) sram_d = q;

    // ---------------------------------------------------------------- DUT
    reg host_req = 0, host_we = 0;
    reg [20:0] host_a = 0;
    reg [7:0] host_di = 0;
    wire [7:0] host_do;
    wire host_wait;
    wire gs_hold;
    reg [20:0] gs_a = 0;
    reg [7:0] gs_do = 0;
    reg gs_oe = 0, gs_wr_n = 1, gs_rd_n = 1;
    wire [7:0] gs_di;
    reg enable = 0;

    sram_arbiter dut (
        .clk_mem(clk_mem), .clk_bus(clk_bus), .reset(1'b0), .enable(enable),
        .host_req(host_req), .host_we(host_we), .host_a(host_a), .host_di(host_di),
        .host_do(host_do), .host_wait(host_wait),
        .gs_hold(gs_hold), .gs_a(gs_a), .gs_do(gs_do), .gs_oe(gs_oe),
        .gs_wr_n(gs_wr_n), .gs_rd_n(gs_rd_n), .gs_di(gs_di),
        .sram_a(sram_a), .sram_d(sram_d), .sram_wr_n(sram_wr_n), .sram_rd_n(sram_rd_n)
    );

    reg [7:0] shadow [0:2097151];
    initial for (i = 0; i < 2097152; i = i + 1) shadow[i] = i ^ (i >> 8);

    integer errors = 0, gs_reads = 0, gs_writes = 0, host_reads = 0, host_writes = 0, stalled = 0;
    real max_host = 0;

    // ---------------------------------------------------------------- GS: a T80 cycle per two CE: T1 starts, T2 takes the data
    reg ce = 0;
    always @(posedge clk_bus) ce <= ~ce;
    wire tick = ce & ~gs_hold;
    reg phase = 0;
    reg gs_write = 0;
    reg gs_write_next = 0;

    // the host region is the upper 512 KB, GS stays below it
    function [20:0] gs_addr(input integer dummy);
        gs_addr = $urandom % 21'h180000;
    endfunction

    always @(posedge clk_bus) begin
        if (ce & gs_hold) stalled <= stalled + 1;
        if (tick) begin
            if (phase == 0) begin
                gs_a <= gs_addr(0);
                gs_do <= $urandom;
                gs_write_next = (($urandom % 4) == 0);
                gs_write <= gs_write_next;
                gs_rd_n <= gs_write_next;
                gs_wr_n <= ~gs_write_next;
                gs_oe <= gs_write_next;
                phase <= 1;
            end else begin
                phase <= 0;
                gs_rd_n <= 1;
                gs_wr_n <= 1;
                if (gs_write) begin
                    shadow[gs_a] <= gs_do;
                    gs_writes <= gs_writes + 1;
                end else begin
                    gs_reads <= gs_reads + 1;
                    if (gs_di !== shadow[gs_a]) begin
                        errors <= errors + 1;
                        if (errors < 10) $display("%0t GS read %h: got %h, expected %h", $time, gs_a, gs_di, shadow[gs_a]);
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------- host
    integer gap;
    real t0;
    reg [20:0] a;
    reg [7:0] d;
    initial begin
        #200 enable = 1;
        forever begin
            gap = $urandom % 1500;
            #(gap + 50);
            a = 21'h180000 + ($urandom % 21'h20000);
            d = $urandom;
            host_a = a;
            host_di = d;
            host_we = (($urandom % 3) == 0);
            #3;
            t0 = $realtime;
            host_req = 1;
            #1;
            wait (!host_wait);
            if ($realtime - t0 > max_host) max_host = $realtime - t0;
            #2;
            if (host_we) begin
                shadow[a] = d;
                host_writes = host_writes + 1;
            end else begin
                host_reads = host_reads + 1;
                if (host_do !== shadow[a]) begin
                    errors = errors + 1;
                    if (errors < 10) $display("%0t host read %h: got %h, expected %h", $time, a, host_do, shadow[a]);
                end
            end
            #($urandom % 100);
            host_req = 0;
        end
    end

    initial begin
        #(RUN_US * 1000);
        // everything written has to be in the SRAM
        for (i = 0; i < 2097152; i = i + 1)
            if (mem[i] !== shadow[i]) begin
                errors = errors + 1;
                if (errors < 10) $display("final: %h has %h, expected %h", i, mem[i], shadow[i]);
            end
        $display("gs reads %0d writes %0d, host reads %0d writes %0d, GS CE stalled %0d, worst host latency %0.1f ns, errors %0d",
            gs_reads, gs_writes, host_reads, host_writes, stalled, max_host, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
