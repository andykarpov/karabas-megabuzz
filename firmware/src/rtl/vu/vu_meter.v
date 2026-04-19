

module vu_meter (
    input wire clk,
    input wire sample_tick,                 // Импульс новой выборки (~48 кГц)
    input wire signed [15:0] audio_sample,  // Амплитуда (знаковок)
    output wire [7:0] leds                  // Выход на светодиоды
);

    reg [15:0] audio_abs;

    // Получаем модуль (амплитуду)
    always @(posedge clk) begin
        if (audio_sample[15])
            audio_abs <= ~audio_sample + 1'b1;
        else 
            audio_abs <= audio_sample;
    end

    reg [15:0] bar_val;     // Уровень основного столбика
    reg [15:0] dot_val;     // Уровень падающей точки
    reg [23:0] hold_cnt;    // Счетчик для паузы перед падением
    reg [23:0] decay_cnt;   // Счетчик для скорости падения

    parameter HOLD_TIME  = 24'd7000000; // Точка замирает на ~250 мс при 28МГц
    parameter FALL_SPEED = 24'd2800000;  // Шаг падения каждые 100 мс (вся шкала за 0.8 сек)

    always @(posedge clk) begin
        // --- Логика основного столбика (быстрый спад) ---
        if (audio_abs > bar_val) 
            bar_val <= audio_abs;
        else if (sample_tick)
            bar_val <= bar_val - (bar_val >> 6); // Быстрое затухание

        // --- Логика падающей точки ---
        if (audio_abs > dot_val) begin
            dot_val <= audio_abs;
            hold_cnt <= 0; // Сброс паузы при новом пике
        end else if (sample_tick) begin
            if (hold_cnt < HOLD_TIME) begin
                hold_cnt <= hold_cnt + 1'b1;
            end else begin
                // Падение после паузы
                if (decay_cnt >= FALL_SPEED) begin
                    if (dot_val > 0) dot_val <= dot_val - 16'd1024; 
                    decay_cnt <= 0;
                end else begin
                    decay_cnt <= decay_cnt + 1'b1;
                end
            end
        end
    end

    // --- Отображение (Комбинаторная логика) ---
    function [7:0] to_leds(input [15:0] val);
        begin
            to_leds = (val > 56000) ? 8'b11111111 :
                      (val > 48000) ? 8'b01111111 :
                      (val > 40000) ? 8'b00111111 :
                      (val > 32000) ? 8'b00011111 :
                      (val > 24000) ? 8'b00001111 :
                      (val > 16000) ? 8'b00000111 :
                      (val > 8000)  ? 8'b00000011 :
                      (val > 4000)  ? 8'b00000001 : 8'b00000000;
        end
    endfunction

    function [7:0] to_dot_bit(input [15:0] val);
        begin
            to_dot_bit = (val > 56000) ? 8'b10000000 :
                         (val > 48000) ? 8'b01000000 :
                         (val > 40000) ? 8'b00100000 :
                         (val > 32000) ? 8'b00010000 :
                         (val > 24000) ? 8'b00001000 :
                         (val > 16000) ? 8'b00000100 :
                         (val > 8000)  ? 8'b00000010 :
                         (val > 4000)  ? 8'b00000001 : 8'b00000000;
        end
    endfunction

    // Точка отображается как отдельный бит через XOR или OR
    assign leds = ~(to_leds(bar_val) | to_dot_bit(dot_val));

endmodule

