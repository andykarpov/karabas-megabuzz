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
--         ####### ####### ####### #######         ############### ############### ############### ############### 
--                                                 #      #      # #             # #                             # 
--                                                 #      #      # ############### #       ####### ############### 
--                                                 #      #      # #               #             # #             # 
--                                                 #      #      # ############### ############### ############### 
--                                                 
--                                                 #               #             # ############### ###############
--                                                 #               #             #               #               #
--                                                 ############### #             # ############### ###############
--                                                 #             # #             # #               #
--                                                 ############### ############### ############### ###############
--
-- https://github.com/andykarpov/karabas-megabuzz
-- FPGA firmware for Karabas-MegaBuzz soundcard
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- EU, 2026
------------------------------------------------------------------------------------------------------------------*/
`default_nettype none

// todo:
// 1. use CFG to disable things
// 2. clk_bus = 28, clk_opl3 = 28.6! think about it

module karabas_megabuzz(
    input wire clk,
    input wire [4:0] cfg_n,
    input wire btn_reset_n,

    input wire bus_rst_n,
    input wire [15:0] bus_a,
    inout wire [7:0] bus_d,
    input wire bus_rd_n,
    input wire bus_wr_n,
    input wire bus_iorq_n,
    input wire bus_mreq_n,
    input wire bus_m1_n,
    output wire bus_wait_n,
    output wire bus_iorqge_n,
    input wire bus_dos_n,
    input wire bus_iodos_n,

    output wire midi_clk,
    output wire midi_tx,
	 output wire midi_reset_n,

    output wire [20:0] mem_a,
    inout wire [7:0] mem_d,
    output wire mem_wr_n,
    output wire mem_rd_n,

    output wire opl3_clk,
    output wire [1:0] opl3_a,
    output wire opl3_cs_n,
    input wire [1:0] opl3_smp,
    input wire opl3_data,
    input wire opl3_dclk,

    output wire adc_clk,
    output wire adc_bck,
    output wire adc_lrck,
    input wire adc_dat,

    output wire dac_bck,
    output wire dac_ws,
    output wire dac_dat,

    output wire flash_cs_n,
    output wire flash_sck,
    output wire flash_mosi,
    input wire flash_miso,
    output wire flash_hold_n,
    output wire flash_wp_n,

    output wire [7:0] led_meter_l,
    output wire [7:0] led_meter_r
);

// unused signals
assign flash_cs_n = 1'b1;
assign flash_sck = 1'b1;
assign flash_mosi = 1'b1;
assign flash_hold_n = 1'b1;
assign flash_wp_n = 1'b1;

// pll
wire clk_bus, clk12, clk8, locked, areset;
pll pll(
	.CLK_IN1			(clk),
	.CLK_OUT1		(clk_bus), // 28
	.CLK_OUT2		(clk12),	  // 12
	.CLK_OUT3		(clk8),	  // 8
	.LOCKED			(locked)
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
assign bus_wait_n = 1'bz;
assign bus_iorqge_n = 1'bz;

// ------- i2s DAC --------------
wire signed [15:0] audio_mix_l, audio_mix_r;

PCM5102 #(.DAC_CLK_DIV_BITS(2)) PCM5102(
	.clk				(clk_bus),
	.reset			(areset),
	.left				(audio_mix_l),
	.right			(audio_mix_r),
	.din				(dac_dat),
	.bck				(dac_bck),
	.lrck				(dac_ws)
);

// ------- PCM1808 ADC ---------
wire signed [23:0] adc_l, adc_r;

i2s_transceiver adc(
	.reset_n			(~areset),
	.mclk				(clk_bus),
	.sclk				(adc_bck),
	.ws				(adc_lrck),
	.sd_tx			(),
	.sd_rx			(adc_dat),
	.l_data_tx		(24'b0),
	.r_data_tx		(24'b0),
	.l_data_rx		(adc_l),
	.r_data_rx		(adc_r)
);

ODDR2 oddr_adc2(.Q(adc_clk), .C0(clk_bus), .C1(~clk_bus), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));
ODDR2 oddr_midi(.Q(midi_clk), .C0(clk12), .C1(~clk12), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------- SOUNDRIVE ----------
wire [7:0] covox_a, covox_b, covox_c, covox_d, covox_fb;

covox covox
(
	.I_RESET			(reset),
	.I_CLK			(clk_bus),
	.I_CS				(1'b1), // todo: cfg
	.I_ADDR			(bus_a[7:0]),
	.I_DATA			(bus_d),
	.I_WR_N			(bus_wr_n),
	.I_IORQ_N		(bus_iorq_n),
	.I_DOS			(bus_dos_n), 
	.O_A				(covox_a),
	.O_B				(covox_b),
	.O_C				(covox_c),
	.O_D				(covox_d),
	.O_FB				(covox_fb)
);

// SAA1099

wire saa_wr_n;
wire [7:0] saa_out_l;
wire [7:0] saa_out_r;

saa1099 saa1099
(
	.clk				(clk8),
	.rst_n			(~reset),
	.cs_n				(1'b0), // todo: cfg
	.a0				(bus_a[8]),
	.wr_n				(saa_wr_n),
	.din				(bus_d),
	.out_l			(saa_out_l),
	.out_r			(saa_out_r)
);

assign saa_wr_n = bus_iorq_n || bus_wr_n || ~(bus_a[7:0] == 8'hFF);

// beeper

reg [7:0] port_xxfe_reg;
always @(posedge clk_bus) begin
	if (reset) port_xxfe_reg <= 0;
	else if (~bus_iorq_n && ~bus_wr_n && bus_a[7:0] == 8'hFE) port_xxfe_reg <= bus_d;
end

wire beeper = port_xxfe_reg[4];

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

gs_top gs_top
(
    .clk_bus		(clk_bus),
	 .ce				(ce_14m),
    .reset			(reset),
    .areset			(areset),

    .a				(bus_a),
    .di				(bus_d),
    .mreq_n			(bus_mreq_n),
    .iorq_n			(bus_iorq_n),
    .m1_n			(bus_m1_n),
    .rd_n			(bus_rd_n),
    .wr_n			(bus_wr_n),

    .oe				(gs_oe),
    .do_bus			(gs_do_bus),

    .sram_d			(mem_d),
    .sram_a			(mem_a),
    .sram_wr_n		(mem_wr_n),
    .sram_rd_n		(mem_rd_n),

    .out_l			(gs_out_l),
    .out_r			(gs_out_r)    
);

// turbosound fm
wire ts_enable = ~bus_iorq_n & bus_a[15] & (bus_a[3:0] == 4'b1101);
wire ts_we     = ts_enable & ~bus_wr_n;
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

turbosound turbosound
(
	.RESET			(reset),
	.CLK				(clk_bus),
	.CE				(ce_ym),
	.BDIR				(ts_we),
	.BC				(bus_a[14]),
	.DI				(bus_d),
	.DO				(ts_do),
	.AY_MODE			(1'b0), // ay / ym
		
	.SSG0_AUDIO_A	(ts_ssg0_a),
	.SSG0_AUDIO_B	(ts_ssg0_b),
	.SSG0_AUDIO_C	(ts_ssg0_c),

	.SSG1_AUDIO_A	(ts_ssg1_a),
	.SSG1_AUDIO_B	(ts_ssg1_b),
	.SSG1_AUDIO_C	(ts_ssg1_c),
	
	.SSG0_AUDIO_FM	(ts_ssg0_fm),
	.SSG1_AUDIO_FM	(ts_ssg1_fm),
	
	.SSG_FM_ENA		(ts_fm_ena),
	.MIDI_TX			(midi_tx)
);

// opl3
wire signed [15:0] opl3_l, opl3_r;
wire opl3_iorqge_n;
opl3 opl3(
	.clk				(clk_bus),
	.ce				(ce_14m),
	.reset			(reset),
	
	.bus_a			(bus_a),
	.bus_d			(bus_d),
	.bus_rd_n		(bus_rd_n),
	.bus_wr_n		(bus_wr_n),
	.bus_mreq_n		(bus_mreq_n),
	.bus_iorq_n		(bus_iorq_n),
	.bus_m1_n		(bus_m1_n),	
	
   .opl3_clk		(opl3_clk),
   .opl3_a			(opl3_a),
   .opl3_cs_n		(opl3_cs_n),

   .opl3_smp		(opl3_smp),
   .opl3_data		(opl3_data),
   .opl3_dclk		(opl3_dclk),
	
	.opl3_iorqge_n (opl3_iorqge_n),
	
	.out_l			(opl3_l),
	.out_r			(opl3_r)
);

// audio mixer
audio_mixer audio_mixer
(
	.clk				(clk_bus),

	.mute				(1'b0), // todo
	.mode				(2'b00), // abc/acb/mono ? 
	
	.speaker			(port_xxfe_reg[4]),
	.tape_in			(1'b0),
	
	.ssg0_a			(ts_ssg0_a),
	.ssg0_b			(ts_ssg0_b),
	.ssg0_c			(ts_ssg0_c),
	.ssg1_a			(ts_ssg1_a),
	.ssg1_b			(ts_ssg1_b),
	.ssg1_c			(ts_ssg1_c),
	
	.covox_a			(covox_a),
	.covox_b			(covox_b),
	.covox_c			(covox_c),
	.covox_d			(covox_d),
	.covox_fb		(covox_fb),
	
	.saa_l			(saa_out_l),
	.saa_r			(saa_out_r),
	
	.gs_l				(gs_out_l),
	.gs_r				(gs_out_r),
	
	.fm_l				(ts_ssg0_fm),
	.fm_r				(ts_ssg1_fm),
	.fm_ena			(ts_fm_ena),

	.adc_l			(adc_l[23:8]),
	.adc_r			(adc_r[23:8]),
	
	.opl3_l			(opl3_l),
	.opl3_r			(opl3_r),
	
	.audio_l			(audio_mix_l),
	.audio_r			(audio_mix_r)	
);

// BUS
assign bus_d = 
    (ts_enable && ~bus_rd_n) ? ts_do : // TurboSound
    (gs_oe) ? gs_do_bus : // gs
    8'bZZZZZZZZ;

// todo: other bus signals (iorqge, ...) from multisound

// vu meter
vu_meter vu_meter_l(
	.clk				(clk_bus),
	.sample_tick	(dac_bck),
	.audio_sample	(audio_mix_l),
	.leds				(led_meter_l)
);

vu_meter vu_meter_r(
	.clk				(clk_bus),
	.sample_tick	(dac_bck),
	.audio_sample	(audio_mix_r),
	.leds				(led_meter_r)
);

endmodule

