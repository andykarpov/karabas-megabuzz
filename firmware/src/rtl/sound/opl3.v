module opl3(
	input wire clk,
	input wire ce,
	input wire en,
	input wire reset,

	input wire [15:0] bus_a,
	input wire [7:0] bus_d,
	input wire bus_rd_n,
	input wire bus_wr_n,
	input wire bus_mreq_n,
	input wire bus_iorq_n,
	input wire bus_m1_n,
	
   output wire opl3_clk,
   output wire [1:0] opl3_a,
   output wire opl3_cs_n,
   input wire [1:0] opl3_smp,
   input wire opl3_data,
   input wire opl3_dclk,
	
	output wire opl3_iorqge_n,
	
	output wire [15:0] out_l,
	output wire [15:0] out_r
);

// port access (range 0xc4 ... 0xc7)
wire port_cs = (bus_a[7:2] == 6'b110001) & en;

// ymf262-m chip select
assign opl3_cs_n = ~(bus_m1_n & ~bus_iorq_n & port_cs);

// ym address
assign opl3_a[1:0] = bus_a[1:0];

// iorqge
assign opl3_iorqge_n = bus_m1_n & port_cs;

// registers in clock domain clk
reg opl3_dclk_r, opl3_dclk_r2; 
reg opl3_data_r, opl3_data_r2;
reg [1:0] opl3_smp_r, opl3_smp_r2;
always @(posedge clk) begin
	opl3_dclk_r <= opl3_dclk;
	opl3_smp_r <= opl3_smp;
	opl3_data_r <= opl3_data;
	opl3_dclk_r2 <= opl3_dclk_r;
	opl3_smp_r2 <= opl3_smp_r;
	opl3_data_r2 <= opl3_data_r;
end

// sample ym_dclk in main clock domain
reg [1:0] ym_dclk_r = 0;
wire ym_dclk_strobe;
always @(posedge clk) begin
		ym_dclk_r <= {ym_dclk_r[0], opl3_dclk_r2};
end
assign ym_dclk_strobe = (ym_dclk_r == 2'b01) ? 1'b1 : 1'b0; // rising edge 

// convert data stream for i2s from lsb-first to msb-first
// yac512 expects offset-binary PCM @ https://yehar.com/blog/?p=665#comment-5472
// Value 0x8000 means silence 0, 0xFFFF means +32767 and 0x0000 means -32768. 
reg [1:0] prev_smp;
reg [17:0] serial;
reg [15:0] opl_l, opl_r;
reg opl_valid;
always @(posedge clk) begin
  opl_valid <= 0;
  if (ym_dclk_strobe) begin
	  prev_smp <= opl3_smp_r2;
	  serial <= {opl3_data_r2, serial[17:1]};
	  if (prev_smp[0] & ~opl3_smp_r2[0]) // latch smp0 on falling edge
		  opl_l <= {~serial[17], serial[16:2]};
	  else if (prev_smp[1] & ~opl3_smp_r2[1]) begin // latch smp1
		  opl_r <= {~serial[17], serial[16:2]};
		  opl_valid <= 1;
	  end
  end
end

// assign clock
// todo: OODR2
assign opl3_clk = ce;

// resample + interpolation
opl3_resample opl3_resample_l(.clk(clk), .reset(reset), .valid_in(opl_valid), .data_in(opl_l), .data_out(out_l));
opl3_resample opl3_resample_r(.clk(clk), .reset(reset), .valid_in(opl_valid), .data_in(opl_r), .data_out(out_r));

endmodule
