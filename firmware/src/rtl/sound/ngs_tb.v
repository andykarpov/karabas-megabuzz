`timescale 1ns / 1ps
`default_nettype none
// ----------------------------------------------------------------------------
// NeoGS ports testbench: gs.v (with a bus model in place of T80s) + ngs_mp3 +
// vs1053 + sd_arbiter + zc_spi (the host side), a VS1053 SCI/SDI model and an
// SD card model. Run: ./ngs_tb.sh  (chip mode, then -DRV32 for neorv32 mode)
// ----------------------------------------------------------------------------

// Bus model of T80s (T2Write = 1, IOWait = 1) as seen on its pins: the strobes
// go low on a CE edge and go high on the first later CE edge with WAIT_n = 1,
// where DI is sampled. Checked against the real T80s in GHDL: there the strobes
// also stay low while WAIT_n = 0 and DI is taken on the edge where they go
// high; without a wait the real cycle is one CE longer, so this model is stricter.
module t80s #(parameter Mode = 0, parameter T2Write = 1, parameter IOWait = 1) (
    input  wire        RESET_n,
    input  wire        CLK,
    input  wire        CEN,
    input  wire        WAIT_n,
    input  wire        INT_n,
    input  wire        NMI_n,
    input  wire        BUSRQ_n,
    output reg         M1_n,
    output reg         MREQ_n,
    output reg         IORQ_n,
    output reg         RD_n,
    output reg         WR_n,
    output wire        RFSH_n,
    output wire        HALT_n,
    output wire        BUSAK_n,
    output reg  [15:0] A,
    input  wire [7:0]  DI,
    output reg  [7:0]  DO
);
    assign RFSH_n = 1'b1;
    assign HALT_n = 1'b1;
    assign BUSAK_n = 1'b1;
    initial begin
        M1_n = 1; MREQ_n = 1; IORQ_n = 1; RD_n = 1; WR_n = 1; A = 16'h0000; DO = 8'h00;
    end
    integer waits;
    task ce; begin @(posedge CLK); while (!CEN) @(posedge CLK); end endtask
    task cycle(input is_io, input is_wr, input [15:0] adr, input [7:0] d, output [7:0] q);
        begin
            ce; // T1
            A <= adr; DO <= d;
            if (is_io) IORQ_n <= 0; else MREQ_n <= 0;
            if (is_wr) WR_n <= 0; else RD_n <= 0;
            waits = 0;
            ce;
            while (!WAIT_n) begin waits = waits + 1; ce; end
            q = DI;
            IORQ_n <= 1; MREQ_n <= 1; RD_n <= 1; WR_n <= 1;
            ce; ce; // the rest of the cycle and the next opcode fetch
        end
    endtask
    reg [7:0] dummy;
    task io_wr(input [7:0] p, input [7:0] d); cycle(1, 1, {8'h00, p}, d, dummy); endtask
    task io_rd(input [7:0] p, output [7:0] q); cycle(1, 0, {8'h00, p}, 8'h00, q); endtask
    task mem_rd(input [15:0] adr, output [7:0] q); cycle(0, 0, adr, 8'h00, q); endtask
    task mem_wr(input [15:0] adr, input [7:0] d); cycle(0, 1, adr, d, dummy); endtask
endmodule

module ngs_tb;
    reg clk_mem = 0, clk_bus = 0;
    always #3.571 clk_mem = ~clk_mem;               // 140 MHz
    reg [2:0] div = 0;
    always @(posedge clk_mem) begin                 // 28 MHz from it, as the PLL does
        div <= (div == 4) ? 0 : div + 1;
        if (div == 0 || div == 2) clk_bus <= ~clk_bus;
    end
    reg ce = 0;
    always @(posedge clk_bus) ce <= ~ce;

    reg reset = 1;
    reg gs_reset_in = 0;
    wire gs_reset = reset | gs_reset_in;

    integer errors = 0;
    task check(input cond, input [8*64-1:0] what);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s (t=%0t)", what, $time);
            end
        end
    endtask

    // ------------------------------------------------------------------ GS
    wire [20:0] ma;
    wire [7:0] mdo;
    wire mwe_n, mrd_n;
    wire gs_sd_cs_n, gs_sd_req_t, gs_sd_ack_t;
    wire [7:0] gs_sd_tx, gs_sd_rx;
    wire mc_ncs, mp_xrs, mc_wr, md_wr, mc_busy, mc_rd_wait, mc_ready, md_busy, md_dreq;
    wire [7:0] io_do, mc_read;
    reg  sd_det_n = 0;

    reg [15:0] host_a = 16'h0000;
    reg [7:0]  host_d = 8'h00;
    reg host_wr_n = 1, host_rd_n = 1, host_ioreq = 0;
    wire [7:0] gs_host_do;

    gs gs_inst(
        .CLK(clk_bus), .RESET(gs_reset), .CE(ce), .NMI(1'b0),
        .A(host_a), .DI(host_d), .DO(gs_host_do), .OE(), .WR_n(host_wr_n), .RD_n(host_rd_n), .IOREQ(host_ioreq),
        .MA(ma), .MDI(8'h5A), .MDO(mdo), .MRFSH_n(), .MWE_n(mwe_n), .MRD_n(mrd_n),
        .SD_CS_n(gs_sd_cs_n), .SD_REQ_T(gs_sd_req_t), .SD_TX(gs_sd_tx), .SD_ACK_T(gs_sd_ack_t), .SD_RX(gs_sd_rx), .SD_DET_n(sd_det_n),
        .MC_NCS(mc_ncs), .MP_XRS(mp_xrs), .MC_WR(mc_wr), .MD_WR(md_wr), .IO_DO(io_do), .MC_READ(mc_read),
        .MC_BUSY(mc_busy), .MC_RD_WAIT(mc_rd_wait), .MC_READY(mc_ready), .MD_BUSY(md_busy), .MD_DREQ(md_dreq),
        .OUT_L(), .OUT_R()
    );

    // ------------------------------------------------------------------ MP3
    wire ext_fifo_wr, ext_fifo_ack, ext_fifo_room, ext_soft_reset, ext_hard_reset, ext_vol_wr;
    wire [7:0] ext_fifo_din, ext_vol, cur_volume;
    wire sci_req, sci_rnw, sci_busy;
    wire [7:0] sci_addr;
    wire [15:0] sci_wdata, sci_rdata;
`ifdef RV32
    localparam USE_CHIP = 1'b0;
`else
    localparam USE_CHIP = 1'b1;
`endif

    ngs_mp3 ngs_mp3_inst(
        .clk(clk_bus), .reset(gs_reset), .present(1'b1), .use_chip(USE_CHIP),
        .mcncs(mc_ncs), .mpxrs(mp_xrs), .mc_wr(mc_wr), .mc_byte(io_do), .mc_read(mc_read),
        .mc_busy(mc_busy), .mc_rd_wait(mc_rd_wait), .mc_ready(mc_ready),
        .md_wr(md_wr), .md_byte(io_do), .md_busy(md_busy), .md_dreq(md_dreq),
        .ext_fifo_wr(ext_fifo_wr), .ext_fifo_din(ext_fifo_din), .ext_fifo_ack(ext_fifo_ack), .ext_fifo_room(ext_fifo_room),
        .ext_soft_reset(ext_soft_reset), .ext_hard_reset(ext_hard_reset), .ext_vol_wr(ext_vol_wr), .ext_vol(ext_vol),
        .cur_volume(cur_volume), .sci_req(sci_req), .sci_rnw(sci_rnw), .sci_addr(sci_addr), .sci_wdata(sci_wdata),
        .sci_busy(sci_busy), .sci_rdata(sci_rdata)
    );

    wire vs_sclk, vs_mosi, vs_cs_n, vs_dcs_n, vs_reset_n;
    reg  vs_miso = 0;
    reg  vs_dreq = 1;
`ifdef RV32
    reg  rv_fifo_rd = 0;
    wire [7:0] rv_fifo_data;
    wire rv_fifo_empty, rv_soft, rv_hard;
    wire [7:0] rv_vol;
    integer rv_bytes = 0;
    always @(posedge clk_bus) begin             // neorv32 stand-in: drains the FIFO
        rv_fifo_rd <= 0;
        if (!rv_fifo_empty && !rv_fifo_rd) begin
            rv_fifo_rd <= 1;
            rv_bytes = rv_bytes + 1;
        end
    end
`endif
    vs1053 vs1053_inst(
`ifdef RV32
        .use_chip(1'b0), .fifo_rd_ext(rv_fifo_rd), .fifo_data_ext(rv_fifo_data), .fifo_empty_ext(rv_fifo_empty),
        .soft_reset_ext(rv_soft), .hard_reset_ext(rv_hard), .volume_ext(rv_vol),
`endif
        .clk(clk_bus), .reset(reset),
        .bus_cs_n(1'b1), .bus_rd_n(1'b1), .bus_wr_n(1'b1), .bus_a(2'b00), .bus_di(8'h00), .bus_do(),
        .ext_fifo_wr(ext_fifo_wr), .ext_fifo_din(ext_fifo_din), .ext_fifo_ack(ext_fifo_ack), .ext_fifo_room(ext_fifo_room),
        .ext_soft_reset(ext_soft_reset), .ext_hard_reset(ext_hard_reset), .ext_vol_wr(ext_vol_wr), .ext_vol(ext_vol),
        .cur_volume(cur_volume), .sci_req(sci_req), .sci_rnw(sci_rnw), .sci_addr(sci_addr), .sci_wdata(sci_wdata),
        .sci_busy(sci_busy), .sci_rdata(sci_rdata),
        .vs_sclk(vs_sclk), .vs_miso(vs_miso), .vs_mosi(vs_mosi), .vs_dreq(vs_dreq),
        .vs_cs_n(vs_cs_n), .vs_dcs_n(vs_dcs_n), .vs_reset_n(vs_reset_n)
    );

    // VS1053 model: SCI frames (32 bits on cs_n) and SDI bytes (on dcs_n)
    reg [31:0] sci_sh;
    reg [7:0] sci_op = 0, sci_adr = 0;
    integer sci_bits = 0, sdi_bits = 0, sdi_bytes = 0;
    integer clockf_bad = 0, mode_reset_writes = 0, mode_sdinew_lost = 0, vol_writes = 0;
    reg [15:0] last_vol = 0, last_mode = 16'h0800;
    always @(negedge vs_cs_n) begin sci_bits = 0; sci_sh = 0; end
    always @(negedge vs_dcs_n) sdi_bits = 0;
    always @(posedge vs_sclk) begin
        if (!vs_cs_n) begin
            sci_sh = {sci_sh[30:0], vs_mosi};
            sci_bits = sci_bits + 1;
            if (sci_bits == 16) begin sci_op = sci_sh[15:8]; sci_adr = sci_sh[7:0]; end
            if (sci_bits == 32 && sci_sh[31:24] == 8'h02) begin
                if (sci_sh[23:16] == 8'h03 && sci_sh[15:0] != 16'h4BE8 && sci_sh[15:0] != 16'h8BE8) clockf_bad = clockf_bad + 1;
                if (sci_sh[23:16] == 8'h00) begin
                    last_mode = sci_sh[15:0];
                    if (sci_sh[2]) mode_reset_writes = mode_reset_writes + 1;
                    if (!sci_sh[11]) mode_sdinew_lost = mode_sdinew_lost + 1;
                end
                if (sci_sh[23:16] == 8'h0B) begin last_vol = sci_sh[15:0]; vol_writes = vol_writes + 1; end
            end
        end else if (!vs_dcs_n) begin
            sdi_bits = sdi_bits + 1;
            if (sdi_bits % 8 == 0) sdi_bytes = sdi_bytes + 1;
        end
    end
    // read answers: STATUS = 0x0040 (VS1053), MODE = last written, others 0x1234
    reg [15:0] sci_ans;
    always @(negedge vs_sclk) begin
        if (!vs_cs_n && sci_bits >= 16 && sci_bits < 32 && sci_op == 8'h03) begin
            sci_ans = (sci_adr == 8'h01) ? 16'h0040 : (sci_adr == 8'h00) ? last_mode : 16'h1234;
            vs_miso <= sci_ans[15 - (sci_bits - 16)];
        end
    end

    // ------------------------------------------------------------------ SD
    wire host_sd_clk, host_sd_mosi, host_sd_grant, host_active;
    reg  host_cs_n = 1;
    reg  host_tx = 0, host_rx = 0;
    reg  [7:0] host_din = 8'h00;
    wire [7:0] host_dout;
    wire host_wait;
    reg  [3:0] zc_cnt = 0;
    always @(posedge clk_mem) zc_cnt <= (zc_cnt >= 5) ? 0 : zc_cnt + 1;
    wire sd_cs_n, sd_sclk, sd_mosi;
    reg  sd_miso = 1;

    zc_spi host_spi(
        .clk_sys(clk_mem), .ena(zc_cnt == 0), .tx(host_tx & host_sd_grant), .rx(host_rx & host_sd_grant),
        .din(host_din), .dout(host_dout), .spi_clk(host_sd_clk), .spi_di(sd_miso), .spi_do(host_sd_mosi),
        .spi_wait(host_wait), .active(host_active)
    );

    sd_arbiter #(.TIMEOUT(23'd20000)) sd_arb(
        .clk(clk_mem), .reset(reset), .host_en(1'b1),
        .host_cs_n(host_cs_n), .host_sclk(host_sd_clk), .host_mosi(host_sd_mosi),
        .host_req(host_tx | host_rx), .host_active(host_active), .host_grant(host_sd_grant),
        .gs_reset(gs_reset), .gs_cs_n(gs_sd_cs_n), .gs_req_t(gs_sd_req_t), .gs_tx(gs_sd_tx),
        .gs_ack_t(gs_sd_ack_t), .gs_rx(gs_sd_rx),
        .sd_cs_n(sd_cs_n), .sd_sclk(sd_sclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );

    // SD card model: logs every byte with the owner seen at its first and last clock;
    // answers each byte with the bitwise inverse of the previous one
    reg [7:0] sd_rx_sh = 0, sd_tx_sh = 8'hFF, sd_prev = 8'hFF;
    integer sd_bits = 0, sd_bytes = 0, sd_mixed = 0;
    reg sd_owner_first;
    reg [7:0] sd_log [0:255];
    reg       sd_log_gs [0:255];
    always @(posedge sd_sclk) begin
        if (!sd_cs_n) begin
            if (sd_bits == 0) sd_owner_first = sd_arb.owner_gs;
            sd_rx_sh = {sd_rx_sh[6:0], sd_mosi};
            sd_bits = sd_bits + 1;
            if (sd_bits == 8) begin
                if (sd_arb.owner_gs != sd_owner_first) sd_mixed = sd_mixed + 1;
                sd_log[sd_bytes[7:0]] = sd_rx_sh;
                sd_log_gs[sd_bytes[7:0]] = sd_owner_first;
                sd_bytes = sd_bytes + 1;
                sd_bits = 0;
                sd_prev = sd_rx_sh;
                sd_tx_sh = ~sd_rx_sh;
            end
        end
    end
    always @(negedge sd_sclk or negedge sd_cs_n) begin
        if (!sd_cs_n) begin
            sd_miso <= sd_tx_sh[7 - sd_bits];
        end
    end
    always @(posedge sd_cs_n) sd_bits = 0;

    // host side ZC byte exchange: as zc_divmmc does it, the I/O cycle lasts until the byte is done
    task host_xfer(input [7:0] d);
        begin
            @(posedge clk_mem);
            host_din <= d; host_tx <= 1;
            // the I/O cycle: at least ~300 ns, longer while the host waits for the card or the exchange
            repeat (40) @(posedge clk_mem);
            while (host_wait || !host_sd_grant) @(posedge clk_mem);
            repeat (10) @(posedge clk_mem);
            host_tx <= 0;
            repeat (20) @(posedge clk_mem);
            while (host_active) @(posedge clk_mem);
        end
    endtask

    // host writes to the GS (#B3)
    task host_wr_b3(input [7:0] d);
        begin
            @(posedge clk_bus); host_a <= 16'h00B3; host_d <= d; host_wr_n <= 0; host_ioreq <= 1;
            repeat (8) @(posedge clk_bus);
            host_wr_n <= 1; host_ioreq <= 0;
            repeat (4) @(posedge clk_bus);
        end
    endtask

    // ------------------------------------------------------------------ GS programs
    reg [7:0] q;
    integer i, k;
    task gs_out(input [7:0] p, input [7:0] d); gs_inst.z80_unit.io_wr(p, d); endtask
    task gs_in(input [7:0] p, output [7:0] d); gs_inst.z80_unit.io_rd(p, d); endtask

    task sci_write(input [7:0] adr, input [15:0] d);
        begin
            gs_out(8'h11, 8'h02);       // MCNCS = 0
            gs_out(8'h15, 8'h02);
            gs_out(8'h15, adr);
            gs_out(8'h15, d[15:8]);
            gs_out(8'h15, d[7:0]);
            gs_out(8'h11, 8'h82);       // MCNCS = 1
        end
    endtask
    task sci_read(input [7:0] adr, output [15:0] d);
        begin
            gs_out(8'h11, 8'h02);
            gs_out(8'h15, 8'h03);
            gs_out(8'h15, adr);
            gs_out(8'h15, 8'hFF);
            gs_in(8'h15, d[15:8]);
            gs_out(8'h15, 8'hFF);
            gs_in(8'h15, d[7:0]);
            gs_out(8'h11, 8'h82);
        end
    endtask

    reg [15:0] w;
    integer sd_before, waits_seen;

    initial begin
        $dumpfile("ngs_tb.vcd");
        $dumpvars(0, ngs_tb);
        repeat (20) @(posedge clk_bus);
        reset = 0;
        repeat (20) @(posedge clk_bus);

        // -------- GSCFG0, decode, SCTRL
        gs_in(8'h0F, q);  check(q == 8'h23, "GSCFG0 reset value #23");
        gs_out(8'h0F, 8'h2B); gs_in(8'h0F, q); check(q == 8'h2B, "GSCFG0 reads back");
        gs_out(8'h0F, 8'h23);
        gs_in(8'h11, q);  check(q == 8'h0B, "SCTRL reset value #0B");
        gs_in(8'h12, q);  check(q[1] == 1'b0, "SSTAT SDDET = card present");

        host_wr_b3(8'h77);                    // data bit set
        gs_in(8'h04, q);  check(q[7] == 1'b1, "data bit set by the host");
        gs_in(8'h12, q);                      // SSTAT: must not clear it (was an alias of #02)
        gs_in(8'h04, q);  check(q[7] == 1'b1, "SSTAT does not touch the data bit");
        gs_in(8'h02, q);  check(q == 8'h77, "ZXDATRD");
        gs_in(8'h04, q);  check(q[7] == 1'b0, "ZXDATRD clears the data bit");

        // -------- paging
        gs_out(8'h00, 8'h05);
        gs_inst.z80_unit.mem_rd(16'h8000, q); check(ma[20:14] == 7'd10, "MPAG 5: #8000 = page 10");
        gs_inst.z80_unit.mem_rd(16'hC000, q); check(ma[20:14] == 7'd11, "MPAG 5: #C000 = page 11");
        gs_out(8'h0F, 8'h2B);                  // EXPAG
        gs_out(8'h00, 8'h83);                  // page 7
        gs_out(8'h10, 8'h12);                  // page #24
        gs_inst.z80_unit.mem_rd(16'h8000, q); check(ma[20:14] == 7'd7, "EXPAG: MPAG #83 = page 7");
        gs_inst.z80_unit.mem_rd(16'hC000, q); check(ma[20:14] == 7'h24, "EXPAG: MPAGEX #12 = page #24");
        gs_out(8'h0F, 8'h2A);                  // NOROM = 0, EXPAG: windows 0, 2, 3 = ROM copy
        gs_inst.z80_unit.mem_rd(16'hC000, q); check(ma[20:14] == 7'd0, "NOROM=0: #C000 reads the ROM copy");
        gs_inst.z80_unit.mem_rd(16'h4000, q); check(ma[20:14] == 7'd3, "NOROM=0: #4000 stays RAM (page 3)");
        gs_out(8'h0F, 8'h23);
        gs_out(8'h00, 8'h00);

        // -------- SD: GS alone
        sd_before = sd_bytes;
        gs_out(8'h11, 8'h01);                  // SDNCS = 0
        gs_out(8'h13, 8'h40);                  // SD_SEND
        gs_out(8'h13, 8'h12);
        gs_in(8'h13, q);   check(q == 8'hBF, "SD_READ: answer to the byte before (~#40)");
        gs_in(8'h14, q);   check(q == 8'hBF, "SD_RSTR returns the last byte");
        gs_in(8'h14, q);   check(q == 8'hED, "SD_RSTR: answer to #12");
        gs_out(8'h11, 8'h81);                  // SDNCS = 1
        repeat (200) @(posedge clk_mem);
        check(sd_bytes - sd_before == 4, "4 bytes on the card");
        check(sd_log[sd_before[7:0]] == 8'h40 && sd_log[sd_before[7:0]+1] == 8'h12 && sd_log[sd_before[7:0]+2] == 8'hFF, "SD bytes #40 #12 #FF");
        check(sd_log_gs[sd_before[7:0]] == 1'b1, "the GS owned the card");

        // -------- SD: host and GS at the same time
        sd_before = sd_bytes;
        fork
            begin
                host_cs_n <= 0;
                for (i = 0; i < 6; i = i + 1) host_xfer(8'hA0 + i);
                host_cs_n <= 1;
            end
            begin
                repeat (60) @(posedge clk_bus);
                gs_out(8'h11, 8'h01);
                for (k = 0; k < 6; k = k + 1) gs_out(8'h13, 8'h50 + k);
                gs_out(8'h11, 8'h81);
            end
        join
        repeat (200) @(posedge clk_mem);
        check(sd_mixed == 0, "no byte with two owners");
        check(sd_bytes - sd_before == 12, "12 bytes on the card");
        // the host session went first and was not interleaved
        k = 0;
        for (i = 0; i < 12; i = i + 1)
            if (i > 0 && sd_log_gs[(sd_before + i) % 256] != sd_log_gs[(sd_before + i - 1) % 256]) k = k + 1;
        check(k == 1, "one owner change: whole sessions");
        for (i = 0; i < 6; i = i + 1) check(sd_log[(sd_before + i) % 256] == 8'hA0 + i, "host bytes in order");
        for (i = 0; i < 6; i = i + 1) check(sd_log[(sd_before + 6 + i) % 256] == 8'h50 + i, "GS bytes in order");

        // -------- SD: the host leaves its CS low, the GS takes the card after the timeout
        sd_before = sd_bytes;
        host_cs_n <= 0;
        host_xfer(8'hC1);
        gs_out(8'h11, 8'h01);
        gs_out(8'h13, 8'h61);
        gs_inst.z80_unit.io_rd(8'h13, q);       // waits for the timeout
        waits_seen = gs_inst.z80_unit.waits;
        check(waits_seen > 1000, "SD_READ waited for the timeout");
        gs_out(8'h11, 8'h81);
        host_cs_n <= 1;
        repeat (200) @(posedge clk_mem);
        check(sd_bytes - sd_before == 2 && sd_log[(sd_before + 1) % 256] == 8'h61, "GS byte after the timeout");

        // -------- SD: a GS reset (#33) gives the card back to the host at once
        gs_out(8'h11, 8'h01);                  // the GS takes the card and leaves its CS low
        gs_out(8'h13, 8'h71);
        gs_in(8'h13, q);
        check(sd_arb.owner_gs == 1'b1, "the GS owns the card");
        host_cs_n <= 0;
        fork
            begin
                k = $time;
                host_xfer(8'hD1);              // waits: the GS CS is low
                k = $time - k;
            end
            begin
                repeat (200) @(posedge clk_bus);
                gs_reset_in = 1;
                repeat (64) @(posedge clk_bus);
                gs_reset_in = 0;
            end
        join
        host_cs_n <= 1;
        check(k < 20000, "the host got the card right after the GS reset, not after the timeout");
        check(sd_log[(sd_bytes - 1) % 256] == 8'hD1 && sd_log_gs[(sd_bytes - 1) % 256] == 1'b0, "the host byte went through");
        check(gs_inst.sd_busy == 1'b0, "no SD exchange pending after the GS reset");
        // a GS request left pending by the reset is dropped
        host_cs_n <= 0;
        host_xfer(8'hD2);                      // the host owns the card, CS low
        gs_out(8'h11, 8'h01);
        gs_out(8'h13, 8'h72);                  // pending: the host CS is low
        gs_reset_in = 1;
        repeat (64) @(posedge clk_bus);
        gs_reset_in = 0;
        repeat (20) @(posedge clk_bus);
        check(gs_inst.sd_busy == 1'b0, "the pending GS byte is dropped by the reset");
        host_cs_n <= 1;
        repeat (40000) @(posedge clk_mem);
        check(sd_log[(sd_bytes - 1) % 256] == 8'hD2, "the dropped GS byte never reached the card");
        gs_in(8'h11, q);  check(q == 8'h0B, "SCTRL back to #0B after the GS reset");

        // -------- MP3
`ifndef RV32
        // wait for the controller init (hard reset, STATUS, CLOCKF, BASS, VOL, MODE, 2048 zeros)
        wait (vs1053_inst.ctrl_inst.state == 5'd8);
        repeat (100) @(posedge clk_bus);
`endif
        sci_read(8'h01, w);  check(w == 16'h0040, "SCI STATUS = #0040 (VS1053)");
        sci_write(8'h03, 16'h9B58);            // VS1001-style CLOCKF: dropped
        sci_write(8'h0B, 16'hFEFE);
        repeat (2000) @(posedge clk_bus);
        check(cur_volume == 8'hFE, "SCI VOL -> reg_volume");
        sci_write(8'h0B, 16'h1020);
        repeat (2000) @(posedge clk_bus);
        check(cur_volume == 8'h10, "SCI VOL: the louder channel");
        sci_read(8'h00, w);  check(w[11] == 1'b1, "MODE reads with SM_SDINEW");
        sci_write(8'h00, w | 16'h0004);        // soft reset
        sci_write(8'h00, w & ~16'h0004);
`ifndef RV32
        wait (vs1053_inst.ctrl_inst.state == 5'd8);
        repeat (2000) @(posedge clk_bus);
        check(clockf_bad == 0, "the chip never saw a foreign CLOCKF");
        check(mode_reset_writes == 1, "SM_RESET reached the chip once (controller soft reset)");
        check(mode_sdinew_lost == 0, "SM_SDINEW never cleared on the chip");
        check(last_vol == 16'h1010, "the chip volume follows the SCI VOL");
        sci_write(8'h0C, 16'hABCD);            // AICTRL0: passes through
        repeat (3000) @(posedge clk_bus);
`endif

        // data
        gs_in(8'h12, q); check(q[0] == 1'b1, "MDDRQ");
        sd_before = sdi_bytes;
`ifdef RV32
        sd_before = rv_bytes;
`endif
        for (i = 0; i < 100; i = i + 1) gs_out(8'h14, i[7:0]);
        repeat (40000) @(posedge clk_bus);
`ifdef RV32
        check(rv_bytes - sd_before == 100, "100 MD_SEND bytes reached neorv32");
`else
        check(sdi_bytes - sd_before == 100, "100 MD_SEND bytes reached the chip (tail < 32 too)");
`endif

        // hard reset by MPXRS 0 -> 1
        gs_out(8'h11, 8'h04);
        gs_out(8'h11, 8'h84);
`ifndef RV32
        repeat (20) @(posedge clk_bus);
        check(vs1053_inst.ctrl_inst.state == 5'd0 || vs_reset_n == 1'b0 || vs1053_inst.ctrl_inst.state < 5'd8, "MPXRS: decoder hard reset");
`endif

        $display("%0s: %0d errors", errors == 0 ? "PASS" : "FAIL", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
