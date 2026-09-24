// ----------------------------------------------------------------------------
// vs1053/vs1063 pseudo-parallel module
// clocked by XTALI = 12.000 MHz
//
// clk - 28 MHz
//
// Registers: 
//
// 0 Status:
//
// bus_a = 00, rd - returns a status register
// - bit 7 - overflow flag
// - bit 6:0 - count of 32-bytes block in the fifo
//
// bus_a = 00, wr - write a command to the controller
// - bit 7 = 1 - soft reset
// - bit 6 = 1 - hard reset
// - bit 5:0   - n/a
//
// 1 Data:
//
// bus_a = 01, wr - write a byte to the FIFO
// bus_a = 01, rd - return a status register also
//
// 2 Volume:
// bus_a = 10, rd/wr - read/write a byte of volume control (00 - max volume, FE - silence)
//
// 3 Effects:
// 
// bus_a = 11, rd/wr - read/write a byte of effects control
// - bit 7:6 - ear speaker (00 - off, 01 - low, 10 - mid, 11 - high)
// - bit 5:3 - treble boost (000 - off, 111 - max +10.5dB) at 5kHz
// - bit 2:0 - bass boost (000 - off, 111 - max + 14dB) at 60Hz
//  
// ----------------------------------------------------------------------------
/* verilator lint_off DECLFILENAME */
module vs1053 (
    input  wire        clk,
    input  wire        reset,

    input  wire        bus_cs_n,
    input  wire        bus_rd_n,
    input  wire        bus_wr_n,
    input  wire [1:0]  bus_a, // 00 - status, 01 - data, 10 - volume, 11 - effects
    input  wire [7:0]  bus_di,
    output wire [7:0]  bus_do,

    output wire        vs_sclk,
    input  wire        vs_miso,
    output wire        vs_mosi,
    input  wire        vs_dreq,
    output wire        vs_cs_n,
    output wire        vs_dcs_n,
    output wire        vs_reset_n
);

    parameter [7:0] DEFAULT_VOLUME = 8'h08;
    parameter [7:0] DEFAULT_EFFECT = 8'h00;

    wire        fifo_rd_en;
    wire [7:0]  fifo_data_out;
    wire        fifo_empty;
    wire        fifo_full;
    wire [11:0] fifo_count;
    wire        soft_reset_cmd;
    wire        hard_reset_cmd;

    wire        spi_start;
    wire        spi_is_data;
    wire        spi_rnw;
    wire [7:0]  spi_addr;
    wire [15:0] spi_data_in;
    wire        spi_busy;
    wire [15:0] spi_data_out;
    wire        spi_fast_mode;
    wire [3:0]  chip_version;
    wire [7:0]  reg_volume;
    wire [7:0]  reg_effects;

    vs1053_host_interface #(.DEFAULT_VOLUME(DEFAULT_VOLUME), .DEFAULT_EFFECT(DEFAULT_EFFECT)) host_if_inst (
        .clk(clk),
        .rst(reset),
        .bus_cs_n(bus_cs_n),
        .bus_rd_n(bus_rd_n),
        .bus_wr_n(bus_wr_n),
        .bus_a(bus_a),
        .bus_di(bus_di),
        .bus_do(bus_do),
        .fifo_rd_en(fifo_rd_en),
        .fifo_data_out(fifo_data_out),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full),
        .fifo_count(fifo_count),
        .soft_reset_cmd(soft_reset_cmd),
        .hard_reset_cmd(hard_reset_cmd),
        .reg_volume(reg_volume),
        .reg_effects(reg_effects)
    );

    vs1053_controller ctrl_inst (
        .clk(clk),
        .rst(reset),
        .soft_reset_cmd(soft_reset_cmd),
        .hard_reset_cmd(hard_reset_cmd),
        .fifo_rd_en(fifo_rd_en),
        .fifo_data_out(fifo_data_out),
        .fifo_empty(fifo_empty),
        .fifo_count(fifo_count),
        .spi_start(spi_start),
        .spi_is_data(spi_is_data),
        .spi_rnw(spi_rnw),
        .spi_addr(spi_addr),
        .spi_data_in(spi_data_in),
        .spi_busy(spi_busy),
        .spi_data_out(spi_data_out),
        .spi_fast_mode(spi_fast_mode),
        .vs_reset_n(vs_reset_n),
        .vs_dreq(vs_dreq),
        .chip_version(chip_version),
        .reg_volume(reg_volume),
        .reg_effects(reg_effects)
    );

    vs1053_spi_master spi_master_inst (
        .clk(clk),
        .rst(reset || soft_reset_cmd || hard_reset_cmd),
        .fast_mode(spi_fast_mode),
        .start(spi_start),
        .is_data(spi_is_data),
        .rnw(spi_rnw),
        .addr(spi_addr),
        .data_in(spi_data_in),
        .busy(spi_busy),
        .data_out(spi_data_out),
        .vs_sclk(vs_sclk),
        .vs_miso(vs_miso),
        .vs_mosi(vs_mosi),
        .vs_cs_n(vs_cs_n),
        .vs_dcs_n(vs_dcs_n)
    );

