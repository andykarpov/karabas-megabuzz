/*-------------------------------------------------------------------------------------------------------------------
-- 
-- 
-- #       #######                                                 #                                               
-- #                                                               #                                               
-- #                                                               #                                               
-- ############### ############### ############### ############### ############### ############### ############### 
-- #             #               # #                             # #             #               # #               
-- #             # ############### #               ############### #             # ############### ############### 
-- #             # #             # #               #             # #             # #             #               # 
-- #             # ############### #               ############### ############### ############### ############### 
--                                                                                                                 
--         ####### ####### ####### #######          ## ##   ######  #####   #####  ######  #     # ####### #######
--                                                 #  #  # #       #       #     # #     # #     #      ##      ##
--                                                 #  #  # #####   #   ### ####### ######  #     #   ###     ### 
--                                                 #  #  # #       #     # #     # #     # #     # ##      ##     
--                                                 #  #  #  ######  #####  #     # ######   #####  ####### #######
--
-- https://github.com/andykarpov/karabas-megabuzz
-- FPGA firmware for Karabas-MegaBuzz soundcard
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- EU, 2026
------------------------------------------------------------------------------------------------------------------*/
`default_nettype none

// todo:
// 1. clk_bus = 28, clk_opl3 = 28.6! think about it
// 2. iorqge - check for GS

module karabas_megabuzz(
    input wire          clk,
    input wire  [4:0]   cfg_n,
    input wire          btn_reset_n,

    input wire          bus_rst_n,
    input wire  [15:0]  bus_a,
    inout wire  [7:0]   bus_d,
    input wire          bus_rd_n,
    input wire          bus_wr_n,
    input wire          bus_iorq_n,
    input wire          bus_mreq_n,
    input wire          bus_m1_n,
    output wire         bus_wait_n,
    output wire         bus_iorqge_n,
    input wire          bus_dos_n,
    input wire          bus_iodos_n,

    output wire         midi_clk,
    output wire         midi_tx,
    output wire         midi_reset_n,

    output wire [20:0]  mem_a,
    inout wire  [7:0]   mem_d,
    output wire         mem_wr_n,
    output wire         mem_rd_n,

    output wire         opl3_clk,
    output wire [1:0]   opl3_a,
    output wire         opl3_cs_n,
    input wire  [1:0]   opl3_smp,
    input wire          opl3_data,
    input wire          opl3_dclk,

    output wire         adc_clk,
    output wire         adc_bck,
    output wire         adc_lrck,
    input wire          adc_dat,

    output wire         dac_bck,
    output wire         dac_ws,
    output wire         dac_dat,

    output wire         flash_cs_n,
    output wire         flash_sck,
    output wire         flash_mosi,
    input wire          flash_miso,
    output wire         flash_hold_n,
    output wire         flash_wp_n,

    output wire [7:0]   led_meter_l,
    output wire [7:0]   led_meter_r
);

// unused signals
assign flash_cs_n   = 1'b1;
assign flash_sck    = 1'b1;
assign flash_mosi   = 1'b1;
assign flash_hold_n = 1'b1;
assign flash_wp_n   = 1'b1;

// config bits expanded to named signals
wire soundrive_en   = cfg_n[0];
wire beeper_en      = cfg_n[0];
wire saa_en         = cfg_n[1];
wire gs_en          = cfg_n[2];
wire turbosound_en  = cfg_n[3];
wire midi_en        = cfg_n[3]; // depends on AY port
wire opl3_en        = ~cfg_n[4]; // выключено по-умолчанию (веременно)

// pll
wire clk_bus, clk12, clk8, locked, areset;
pll pll_inst(
    .CLK_IN1         (clk),
    .CLK_OUT1        (clk_bus), // 28
    .CLK_OUT2        (clk12),   // 12
    .CLK_OUT3        (clk8),    // 8
    .LOCKED          (locked)
);
assign areset = ~locked;

// reset
reg reset = 0;
always @(posedge clk_bus, posedge areset) begin
    if (~bus_rst_n || ~btn_reset_n || areset) 
        reset <= 1;
    else
        reset <= 0;
end

assign midi_reset_n = ~reset;
assign bus_wait_n   = 1'bz;

// bus_iorq_n is useless on zxevo :(
// so we're detecting bus_iorq_n cycle by bus_rd_n/bus_wr_n signal asserted without bus_m1_n/bus_mreq_n
reg ioreq, ioreq_prev;
always @(negedge clk_bus) begin
    ioreq_prev  <= ioreq;
    ioreq       <= bus_m1_n && bus_mreq_n && (~bus_rd_n || ~bus_wr_n);
end
wire ioreq_rd = ioreq && ~bus_rd_n;
wire ioreq_wr = ioreq && ~bus_wr_n;

// bus_dos_n is useless on zxevo :(
// so we're just lock some ports access when instruction has been fetched from rom
reg rom_m1_access;
always @(negedge clk_bus or posedge reset) begin
    if (reset)
        rom_m1_access <= 0;
    else if (~bus_m1_n)
        rom_m1_access <= bus_a[15:14] == 2'b00;
end

// ------- i2s DAC --------------
wire signed [15:0] audio_mix_l, audio_mix_r;

PCM5102 #(.DAC_CLK_DIV_BITS(2)) dac_inst(
    .clk              (clk_bus),
    .reset            (areset),
    .left             (audio_mix_l),
    .right            (audio_mix_r),
    .din              (dac_dat),
    .bck              (dac_bck),
    .lrck             (dac_ws)
);

// ------- PCM1808 ADC ---------
wire signed [23:0] adc_l, adc_r;

i2s_transceiver adc_inst(
    .reset_n          (~areset),
    .mclk             (clk_bus),
    .sclk             (adc_bck),
    .ws               (adc_lrck),
    .sd_tx            (),
    .sd_rx            (adc_dat),
    .l_data_tx        (24'b0),
    .r_data_tx        (24'b0),
    .l_data_rx        (adc_l),
    .r_data_rx        (adc_r)
);

ODDR2 oddr_adc2(.Q(adc_clk), .C0(clk_bus), .C1(~clk_bus), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));
ODDR2 oddr_midi(.Q(midi_clk), .C0(clk12), .C1(~clk12), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------- SOUNDRIVE ----------
wire [7:0] covox_a, covox_b, covox_c, covox_d, covox_fb;

soundrive soundrive_inst(
    .clk              (clk_bus),
    .reset            (reset),
    .cs               (soundrive_en),
    .a                (bus_a),
    .d                (bus_d),
    .ioreq_wr         (ioreq_wr),
    .rom_m1_access    (rom_m1_access),
    .out_a            (covox_a),
    .out_b            (covox_b),
    .out_c            (covox_c),
    .out_d            (covox_d),
    .out_fb           (covox_fb)
);

// ------- BEEPER --------------
wire beeper;
beeper beeper_inst(
    .clk              (clk_bus),
    .reset            (reset),
    .cs               (beeper_en),
    .a                (bus_a),
    .d                (bus_d),
    .ioreq_wr         (ioreq_wr),
    .out_beeper       (beeper)
);

// SAA1099

wire [7:0] saa_out_l, saa_out_r;
wire saa_wr_n = ~(ioreq_wr && bus_a[7:0] == 8'hFF && ~rom_m1_access);

saa1099 saa1099_inst(
    .clk              (clk8),
    .rst_n            (~reset),
    .cs_n             (saa_en),
    .a0               (bus_a[8]),
    .wr_n             (saa_wr_n),
    .din              (bus_d),
    .out_l            (saa_out_l),
    .out_r            (saa_out_r)
);

// turbosound fm
wire ts_enable = turbosound_en & ioreq & bus_a[15] & (bus_a[3:0] == 4'b1101);
wire ts_we     = ts_enable & ioreq_wr;
wire [7:0] ts_do;
wire [7:0] ts_ssg0_a, ts_ssg0_b, ts_ssg0_c, ts_ssg1_a, ts_ssg1_b, ts_ssg1_c;
wire [15:0] ts_ssg0_fm, ts_ssg1_fm;
wire ts_fm_ena;

reg ce_ym;
reg [2:0] div;
always @(posedge clk_bus) begin
    div <= div + 1'd1;
    ce_ym <= !div[2] & !div[1] & !div[0]; // 3.5
end

turbosound turbosound_inst(
    .CLK              (clk_bus),
    .RESET            (reset),
    .CE               (ce_ym),
    .BDIR             (ts_we),
    .BC               (bus_a[14]),
    .DI               (bus_d),
    .DO               (ts_do),
    .AY_MODE          (1'b0), // ay / ym
        
    .SSG0_AUDIO_A     (ts_ssg0_a),
    .SSG0_AUDIO_B     (ts_ssg0_b),
    .SSG0_AUDIO_C     (ts_ssg0_c),

    .SSG1_AUDIO_A     (ts_ssg1_a),
    .SSG1_AUDIO_B     (ts_ssg1_b),
    .SSG1_AUDIO_C     (ts_ssg1_c),
    
    .SSG0_AUDIO_FM    (ts_ssg0_fm),
    .SSG1_AUDIO_FM    (ts_ssg1_fm),
    
    .SSG_FM_ENA       (ts_fm_ena),
    .MIDI_TX          (midi_tx)
);

// ------- GS

wire clk_gs;
reg ce_14m;
always @(negedge clk_bus)
begin
    ce_14m <= !ce_14m;
end

BUFGCE U_BUFG14 (.O(clk_gs), .I(clk_bus), .CE(ce_14m));

wire gs_oe;
wire [7:0] gs_do_bus;
wire [14:0] gs_out_l, gs_out_r;

gs_top gs_inst(
    .clk_bus        (clk_bus),
     .ce            (ce_14m),
    .reset          (reset),
    .areset         (areset),

    .a              (bus_a),
    .di             (bus_d),
    .mreq_n         (bus_mreq_n),
    .iorq_n         (bus_iorq_n),
    .m1_n           (bus_m1_n),
    .rd_n           (bus_rd_n),
    .wr_n           (bus_wr_n),

    .oe             (gs_oe),
    .do_bus         (gs_do_bus),

    .sram_d         (mem_d),
    .sram_a         (mem_a),
    .sram_wr_n      (mem_wr_n),
    .sram_rd_n      (mem_rd_n),

    .out_l          (gs_out_l),
    .out_r          (gs_out_r)    
);

// opl3
wire signed [15:0] opl3_l, opl3_r;
wire opl3_iorqge_n;
opl3 opl3_inst(
    .clk            (clk_bus),
    .ce             (ce_14m),
    .reset          (reset),
    
    .bus_a          (bus_a),
    .bus_d          (bus_d),
    .bus_rd_n       (bus_rd_n),
    .bus_wr_n       (bus_wr_n),
    .bus_mreq_n     (bus_mreq_n),
    .bus_iorq_n     (bus_iorq_n),
    .bus_m1_n       (bus_m1_n),    
    
   .opl3_clk        (opl3_clk),
   .opl3_a          (opl3_a),
   .opl3_cs_n       (opl3_cs_n),

   .opl3_smp        (opl3_smp),
   .opl3_data       (opl3_data),
   .opl3_dclk       (opl3_dclk),
    
    .opl3_iorqge_n  (opl3_iorqge_n),
    
    .out_l          (opl3_l),
    .out_r          (opl3_r)
);

// audio mixer
audio_mixer audio_mixer_inst(
    .clk            (clk_bus),

    .mute           (1'b0), // todo
    .mode           (2'b00), // abc/acb/mono ? 
    
    .soundrive_en   (soundrive_en),
    .beeper_en      (beeper_en),
    .turbosound_en  (turbosound_en),
    .saa_en         (saa_en),
    .gs_en          (gs_en),
    .midi_en        (midi_en),
    .opl3_en        (opl3_en),
    
    .speaker        (beeper),
    .tape_in        (1'b0),
    
    .ssg0_a         (ts_ssg0_a),
    .ssg0_b         (ts_ssg0_b),
    .ssg0_c         (ts_ssg0_c),
    .ssg1_a         (ts_ssg1_a),
    .ssg1_b         (ts_ssg1_b),
    .ssg1_c         (ts_ssg1_c),
    
    .covox_a        (covox_a),
    .covox_b        (covox_b),
    .covox_c        (covox_c),
    .covox_d        (covox_d),
    .covox_fb       (covox_fb),
    
    .saa_l          (saa_out_l),
    .saa_r          (saa_out_r),
    
    .gs_l           (gs_out_l),
    .gs_r           (gs_out_r),
    
    .fm_l           (ts_ssg0_fm),
    .fm_r           (ts_ssg1_fm),
    .fm_ena         (ts_fm_ena),

    .adc_l          (adc_l[23:8]),
    .adc_r          (adc_r[23:8]),
    
    .opl3_l         (opl3_l),
    .opl3_r         (opl3_r),
    
    .audio_l        (audio_mix_l),
    .audio_r        (audio_mix_r)    
);

// BUS
assign bus_d = 
    (ts_enable && ioreq_rd) ? ts_do : // TurboSound
    (gs_oe && ioreq_rd) ? gs_do_bus : // gs
    8'bzzzzzzzz;

// IORQGE
assign bus_iorqge_n = (bus_m1_n && (ts_enable || gs_oe || ~opl3_iorqge_n))? 1'b0 : 1'b1;

// vu meter
vu_meter vu_meter_l_inst(
    .clk            (clk_bus),
    .sample_tick    (dac_ws),
    .audio_sample   (audio_mix_l),
    .leds           (led_meter_l)
);

vu_meter vu_meter_r_inst(
    .clk            (clk_bus),
    .sample_tick    (dac_ws),
    .audio_sample   (audio_mix_r),
    .leds           (led_meter_r)
);

endmodule

