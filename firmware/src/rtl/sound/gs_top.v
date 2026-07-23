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
    input wire            iorq_n,
    input wire            m1_n,
    input wire            rd_n,
    input wire            wr_n,

    // data out to cpu
    output wire           oe,
    output wire [7:0]     do_bus,

	// interface to sram
	inout  wire [7:0]    sram_d,
	output wire [20:0]   sram_a,
	output wire          sram_wr_n,
	output wire          sram_rd_n,

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
    .IORQ_n(iorq_n),
    .M1_n(m1_n),

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

assign sram_a = (loader_act) ? loader_ram_a : gs_mem_addr;
assign gs_mem_din = (loader_act) ? 8'hFF : sram_d;
assign sram_d = (loader_act) ? loader_ram_do : 
					 (~gs_mem_wr_n) ? gs_mem_dout : 8'bz;
assign sram_wr_n = (loader_act) ? ~loader_ram_wr : 
						 (is_rom) ? 1'b1 : gs_mem_wr_n;
assign sram_rd_n = (loader_act) ? 1'b1 : gs_mem_rd_n;

endmodule