endmodule

// ----------------------------------------------------------------------------

module vs1053_spi_master (
    input  wire        clk,
    input  wire        rst,
    input  wire        fast_mode, // 0 = ~250 kHz, 1 = ~3.5 MHz

    input  wire        start,
    input  wire        is_data, // 0 = SCI (CS), 1 = SDI (DCS)
    input  wire        rnw, // 1 = Read, 0 = Write
    input  wire [7:0]  addr, // SCI register address
    input  wire [15:0] data_in, // Data for SCI or SDI
    output reg         busy,
    output reg  [15:0] data_out,

    output reg         vs_sclk,
    input  wire        vs_miso,
    output reg         vs_mosi,
    output reg         vs_cs_n,
    output reg         vs_dcs_n
);

    // clock divier to generate spi_x2_tick (2 times faster than SCLK)
    // clk_div_half = clk_div / 2
    // fast_mode: ~3.5 MHz
    // slow_mode: ~250 kHz
    wire [7:0] clk_div_half = fast_mode ? 8'd4 : 8'd56;
    reg  [7:0] clk_cnt;
    reg        spi_x2_tick;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt     <= 0;
            spi_x2_tick <= 0;
        end else if (busy) begin
            if (clk_cnt >= clk_div_half - 1) begin
                clk_cnt     <= 0;
                spi_x2_tick <= 1;
            end else begin
                clk_cnt     <= clk_cnt + 1;
                spi_x2_tick <= 0;
            end
        end else begin
            clk_cnt     <= 0;
            spi_x2_tick <= 0;
        end
    end

    localparam IDLE      = 3'd0;
    localparam SETUP     = 3'd1;
    localparam LEAD      = 3'd2;
    localparam DRIVE     = 3'd3;
    localparam SAMPLE    = 3'd4;
    localparam HOLD      = 3'd5;

    reg [2:0]  state;
    reg [5:0]  bit_cnt;
    reg [31:0] shift_reg;
    reg        sclk_next;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            busy     <= 0;
            vs_sclk  <= 0;
            vs_mosi  <= 0;
            vs_cs_n  <= 1;
            vs_dcs_n <= 1;
            data_out <= 0;
            bit_cnt  <= 0;
            shift_reg<= 0;
        end else begin
            case (state)
                IDLE: begin
                    vs_sclk <= 0;
                    vs_mosi <= 0;
                    if (start) begin
                        busy  <= 1;
                        state <= SETUP;
                        // raise cs before first clock
                        vs_cs_n  <= is_data;
                        vs_dcs_n <= !is_data;

                        if (!is_data) begin
                            shift_reg <= {rnw ? 8'h03 : 8'h02, addr, data_in};
                            bit_cnt   <= 6'd32;
                        end else begin
                            shift_reg <= {data_in[7:0], 24'h0};
                            bit_cnt   <= 6'd8;
                        end
                    end else begin
                        busy     <= 0;
                        vs_cs_n  <= 1'b1;
                        vs_dcs_n <= 1'b1;
                    end
                end

                SETUP: begin
                    // tXCS
                    if (spi_x2_tick) begin
                        state <= DRIVE;
                    end
                end

                DRIVE: begin
                    // phase 1: MOSI data while SCLK = 0
                    if (spi_x2_tick) begin
                        vs_mosi <= shift_reg[31];
                        state   <= SAMPLE;
                    end
                end

                SAMPLE: begin
                    // phase 2: raise SCLK to 1
                    if (spi_x2_tick) begin
                        vs_sclk   <= 1'b1;
                        shift_reg <= {shift_reg[30:0], vs_miso};
                        bit_cnt   <= bit_cnt - 1;
                        state     <= LEAD;
                    end
                end

                LEAD: begin
                    // phase 3: fall SCLK to 0
                    if (spi_x2_tick) begin
                        vs_sclk <= 1'b0;
                        if (bit_cnt == 0) begin
                            state <= HOLD;
                        end else begin
                            state <= DRIVE;
                        end
                    end
                end

                HOLD: begin
                    // tXCH
                    if (spi_x2_tick) begin
                        if (!is_data && rnw) begin
                            data_out <= shift_reg[15:0];
                        end
                        vs_cs_n  <= 1'b1;
                        vs_dcs_n <= 1'b1;
                        busy     <= 0;
                        state    <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule

// ----------------------------------------------------------------------------

module vs1053_host_interface (
    input  wire        clk,
    input  wire        rst,

    input  wire        bus_cs_n,
    input  wire        bus_rd_n,
    input  wire        bus_wr_n,
    input  wire [1:0]  bus_a,
    input  wire [7:0]  bus_di,
    output reg  [7:0]  bus_do,

    input  wire        fifo_rd_en,
    output wire [7:0]  fifo_data_out,
    output wire        fifo_empty,
    output wire        fifo_full,
    output wire [11:0]  fifo_count,

    output reg         soft_reset_cmd,
    output reg         hard_reset_cmd,

    output reg  [7:0]  reg_volume,
    output reg  [7:0]  reg_effects
);

    parameter [7:0] DEFAULT_VOLUME = 8'h08;
    parameter [7:0] DEFAULT_EFFECT = 8'h00;

    // detect z80 fronts
    reg [2:0] wr_sync;
    always @(posedge clk) begin
        wr_sync <= {wr_sync[1:0], bus_wr_n};
    end
    wire wr_pulse = (wr_sync[2] == 1 && wr_sync[1] == 0) && !bus_cs_n;

    // 4096 bytes FIFO
    reg fifo_wr_en;
    reg fifo_clear;
    fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(12)) fifo(
        .clk(clk),
        .reset(fifo_clear),
        .rd(fifo_rd_en),
        .wr(fifo_wr_en),
        .din(bus_di),
        .dout(fifo_data_out),
        .full(fifo_full),
        .empty(fifo_empty),
        .data_count(fifo_count)
    );

    always @(*) begin
        case (bus_a)
            2'b00:   bus_do = {fifo_full, fifo_count[11:5]}; // FIFO status
            2'b01:   bus_do = {fifo_full, fifo_count[11:5]}; // FIFO status
            2'b10:   bus_do = reg_volume; // Read current volume
            2'b11:   bus_do = reg_effects; // Read current effects
            default: bus_do = 8'hFF;
        endcase
    end

    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_clear <= 1;
            fifo_wr_en <= 0;
            soft_reset_cmd <= 0;
            hard_reset_cmd <= 0;
            reg_volume     <= DEFAULT_VOLUME;
            reg_effects    <= DEFAULT_EFFECT;
        end else begin
            soft_reset_cmd <= 0;
            hard_reset_cmd <= 0;
            fifo_wr_en <= 0;
            fifo_clear <= 0;

            if (wr_pulse) begin
                case (bus_a)
                    2'b00: begin // control (soft and hard reset)
                        if (bus_di[7]) begin
                            soft_reset_cmd <= 1;
                            fifo_clear <= 1;
                        end
                        if (bus_di[6]) begin
                            hard_reset_cmd <= 1;
                            fifo_clear <= 1;
                        end
                    end
                    2'b01: begin // Write data into FIFO
                        if (!fifo_full) begin
                            fifo_wr_en <= 1;
                        end
                    end
                    2'b10: begin // Write a new volume register
                        reg_volume <= bus_di;
                    end
                    2'b11: begin // Write a new effects register
                        reg_effects <= bus_di;
                    end
                    default: ; // no operation
                endcase
            end
        end
    end

