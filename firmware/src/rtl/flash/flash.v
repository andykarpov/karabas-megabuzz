//-----------------------------------------------------------------[25.07.2019]
// SPI flash parallel interface
//
// Copyright (c) 2020 Andy Karpov <andy.karpov@gmail.com>
//
// Datasheets:
// 	https://www.winbond.com/resource-files/w25q16dv_revi_nov1714_web.pdf
//  https://www.micron.com/-/media/client/global/documents/products/data-sheet/nor-flash/serial-nor/m25p/m25p16.pdf
//	https://www.digikey.com/eewiki/pages/viewpage.action?pageId=4096096
//-----------------------------------------------------------------------------

module flash(
    input wire          CLK,
    input wire          RESET,

    input wire [23:0]   A,
    input wire [7:0]    DI,
    output reg [7:0]    DO,
    input wire          WR_N,
    input wire          RD_N,
    input wire          ER_N,

    input wire          DATA0,
    output wire         NCSO,
    output wire         DCLK,
    output wire         ASDO,

    output wire         BUSY,
    output wire         DATA_READY
);

    localparam [7:0] SPI_CMD_SETSTATUS=8'h01;
    localparam [7:0] SPI_CMD_PAGEPRG=8'h02;
    localparam [7:0] SPI_CMD_READ=8'h03;
    localparam [7:0] SPI_CMD_WRITE_DIS=8'h04;
    localparam [7:0] SPI_CMD_STATUSREG=8'h05;
    localparam [7:0] SPI_CMD_WRITE_EN=8'h06;
    localparam [7:0] SPI_CMD_BLOCK_ERASE=8'hD8;
    localparam [7:0] SPI_CMD_POWERON=8'hAB;

    localparam [3:0]
      init = 0,
      idle = 1,
      cmd_read = 2,
      cmd_wp_off = 3,
      cmd_write_en = 4,
      cmd_erase_block = 5,
      cmd_write = 6,
      cmd_check_status = 7,
      cmd_write_dis = 8,
      cmd_wp_on = 9;

    // SPI
    reg [7:0] spi_di_bus;
    wire [7:0] spi_do_bus;
    wire spi_busy;
    reg spi_busy_prev;
    reg spi_ena;
    reg spi_cont;
    wire spi_si;
    wire spi_so;
    wire spi_clk;
    wire [0:0] spi_ss_n;
    reg prev_rd_n;
    reg prev_wr_n;
    reg prev_er_n;

    reg [3:0] state = init;  // current state
    reg [3:0] next_state = init;  // state to return after some operations
    reg is_busy = 1;
    reg is_ready = 0;
    wire nreset = 1;
    reg [7:0] count = 0;

    assign nreset =  ~RESET;
    assign NCSO = spi_ss_n[0];
    assign spi_so = DATA0;
    assign ASDO = spi_si;
    assign DCLK = spi_clk;
    assign BUSY = is_busy;
    assign DATA_READY = is_ready;

    // SPI FLASH 25MHz 
    spi_master #(.slaves(1), .d_width(8)) spi_master(
        .clock(CLK),
        .reset_n(nreset),
        .enable(spi_ena),
        .cpol(0),
        .cpha(0),
        .cont(spi_cont),
        .clk_div(1),
        .addr(0),
        .tx_data(spi_di_bus),
        .miso(spi_so),
        .sclk(spi_clk),
        .ss_n(spi_ss_n),
        .mosi(spi_si),
        .busy(spi_busy),
        .rx_data(spi_do_bus)
    );

  //-----------------------------------------------------------------------------
  // flash read / write state machine
  always @(posedge RESET, posedge CLK) begin
    if(RESET) begin
      spi_ena <= 0;
      spi_cont <= 0;
      spi_di_bus <= 8'h00;
      count <= 0;
      state <= init;
      is_busy <= 1;
      is_ready <= 0;
    end else begin
      case(state)

          init : begin // power on command            
            spi_busy_prev <= spi_busy;
            if (spi_busy_prev & ~spi_busy) count <= count + 1;
            case(count)
                0 : begin spi_ena <= 1; spi_di_bus <= SPI_CMD_POWERON; end
                1 : spi_ena <= 0;
                2 : begin count <= 0; state <= idle; end
            endcase
          end

          idle : begin // ready to begin read / write cycle
            is_busy <= 0;
            spi_ena <= 0;
            spi_cont <= 0;
            count <= 0;
            spi_busy_prev <= 0;
            prev_wr_n <= WR_N;
            prev_rd_n <= RD_N;
            prev_er_n <= ER_N;
            if(~RD_N) state <= cmd_read;
            else if( ~WR_N & prev_wr_n) begin
              state <= cmd_write_en;
              next_state <= cmd_write;
            end
            else if(~ER_N & prev_er_n) begin
              state <= cmd_write_en;
              next_state <= cmd_erase_block;
            end
          end

          cmd_read : begin // read command
            is_busy <= 1;
            spi_busy_prev <= spi_busy;
            if(spi_busy_prev & ~spi_busy) count <= count + 1;
            case(count)
                0 : begin
                  if (~spi_busy) begin
                    spi_cont <= 1;
                    spi_ena <= 1;
                    is_ready <= 0;
                    spi_di_bus <= SPI_CMD_READ;
                  end
                  else begin
                    spi_di_bus <= A[23:16];
                  end
                end
                1 : spi_di_bus <= A[15:8];
                2 : spi_di_bus <= A[7:0];
                3 : spi_di_bus <= 8'h00;
                4 : begin
                  spi_cont <= 0;
                  spi_ena <= 0;
                end
                5 : begin
                  count <= 0;
                  is_ready <= 1;
                  DO <= spi_do_bus;
                  state <= idle;
                end
            endcase
          end

          cmd_write_en : begin // write enable
            is_busy <= 1;
            is_ready <= 0;
            spi_busy_prev <= spi_busy;
            if (spi_busy_prev & ~spi_busy) count <= count + 1;
            case(count)
                0 : begin
                  spi_ena <= 1;
                  spi_cont <= 0;
                  spi_di_bus <= SPI_CMD_WRITE_EN;
                end
                1 : spi_ena <= 1'b0;
                2 : begin
                  count <= 0;
                  state <= next_state;
                end
            endcase
          end

          cmd_erase_block : begin // erase 64k block command
            spi_busy_prev <= spi_busy;
            if(spi_busy_prev & ~spi_busy) count <= count + 1;
            case(count)
                0 : begin
                  if(~spi_busy) begin
                    spi_cont <= 1;
                    spi_ena <= 1;
                    spi_di_bus <= SPI_CMD_BLOCK_ERASE;
                  end
                  else spi_di_bus <= A[23:16];
                end
                1 : spi_di_bus <= A[15:8];
                2 : spi_di_bus <= A[7:0];
                3 : begin
                  spi_cont <= 0;
                  spi_ena <= 0;
                end
                4 : begin
                  count <= 0;
                  state <= cmd_check_status;
                  next_state <= cmd_write_dis;
                end
            endcase
          end

          cmd_write : begin // write command
            spi_busy_prev <= spi_busy;
            if(spi_busy_prev & ~spi_busy) begin
              count <= count + 1;
            end
            case(count)
                0 : begin
                  if(~spi_busy) begin
                    spi_cont <= 1;
                    spi_ena <= 1;
                    spi_di_bus <= SPI_CMD_PAGEPRG;
                  end
                  else spi_di_bus <= A[23:16];
                end
                1 : spi_di_bus <= A[15:8];
                2 : spi_di_bus <= A[7:0];
                3 : spi_di_bus <= DI;
                4 : begin
                  spi_cont <= 1'b0;
                  spi_ena <= 1'b0;
                end
                5 : begin
                  count <= 0;
                  state <= cmd_check_status;
                  next_state <= cmd_write_dis;
                end
            endcase
          end

          cmd_check_status : begin // check status (after write or erase)
            spi_busy_prev <= spi_busy;
            if(spi_busy_prev & ~spi_busy) count <= count + 1;
            case(count)
                0 : begin
                  if(~spi_busy) begin
                    spi_cont <= 1;
                    spi_ena <= 1;
                    is_ready <= 0;
                    spi_di_bus <= SPI_CMD_STATUSREG;
                  end
                  else spi_di_bus <= 8'h00;
                end
                1 : begin
                  spi_cont <= 0;
                  spi_ena <= 0;
                end
                2 : begin
                  count <= 0;
                  if(spi_do_bus[0]) state <= cmd_check_status;
                  else state <= next_state;
                end
            endcase
          end

          cmd_write_dis : begin // write disable
            spi_busy_prev <= spi_busy;
            if(spi_busy_prev & ~spi_busy) count <= count + 1;
            case(count)
                0 : begin
                  spi_ena <= 1'b1;
                  spi_cont <= 1'b0;
                  spi_di_bus <= SPI_CMD_WRITE_DIS;
                end
                1 : spi_ena <= 1'b0;
                2 : begin
                  count <= 0;
                  state <= idle;
                end
            endcase
          end
      endcase
    end
  end

endmodule
