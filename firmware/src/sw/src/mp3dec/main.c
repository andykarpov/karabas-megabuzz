#include <neorv32.h>

#ifdef __cplusplus
extern "C" {
#endif
#include "lib/mp3dec.h" // Сюда подключаем Helix
#ifdef __cplusplus
}
#endif

#define DREQ_PIN         0   // GPIO Выход: 1 - хост может слать 32 байта SPI
#define DATA_READY_PIN   1   // GPIO Выход: Строб готовности PCM (импульс)

#define RING_BUF_SIZE   4096 // Кольцевой буфер (степень 2)
uint8_t ring_buf[RING_BUF_SIZE];
volatile uint32_t head = 0;
volatile uint32_t tail = 0;

// Функция заполнения буфера из аппаратного FIFO SLINK (наш SPI-Slave)
void check_and_receive_spi_stream(void) {
    // Исправлено: проверяем доступность SLINK без аргументов
    while (neorv32_slink_available()) { 
        uint32_t next = (head + 1) & (RING_BUF_SIZE - 1);
        if (next != tail) {
            // Исправлено: чтение из SLINK без передачи номера канала
            ring_buf[head] = (uint8_t)neorv32_slink_get(); 
            head = next;
        } else {
            break; // Кольцевой буфер переполнен
        }
    }
}

uint32_t ring_buf_free_space(void) {
    return RING_BUF_SIZE - 1 - ((head - tail) & (RING_BUF_SIZE - 1));
}

int main(void) {
    neorv32_rte_setup();
    
    // Настройка SLINK (включаем rx/tx, настраиваем FIFO)
    neorv32_slink_setup(SLINK_CTRL_EN); 

    // Инициализация GPIO через (pin, value)
    neorv32_gpio_pin_set(DREQ_PIN, 0);       // Изначально DREQ = 0
    neorv32_gpio_pin_set(DATA_READY_PIN, 0); // Изначально DATA_READY = 0
    
    HMP3Decoder hMP3Decoder = MP3InitDecoder();
    MP3FrameInfo mp3FrameInfo;
    
    uint8_t local_dec_buf[2 * MAINBUF_SIZE]; 
    short pcm_out_buf[1152 * 2];

    while(1) {
        // 1. Управление логикой DREQ для внешней схемы
        if (ring_buf_free_space() >= 32) {
            neorv32_gpio_pin_set(DREQ_PIN, 1);
        } else {
            neorv32_gpio_pin_set(DREQ_PIN, 0);
        }

        // 2. Выгребаем всё, что прилетело по SPI в SLINK
        check_and_receive_spi_stream();

        // 3. Если накопилось достаточно данных для декодирования кадра
        uint32_t available = (head - tail) & (RING_BUF_SIZE - 1);
        if (available >= MAINBUF_SIZE) {
            
            for(int i = 0; i < MAINBUF_SIZE; i++) {
                local_dec_buf[i] = ring_buf[tail];
                tail = (tail + 1) & (RING_BUF_SIZE - 1);
            }
            
            int bytesLeft = MAINBUF_SIZE;
            uint8_t *readPtr = local_dec_buf;
            
            int offset = MP3FindSyncWord(readPtr, bytesLeft);
            if (offset >= 0) {
                readPtr += offset;
                bytesLeft -= offset;
                
                int err = MP3Decode(hMP3Decoder, &readPtr, &bytesLeft, pcm_out_buf, 0);
                if (err == ERR_MP3_NONE) {
                    MP3GetLastFrameInfo(hMP3Decoder, &mp3FrameInfo);
                    int samples = mp3FrameInfo.outputSamps;
                    
                    // 4. Вывод в CFS порты со стробированием GPIO
                    if (mp3FrameInfo.nChans == 2) {
                        for (int i = 0; i < samples; i += 2) {
                            // Записываем левый канал в регистр 0, правый в регистр 1
                            NEORV32_CFS->REG[0] = (uint32_t)pcm_out_buf[i];   // Index [0] - Left
                            NEORV32_CFS->REG[1] = (uint32_t)pcm_out_buf[i+1]; // Index [1] - Right
                            
                            // Генерируем импульс готовности для внешнего FIFO
                            neorv32_gpio_pin_set(DATA_READY_PIN, 1);
                            asm volatile("nop"); // Небольшая задержка ширины импульса
                            neorv32_gpio_pin_set(DATA_READY_PIN, 0);
                        }
                    } else {
                        // Моно поток: дублируем один и тот же семпл в оба регистра
                        for (int i = 0; i < samples; i++) {
                            NEORV32_CFS->REG[0] = (uint32_t)pcm_out_buf[i];
                            NEORV32_CFS->REG[1] = (uint32_t)pcm_out_buf[i];
                            
                            neorv32_gpio_pin_set(DATA_READY_PIN, 1);
                            asm volatile("nop");
                            neorv32_gpio_pin_set(DATA_READY_PIN, 0);
                        }
                    }

                }
            }
        }
    }
    return 0;
}

