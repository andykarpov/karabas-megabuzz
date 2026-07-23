/**
 * VS1053 pseudo-parallel interface
 *
 * Status register (bus_addr=0), read (bus_we_n = 1):
 * - Bit [6:0] — count of 32-bytes items in the FIFO (0-127).
 * - Bit 7 — FIFO overflow flag (fifo_full).
 * Status register (bus_addr=0), write (bus_we_n = 0):
 * - Bit 7 — 1 soft reset for VS1053.
 */
module vs1053 (
    input  wire        clk,
    input  wire        rst_n,

    // vs1053 pins
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    input  wire        dreq,
    output wire        xreset,
    output wire        xdcs,
    output wire        xcs,

    // parallel bus
    input  wire        bus_cs_n,
    input  wire        bus_we_n,
    input  wire        bus_addr,     // 0: status, 1: data
    input  wire [7:0]  bus_din,
    output reg  [7:0]  bus_dout
);

wire [11:0] fifo_count;
wire [7:0] fifo_rdata;
wire fifo_rd_en;
wire soft_reset;
vs1053_host_interface vs1053_host_interface(
    .clk(clk),
    .rst_n(rst_n),
    .bus_cs_n(bus_cs_n),
    .bus_we_n(bus_we_n),
    .bus_addr(bus_addr),
    .bus_din(bus_din),
    .bus_dout(bus_dout),
    .soft_reset(soft_reset),
    .fifo_count(fifo_count),
    .fifo_rd_en(fifo_rd_en),
    .fifo_rdata(fifo_rdata)
);

wire speed_sel;
wire [7:0] tx_data;
wire start;
wire busy;
vs1053_spi_master vs1053_spi_master(
    .clk(clk),
    .rst_n(rst_n),
    .speed_sel(speed_sel),

    .tx_data(tx_data),
    .start(start),
    .busy(busy),

    .spi_sclk(spi_sclk),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
);

vs1053_controller vs1053_controller(
    .clk(clk),
    .rst_n(rst_n),
    .soft_reset(soft_reset),

    .vs_dreq(dreq),
    .vs_xreset(xreset),
    .vs_xdcs(xdcs),
    .cs_xcs(xcs),

    .spi_tx_data(tx_data),
    .spi_start(start),
    .spi_busy(busy),
    .spi_speed(speed),

    .fifo_count(fifo_count),
    .fifo_rd_en(fifo_rd_en),
    .fifo_rdata(fifo_rdata)
);

endmodule

// ------------------------------------------------------------

