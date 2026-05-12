//============================================================================
// 
//  SAA1099 sound generator
//  Copyright (C) 2016-2019 Sorgelig
//
//  Based on SAA1099.v code from Miguel Angel Rodriguez Jodar
//  Based on SAASound code  from Dave Hooper
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================
`timescale 1ns / 1ps
`default_nettype none

module saa1099 (
	input wire          clk_sys,
	input wire          ce, // 8 MHz
	input wire          rst_n,
	input wire          cs_n,
	input wire          a0, // 0=data, 1=address
	input wire          wr_n,
	input wire [7:0]    din,
	output wire [7:0]   out_l,
	output wire [7:0]   out_r
);

reg [7:0] amplit0, amplit1, amplit2, amplit3, amplit4, amplit5;
reg [7:0] freq0, freq1, freq2, freq3, freq4, freq5;
reg [7:0] oct10, oct32, oct54;
reg [7:0] freqenable;
reg [7:0] noiseenable;
reg [7:0] noisegen;
reg [7:0] envelope0, envelope1;
reg [7:0] ctrl;

reg [4:0] addr;
wire rst = ~rst_n | ctrl[1];
reg wr, old_wr;

always @(posedge clk_sys) begin
	old_wr <= wr_n;
	wr <= 0;
	if (~rst_n) begin
		addr <= 0;
		{amplit0, amplit1, amplit2, amplit3, amplit4, amplit5} <= 0;
		{freq0, freq1, freq2, freq3, freq4, freq5} <= 0;
		{oct10, oct32, oct54} <= 0;
		{freqenable, noiseenable, noisegen} <= 0;
		{envelope0, envelope1} <= 0;
		ctrl <= 0;
	end
	else if ((!cs_n & old_wr) & !wr_n) begin
		wr <= 1;
		if (a0)
			addr <= din[4:0];
		else
			case (addr)
				'h00: amplit0 <= din;
				'h01: amplit1 <= din;
				'h02: amplit2 <= din;
				'h03: amplit3 <= din;
				'h04: amplit4 <= din;
				'h05: amplit5 <= din;

				'h08: freq0 <= din;
				'h09: freq1 <= din;
				'h0a: freq2 <= din;
				'h0b: freq3 <= din;
				'h0c: freq4 <= din;
				'h0d: freq5 <= din;

				'h10: oct10 <= din;
				'h11: oct32 <= din;
				'h12: oct54 <= din;

				'h14: freqenable <= din;
				'h15: noiseenable <= din;
				'h16: noisegen <= din;

				'h18: envelope0 <= din;
				'h19: envelope1 <= din;

				'h1c: ctrl <= din;
			endcase
	end
end

