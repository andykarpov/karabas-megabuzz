`default_nettype none
/*
  -----------------------------------------------------------------------------
   General Sound Top
  -----------------------------------------------------------------------------
*/

module gs_top (
    // clocks
    input wire            clk_bus,
    input wire            ce,
    input wire            reset,

    // cpu input signals
    input wire [15:0]     a,
    input wire [7:0]      di,
    input wire            mreq_n,
    input wire            ioreq,        // synchronized host I/O cycle
    input wire            rd_n,
    input wire            wr_n,

    // data out to cpu
    output wire           oe,
    output wire [7:0]     do_bus,

    // interface to sram
    input  wire [7:0]    sram_di,
    output wire [7:0]    sram_do,
    output wire          sram_oe,
    output wire [20:0]   sram_a,
    output wire          sram_wr_n,
    output wire          sram_rd_n,

    input wire           reserve_upper,
    input wire 			 loader_act,
    input wire [20:0]    loader_ram_a,
    input wire [7:0]     loader_ram_do,
    input wire           loader_ram_wr,

    // sound output
    output wire signed [14:0] out_l,
    output wire signed [14:0] out_r

);

    // gs

    wire [20:0] gs_mem_addr;
    wire  [7:0] gs_mem_dout;
    wire  [7:0] gs_mem_din;
    wire        gs_mem_rd_n;
    wire        gs_mem_wr_n;

    wire gs_reset = reset | loader_act;

    gs gs
    (
        .RESET(gs_reset),
        .CLK(clk_bus),
        .CE(ce),

        .A(a),
        .DI(di),
        .DO(do_bus),
        .OE(oe),
        .WR_n(wr_n),
        .RD_n(rd_n),
        .IOREQ(ioreq),

        .OUT_L(out_l),
        .OUT_R(out_r),

        .MA(gs_mem_addr),
        .MDI(gs_mem_din),
        .MDO(gs_mem_dout),
        .MRFSH_n(),
        .MWE_n(gs_mem_wr_n),
        .MRD_n(gs_mem_rd_n)
    );

    wire is_rom = (gs_mem_addr < 32768);
    // the upper 512 KB belong to the RAM of DivMMC
    wire reserved = reserve_upper & (gs_mem_addr[20:19] == 2'b11);

    assign sram_a = (loader_act) ? loader_ram_a : gs_mem_addr;
    assign gs_mem_din = (loader_act | reserved) ? 8'hFF : sram_di;
    assign sram_do = (loader_act) ? loader_ram_do : gs_mem_dout;
    assign sram_oe = (loader_act) ? 1'b1 : (~gs_mem_wr_n & ~reserved);
    assign sram_wr_n = (loader_act) ? ~loader_ram_wr :
    (is_rom | reserved) ? 1'b1 : gs_mem_wr_n;
    assign sram_rd_n = (loader_act | reserved) ? 1'b1 : gs_mem_rd_n;

endmodule