endmodule

// ----------------------------------------------------------------------------

module vs1053_controller (
    input  wire        clk,
    input  wire        rst,
    input  wire        soft_reset_cmd,
    input  wire        hard_reset_cmd,

    output reg         fifo_rd_en,
    input  wire [7:0]  fifo_data_out,
    input  wire        fifo_empty,
    input  wire [11:0]  fifo_count,

    output reg         spi_start,
    output reg         spi_is_data,
    output reg         spi_rnw,
    output reg  [7:0]  spi_addr,
    output reg  [15:0] spi_data_in,
    input  wire        spi_busy,
    input  wire [15:0] spi_data_out,
    output reg         spi_fast_mode,

    output reg         vs_reset_n,
    input  wire        vs_dreq,

    input  wire [7:0]  reg_volume,
    input  wire [7:0]  reg_effects,
    output reg [3:0]   chip_version
);

`ifdef SIMULATION
    localparam DLY_HW_RESET   = 16'd50;   // Short reset
    localparam DLY_PLL_LOCK   = 16'd100;  // Short wait for PLL
    localparam DLY_CS_SLOW    = 8'd60;    // CS delay on slow speed
    localparam DLY_CS_FAST    = 8'd15;    // CS delay on high speed
`else
    localparam DLY_HW_RESET   = 16'd5000; // ~178 us RESET hold time
    localparam DLY_PLL_LOCK   = 16'd14000; // ~500 us PLL lock (12MHz XTAL)
    localparam DLY_CS_SLOW    = 8'd60; // ~2.14 us CS delay on slow speed
    localparam DLY_CS_FAST    = 8'd15; // ~0.53 us CS delay on high speed
