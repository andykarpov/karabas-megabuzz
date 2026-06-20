module zc_divmmc(
    input wire clk,
	 input wire clk_mem,
    input wire reset,
	 input wire areset,
    input wire divmmc_en,

    input wire [15:0] bus_a,
    input wire [7:0] bus_d,
    input wire bus_iorq_n,
    input wire bus_mreq_n,
    input wire bus_m1_n,
    input wire bus_wr_n,
    input wire bus_rd_n,
	 inout wire bus_nmi_n,
    input wire btn_nmi_n,

    output wire sd_clk,
    inout wire sd_do,
    inout wire sd_di,
    output wire sd_cs_n,
	 
    output wire [7:0] dout,
	 output wire divmmc_mem,
	 output wire [7:0] divmmc_dout,
	 output wire divmmc_zxrom_block,
    output wire busy
);

// SPI Z-Controller + DivMMC
wire zc_spi_start = (((bus_a[7:0] == 8'h57) | (divmmc_en & (bus_a[7:0] == 8'hEB))) & ~bus_iorq_n & bus_m1_n) ? 1 : 0;
wire zc_wr_en = (zc_spi_start & ~bus_wr_n) ? 1 : 0;
wire zc_rd_en = (zc_spi_start & ~bus_rd_n) ? 1 : 0;
wire port77_wr = (((bus_a[7:0] == 8'h77) | (divmmc_en & (bus_a[7:0] == 8'hE7))) & ~bus_iorq_n & ~bus_wr_n & bus_m1_n) ? 1 : 0;

