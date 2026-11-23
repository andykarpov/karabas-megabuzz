`default_nettype none
// ----------------------------------------------------------------------------
// NeoGS MP3 interface (GS side ports MD_SEND, MC_SEND/MC_READ, SCTRL MCNCS/MPXRS)
// on top of the Megabuzz MP3 path (vs1053.v FIFO + controller, or neorv32).
//
// NeoGS software talks to a VS1001/VS1011 over two raw SPI channels. Here:
// - MD_SEND bytes go to the FIFO of vs1053.v (the same one as ZXUNO #F6);
//   MDDRQ = at least 32 bytes free in the FIFO.
// - MC_SEND bytes with MCNCS = 0 are put together into SCI frames
//   (op 02 = write / 03 = read, addr, hi, lo) and filtered:
//     MODE with SM_RESET  -> soft reset of the Megabuzz decoder (and the FIFO)
//     MODE                -> the chip with SM_SDINEW forced (the board needs it)
//     CLOCKF              -> dropped: VS1001 values set a wrong clock on a VS1053
//     VOL                 -> reg_volume (the louder of the two channels), the
//                            same register as ZXUNO #FB
//     others              -> the chip as they are (patches, real-time MIDI)
//   Reads go to the chip; with neorv32 they are answered from shadow values.
// - MPXRS 0 -> 1 written by GS: hard reset of the decoder.
// The GS CPU waits (WAIT_n) on md_busy, mc_busy and mc_rd_wait.
// ----------------------------------------------------------------------------
module ngs_mp3 (
    input  wire        clk,
    input  wire        reset,           // GS reset: the decoder itself is not touched

    input  wire        present,         // there is a decoder behind the FIFO
    input  wire        use_chip,        // 1 = VS1053 chip, 0 = neorv32

    // GS side
    input  wire        mcncs,           // SCTRL _MPNCS (1 = deselected)
    input  wire        mpxrs,           // SCTRL _MPXRS (0 = reset)
    input  wire        mc_wr,           // pulse: a byte written to MC_SEND
    input  wire [7:0]  mc_byte,
    output wire [7:0]  mc_read,         // MC_READ: the byte "received" by the last MC_SEND
    output wire        mc_busy,         // MC_SEND has to wait
    output wire        mc_rd_wait,      // MC_READ has to wait
    output wire        mc_ready,        // SSTAT _MCRDY
    input  wire        md_wr,           // pulse: a byte written to MD_SEND
    input  wire [7:0]  md_byte,
    output wire        md_busy,         // MD_SEND has to wait
    output wire        md_dreq,         // SSTAT _MPDRQ

    // vs1053.v
    output reg         ext_fifo_wr,
    output reg  [7:0]  ext_fifo_din,
    input  wire        ext_fifo_ack,
    input  wire        ext_fifo_room,
    output reg         ext_soft_reset,
    output reg         ext_hard_reset,
    output reg         ext_vol_wr,
    output reg  [7:0]  ext_vol,
    input  wire [7:0]  cur_volume,
    output reg         sci_req,
    output reg         sci_rnw,
    output reg  [7:0]  sci_addr,
    output reg  [15:0] sci_wdata,
    input  wire        sci_busy,
    input  wire [15:0] sci_rdata
);

    localparam SCI_MODE   = 8'h00;
    localparam SCI_STATUS = 8'h01;
    localparam SCI_BASS   = 8'h02;
    localparam SCI_CLOCKF = 8'h03;
    localparam SCI_VOL    = 8'h0B;

    // ------------------------------------------------------------- data
    assign md_busy = ext_fifo_wr;
    assign md_dreq = present ? ext_fifo_room : 1'b1;

    // ------------------------------------------------------------- control
    reg [2:0]  idx;          // byte number in the SCI frame (4 = past the end)
    reg [7:0]  op, addr, hi;
    reg [15:0] rdata;        // result of the last read
    reg        rd_pending;   // read result not there yet
    reg        chip_busy;    // an SCI request is with the controller
    reg        chip_seen;    // ... and the controller took it
    reg        chip_rd;      // ... it is a read
    reg [15:0] mode_sh, bass_sh, clockf_sh;
    reg        mcncs_d, mpxrs_d;

    assign mc_busy = chip_busy & ~((op == 8'h03) & (idx >= 3'd2));
    assign mc_rd_wait = rd_pending;
    assign mc_ready = ~chip_busy;
    // a read frame: the 3rd byte clocks out the hi byte of the result, the 4th the lo byte
    assign mc_read = (op != 8'h03) ? 8'h00 :
                     (idx == 3'd3) ? rdata[15:8] :
                     (idx == 3'd4) ? rdata[7:0] : 8'h00;

    wire [15:0] mc_word = {hi, mc_byte};
    wire [15:0] mode_chip = (mc_word & ~16'h0704) | 16'h0800; // SDINEW, no SDISHARE/SDIORD/DACT, no RESET
    wire [7:0]  vol_byte = (hi < mc_byte) ? hi : mc_byte;

    // read answer without the chip
    function [15:0] shadow_read(input [7:0] a);
        case (a)
            SCI_MODE:   shadow_read = (mode_sh & ~16'h0004) | 16'h0800;
            SCI_STATUS: shadow_read = 16'h0040; // version 4: VS1053
            SCI_BASS:   shadow_read = bass_sh;
            SCI_CLOCKF: shadow_read = clockf_sh;
            SCI_VOL:    shadow_read = {cur_volume, cur_volume};
            default:    shadow_read = 16'h0000;
        endcase
    endfunction

    always @(posedge clk) begin
        ext_soft_reset <= 0;
        ext_hard_reset <= 0;
        ext_vol_wr     <= 0;
        mcncs_d <= mcncs;
        mpxrs_d <= mpxrs;

        if (reset) begin
            ext_fifo_wr <= 0;
            ext_fifo_din <= 8'h00;
            sci_req   <= 0;
            sci_rnw   <= 0;
            sci_addr  <= 8'h00;
            sci_wdata <= 16'h0000;
            idx  <= 3'd0;
            op   <= 8'h00;
            addr <= 8'h00;
            hi   <= 8'h00;
            rdata <= 16'h0000;
            rd_pending <= 0;
            chip_busy  <= 0;
            chip_seen  <= 0;
            chip_rd    <= 0;
            mode_sh   <= 16'h0800;
            bass_sh   <= 16'h0000;
            clockf_sh <= 16'h0000;
            ext_vol   <= 8'h00;
        end else begin
            // data byte -> FIFO (held until the FIFO takes it)
            if (ext_fifo_ack)
                ext_fifo_wr <= 0;
            if (md_wr && present && !ext_fifo_wr) begin
                ext_fifo_wr  <= 1;
                ext_fifo_din <= md_byte;
            end

            // SCI request to the controller: held until it is taken, done when it is free again
            if (chip_busy) begin
                if (sci_busy) begin
                    chip_seen <= 1;
                    sci_req   <= 0;
                end else if (chip_seen) begin
                    chip_busy <= 0;
                    chip_seen <= 0;
                    if (chip_rd) begin
                        rdata <= sci_rdata;
                        rd_pending <= 0;
                    end
                end
            end

            // chip select edges start a new frame
            if (mcncs != mcncs_d)
                idx <= 3'd0;

            if (mc_wr && !mcncs) begin
                if (idx != 3'd4) idx <= idx + 3'd1;
                case (idx)
                    3'd0: op <= mc_byte;
                    3'd1: begin
                        addr <= mc_byte;
                        if (op == 8'h03) begin
                            if (present & use_chip) begin
                                chip_busy <= 1;
                                chip_rd   <= 1;
                                sci_req   <= 1;
                                sci_rnw   <= 1;
                                sci_addr  <= mc_byte;
                                rd_pending <= 1;
                            end else begin
                                rdata <= shadow_read(mc_byte);
                            end
                        end
                    end
                    3'd2: hi <= mc_byte;
                    3'd3: begin
                        if (op == 8'h02) begin
                            // a complete write frame: addr, {hi, mc_byte}
                            case (addr)
                                SCI_MODE: begin
                                    mode_sh <= mc_word & ~16'h0004;
                                    if (mc_byte[2]) begin
                                        if (present) ext_soft_reset <= 1;
                                    end else if (present & use_chip) begin
                                        chip_busy <= 1;
                                        chip_rd   <= 0;
                                        sci_req   <= 1;
                                        sci_rnw   <= 0;
                                        sci_addr  <= SCI_MODE;
                                        sci_wdata <= mode_chip;
                                    end
                                end
                                SCI_CLOCKF: clockf_sh <= mc_word;
                                SCI_VOL: begin
                                    ext_vol_wr <= 1;
                                    ext_vol    <= vol_byte;
                                end
                                default: begin
                                    if (addr == SCI_BASS) bass_sh <= mc_word;
                                    if (present & use_chip) begin
                                        chip_busy <= 1;
                                        chip_rd   <= 0;
                                        sci_req   <= 1;
                                        sci_rnw   <= 0;
                                        sci_addr  <= addr;
                                        sci_wdata <= mc_word;
                                    end
                                end
                            endcase
                        end
                    end
                    default: ;
                endcase
            end

            // MPXRS 0 -> 1: hard reset of the decoder (the FIFO is flushed too)
            if (mpxrs & ~mpxrs_d) begin
                if (present) ext_hard_reset <= 1;
                ext_fifo_wr <= 0;
            end
        end
    end

endmodule