wire [21:0] out0;
saa1099_triplet top(
	.rst(rst),
	.clk_sys(clk_sys),
	.ce(ce),
	.vol({amplit0, amplit1, amplit2}),
	.env(envelope0),
	.freq({freq0, freq1, freq2}),
	.octave({oct10[2:0], oct10[6:4], oct32[2:0]}),
	.freq_en(freqenable[2:0]),
	.noise_en(noiseenable[2:0]),
	.noise_freq(noisegen[1:0]),
	.wr_addr((wr & a0) & (din[4:0] == 'h18)),
	.wr_data((wr & !a0) & (addr == 'h18)),
	.out(out0)
);

wire [21:0] out1;
saa1099_triplet bottom(
	.rst(rst),
	.clk_sys(clk_sys),
	.ce(ce),
	.vol({amplit3, amplit4, amplit5}),
	.env(envelope1),
	.freq({freq3, freq4, freq5}),
	.octave({oct32[6:4], oct54[2:0], oct54[6:4]}),
	.freq_en(freqenable[5:3]),
	.noise_en(noiseenable[5:3]),
	.noise_freq(noisegen[5:4]),
	.wr_addr((wr & a0) & (din[4:0] == 'h19)),
	.wr_data((wr & !a0) & (addr == 'h19)),
	.out(out1)
);

saa1099_output_mixer outmix_l(
	.clk_sys(clk_sys),
	.ce(ce),
	.en(ctrl[0]),
	.in0(out0[10:0]),
	.in1(out1[10:0]),
	.out(out_l)
);

saa1099_output_mixer outmix_r(
	.clk_sys(clk_sys),
	.ce(ce),
	.en(ctrl[0]),
	.in0(out0[21:11]),
	.in1(out1[21:11]),
	.out(out_r)
);
endmodule

/////////////////////////////////////////////////////////////////////////////////

module saa1099_triplet (
	input wire rst,
	input wire clk_sys,
	input wire ce,
	input wire [23:0] vol,
	input wire [7:0] env,
	input wire [23:0] freq,
	input wire [8:0] octave,
	input wire [2:0] freq_en,
	input wire [2:0] noise_en,
	input wire [1:0] noise_freq,
	input wire wr_addr,
	input wire wr_data,
	output wire [21:0] out
);

wire       tone0, tone1, tone2, noise;
wire       pulse_noise, pulse_envelope;
wire[17:0] out0, out1, out2;

saa1099_tone freq_gen0(
	.rst(rst),
	.clk_sys(clk_sys),
	.ce(ce),
	.out(tone0),
	.octave(octave[6+:3]),
	.freq(freq[16+:8]),
	.pulse(pulse_noise)
);

saa1099_tone freq_gen1(
	.rst(rst),
	.clk_sys(clk_sys),
	.ce(ce),
	.out(tone1),
	.octave(octave[3+:3]),
	.freq(freq[8+:8]),
	.pulse(pulse_envelope)
);

saa1099_tone freq_gen2(
	.rst(rst),
	.clk_sys(clk_sys),
	.ce(ce),
	.out(tone2),
	.octave(octave[0+:3]),
	.freq(freq[0+:8]),
	.pulse()
);

saa1099_noise noise_gen(
	.rst(rst),
	.clk_sys(clk_sys),
	.ce(ce),
	.pulse_noise(pulse_noise),
	.noise_freq(noise_freq),
	.out(noise)
);

saa1099_amp amp0(
	.rst(rst),
	.clk_sys(clk_sys),
	.noise(noise),
	.wr_addr(wr_addr),
	.wr_data(wr_data),
	.pulse_envelope(pulse_envelope),
	.mixmode({noise_en[0], freq_en[0]}),
	.tone(tone0),
	.envreg(0),
	.vol(vol[16+:8]),
	.out(out0)
);

saa1099_amp amp1(
	.rst(rst),
	.clk_sys(clk_sys),
	.noise(noise),
	.wr_addr(wr_addr),
	.wr_data(wr_data),
	.pulse_envelope(pulse_envelope),
	.mixmode({noise_en[1], freq_en[1]}),
	.tone(tone1),
	.envreg(0),
	.vol(vol[8+:8]),
	.out(out1)
);

saa1099_amp amp2(
	.rst(rst),
	.clk_sys(clk_sys),
	.noise(noise),
	.wr_addr(wr_addr),
	.wr_data(wr_data),
	.pulse_envelope(pulse_envelope),
	.mixmode({noise_en[2], freq_en[2]}),
	.tone(tone2),
	.envreg(env),
	.vol(vol[0+:8]),
	.out(out2)
);

assign out[10:0] = ({2'b00, out0[8:0]} + {2'b00, out1[8:0]}) + {2'b00, out2[8:0]};
assign out[21:11] = ({2'b00, out0[17:9]} + {2'b00, out1[17:9]}) + {2'b00, out2[17:9]};

endmodule

/////////////////////////////////////////////////////////////////////////////////

module saa1099_tone (
	input wire rst,
	input wire clk_sys,
	input wire ce,
	input wire [2:0] octave,
	input wire [7:0] freq,
	output reg out,
	output reg pulse
);

wire [16:0] fcount = ((17'd511 - freq) << (4'd8 - octave)) - 1'd1;
reg [16:0] count;

always @(posedge clk_sys) begin	
	pulse <= 0;
	if (rst) begin
		count <= fcount;
		out <= 0;
	end
	else if (ce) begin
		if (!count) begin
			count <= fcount;
			pulse <= 1;
			out <= ~out;
		end
		else
			count <= count - 1'd1;
	end
end

endmodule

/////////////////////////////////////////////////////////////////////////////////

module saa1099_noise (
	input wire rst,
	input wire clk_sys,
	input wire ce,
	input wire pulse_noise,
	input wire [1:0] noise_freq,
	output wire out
);

reg [16:0] lfsr = 0;
wire [16:0] new_lfsr = {(lfsr[0] ^ lfsr[2]) ^ !lfsr, lfsr[16:1]};
wire [10:0] fcount = (11'd256 << noise_freq) - 1'b1;
reg [10:0] count;

always @(posedge clk_sys) begin	
	if (rst)
		count <= fcount;
	else if (noise_freq != 3) begin
		if (ce) begin
			if (!count) begin
				count <= fcount;
				lfsr <= new_lfsr;
			end
			else
				count <= count - 1'd1;
		end
	end
	else if (pulse_noise)
		lfsr <= new_lfsr;
end
assign out = lfsr[0];

endmodule

/////////////////////////////////////////////////////////////////////////////////

module saa1099_amp (
	input wire rst,
	input wire clk_sys,
	input wire [7:0] envreg,
	input wire [1:0] mixmode,
	input wire tone,
	input wire noise,
	input wire wr_addr,
	input wire wr_data,
	input wire pulse_envelope,
	input wire [7:0] vol,
	output reg [17:0] out
);
	wire [0:7] phases = 8'h0c;
	wire [31:0] env = 32'h0588eecc;
	wire [255:0] levels = 256'h0000000000000000fffffffffffffffffedcba98765432100123456789abcdef;
	reg [2:0] shape;
	reg stereo;
	wire resolution = envreg[4];
	wire enable = envreg[7];
	reg [3:0] counter;
	reg phase;
	wire [3:0] mask = {3'b000, resolution};
	reg clock;
	reg new_data;

	always @(posedge clk_sys) begin
		if (rst | ~enable) begin
			new_data <= 0;
			stereo <= envreg[0];
			shape <= envreg[3:1];
			clock <= envreg[5];
			phase <= 0;
			counter <= 0;
		end
		else begin
			if (wr_data)
				new_data <= 1;
			if ((clock ? wr_addr : pulse_envelope)) begin // pulse from internal or external clock?
				counter <= (counter + resolution) + 1'd1;
				if ((counter | mask) == 15) begin
					if (phase >= phases[shape]) begin
						if (~shape[0])
							counter <= 15;
						if (new_data | shape[0]) begin // if we reached one of the designated points (3) or (4) and there is pending data, load it
							new_data <= 0;
							stereo <= envreg[0];
							shape <= envreg[3:1];
							clock <= envreg[5];
							phase <= 0;
							if (new_data)
								counter <= 0;
						end
					end
					else
						phase <= 1;
				end
			end
		end
	end

	wire [3:0] env_l = levels[(((3 - env[(((7 - shape) * 2) + (1 - phase)) * 2+:2]) * 16) + (15 - counter)) * 4+:4] & ~mask;
	wire [3:0] env_r = (stereo ? (4'd15 & ~mask) - env_l : env_l); // bit 0 of envreg inverts envelope shape
	reg [1:0] outmix;
	always @(*) begin
		case (mixmode)
			0: outmix <= 0;
			1: outmix <= {tone, 1'b0};
			2: outmix <= {noise, 1'b0};
			3: outmix <= {tone & ~noise, tone & noise};
		endcase
	end

	wire [8:0] vol_mix_l = {vol[3:1], vol[0] & ~enable, 5'b00000} >> outmix[0];
	wire [8:0] vol_mix_r = {vol[7:5], vol[4] & ~enable, 5'b00000} >> outmix[0];
	wire [8:0] env_out_l;
	wire [8:0] env_out_r;

	saa1099_mul_env mod_l(
		.vol(vol_mix_l[8:4]),
		.env(env_l),
		.out(env_out_l)
	);

	saa1099_mul_env mod_r(
		.vol(vol_mix_r[8:4]),
		.env(env_r),
		.out(env_out_r)
	);

	always @(*) begin
		case ({enable, outmix})
			'b100, 'b101: out = {env_out_r, env_out_l};
			'b1, 'b10: out = {vol_mix_r, vol_mix_l};
			default: out = 0;
		endcase
	end
endmodule

/////////////////////////////////////////////////////////////////////////////////

module saa1099_mul_env (
	input wire [4:0] vol,
	input wire [3:0] env,
	output wire [8:0] out
);

assign out = (((env[0] ? vol : 9'd0) + (env[1] ? {vol, 1'b0} : 9'd0)) + (env[2] ? {vol, 2'b00} : 9'd0)) + (env[3] ? {vol, 3'b000} : 9'd0);

endmodule

/////////////////////////////////////////////////////////////////////////////////

module saa1099_output_mixer (
	input wire clk_sys,
	input wire ce,
	input wire en,
	input wire [10:0] in0,
	input wire [10:0] in1,
	output reg [7:0] out
);

wire [17:0] o = 18'd91 * ({1'b0, in0} + {1'b0, in1});

// Clean the audio.
reg ced;
always @(posedge clk_sys) begin
	ced <= ce;
	if (ced)
		out <= (~en ? 8'h00 : o[17:10]);
end

endmodule

