/**
 * MP3 decoder firmware. 
 * VS1053 emulation:
 * - SPI + DREQ for incoming data
 * - CSF + DATA_READY for decoded stereo data
 */

#include <neorv32.h>

#ifdef __cplusplus
extern "C" {
#endif
#include "lib/mp3dec.h"
#ifdef __cplusplus
}
#endif

#define BAUD_RATE        115200    // UART baud
#define DREQ_PIN         0         // GPIO output: 1 - host can send 32 bytes by SPI
#define DATA_READY_PIN   1         // GPIO output: PCM data ready strobe

#define RING_BUF_SIZE   4096       // Ring buffer size
uint8_t ring_buf[RING_BUF_SIZE];
volatile uint32_t head = 0;
volatile uint32_t tail = 0;

// Get data from SDI buffer (our SPI-Slave)
void check_and_receive_spi_stream(void) {
    while (!neorv32_sdi_rx_empty()) {
        uint32_t next = (head + 1) & (RING_BUF_SIZE - 1);
        if (next != tail) {
            ring_buf[head] = (uint8_t)neorv32_sdi_get_nonblocking();
            head = next;
        } else {
            break; // Ring buffer overflow
        }
    }
}

uint32_t ring_buf_free_space(void) {
    return RING_BUF_SIZE - 1 - ((head - tail) & (RING_BUF_SIZE - 1));
}

int main(void) {
    
    neorv32_rte_setup();

    neorv32_uart0_setup(BAUD_RATE, 0);

    if (neorv32_uart0_available() == 0) {
        return 1;
    }
    
    neorv32_uart0_printf("\n<<< NEORV32 MP3 decoder >>>\n\n");

    if (neorv32_sdi_available() == 0) {
        neorv32_uart0_printf("ERROR! No SDI unit implemented.");
        return 1;
    }

    if (neorv32_smc_available() == 0) {
        neorv32_uart0_printf("ERROR! No SMC unit implemented.\n");
        return 1;
    }

    if (neorv32_gpio_available() == 0) { // GPIO available?
        neorv32_uart0_printf("ERROR! No GPIO module implemented!\n");
        return 1;
    }

    // setup SDI module
    neorv32_sdi_setup(0); // no interrupts

    // setup GPIO (pin, value)
    neorv32_gpio_pin_set(DREQ_PIN, 0);       // Default: DREQ = 0
    neorv32_gpio_pin_set(DATA_READY_PIN, 0); // Default: DATA_READY = 0

    // setup SMC (PSRAM)
    neorv32_smc_setup(
        0,             // single-chip mode; use only one PSRAM
        SMC_MSIZE_8MB, // PSRAM size = 8MB
        6,             // clock prescaler; use second-slowest PSRAM clock as default
        0,             // wait cycles for read access
        0x03,          // read command
        0x02,          // write command
        0x996600       // initialization sequence: 1. NOP (0x00), 2. RESET-EN (0x66), 3. RESET (0x99)
    );

    // get configured PSRAM clock speed in Hz
    uint32_t psram_fclk = neorv32_smc_get_clockspeed();
    neorv32_uart0_printf("PSRAM clock: %u Hz\n", psram_fclk);

    // get PSRAM base address (configured via top generic)
    uint32_t psram_base = neorv32_smc_get_baseaddr();
    neorv32_uart0_printf("PSRAM base:  0x%x\n", psram_base);


    // init MP3 decoder    
    HMP3Decoder hMP3Decoder = MP3InitDecoder();
    MP3FrameInfo mp3FrameInfo;
    
    uint8_t local_dec_buf[2 * MAINBUF_SIZE]; 
    short pcm_out_buf[1152 * 2];

    while(1) {
        // DREQ control logic for external hw
        if (ring_buf_free_space() >= 32) {
            neorv32_gpio_pin_set(DREQ_PIN, 1);
        } else {
            neorv32_gpio_pin_set(DREQ_PIN, 0);
        }

        // Receive data by SPI
        check_and_receive_spi_stream();

        // If is enough data to decode a frame
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
                    
                    // Otput decoded audio data to CFS ports
                    if (mp3FrameInfo.nChans == 2) {
                        // Stereo streasm
                        for (int i = 0; i < samples; i += 2) {
                            NEORV32_CFS->REG[0] = (uint32_t)pcm_out_buf[i];   // Index [0] - Left
                            NEORV32_CFS->REG[1] = (uint32_t)pcm_out_buf[i+1]; // Index [1] - Right
                            
                            neorv32_gpio_pin_set(DATA_READY_PIN, 1);
                            asm volatile("nop");
                            neorv32_gpio_pin_set(DATA_READY_PIN, 0);
                        }
                    } else {
                        // Mono stream
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

