`default_nettype none
// ----------------------------------------------------------------------------
// One SD card for two masters: the host (Z-Controller / DivMMC, zc_spi) and
// the GS CPU (NeoGS ports SD_SEND / SD_READ / SD_RSTR, SCTRL _SDNCS).
// Everything runs on clk_mem; the GS side comes from clk_bus through a
// toggle handshake.
//
// The card has one owner at a time (the host by default), and only the owner
// reaches the pads. Both masters start a byte exchange only while they own
// the card (host_grant / owner_gs, the same register), so bytes of the two
// never mix. A master that does not own the card waits: the host on /WAIT,
// the GS CPU on WAIT_n (its request stays pending).
// The owner changes when the other master wants to exchange a byte and the
// owner is idle: no request, no exchange, and its CS is high, or its CS has
// stayed low with no exchange for TIMEOUT clocks (~50 ms). A GS reset gives
// the card back to the host.
// ----------------------------------------------------------------------------
module sd_arbiter #(
    parameter TIMEOUT = 23'd7000000     // 50 ms at 140 MHz
)(
    input  wire        clk,             // clk_mem
    input  wire        reset,
    input  wire        host_en,         // DivMMC or Z-Controller is on

    // host (zc_divmmc), clk domain
    input  wire        host_cs_n,
    input  wire        host_sclk,
    input  wire        host_mosi,
    input  wire        host_req,        // the host is asking for a byte exchange
    input  wire        host_active,     // zc_spi is exchanging a byte
    output reg         host_grant,

    // GS side, clk_bus domain
    input  wire        gs_reset,
    input  wire        gs_cs_n,
    input  wire        gs_req_t,        // toggles once per byte exchange
    input  wire [7:0]  gs_tx,           // stable while the exchange is pending
    output reg         gs_ack_t,        // = gs_req_t when the exchange is done
    output reg  [7:0]  gs_rx,           // stable while no exchange is pending

    // pads
    output wire        sd_cs_n,
    output wire        sd_sclk,
    output wire        sd_mosi,
    input  wire        sd_miso
);

    // GS signals into clk
    reg [1:0] gs_req_s = 2'b00, gs_cs_s = 2'b11, gs_rst_s = 2'b00;
    always @(posedge clk) begin
        gs_req_s <= {gs_req_s[0], gs_req_t};
        gs_cs_s  <= {gs_cs_s[0], gs_cs_n};
        gs_rst_s <= {gs_rst_s[0], gs_reset};
    end
    wire gs_rst  = gs_rst_s[1] | reset;
    wire gs_csn  = gs_cs_s[1];
    wire gs_pend = gs_req_s[1] ^ gs_ack_t;

    reg owner_gs;

    // ------------------------------------------------------------- GS SPI master
    // SPI mode 0, SCK = clk / 12 (11.7 MHz, as zc_spi): a byte takes 96 clocks
    // (0.69 us), within the 16 Z80 clocks NeoGS allows between exchanges.
    // MISO is sampled at the end of the high phase, as zc_spi does: the card
    // drives it after the falling edge, and sampling at the rising edge left
    // only 36 ns for the pads, the board and the card's output delay.
    reg       gs_busy;
    reg [3:0] ph;
    reg [2:0] bitn;
    reg [7:0] sh;
    reg       gs_sclk, gs_mosi;

    always @(posedge clk) begin
        if (gs_rst) begin
            gs_busy  <= 0;
            gs_ack_t <= gs_req_s[1]; // drop whatever was pending
            gs_sclk  <= 0;
            gs_mosi  <= 1;
            ph       <= 0;
            bitn     <= 0;
        end else if (!gs_busy) begin
            gs_sclk <= 0;
            if (gs_pend && owner_gs) begin
                gs_busy <= 1;
                sh      <= gs_tx;
                gs_mosi <= gs_tx[7];
                ph      <= 0;
                bitn    <= 0;
            end
        end else begin
            ph <= (ph == 4'd11) ? 4'd0 : ph + 4'd1;
            if (ph == 4'd5) begin
                gs_sclk <= 1;
            end else if (ph == 4'd11) begin
                gs_sclk <= 0;
                sh <= {sh[6:0], sd_miso};
                bitn <= bitn + 3'd1;
                if (bitn == 3'd7) begin
                    gs_busy  <= 0;
                    gs_rx    <= {sh[6:0], sd_miso};
                    gs_ack_t <= gs_req_s[1];
                    gs_mosi  <= 1;
                end else begin
                    gs_mosi <= sh[6];
                end
            end
        end
    end

    // ------------------------------------------------------------- owner
    reg [22:0] idle_cnt;
    wire idle_to = (idle_cnt == TIMEOUT);

    wire host_quiet = ~host_req & ~host_active;
    wire gs_quiet   = ~gs_pend & ~gs_busy;
    wire host_idle  = host_quiet & (host_cs_n | idle_to);
    wire gs_idle    = gs_quiet & (gs_csn | idle_to);

    always @(posedge clk) begin
        if (reset) begin
            owner_gs   <= 0;
            host_grant <= 1;
            idle_cnt   <= 0;
        end else begin
            // the owner's CS low with no exchange: count towards the timeout
            if ((owner_gs ? (gs_quiet & ~gs_csn) : (host_quiet & ~host_cs_n)) && !idle_to)
                idle_cnt <= idle_cnt + 23'd1;
            else if (!(owner_gs ? (gs_quiet & ~gs_csn) : (host_quiet & ~host_cs_n)))
                idle_cnt <= 0;

            if (gs_rst_s[1] && owner_gs && !gs_busy) begin
                owner_gs   <= 0;
                host_grant <= 1;
                idle_cnt   <= 0;
            end else if (!owner_gs && gs_pend && !gs_rst_s[1] && (host_idle || !host_en)) begin
                owner_gs   <= 1;
                host_grant <= 0;
                idle_cnt   <= 0;
            end else if (owner_gs && host_req && host_en && gs_idle) begin
                owner_gs   <= 0;
                host_grant <= 1;
                idle_cnt   <= 0;
            end
        end
    end

    assign sd_cs_n = owner_gs ? gs_csn  : host_cs_n;
    assign sd_sclk = owner_gs ? gs_sclk : host_sclk;
    assign sd_mosi = owner_gs ? gs_mosi : host_mosi;

endmodule