reg zc_cs_n;
always @(posedge clk_mem or posedge reset) begin
    if (reset) 
        zc_cs_n <= 1;
    else if (port77_wr) begin
        if (bus_a[7:0] == 8'hE7)
            zc_cs_n <= bus_d[0]; // divmmc uses bit0
        else
            zc_cs_n <= bus_d[1]; // zc uses bit1
    end
end

reg [3:0] zc_cnt;
always @(posedge clk_mem)
	if (zc_cnt >= 5)
		zc_cnt <= 0;
	else
		zc_cnt <= zc_cnt + 1;
wire zc_ena = (zc_cnt == 4'b0000);

wire zc_sclk, zc_mosi;
wire [7:0] zc_do_bus;
zc_spi zc_spi(
    .clk_sys(clk_mem),
    .ena(zc_ena),
    .tx(zc_wr_en),
    .rx(zc_rd_en),
    .din(bus_d),
    .dout(zc_do_bus),
    .spi_clk(zc_sclk),
    .spi_di(sd_do),
    .spi_do(zc_mosi),
    .spi_wait(busy)
);

assign sd_cs_n	= zc_cs_n;
assign sd_clk 	= zc_sclk;
assign sd_di 	= zc_mosi;

// ------------------------ divmmc-----------------------------
// Engineer:   Mario Prato
// 11.07.2013:OCH: adapted by me
// i take this implementation to correctly and easy make nmi 

reg mapterm, map3DXX, map1F00;
always @(*)
begin
    if (areset | ~divmmc_en) begin 
        mapterm <= 0;
        map3DXX <= 0;
        map1F00 <= 1;
    end
    else begin
         if ((bus_a == 16'h0000) | 
             (bus_a == 16'h0008) | 
             (bus_a == 16'h0038) | 
             (bus_a == 16'h0066) | 
             (bus_a == 16'h04c6) | 
             (bus_a == 16'h0562)) 
            mapterm <= 1;
        else 
            mapterm <= 0;

        // mappa 3D00 - 3DFF
        if (bus_a[15:8] == 8'b00111101) 
            map3DXX <= 1; 
        else 
            map3DXX <= 0;

        // 1ff8 - 1fff
        if (bus_a[15:3] == 13'b0001111111111) 
            map1F00 <= 0;
        else 
            map1F00 <= 1;
    end
end

reg mapcond, automap;
always @(posedge areset or negedge bus_mreq_n) begin
    if (areset | ~divmmc_en) begin
        mapcond <= 0;
        automap <= 0;
    end 
    else begin
        if (~bus_m1_n) begin
            mapcond <= (mapterm | map3DXX | (mapcond & map1F00)) & divmmc_en;
            automap <= (mapcond | map3DXX) & divmmc_en;
        end
    end
end

reg [7:0] port_e3_reg;
wire conmem = port_e3_reg[7];
wire divideio = (~bus_iorq_n & ~bus_wr_n & bus_m1_n & (bus_a[7:0] == 8'hE3) & divmmc_en) ? 0 : 1;
always @(posedge areset or posedge divideio) begin
    if (areset) begin // poweron
        port_e3_reg[5:0] <= 6'b00000000;
		  port_e3_reg[7] <= 0;
    end else
		port_e3_reg <= {bus_d[7], port_e3_reg[6] | bus_d[6], bus_d[5:0]};
end

// nmi signal
assign bus_nmi_n = (~btn_nmi_n & divmmc_en & ~mapcond) ? 1'b0 : 
                   (~btn_nmi_n & ~divmmc_en & ~bus_m1_n & ~bus_mreq_n & (bus_a[15:14] != 2'b00)) ? 1'b0 : 1'bz;

// divmmc ram / rom, zx rom

wire is_rom_divmmc = (divmmc_en & ~bus_mreq_n & (automap | conmem) & (bus_a[15:13] == 3'b000)) ? 1 : 0;
wire is_ram_divmmc = (divmmc_en & ~bus_mreq_n & (automap | conmem) & (bus_a[15:13] == 3'b001)) ? 1 : 0;
wire is_rom = (divmmc_en & ~bus_mreq_n & (bus_a[15:14] == 2'b00)) ? 1 : 0;

wire [7:0] rom_do;
sprom #(.ADDRWIDTH(13), .MEM_INIT_FILE("esxdos.mem")) esxdos_rom(.clock(clk_mem), .address(bus_a[12:0]), .q(rom_do));

//wire [7:0] zxrom_do;
//sprom #(.ADDRWIDTH(14), .MEM_INIT_FILE("1982.mem")) zx_rom(.clock(clk_mem), .address(bus_a[13:0]), .q(zxrom_do));

wire [7:0] ram_do;
spram #(.ADDRWIDTH(16)) esxdos_ram(.clock(clk_mem), .address({port_e3_reg[2:0], bus_a[12:0]}), .data(bus_d), .wren(is_ram_divmmc & ~bus_wr_n), .q(ram_do));

//assign divmmc_mem = (is_rom_divmmc | is_ram_divmmc | is_rom) ? 1 : 0;
assign divmmc_mem = (is_rom_divmmc | is_ram_divmmc) ? 1 : 0;
assign divmmc_dout = (is_ram_divmmc) ? ram_do : 
							(is_rom_divmmc) ? rom_do : 
							divmmc_dout;
							//zxrom_do;

//assign divmmc_zxrom_block = divmmc_en & (is_rom | automap | conmem);
assign divmmc_zxrom_block = divmmc_en & (automap | conmem);
assign dout = (bus_a[7:0] == 8'h77) ? {~busy, 7'b1111100} : zc_do_bus;

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////

module zc_spi
(
    input wire        clk_sys,
    input wire        ena,

    input wire        tx,        // Byte ready to be transmitted
    input wire        rx,        // request to read one byte
    input wire  [7:0] din,
    output wire [7:0] dout,

    output wire       spi_clk,
    input wire        spi_di,
    output wire       spi_do,
    output reg        spi_wait
);

assign    spi_clk = counter[0];
assign    spi_do  = io_byte[7]; // data is shifted up during transfer
assign    dout    = data;

reg [4:0] counter = 5'b10000;  // tx/rx counter is idle
reg [7:0] io_byte, data;
reg tx_stb, rx_stb;
reg prev_tx, prev_rx;
reg spi_clk_stb, prev_spi_clk;

// tx/rx/spi_clk strobes
always @(posedge clk_sys) begin
    tx_stb <= 1'b0;
    rx_stb <= 1'b0;
    spi_clk_stb <= 1'b0;
    if (~prev_tx && tx) tx_stb <= 1'b1;
    if (~prev_rx && rx) rx_stb <= 1'b1;
    if (~prev_spi_clk && spi_clk) spi_clk_stb <= 1'b1;
    prev_tx <= tx;
    prev_rx <= rx;    
    prev_spi_clk <= spi_clk;
end

// shift register
always @(negedge clk_sys) begin
     if(counter[4]) begin
        spi_wait <= 1'b0;
          if(rx_stb | tx_stb) begin
                counter <= 0;
                data <= io_byte;
                io_byte <= tx_stb ? din : 8'hff;
          end
     end 
     else begin
        if (counter >= 4) spi_wait <= 1'b1; // wait cycle with a small delay
        if (ena) begin
            if(spi_clk) io_byte <= { io_byte[6:0], spi_di };
            counter <= counter + 2'd1;
        end 
     end
end

endmodule

