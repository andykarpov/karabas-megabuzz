# Application makefile.
# Use this makefile to configure all relevant CPU / compiler options.

# Override the default CPU ISA
# Переопределяем архитектуру: rv32i + M (умножение) + C (сжатые инструкции)
MARCH = rv32imc_zicsr_zifencei

# Override the default RISC-V GCC prefix
RISCV_PREFIX ?= riscv-none-elf-

# Override default optimization goal
EFFORT = -Os

# Add extended debug symbols
#USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k

# Adjust processor DMEM size
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=32k

#USER_FLAGS += -Wno-narrowing
#USER_FLAGS += -march=rv32imc_zicsr_zifencei -mabi=ilp32

# Adjust maximum heap size
USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=0

# Decoder options: polyphase on the MAC CFU, no heap
USER_FLAGS += -DUSE_CFU_MAC -DHELIX_STATIC

# SIM=1: UART output goes to the simulator
ifeq ($(SIM),1)
USER_FLAGS += -DSIM
endif

# Additional sources
#APP_SRC += $(wildcard ./*.c)
#APP_INC += -I .

APP_SRC = main.c

# Добавляем ВСЕ исходники библиотеки Helix MP3
APP_SRC += lib/mp3dec.c
APP_SRC += lib/mp3tabs.c
APP_SRC += lib/bitstream.c
APP_SRC += lib/buffers.c
APP_SRC += lib/dequant.c
APP_SRC += lib/huffman.c
APP_SRC += lib/imdct.c
APP_SRC += lib/scalfact.c
APP_SRC += lib/stproc.c
APP_SRC += lib/subband.c
APP_SRC += lib/dqchan.c
APP_SRC += lib/dct32.c
APP_SRC += lib/hufftabs.c
APP_SRC += lib/polyphase.c
APP_SRC += lib/trigtabs.c

# Set path to NEORV32 root directory
NEORV32_HOME ?= ../../..

# Include the main NEORV32 makefile
include $(NEORV32_HOME)/sw/common/common.mk

# Use c++ compiler and define c++ standard
#override CC = $(RISCV_PREFIX)g++
#USER_FLAGS += -std=c++11

