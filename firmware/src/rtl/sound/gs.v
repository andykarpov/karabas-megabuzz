//`default_nettype none

// General Sound with the NeoGS extensions of the GS CPU side
// (NeoGS GS_info v0.4.2.2, the standard NeoGS FPGA firmware):
//   #0F GSCFG0  reads back what was written; NOROM and EXPAG work, RAMRO,
//               the clock bits, 8CHANS, PAN4CH, INV7B are only stored
//               (pages 0-1 hold the GS ROM and stay write-protected)
//   #10 MPAGEX  page of #C000 in the extended paging mode
//   #11 SCTRL   _SDNCS, _MPNCS, _MPXRS, _MPHLF, _MDHLF (write: d7 = value, d5..d0 = mask)
//   #12 SSTAT   _MPDRQ, _SDDET, _SDWP, _MCRDY
//   #13 SD_SEND / SD_READ, #14 SD_RSTR (read) / MD_SEND (write), #15 MC_SEND / MC_READ
//   #16-#19     volumes of the channels 5-8: taken and ignored
// Ports are decoded by A5..A0. The CPU waits on WAIT_n while an SD exchange
// cannot start or a decoder request is pending.

module gs(
    input wire         CLK,
    input wire         RESET,
    input wire         CE,
    input wire         NMI,     // NMI request from the host (#33)

    input wire [15:0]  A,
    input wire [7:0]   DI,
    output wire [7:0]  DO,
    output wire        OE,
    input wire         WR_n,
    input wire         RD_n,
    input wire         IOREQ,   // synchronized host I/O cycle

    output wire [20:0] MA,
    input wire [7:0]   MDI,
    output wire [7:0]  MDO,
    output wire        MRFSH_n,
    output wire        MWE_n,
    output wire        MRD_n,

    // NeoGS SD card (sd_arbiter, clk_mem domain)
    output wire        SD_CS_n,
    output reg         SD_REQ_T,    // toggles once per byte exchange
    output reg  [7:0]  SD_TX,
    input wire         SD_ACK_T,
    input wire  [7:0]  SD_RX,
    input wire         SD_DET_n,

    // NeoGS MP3 (ngs_mp3)
    output wire        MC_NCS,
    output wire        MP_XRS,
    output reg         MC_WR,
    output reg         MD_WR,
    output wire [7:0]  IO_DO,
    input wire  [7:0]  MC_READ,
    input wire         MC_BUSY,
    input wire         MC_RD_WAIT,
    input wire         MC_READY,
    input wire         MD_BUSY,
    input wire         MD_DREQ,

    output wire signed [14:0] OUT_L,
    output wire signed [14:0] OUT_R
);

    // INT sets the sample rate: exactly 37.5 kHz, 14 MHz / 37.5 kHz = 373.33 = 1120 / 3
    localparam INT_STEP = 3;
    localparam INT_MOD = 1120;

    // NeoGS GS-side ports
    localparam P_MPAG    = 6'h00;
    localparam P_ZXCMD   = 6'h01;
    localparam P_ZXDATRD = 6'h02;
    localparam P_ZXDATWR = 6'h03;
    localparam P_ZXSTAT  = 6'h04;
    localparam P_CLRCBIT = 6'h05;
    localparam P_VOL1    = 6'h06;
    localparam P_VOL2    = 6'h07;
    localparam P_VOL3    = 6'h08;
    localparam P_VOL4    = 6'h09;
    localparam P_DPORT1  = 6'h0A;
    localparam P_DPORT2  = 6'h0B;
    localparam P_GSCFG0  = 6'h0F;
    localparam P_MPAGEX  = 6'h10;
    localparam P_SCTRL   = 6'h11;
    localparam P_SSTAT   = 6'h12;
    localparam P_SD      = 6'h13; // SD_SEND (w) / SD_READ (r)
    localparam P_SDMD    = 6'h14; // SD_RSTR (r) / MD_SEND (w)
    localparam P_MC      = 6'h15; // MC_SEND (w) / MC_READ (r)

    // reset value of GSCFG0: NOROM, RAMRO, "20 MHz", as the NeoGS loader leaves it
    // (the Megabuzz starts the GS ROM right away)
    localparam GSCFG0_RESET = 8'h23;
    // reset value of SCTRL: _SDNCS = 1, _MPNCS = 1, _MPXRS = 0, _MPHLF = 1
    localparam SCTRL_RESET  = 6'h0B;

    // cs from host
    wire gs_sel = IOREQ & (A[7:4] == 4'hB && A[2:0] == 3'h3);
    wire gs_cs_n = ~gs_sel;
    wire a = A[3];

    // one strobe per host access: the flags must not be held for the whole bus cycle against the GS CPU
    wire host_wr = gs_sel & ~WR_n;
    wire host_rd = gs_sel & ~RD_n;
    reg host_wr_d = 0, host_rd_d = 0;
    always @(posedge CLK) begin
        host_wr_d <= host_wr;
        host_rd_d <= host_rd;
    end
    wire host_wr_stb = host_wr & ~host_wr_d;
    wire host_rd_stb = host_rd & ~host_rd_d;

    // чтение со стороны спектрума #BB, #B3
    assign DO = (a) ? {bit7_flag, 6'b111111, bit0_flag} : port_xx03_reg;

    // z80 cpu
    wire cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n;
    wire [15:0] cpu_a_bus;
    wire [7:0] cpu_di_bus, cpu_do_bus;
    wire cpu_wait_n;
    reg int_n;
    t80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_unit (
        .RESET_n (~RESET),
        .CLK     (CLK),
        .CEN     (CE),
        .WAIT_n  (cpu_wait_n),
        .INT_n   (int_n),
        .NMI_n   (~NMI),
        .BUSRQ_n (1'b1),
        .M1_n    (cpu_m1_n),
        .MREQ_n  (cpu_mreq_n),
        .IORQ_n  (cpu_iorq_n),
        .RD_n    (cpu_rd_n),
        .WR_n    (cpu_wr_n),
        .RFSH_n  (cpu_rfsh_n),
        .HALT_n  (),
        .BUSAK_n (),
        .A       (cpu_a_bus),
        .DI      (cpu_di_bus),
        .DO      (cpu_do_bus)
    );

    // int generator
    reg [10:0] cnt;
    wire [10:0] cnt_next = cnt + INT_STEP;
    always @(posedge CLK) begin
        if (RESET) begin
            cnt <= 0;
            int_n <= 1;
        end else if (CE) begin
            cnt <= cnt_next;
            if (cnt_next >= INT_MOD) begin
                cnt <= cnt_next - INT_MOD;
                int_n <= 0;
            end
        end

        if (~cpu_iorq_n & ~cpu_m1_n) int_n <= 1;
    end

    // ports
    reg bit7_flag, bit0_flag;
    reg [7:0] port_xxbb_reg, port_xxb3_reg, port_xx03_reg;
    reg [7:0] port_xx00_reg;   // MPAG
    reg [7:0] gscfg0;
    reg [6:0] pg2, pg3;        // 16 KB pages of #8000 and #C000 (2 MB: 128 pages)
    reg [5:0] sctrl;
    reg signed [6:0] port_xx06_reg, port_xx07_reg, port_xx08_reg, port_xx09_reg;
    reg signed [7:0] ch_a_reg, ch_b_reg, ch_c_reg, ch_d_reg;

    wire norom = gscfg0[0];
    wire expag = gscfg0[3];

    // GS CPU I/O cycles
    wire [5:0] port = cpu_a_bus[5:0];
    wire io    = ~cpu_iorq_n & cpu_m1_n;
    wire io_rd = io & ~cpu_rd_n;
    wire io_wr = io & ~cpu_wr_n;

    // the page has to change together with the address: as a register it lagged one CE behind,
    // on the same edge as the falling /WE
    // NOROM = 0: windows 0, 2 and 3 read the "flash". There is no NeoGS flash here,
    // the GS ROM (pages 0-1) stands in for it and writes are ignored.
    wire flash_win = ~norom & (cpu_a_bus[15] | ~cpu_a_bus[14]);
    wire [6:0] mem = (cpu_a_bus[15:14] == 2'b00) ? 7'd0 :                     // #0000 - #3FFF
                     (cpu_a_bus[15:14] == 2'b01) ? 7'd3 :                     // #4000 - #7FFF: page 3, the upper half of MPAG 1, as on GS and NeoGS
                     (cpu_a_bus[15:14] == 2'b10) ? (norom ? pg2 : {6'd0, pg2[0]}) : // #8000 - #BFFF
                                                   (norom ? pg3 : {6'd0, pg3[0]});  // #C000 - #FFFF

    always @(posedge CLK) begin
        if (RESET) begin
            bit7_flag <= 0;
            bit0_flag <= 0;
        end
        else begin
            if (io & CE) begin
                case(port)
                    P_ZXDATRD: bit7_flag <= 0;
                    P_ZXDATWR: bit7_flag <= 1;
                    P_CLRCBIT: bit0_flag <= 0;
                    P_DPORT1:  bit7_flag <= ~port_xx00_reg[0];
                    P_DPORT2:  bit0_flag <= port_xx09_reg[5];
                    default: ; // no operation
                endcase
            end
            if (host_rd_stb & ~a) bit7_flag <= 0;
            if (host_wr_stb & ~a) bit7_flag <= 1;
            if (host_wr_stb &  a) bit0_flag <= 1;
        end
    end

    // запись со стороны спектрума
    always @(posedge CLK)
    begin
        if (RESET) begin
            port_xxbb_reg <= 0;
            port_xxb3_reg <= 0;
        end
        else begin
            if (~gs_cs_n && ~WR_n) begin
                if (a) port_xxbb_reg <= DI;
                else port_xxb3_reg <= DI;
            end
        end
    end

    // ------------------------------------------------------------ SPI / decoder ports
    // a port that starts an operation does it once per I/O cycle (io_done);
    // until it can, the CPU waits
    reg [1:0] sd_ack_s = 2'b00;
    always @(posedge CLK)
        sd_ack_s <= {sd_ack_s[0], SD_ACK_T};
    wire sd_busy = SD_REQ_T ^ sd_ack_s[1];

    reg io_done;
    reg [7:0] sd_rd_latch;
    initial SD_REQ_T = 1'b0;

    wire acc_sd_send = io_wr & (port == P_SD);
    wire acc_sd_read = io_rd & (port == P_SD);
    wire acc_sd_rstr = io_rd & (port == P_SDMD);
    wire acc_md_send = io_wr & (port == P_SDMD);
    wire acc_mc_send = io_wr & (port == P_MC);
    wire acc_mc_read = io_rd & (port == P_MC);
    wire acc_sctrl   = io_wr & (port == P_SCTRL);

    // SCTRL: _SDNCS must not change under a running exchange
    wire sctrl_wait = acc_sctrl & cpu_do_bus[0] & sd_busy;

    wire io_wait = (~io_done & (acc_sd_send | acc_sd_rstr) & sd_busy) |
                   (acc_sd_read & sd_busy) |
                   (~io_done & acc_md_send & MD_BUSY) |
                   (~io_done & acc_mc_send & MC_BUSY) |
                   (acc_mc_read & MC_RD_WAIT) |
                   sctrl_wait;
    assign cpu_wait_n = ~io_wait;

    always @(posedge CLK) begin
        MC_WR <= 0;
        MD_WR <= 0;
        if (RESET) begin
            io_done <= 0;
            SD_TX <= 8'hFF;
            sd_rd_latch <= 8'hFF;
        end else begin
            if (!io)
                io_done <= 0;
            else if (!io_done) begin
                if ((acc_sd_send | acc_sd_rstr) & ~sd_busy) begin
                    SD_TX       <= acc_sd_send ? cpu_do_bus : 8'hFF;
                    SD_REQ_T    <= ~SD_REQ_T;
                    sd_rd_latch <= SD_RX;
                    io_done     <= 1;
                end
                if (acc_md_send & ~MD_BUSY) begin
                    MD_WR   <= 1;
                    io_done <= 1;
                end
                if (acc_mc_send & ~MC_BUSY) begin
                    MC_WR   <= 1;
                    io_done <= 1;
                end
            end
        end
    end

    assign IO_DO  = cpu_do_bus;
    assign SD_CS_n = sctrl[0];
    assign MC_NCS  = sctrl[1];
    assign MP_XRS  = sctrl[2];

    // порты звука
    always @(posedge CLK)
    begin
        if (RESET) begin
            port_xx00_reg <= 0;
            port_xx03_reg <= 0;
            gscfg0 <= GSCFG0_RESET;
            pg2 <= 7'd0;
            pg3 <= 7'd1;
            sctrl <= SCTRL_RESET;
            ch_a_reg <= 0;
            ch_b_reg <= 0;
            ch_c_reg <= 0;
            ch_d_reg <= 0;
            port_xx06_reg <= 0;
            port_xx07_reg <= 0;
            port_xx08_reg <= 0;
            port_xx09_reg <= 0;
        end
        else if (CE) begin

            if (io_wr) begin
                case(port)
                    P_MPAG: begin
                        port_xx00_reg <= cpu_do_bus;
                        if (expag)
                            pg2 <= {cpu_do_bus[5:0], cpu_do_bus[7]};
                        else begin
                            pg2 <= {cpu_do_bus[5:0], 1'b0};
                            pg3 <= {cpu_do_bus[5:0], 1'b1};
                        end
                    end
                    P_MPAGEX: if (expag) pg3 <= {cpu_do_bus[5:0], cpu_do_bus[7]};
                    P_ZXDATWR: port_xx03_reg <= cpu_do_bus;
                    P_VOL1: port_xx06_reg <= cpu_do_bus[5:0];
                    P_VOL2: port_xx07_reg <= cpu_do_bus[5:0];
                    P_VOL3: port_xx08_reg <= cpu_do_bus[5:0];
                    P_VOL4: port_xx09_reg <= cpu_do_bus[5:0];
                    P_GSCFG0: gscfg0 <= cpu_do_bus;
                    P_SCTRL: if (!sctrl_wait)
                        sctrl <= cpu_do_bus[7] ? (sctrl | cpu_do_bus[5:0]) : (sctrl & ~cpu_do_bus[5:0]);
                    default: ; // no operation
                endcase
            end

            if (~cpu_mreq_n && ~cpu_rd_n && cpu_a_bus[15:13] == 3) begin
                case(cpu_a_bus[9:8])
                    0: ch_a_reg <= {~MDI[7], MDI[6:0]};
                    1: ch_b_reg <= {~MDI[7], MDI[6:0]};
                    2: ch_c_reg <= {~MDI[7], MDI[6:0]};
                    3: ch_d_reg <= {~MDI[7], MDI[6:0]};
                    default: ; // no operation
                endcase
            end
        end
    end

    // Шина данных CPU
    assign cpu_di_bus =
    (~cpu_mreq_n && ~cpu_rd_n) ? MDI :
    (~io_rd) ? 8'hFF :
    (port == P_ZXSTAT)  ? {bit7_flag, 6'b111111, bit0_flag} :
    (port == P_ZXCMD)   ? port_xxbb_reg :
    (port == P_ZXDATRD) ? port_xxb3_reg :
    (port == P_GSCFG0)  ? gscfg0 :
    (port == P_SCTRL)   ? {2'b00, sctrl} :
    (port == P_SSTAT)   ? {4'b0000, MC_READY, 1'b0, SD_DET_n, MD_DREQ} :
    (port == P_SD)      ? SD_RX :
    (port == P_SDMD)    ? (io_done ? sd_rd_latch : SD_RX) : // SD_RX until the new exchange starts
    (port == P_MC)      ? MC_READ : 8'hFF;

    assign MA = {mem, cpu_a_bus[13:0]};
    assign MDO = cpu_do_bus;
    assign MWE_n = cpu_wr_n || cpu_mreq_n || flash_win || ~(mem[6] || mem[5] || mem[4] || mem[3] || mem[2] || mem[1]);
    assign MRD_n = cpu_rd_n || cpu_mreq_n;
    assign MRFSH_n = cpu_rfsh_n;
    assign OE = host_rd;

    // sound mix
    reg signed [14:0] out_a, out_b, out_c, out_d;
    reg signed [14:0] mix_l, mix_r;
    always @(posedge CLK)
    begin
        if (CE) begin
            out_a <= ch_a_reg * port_xx06_reg;
            out_b <= ch_b_reg * port_xx07_reg;
            out_c <= ch_c_reg * port_xx08_reg;
            out_d <= ch_d_reg * port_xx09_reg;
            mix_l <= out_a + out_b;
            mix_r <= out_c + out_d;
        end
    end

    assign OUT_L = mix_l;
    assign OUT_R = mix_r;

endmodule
