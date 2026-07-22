/**
 * VS1053 pseudo-parallel interface
 *
 * Статус регистр (bus_addr=0), чтение (bus_we_n = 1):
 * - Bit [6:0] — количество байт в FIFO.
 * - Bit 7 — флаг переполнения FIFO (fifo_full).
 * Статус регистр (bus_addr=0), запись (bus_we_n = 1):
 * - Bit 7 — 1 запускает процедуру полного аппаратного и программного рестарта VS1053. 
 *   Остальные биты игнорируются.
 */
module vs1053 (
    input  wire        clk,
    input  wire        rst_n,

    // физический интерфейс с vs1053
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    input  wire        dreq,
    output wire        xreset,
    output wire        xdcs,
    output wire        xcs,

    // параллельная шина
    input  wire        bus_cs_n,
    input  wire        bus_we_n,
    input  wire        bus_addr,     // 0: Статус, 1: Данные
    input  wire [7:0]  bus_din,
    output reg  [7:0]  bus_dout
);

wire [8:0] fifo_count;
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
    
    // Кастомная параллельная шина
    input  wire        bus_cs_n,
    input  wire        bus_we_n,
    input  wire        bus_addr,     // 0: Статус, 1: Данные
    input  wire [7:0]  bus_din,
    output reg  [7:0]  bus_dout,
    
    // Сигнал программного сброса для автомата управления
    output reg         soft_reset,

    // Интерфейс к контроллеру VS1053
    output wire [8:0]  fifo_count,
    input  wire        fifo_rd_en,
    output wire [7:0]  fifo_rdata
);

    reg        fifo_wr_en;
    reg [7:0]  fifo_wdata;
    wire       fifo_full;
    wire       fifo_empty;
    wire       fifo_clear;

    // Логика записи и чтения по параллельной шине
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_dout   <= 8'h00;
            fifo_wr_en <= 1'b0;
            fifo_wdata <= 8'h00;
            soft_reset <= 1'b0;
        end else begin
            fifo_wr_en <= 1'b0; // Импульс на один такт
            soft_reset <= 1'b0;

            // TODO: чтобы исключить повторный захват данных, 
            // нужно ловить фронт - ввести регистры prev_cs_n, prev_we_n

            if (!bus_cs_n) begin
                if (!bus_we_n) begin
                    // Цикл ЗАПИСИ
                    if (bus_addr == 1'b1) begin // Запись в регистр данных
                        if (!fifo_full) begin
                            fifo_wr_en <= 1'b1;
                            fifo_wdata <= bus_din;
                        end
                    end else begin // Запись в регистр статуса
                        if (bus_din[7] == 1'b1) begin
                            soft_reset <= 1'b1; // Инициируем сброс подсистемы VS1053
                        end
                    end
                end else begin
                    // Цикл ЧТЕНИЯ
                    if (bus_addr == 1'b0) begin
                        // Регистр статуса: возвращает кол-во байт в FIFO
                        // Если FIFO заполнено, верхний бит покажет статус full
                        bus_dout <= {fifo_full, fifo_count[6:0]}; 
                    end else begin
                        bus_dout <= 8'hFF; // Регистр данных не предназначен для чтения
                    end
                end
            end
        end
    end

    // Простая программная модель FIFO (TODO: заменить на модуль fifo, размер увеличить до >=2кБ)
    // Размер: 128 байт (достаточно для демонстрации, fifo_count = 8 бит)
    reg [7:0]  storage [0:127];
    reg [6:0]  wr_ptr;
    reg [6:0]  rd_ptr;
    reg [7:0]  count;

    assign fifo_count = count;
    assign fifo_full  = (count == 8'd128);
    assign fifo_empty = (count == 8'd0);
    assign fifo_rdata = storage[rd_ptr];
    assign fifo_clear = !rst_n || soft_reset;

    always @(posedge clk or posedge fifo_clear) begin
        if (fifo_clear) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            if (fifo_wr_en && !fifo_full) begin
                storage[wr_ptr] <= fifo_wdata;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (fifo_rd_en && !fifo_empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            
            case ({fifo_wr_en && !fifo_full, fifo_rd_en && !fifo_empty})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

// ------------------------------------------------------------

module vs1053_spi_master (
    input  wire        clk,
    input  wire        rst_n,
    
    // Управление скоростью
    input  wire        speed_sel,   // 0: Медленно (команды), 1: Быстро (данные)
    
    // Внутренний интерфейс управления
    input  wire [7:0]  tx_data,
    input  wire        start,
    output reg         busy,
    
    // Физические пины SPI к VS1053
    output reg         spi_sclk,
    output reg         spi_mosi,
    input  wire        spi_miso     // Не используется для SDI, но нужен для SCI
);

    reg [7:0]  shifter;
    reg [3:0]  bit_cnt;
    reg [7:0]  clk_div;
    reg        sclk_edge;
    
    // Генератор гибкого делителя частоты (SPI Mode 0: данные стабильны на переднем фронте SCLK)
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

    // Конечный автомат отправки битов
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
                spi_mosi <= tx_data[7]; // Выставляем MSB сразу
            end else if (busy && sclk_edge) begin
                if (spi_sclk == 1'b0) begin
                    spi_sclk <= 1'b1; // Передний фронт: VS1053 читает данные
                end else begin
                    spi_sclk <= 1'b0; // Задний фронт: сдвигаем данные
                    shifter  <= {shifter[6:0], 1'b0};
                    bit_cnt  <= bit_cnt + 1'b1;
                    
                    if (bit_cnt == 3'd7) begin
                        busy <= 1'b0; // Передача байта завершена
                    end else begin
                        spi_mosi <= shifter[6]; // Выставляем следующий бит
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
    
    // Интерфейс к VS1053
    input  wire        vs_dreq,
    output reg         vs_xreset,
    output reg         vs_xdcs,
    output reg         vs_xcs,
    
    // Интерфейс к SPI Master
    output reg  [7:0]  spi_tx_data,
    output reg         spi_start,
    input  wire        spi_busy,
    output reg         spi_speed,    // Команда изменения скорости для SPI мастера
    
    // Интерфейс к FIFO
    input  wire [8:0]  fifo_count,
    output reg         fifo_rd_en,
    input  wire [7:0]  fifo_rdata
);

    // Состояния FSM
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

    // Таблица инициализации регистров VS1053 [Режим записи SCI (8 бит) + Адрес (8 бит) + Данные (16 бит)]
    // Порядок байт для отправки команд SCI: 0x02 (запись), затем Адрес, затем MSB данных, затем LSB данных.
    reg [7:0] cmd_bytes[0:7];
    initial begin
        // Команда 1: Пишем в SCI_CLOCKF (Адрес 0x03) значение 0x8800 (XTALI x 3.5)
        cmd_bytes[0] = 8'h02; cmd_bytes[1] = 8'h03; cmd_bytes[2] = 8'h88; cmd_bytes[3] = 8'h00;
        // Команда 2: Пишем в SCI_MODE (Адрес 0x00) значение 0x0820 (SM_SDINEW = 1)
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
            spi_speed    <= 1'b0; // Начинаем на медленной скорости
            fifo_rd_en   <= 1'b0;
        end else if (soft_reset) begin // Принудительный сброс всей периферии VS1053
            state        <= ST_RESET;
            rst_timer    <= 0;
            byte_cnt     <= 0;
            cmd_step     <= 0;
            vs_xreset    <= 1'b0;
            vs_xcs       <= 1'b1;
            vs_xdcs      <= 1'b1;
            spi_start    <= 1'b0;
            spi_speed    <= 1'b0; // Возвращаем медленную скорость для SCI конфигурации
            fifo_rd_en   <= 1'b0;
        end else begin
            spi_start  <= 1'b0;
            fifo_rd_en <= 1'b0;
            
            case (state)
                ST_RESET: begin
                    vs_xreset <= 1'b0;
                    if (rst_timer < 24'h0FFFFF) begin // Удерживаем сброс
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
                        vs_xcs   <= 1'b0; // Активируем выбор команд SCI
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
                        vs_xcs <= 1'b1; // Деактивируем SCI
                        if (vs_dreq) begin
                            spi_speed <= 1'b1; // Переключаем SPI на высокую скорость для звука!
                            state     <= ST_IDLE;
                        end
                    end
                end

                ST_IDLE: begin
                    vs_xdcs  <= 1'b1;
                    byte_cnt <= 0;
                    // Ждем готовности чипа (DREQ=1) И накопления 32 байт в FIFO
                    if (vs_dreq && (fifo_count >= 9'd32)) begin
                        fifo_rd_en <= 1'b1; // Делаем упреждающее чтение первого байта
                        state      <= ST_FIFO_READ;
                    end
                end

                ST_FIFO_READ: begin
                    vs_xdcs <= 1'b0; // Включаем SDI передачу аудио-данных
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
                            fifo_rd_en <= 1'b1; // Запрашиваем следующий байт
                            state      <= ST_FIFO_READ;
                        end else begin
                            vs_xdcs <= 1'b1; // Отпускаем шину данных звука
                            state   <= ST_IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule


