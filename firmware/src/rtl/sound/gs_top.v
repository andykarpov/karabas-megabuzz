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
    input wire            host_reset,   // GS reset from the host (#33)
    input wire            host_nmi,     // NMI from the host (#33)
    output wire           gs_reset_out, // the GS is in reset

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
    output wire          rom_reload,    // the GS ROM in pages 0-1 was written to and the GS is reset: load it again
    input wire           reload_act,    // the loader copies the GS ROM again

    // NeoGS SD card (sd_arbiter)
    output wire          sd_cs_n,
    output wire          sd_req_t,
    output wire [7:0]    sd_tx,
    input  wire          sd_ack_t,
    input  wire [7:0]    sd_rx,
    input  wire          sd_det_n,

    // NeoGS MP3 (ngs_mp3)
    output wire          mc_ncs,
    output wire          mp_xrs,
    output wire          mc_wr,
    output wire          md_wr,
    output wire [7:0]    io_do,
    input  wire [7:0]    mc_read,
    input  wire          mc_busy,
    input  wire          mc_rd_wait,
    input  wire          mc_ready,
    input  wire          md_busy,
    input  wire          md_dreq,

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

    wire gs_reset = reset | loader_act | host_reset;

    // NeoGS software may clear RAMRO and change the GS ROM in pages 0-1 (the NeoGS BIOS of NeoTracker
    // and ngsplay is put at #0000, the NeoGS SD driver of the Evo ROM patches the command table).
    // A real NeoGS copies its ROM from flash again on every reset; here the loader does it on the
    // first reset after such a write. Until it is done the CPU stays in reset, the host side runs.
    reg rom_dirty = 1'b0, reload_pend = 1'b0;
    always @(posedge clk_bus) begin
        if ((loader_act & loader_ram_wr) | reload_act)
            rom_dirty <= 1'b0;
        else if (~gs_mem_wr_n & (gs_mem_addr[20:15] == 6'd0))
            rom_dirty <= 1'b1;
        if (reload_act)
            reload_pend <= 1'b0;
        else if (gs_reset & rom_dirty)
            reload_pend <= 1'b1;
    end
    assign rom_reload = reload_pend;
    wire cpu_hold = reload_pend | reload_act;
    assign gs_reset_out = gs_reset | cpu_hold;

    gs gs
    (
        .RESET(gs_reset),
        .HOLD(cpu_hold),
        .CLK(clk_bus),
        .CE(ce),
        .NMI(host_nmi),

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
        .MRD_n(gs_mem_rd_n),

        .SD_CS_n(sd_cs_n),
        .SD_REQ_T(sd_req_t),
        .SD_TX(sd_tx),
        .SD_ACK_T(sd_ack_t),
        .SD_RX(sd_rx),
        .SD_DET_n(sd_det_n),

        .MC_NCS(mc_ncs),
        .MP_XRS(mp_xrs),
        .MC_WR(mc_wr),
        .MD_WR(md_wr),
        .IO_DO(io_do),
        .MC_READ(mc_read),
        .MC_BUSY(mc_busy),
        .MC_RD_WAIT(mc_rd_wait),
        .MC_READY(mc_ready),
        .MD_BUSY(md_busy),
        .MD_DREQ(md_dreq)
    );

    // the upper 512 KB belong to the RAM of DivMMC
    wire reserved = reserve_upper & (gs_mem_addr[20:19] == 2'b11);

    // the write protection of the GS ROM (RAMRO) is done in gs
    wire ld = loader_act | reload_act;
    assign sram_a = ld ? loader_ram_a : gs_mem_addr;
    assign gs_mem_din = (ld | reserved) ? 8'hFF : sram_di;
    assign sram_do = ld ? loader_ram_do : gs_mem_dout;
    assign sram_oe = ld ? 1'b1 : (~gs_mem_wr_n & ~reserved);
    assign sram_wr_n = ld ? ~loader_ram_wr :
                       reserved ? 1'b1 : gs_mem_wr_n;
    assign sram_rd_n = (ld | reserved) ? 1'b1 : gs_mem_rd_n;

endmodule
