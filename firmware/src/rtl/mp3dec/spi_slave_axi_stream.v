module spi_slave_axi_stream (
    // Системные сигналы
    input  wire        clk,       // Системный тактовый сигнал SoC (100 МГц)
    input  wire        rstn,      // Активный низкий сброс

    // Интерфейс SPI (VS1053 SDI)
    input  wire        spi_sclk,  // Тактовая частота от внешнего хоста
    input  wire        spi_mosi,  // Данные от хоста
    input  wire        spi_xdcs,  // Выбор чипа данных (активный низкий)

    // Интерфейс AXI4-Stream (к NEORV32 SLINK RX)
    output reg  [31:0] tdata,     // NEORV32 SLINK принимает 32 бита (младшие 8 под байт)
    output reg         tvalid,    // Флаг готовности байта для процессора
    input  wire        tready     // Сигнал от NEORV32, что он готов принять данные
);

    // Синхронизация асинхронных сигналов SPI на системную частоту 100 МГц
    reg [2:0] sclk_sync;
    reg [1:0] mosi_sync;
    reg [1:0] xdcs_sync;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sclk_sync <= 3'b0;
            mosi_sync <= 2'b0;
            xdcs_sync <= 2'b11;
        end else begin
            sclk_sync <= {sclk_sync[1:0], spi_sclk};
            mosi_sync <= {mosi_sync[0],   spi_mosi};
            xdcs_sync <= {xdcs_sync[0],   spi_xdcs};
        end
    end

    // Детекторы фронтов для синхронизированных линий
    wire sclk_posedge = (sclk_sync[1] && !sclk_sync[2]); // Рост SCLK (захват SPI)
    wire xdcs_active  = !xdcs_sync[1];                   // CS активен (low)

    // Внутренний сдвиговый регистр и счетчик бит
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg       byte_done;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            shift_reg <= 8'h0;
            bit_cnt   <= 3'd0;
            byte_done <= 1'b0;
        end else if (!xdcs_active) begin
            bit_cnt   <= 3'd0;
            byte_done <= 1'b0;
        end else begin
            byte_done <= 1'b0; // Импульс на один такт clk
            
            if (sclk_posedge) begin
                shift_reg <= {shift_reg[6:0], mosi_sync[1]};
                bit_cnt   <= bit_cnt + 1'b1;
                
                if (bit_cnt == 3'd7) begin
                    byte_done <= 1'b1;
                end
            end
        end
    end

    // Очередь (Buffer) для передачи в AXI4-Stream
    reg [7:0] fifo_data;
    reg       fifo_full;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_data <= 8'h0;
            fifo_full <= 1'b0;
            tdata     <= 32'h0;
            tvalid    <= 1'b0;
        end else begin
            // Запись принятого байта в буфер
            if (byte_done) begin
                fifo_data <= shift_reg;
                fifo_full <= 1'b1;
            end

            // Логика рукопожатия AXI4-Stream (Handshake)
            if (fifo_full && !tvalid) begin
                tdata  <= {24'h0, fifo_data}; // Расширяем до 32 бит для NEORV32
                tvalid <= 1'b1;
                fifo_full <= 1'b0;
            end

            if (tvalid && tready) begin
                tvalid <= 1'b0;
            end
        end
    end

endmodule