`endif

    // VS1053b/1063a registers
    localparam SCI_MODE   = 8'h00;
    localparam SCI_STATUS = 8'h01;
    localparam SCI_CLOCKF = 8'h03;
    localparam SCI_BASS   = 8'h02;
    localparam SCI_VOL    = 8'h0B;

    // SCI_CLOCKF values for 12MHz XTAL
    localparam CLOCKF_1063 = 16'h8BE8;
    localparam CLOCKF_1053 = 16'h4BE8;

    reg [4:0] state;
    reg [4:0] next_state;
    reg [15:0] delay_cnt;
    reg [7:0]  cs_delay_counter;
    reg [5:0]  byte_cnt;
    reg [11:0] zero_cnt;
    reg [7:0]  vol_shadow;
    reg [7:0]  eff_shadow;
    reg        req_update_vol;
    reg        req_update_eff;
    reg        init_done;

    wire [15:0] pack_vol   = {reg_volume, reg_volume};
    wire [15:0] pack_bass  = {reg_effects[5:3], 5'd5, reg_effects[2:0], 4'h6}; // EQ: 5kHz (5), 60Гц (6)
    wire [15:0] pack_mode  = {4'h0, 1'b1, 3'h0, reg_effects[7:6], 6'h00}; // SM_SDINEW + EarSpeaker

    localparam ST_HW_RESET       = 5'd0,
    ST_DELAY_1        = 5'd1,
    ST_RD_STATUS      = 5'd2,
    ST_WAIT_RD        = 5'd3,
    ST_WR_CLOCKF      = 5'd4,
    ST_WAIT_WR        = 5'd5,
    ST_DELAY_2        = 5'd6,
    ST_SWITCH_FAST    = 5'd7,
    ST_IDLE           = 5'd8,
    ST_PREPARE_BYTE   = 5'd9,
    ST_SEND_BYTE      = 5'd10,
    ST_WAIT_BYTE      = 5'd11,
    ST_CS_PULSE_DELAY = 5'd12,
    ST_SW_RESET       = 5'd13,
    ST_WAIT_SW_RESET  = 5'd14,
    ST_DELAY_3        = 5'd15,
    ST_INIT_ZEROES    = 5'd16,
    ST_SEND_ZERO_BYTE = 5'd17,
    ST_WAIT_ZERO_BYTE = 5'd18,
    ST_WR_BASS         = 5'd19,
    ST_WAIT_WR_BASS    = 5'd20,
    ST_WR_VOL          = 5'd21,
    ST_WAIT_WR_VOL     = 5'd22,
    ST_WR_AMODE        = 5'd23,
    ST_WAIT_WR_AMODE   = 5'd24;

    always @(posedge clk or posedge rst) begin
        if (rst | hard_reset_cmd | soft_reset_cmd) begin
            vol_shadow     <= 8'hFF; // to apply reg values on reset
            eff_shadow     <= 8'hFF;
            req_update_vol <= 0;
            req_update_eff <= 0;
        end else begin
            if (reg_volume != vol_shadow && state == ST_IDLE) begin req_update_vol <= 1; end
            if (reg_effects != eff_shadow && state == ST_IDLE) begin req_update_eff <= 1; end
            if (state == ST_WR_VOL)  begin
                req_update_vol <= 0;
                vol_shadow <= reg_volume;
            end
            if (state == ST_WR_BASS) begin
                req_update_eff <= 0;
                eff_shadow <= reg_effects;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst | hard_reset_cmd) begin
            state         <= ST_HW_RESET;
            vs_reset_n    <= 0;
            delay_cnt     <= 0;
            spi_start     <= 0;
            spi_is_data   <= 0;
            spi_rnw       <= 0;
            spi_addr      <= 0;
            spi_data_in   <= 0;
            spi_fast_mode <= 0;
            fifo_rd_en    <= 0;
            byte_cnt      <= 0;
            cs_delay_counter <= 0;
            zero_cnt      <= 0;
            init_done     <= 0;
        end else if (soft_reset_cmd) begin
            state         <= ST_SW_RESET;
            vs_reset_n    <= 1; // do not do any hw resets to avoid clicks
            delay_cnt     <= 0;
            spi_start     <= 0;
            spi_is_data   <= 0;
            spi_rnw       <= 0;
            spi_addr      <= 0;
            spi_data_in   <= 0;
            spi_fast_mode <= 0;
            fifo_rd_en    <= 0;
            byte_cnt      <= 0;
            cs_delay_counter <= 0;
            zero_cnt      <= 0;
            init_done     <= 0;
        end else begin
            fifo_rd_en <= 0;
            spi_start  <= 0;

            case (state)
                // hardware reset
                ST_HW_RESET: begin
                    vs_reset_n <= 0;
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt == DLY_HW_RESET) begin
                        vs_reset_n <= 1;
                        delay_cnt <= 0;
                        state <= ST_DELAY_1;
                    end
                end

                ST_DELAY_1: begin
                    if (vs_dreq) begin
                        state <= ST_RD_STATUS;
                    end
                end

                // software reset
                ST_SW_RESET: begin
                    if (!spi_busy && vs_dreq) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 0;
                        spi_addr    <= SCI_MODE;
                        spi_data_in <= 16'h0804; // SM_RESET BIT + SM_SDINEW bits high
                        state       <= ST_WAIT_SW_RESET;
                    end
                end

                ST_WAIT_SW_RESET: begin
                    if (!spi_busy && !spi_start) begin
                        delay_cnt                 <= 0;
                        cs_delay_counter          <= DLY_CS_SLOW;
                        next_state                <= ST_DELAY_3;
                        state                     <= ST_CS_PULSE_DELAY;
                    end
                end

                ST_DELAY_3: begin
                    delay_cnt <= delay_cnt + 1;
                    if ((delay_cnt == DLY_PLL_LOCK) && vs_dreq) begin
                        state <= ST_RD_STATUS;
                    end
                end

                // read status reg
                ST_RD_STATUS: begin
                    if (!spi_busy) begin
                        spi_start   <= 1;
                        spi_rnw     <= 1;
                        spi_is_data <= 0;
                        spi_addr    <= SCI_STATUS;
                        state       <= ST_WAIT_RD;
                    end
                end

                ST_WAIT_RD: begin
                    if (!spi_busy && !spi_start) begin
                        chip_version <= spi_data_out[7:4];
                        cs_delay_counter          <= DLY_CS_SLOW;
                        next_state                <= ST_WR_CLOCKF;
                        state                     <= ST_CS_PULSE_DELAY;
                    end
                end

                // write clockf reg
                ST_WR_CLOCKF: begin
                    if (!spi_busy) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 0;
                        spi_addr    <= SCI_CLOCKF;
                        spi_data_in <= (chip_version == 4'h6) ? CLOCKF_1063 : CLOCKF_1053;
                        state       <= ST_WAIT_WR;
                    end
                end

                ST_WAIT_WR: begin
                    if (!spi_busy && !spi_start) begin
                        delay_cnt                 <= 0;
                        cs_delay_counter          <= DLY_CS_SLOW;
                        next_state                <= ST_DELAY_2;
                        state                     <= ST_CS_PULSE_DELAY;
                    end
                end

                ST_DELAY_2: begin
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt == DLY_PLL_LOCK) begin
                        state <= ST_SWITCH_FAST;
                    end
                end

                // switch spi to fast mode after clockf write
                ST_SWITCH_FAST: begin
                    if (vs_dreq) begin
                        spi_fast_mode <= 1;
                        state         <= ST_WR_BASS;
                    end
                end

                // equalizer setup
                ST_WR_BASS: begin
                    if (!spi_busy && vs_dreq) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 0;
                        spi_addr    <= SCI_BASS;
                        spi_data_in <= pack_bass;
                        state       <= ST_WAIT_WR_BASS;
                    end
                end

                ST_WAIT_WR_BASS: begin
                    if (!spi_busy && !spi_start) begin
                        cs_delay_counter          <= DLY_CS_FAST;
                        next_state                <= ST_WR_VOL;
                        state                     <= ST_CS_PULSE_DELAY;
                    end
                end

                // volume setup
                ST_WR_VOL: begin
                    if (!spi_busy && vs_dreq) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 0;
                        spi_addr    <= SCI_VOL;
                        spi_data_in <= pack_vol;
                        state       <= ST_WAIT_WR_VOL;
                    end
                end

                ST_WAIT_WR_VOL: begin
                    if (!spi_busy && !spi_start) begin
                        cs_delay_counter          <= DLY_CS_FAST;
                        next_state                <= ST_WR_AMODE;
                        state                     <= ST_CS_PULSE_DELAY;
                    end
                end

                // ear mode setup
                ST_WR_AMODE: begin
                    if (!spi_busy && vs_dreq) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 0;
                        spi_addr    <= SCI_MODE;
                        spi_data_in <= pack_mode;
                        state       <= ST_WAIT_WR_AMODE;
                    end
                end

                ST_WAIT_WR_AMODE: begin
                    if (!spi_busy && !spi_start) begin
                        cs_delay_counter          <= DLY_CS_FAST;
                        next_state                <= init_done ? ST_IDLE : ST_INIT_ZEROES;
                        state                     <= ST_CS_PULSE_DELAY;
                    end
                end

                // init zeroes - send 2048 bytes to the chip
                ST_INIT_ZEROES: begin
                    zero_cnt <= 12'd2048;
                    state    <= ST_SEND_ZERO_BYTE;
                end

                ST_SEND_ZERO_BYTE: begin
                    if (vs_dreq && !spi_busy) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 1;
                        spi_data_in <= 16'h0000;
                        state       <= ST_WAIT_ZERO_BYTE;
                    end
                end

                ST_WAIT_ZERO_BYTE: begin
                    if (!spi_busy && !spi_start) begin
                        if (zero_cnt == 1) begin
                            cs_delay_counter <= DLY_CS_FAST;
                            next_state       <= ST_IDLE;
                            state            <= ST_CS_PULSE_DELAY;
                            init_done        <= 1;
                        end else begin
                            zero_cnt <= zero_cnt - 1;
                            state    <= ST_SEND_ZERO_BYTE;
                        end
                    end
                end

                // fifo read and send to vs1053
                ST_IDLE: begin
                    // prio 1: Effects was changed (Apply bass then mode)
                    if (req_update_eff) begin
                        state <= ST_WR_BASS;

                        // prio 2: Volume was changed
                    end else if (req_update_vol) begin
                        state <= ST_WR_VOL;

                        // prio 3: send audio data from FIFO
                    end else if (vs_dreq && (fifo_count >= 32) && !fifo_empty) begin
                        byte_cnt <= 6'd32;
                        state    <= ST_PREPARE_BYTE;
                    end
                end

                ST_PREPARE_BYTE: begin
                    fifo_rd_en <= 1;
                    state      <= ST_SEND_BYTE;
                end

                ST_SEND_BYTE: begin
                    if (!spi_busy) begin
                        spi_start   <= 1;
                        spi_rnw     <= 0;
                        spi_is_data <= 1;
                        spi_data_in <= {8'h0, fifo_data_out};
                        state       <= ST_WAIT_BYTE;
                    end
                end

                ST_WAIT_BYTE: begin
                    if (!spi_busy && !spi_start) begin
                        byte_cnt <= byte_cnt - 1;
                        if (byte_cnt == 1) begin
                            cs_delay_counter          <= DLY_CS_FAST;
                            next_state                <= ST_IDLE;
                            state                     <= ST_CS_PULSE_DELAY;
                        end else begin
                            state <= ST_PREPARE_BYTE;
                        end
                    end
                end

                // special sub-state for cs pulse delay (used by other states as well)
                ST_CS_PULSE_DELAY: begin
                    if (cs_delay_counter > 0) begin
                        cs_delay_counter <= cs_delay_counter - 1;
                    end else begin
                        state <= next_state;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