module vs1053_host_interface (
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire        bus_cs_n,
    input  wire        bus_we_n,
    input  wire        bus_addr,
    input  wire [7:0]  bus_din,
    output reg  [7:0]  bus_dout,
    
    output reg         soft_reset,

    output wire [11:0] fifo_count,
    input  wire        fifo_rd_en,
    output wire [7:0]  fifo_rdata
);

    reg        fifo_wr_en;
    reg [7:0]  fifo_wdata;
    wire       fifo_full, fifo_empty, fifo_clear;

    assign fifo_clear = !rst_n || soft_reset;

    reg prev_cs_n;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_dout   <= 8'h00;
            fifo_wr_en <= 1'b0;
            fifo_wdata <= 8'h00;
            soft_reset <= 1'b0;
            prev_cs_n  <= 1'b1;
        end else begin
            fifo_wr_en <= 1'b0;
            soft_reset <= 1'b0;
            prev_cs_n <= bus_cs_n;

            if (!bus_cs_n & prev_cs_n) begin
                if (!bus_we_n) begin // write
                    if (bus_addr == 1'b1) begin // data
                        if (!fifo_full) begin
                            fifo_wr_en <= 1'b1;
                            fifo_wdata <= bus_din;
                        end
                    end else begin // status
                        if (bus_din[7] == 1'b1) begin
                            soft_reset <= 1'b1;
                        end
                    end
                end else begin // read
                    if (bus_addr == 1'b0) begin
                        bus_dout <= {fifo_full, fifo_count[11:5]};
                    end else begin
                        bus_dout <= 8'hFF;
                    end
                end
            end
        end
    end

    // 4kB FIFO
    fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(12)) fifo(
        .clk(clk),
        .reset(fifo_clear),
        .rd(fifo_rd_en),
        .wr(fifo_wr_en),
        .din(fifo_wdata),
        .dout(fifo_rdata),
        .full(fifo_full),
        .empty(fifo_empty),
        .data_count(fifo_count)
    );

endmodule

// ------------------------------------------------------------

module vs1053_spi_master (
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire        speed_sel,   // 0: slow (commands), 1: fast (data)
    
    input  wire [7:0]  tx_data,
    input  wire        start,
    output reg         busy,
    
    output reg         spi_sclk,
    output reg         spi_mosi,
    input  wire        spi_miso
);

    reg [7:0]  shifter;
    reg [3:0]  bit_cnt;
    reg [7:0]  clk_div;
    reg        sclk_edge;
    
    wire [7:0] max_div = speed_sel ? 8'd7 : 8'd28; // clk = 28MHz: 1=2.0MHz, 0=500kHz

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div   <= 0;
            sclk_edge <= 0;
        end else if (busy) begin
            if (clk_div >= max_div) begin
                clk_div   <= 0;
                sclk_edge <= 1'b1;
            end else begin
                clk_div   <= clk_div + 1'b1;
                sclk_edge <= 1'b0;
            end
        end else begin
            clk_div   <= 0;
            sclk_edge <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 0;
            spi_sclk <= 0;
            spi_mosi <= 0;
            bit_cnt  <= 0;
            shifter  <= 0;
        end else begin
            if (start && !busy) begin
                shifter  <= tx_data;
                busy     <= 1'b1;
                bit_cnt  <= 0;
                spi_sclk <= 0;
                spi_mosi <= tx_data[7]; // MSB
            end else if (busy && sclk_edge) begin
                if (spi_sclk == 1'b0) begin
                    spi_sclk <= 1'b1; // rising edge: VS1053 reading data
                end else begin
                    spi_sclk <= 1'b0; // falling edge: shift data
                    shifter  <= {shifter[6:0], 1'b0};
                    bit_cnt  <= bit_cnt + 1'b1;
                    
                    if (bit_cnt == 3'd7) begin
                        busy <= 1'b0; // transaction end
                    end else begin
                        spi_mosi <= shifter[6]; // next bit
                    end
                end
            end
        end
    end
endmodule

// ------------------------------------------------------------

module vs1053_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        soft_reset,
    
    input  wire        vs_dreq,
    output reg         vs_xreset,
    output reg         vs_xdcs,
    output reg         vs_xcs,
    
    output reg  [7:0]  spi_tx_data,
    output reg         spi_start,
    input  wire        spi_busy,
    output reg         spi_speed,
    
    input  wire [11:0] fifo_count,
    output reg         fifo_rd_en,
    input  wire [7:0]  fifo_rdata
);

    // FSM state
    localparam ST_RESET      = 0,
               ST_WAIT_DREQ1 = 1,
               ST_WRITE_CLK  = 2,
               ST_WRITE_MODE = 3,
               ST_WAIT_DREQ2 = 4,
               ST_IDLE       = 5,
               ST_FIFO_READ  = 6,
               ST_SPI_START  = 7,
               ST_SPI_WAIT   = 8;

    reg [3:0] state;
    reg [23:0] rst_timer;
    reg [5:0]  byte_cnt;
    reg [1:0]  cmd_step;

    // VS1053 regs init table [Write mode SCI (8 bit) + Addr (8 bit) + Data (16 bit)]
    // Bytes order to send SCI commands: 0x02 (write), Addr, MSB data, LSB data.
    reg [7:0] cmd_bytes[0:7];
    initial begin
        // Cmd 1: Write SCI_CLOCKF (Addr 0x03) value 0x8800 (XTALI x 3.5)
        cmd_bytes[0] = 8'h02; cmd_bytes[1] = 8'h03; cmd_bytes[2] = 8'h88; cmd_bytes[3] = 8'h00;
        // Cmd 2: Write SCI_MODE (Addr 0x00) value 0x0820 (SM_SDINEW = 1)
        cmd_bytes[4] = 8'h02; cmd_bytes[5] = 8'h00; cmd_bytes[6] = 8'h08; cmd_bytes[7] = 8'h20;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_RESET;
            rst_timer    <= 0;
            byte_cnt     <= 0;
            cmd_step     <= 0;
            vs_xreset    <= 1'b0;
            vs_xcs       <= 1'b1;
            vs_xdcs      <= 1'b1;
            spi_start    <= 1'b0;
            spi_tx_data  <= 8'h00;
            spi_speed    <= 1'b0;
            fifo_rd_en   <= 1'b0;
        end else if (soft_reset) begin
            state        <= ST_RESET;
            rst_timer    <= 0;
            byte_cnt     <= 0;
            cmd_step     <= 0;
            vs_xreset    <= 1'b0;
            vs_xcs       <= 1'b1;
            vs_xdcs      <= 1'b1;
            spi_start    <= 1'b0;
            spi_speed    <= 1'b0;
            fifo_rd_en   <= 1'b0;
        end else begin
            spi_start  <= 1'b0;
            fifo_rd_en <= 1'b0;
            
            case (state)
                ST_RESET: begin
                    vs_xreset <= 1'b0;
                    if (rst_timer < 24'h0FFFFF) begin // keep reset
                        rst_timer <= rst_timer + 1'b1;
                    end else begin
                        vs_xreset <= 1'b1;
                        state     <= ST_WAIT_DREQ1;
                    end
                end

                ST_WAIT_DREQ1: begin
                    if (vs_dreq) begin
                        state    <= ST_WRITE_CLK;
                        cmd_step <= 0;
                        vs_xcs   <= 1'b0;
                    end
                end

                ST_WRITE_CLK: begin
                    if (!spi_busy && !spi_start) begin
                        spi_tx_data <= cmd_bytes[cmd_step];
                        spi_start   <= 1'b1;
                        cmd_step    <= cmd_step + 1'b1;
                        if (cmd_step == 2'd3) begin
                            state <= ST_WRITE_MODE;
                        end
                    end
                end

                ST_WRITE_MODE: begin
                    if (!spi_busy && !spi_start) begin
                        vs_xcs      <= 1'b0;
                        spi_tx_data <= cmd_bytes[4 + cmd_step[1:0]];
                        spi_start   <= 1'b1;
                        cmd_step    <= cmd_step + 1'b1;
                        if (cmd_step == 2'd3) begin
                            state <= ST_WAIT_DREQ2;
                        end
                    end
                end

                ST_WAIT_DREQ2: begin
                    if (!spi_busy) begin
                        vs_xcs <= 1'b1;
                        if (vs_dreq) begin
                            spi_speed <= 1'b1;
                            state     <= ST_IDLE;
                        end
                    end
                end

                ST_IDLE: begin
                    vs_xdcs  <= 1'b1;
                    byte_cnt <= 0;
                    // waiting for DREQ=1 and 32 bytes in the fifo
                    if (vs_dreq && (fifo_count >= 9'd32)) begin
                        fifo_rd_en <= 1'b1; // read ahead of the first byte from the fifo
                        state      <= ST_FIFO_READ;
                    end
                end

                ST_FIFO_READ: begin
                    vs_xdcs <= 1'b0;
                    state   <= ST_SPI_START;
                end

                ST_SPI_START: begin
                    spi_tx_data <= fifo_rdata;
                    spi_start   <= 1'b1;
                    byte_cnt    <= byte_cnt + 1'b1;
                    state       <= ST_SPI_WAIT;
                end

                ST_SPI_WAIT: begin
                    if (!spi_busy) begin
                        if (byte_cnt < 6'd32) begin
                            fifo_rd_en <= 1'b1; // fetch next byte from the fifo
                            state      <= ST_FIFO_READ;
                        end else begin
                            vs_xdcs <= 1'b1;
                            state   <= ST_IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule


