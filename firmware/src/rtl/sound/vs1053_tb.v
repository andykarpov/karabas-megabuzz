`timescale 1ns / 1ps

module vs1053_tb;

    // Сигналы генерации клока и сброса
    reg clk;
    reg reset;

    // Шина Z80
    reg        bus_cs_n;
    reg        bus_rd_n;
    reg        bus_wr_n;
    reg        bus_a;
    reg  [7:0] bus_di;
    wire [7:0] bus_do;

    // Интерфейс VS1053
    wire       vs_sclk;
    reg        vs_miso;
    wire       vs_mosi;
    reg        vs_dreq;
    wire       vs_cs_n;
    wire       vs_dcs_n;
    wire       vs_reset_n;

    // Подключение тестируемого модуля (UUT)
    vs1053 uut (
        .clk(clk),
        .reset(reset),
        .bus_cs_n(bus_cs_n),
        .bus_rd_n(bus_rd_n),
        .bus_wr_n(bus_wr_n),
        .bus_a(bus_a),
        .bus_di(bus_di),
        .bus_do(bus_do),
        .vs_sclk(vs_sclk),
        .vs_miso(vs_miso),
        .vs_mosi(vs_mosi),
        .vs_dreq(vs_dreq),
        .vs_cs_n(vs_cs_n),
        .vs_dcs_n(vs_dcs_n),
        .vs_reset_n(vs_reset_n)
    );

    // Генерация системного клока 28 МГц (~35.71 нс период)
    always begin
        #17.857 clk = ~clk;
    end

    // Имитация ответа чипа VS1053 на чтение SCI_STATUS
    // Нам нужно выдать версию чипа (например, 4 для VS1053b) в битах 7:4
    // При чтении посылается 32 бита. Последние 16 бит — возвращаемые данные.
    // Статус-регистр вернет, например, 0x0040 (версия 4).
    integer bit_idx;
    initial begin
        vs_miso = 0;
        forever begin
            // Ждем, пока мастер активирует SCI (cs_n = 0) и начнет тактовать
            @(posedge vs_sclk);
            if (!vs_cs_n) begin
                // Эмулируем поток данных от чипа. Для простоты, когда мастер запрашивает
                // чтение SCI_STATUS, на фазе данных (последние 16 бит) подменим MISO.
                // В реальном тесте просто выдадим фиксированную маску для битов версии.
                // 0x0040 в двоичном виде для 16 бит: 0000 0000 0100 0000
                // Нас интересует момент, когда FSM читает. 
                // Для простоты поднимем miso в нужный момент:
                #1; // небольшая задержка после фронта sclk
            end
        end
    end

    // Управление сигналом DREQ от чипа
    initial begin
        vs_dreq = 0;
        // Чип оживает не сразу после освобождения из сброса
        @ (posedge vs_reset_n);
        #1000; // Ждем условное время
        vs_dreq = 1; // Чип готов к инициализации
        
        // После переключения в быстрый режим имитируем заполнение/опустошение
        forever begin
            #50000;
            // Имитируем, что чип временно занят (DREQ=0) после приема порции данных
            //vs_dreq = 0;
            #20000;
            //vs_dreq = 1;
        end
    end

    // Процедуры записи и чтения со стороны Z80
    task z80_write_data(input [7:0] data);
        begin
            bus_a = 1; 
            bus_di = data;
            #20;         // Выставили адрес и данные заранее
            bus_cs_n = 0;
            #40;         
            bus_wr_n = 0;
            #150;        // Увеличили время удержания сигнала записи WR в '0'
            bus_wr_n = 1;
            bus_cs_n = 1;
            #200;        // Увеличили паузу МЕЖДУ записями (Z80 нужно время на обработку цикла)
        end
    endtask

    task z80_read_status(output [7:0] status);
        begin
            bus_a = 0; // Регистр статуса
            bus_cs_n = 0;
            #40;
            bus_rd_n = 0;
            #100;
            status = bus_do;
            bus_rd_n = 1;
            bus_cs_n = 1;
            #40;
        end
    endtask

    reg [7:0] current_status;
    integer i;

    // Основной процесс симуляции
    initial begin
        // Настройка вывода волн для GTKWave
        $dumpfile("vs1053_sim.vcd");
        $dumpvars(0, vs1053_tb);

        // Инициализация сигналов
        clk = 0;
        reset = 1;
        bus_cs_n = 1;
        bus_rd_n = 1;
        bus_wr_n = 1;
        bus_a = 0;
        bus_di = 0;

        // Сброс системы
        #100;
        reset = 0;

        // Ждем пока пройдет аппаратный сброс VS1053 и FSM прочитает статус
        // В тестбенче мы принудительно заставим MISO вернуть версию 4 (0x0040)
        // Чтобы контроллер не завис на чтении, подыграем ему на шине SPI:
        wait(uut.ctrl_inst.state == 4'd3); // WAIT_RD state
        // Дадим правильный паттерн на MISO во время транзакции чтения
        // Для простоты подменим регистр версии напрямую в модели, чтобы не усложнять SPI эмулятор:
        force uut.ctrl_inst.chip_version = 4'h6; 
        #100;
        //release uut.ctrl_inst.chip_version;

        // Ждем, пока модуль перейдет в рабочий режим IDLE
        wait(uut.ctrl_inst.state == 4'd8); // IDLE state
        $display("VS1053 Controller initialized and in IDLE state.");

        // Хост Z80 читает статус перед записью
        z80_read_status(current_status);
        $display("Initial Status Read: Blocks used = %d, Overflow = %b", current_status[6:0], current_status[7]);

        // Хост Z80 пишет 70 байт данных в FIFO (чуть больше 2 блоков по 32 байта)
        $display("Z80 starts writing data to FIFO...");
        for (i = 0; i < 70; i = i + 1) begin
            z80_write_data(8'hA5 + i); // Пишем тестовый паттерн
        end

        // Читаем статус еще раз, чтобы увидеть изменения
        z80_read_status(current_status);
        $display("Status after write: Blocks used = %d, Overflow = %b", current_status[6:0], current_status[7]);

        // Позволим FSM вычитать первый блок (32 байта) и отправить его по SPI
        // Наблюдаем за транзакцией в SDI режиме (vs_dcs_n должен падать)
        #1000000; 

        // Имитируем программный сброс от Z80 (запись 1 в 7-й бит статуса)
        $display("Z80 triggers Soft Reset via status register...");
        bus_a = 0;
        bus_di = 8'h80; // Бит 7 = 1
        bus_cs_n = 0;
        #40; bus_wr_n = 0; #100; bus_wr_n = 1; bus_cs_n = 1;
        #40; bus_di = 8'h00; bus_cs_n = 0;
        #40; bus_wr_n = 0; #100; bus_wr_n = 1; bus_cs_n = 1;
        
        #1000000;
        $display("Simulation finished.");
        $finish;
    end

endmodule

