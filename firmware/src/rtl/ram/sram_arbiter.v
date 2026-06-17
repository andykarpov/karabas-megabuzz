module sram_arbiter (
    input  wire        clk,        // Главный клок арбитра (например, 50 МГц = 20нс период)
    input  wire        rst_n,      // Асинхронный сброс (активный ноль)

    // Интерфейс Устройства 1 (Макс. приоритет)
    input  wire        clk1,       // Клок первого устройства
    input  wire        req1,       // Запрос памяти
    input  wire [20:0] addr1,      // Адрес
    input  wire        we1,        // 1 - запись, 0 - чтение
    input  wire [7:0] din1,       // Данные для записи
    output reg  [7:0] dout1,      // Прочитанные данные
    output reg         ack1,       // Подтверждение выполнения операции

    // Интерфейс Устройства 2 (Низкий приоритет, с поддержкой Wait)
    input  wire        clk2,       // Клок второго устройства
    input  wire        req2,       // Запрос памяти
    input  wire [20:0] addr2,      // Адрес
    input  wire        we2,        // 1 - запись, 0 - чтение
    input  wire [7:0] din2,       // Данные для записи
    output reg  [7:0] dout2,      // Прочитанные данные
    output wire        wait2,      // Сигнал ожидания (1 - память занята Устройством 1)

    // Физический асинхронный интерфейс к 45нс SRAM
    output reg  [20:0] sram_addr,
    inout  wire [7:0] sram_data,
    output reg         sram_ce_n,  // Chip Enable
    output reg         sram_oe_n,  // Output Enable
    output reg         sram_we_n   // Write Enable
);

    // --- 1. Синхронизация запросов из разных клок-доменов (CDC) ---
    reg [1:0] sync1_ff, sync2_ff;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1_ff <= 2'b0;
            sync2_ff <= 2'b0;
        end else begin
            sync1_ff <= {sync1_ff[0], req1};
            sync2_ff <= {sync2_ff[0], req2};
        end
    end
    
    wire req1_sync = sync1_ff[1];
    wire req2_sync = sync2_ff[1];

    // --- 2. Автомат состояний (FSM) для выдерживания таймингов (>= 45 нс) ---
    // Если clk = 50 МГц (период 20 нс), то цикл SRAM займет 3 такта (60 нс)
    localparam STATE_IDLE  = 2'b00;
    localparam STATE_DEV1  = 2'b01;
    localparam STATE_DEV2  = 2'b10;
    
    reg [1:0] state;
    reg [1:0] cycle_cnt; // Счетчик тактов для удержания 45 нс
    
    // Логика Wait для 2-го устройства: ждет, если есть запрос от 1-го или 1-й уже работает
    assign wait2 = req2 && (req1_sync || (state == STATE_DEV1));

    // Направление шины данных SRAM (тристат)
    reg        sram_bus_dir; // 1 - выход из FPGA в SRAM, 0 - вход
    reg [7:0] sram_dout_reg;
    assign sram_data = sram_bus_dir ? sram_dout_reg : 8'hZZ;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= STATE_IDLE;
            cycle_cnt    <= 2'b0;
            ack1         <= 1'b0;
            sram_ce_n    <= 1'b1;
            sram_oe_n    <= 1'b1;
            sram_we_n    <= 1'b1;
            sram_bus_dir <= 1'b0;
        end else begin
            ack1 <= 1'b0; // По умолчанию сбрасываем ack

            case (state)
                STATE_IDLE: begin
                    sram_ce_n <= 1'b1;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    sram_bus_dir <= 1'b0;
                    cycle_cnt <= 2'b0;

                    // Абсолютный приоритет Устройства 1
                    if (req1_sync) begin
                        state     <= STATE_DEV1;
                        sram_addr <= addr1;
                        sram_ce_n <= 1'b0;
                        sram_we_n <= !we1;
                        sram_oe_n <= we1;
                        if (we1) begin
                            sram_dout_reg <= din1;
                            sram_bus_dir  <= 1'b1;
                        end
                    end 
                    // Если Устройство 1 молчит, пускаем Устройство 2
                    else if (req2_sync) begin
                        state     <= STATE_DEV2;
                        sram_addr <= addr2;
                        sram_ce_n <= 1'b0;
                        sram_we_n <= !we2;
                        sram_oe_n <= we2;
                        if (we2) begin
                            sram_dout_reg <= din2;
                            sram_bus_dir  <= 1'b1;
                        end
                    end
                end

                STATE_DEV1: begin
                    if (cycle_cnt < 2'd2) begin // Держим сигналы 3 такта (60 нс при 50 МГц)
                        cycle_cnt <= cycle_cnt + 1'b1;
                    end else begin
                        if (!sram_we_n) dout1 <= sram_data; // Защелкиваем чтение
                        ack1      <= 1'b1;                 // Даем ack для Dev1
                        sram_ce_n <= 1'b1;                 // Гасим чип селект
                        sram_we_n <= 1'b1;
                        sram_oe_n <= 1'b1;
                        state     <= STATE_IDLE;
                    end
                end

                STATE_DEV2: begin
                    if (cycle_cnt < 2'd2) begin
                        cycle_cnt <= cycle_cnt + 1'b1;
                    end else begin
                        if (!sram_we_n) dout2 <= sram_data; // Защелкиваем чтение
                        sram_ce_n <= 1'b1;
                        sram_we_n <= 1'b1;
                        sram_oe_n <= 1'b1;
                        state     <= STATE_IDLE; // В IDLE на следующем такте проверится req1
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

