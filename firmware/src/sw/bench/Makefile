# Application makefile.
# Use this makefile to configure all relevant CPU / compiler options.

# Override the default CPU ISA
# Переопределяем архитектуру: rv32i + M (умножение) + C (сжатые инструкции)
MARCH = rv32imc_zicsr_zifencei

# Override the default RISC-V GCC prefix
RISCV_PREFIX ?= riscv-none-elf-

# Override default optimization goal
EFFORT = -Os

# CFU=1: Helix polyphase on the MAC CFU
ifeq ($(CFU),1)
USER_FLAGS += -DUSE_CFU_MAC
endif

# Add extended debug symbols
#USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k

# Adjust processor DMEM size
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=64k

#USER_FLAGS += -Wno-narrowing
#USER_FLAGS += -march=rv32imc_zicsr_zifencei -mabi=ilp32

# Adjust maximum heap size
USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=48k

# Additional sources
#APP_SRC += $(wildcard ./*.c)
#APP_INC += -I .

APP_SRC = main.c

# Добавляем ВСЕ исходники библиотеки Helix MP3
APP_SRC += ../src/mp3dec/lib/mp3dec.c
APP_SRC += ../src/mp3dec/lib/mp3tabs.c
APP_SRC += ../src/mp3dec/lib/bitstream.c
APP_SRC += ../src/mp3dec/lib/buffers.c
APP_SRC += ../src/mp3dec/lib/dequant.c
APP_SRC += ../src/mp3dec/lib/huffman.c
APP_SRC += ../src/mp3dec/lib/imdct.c
APP_SRC += ../src/mp3dec/lib/scalfact.c
APP_SRC += ../src/mp3dec/lib/stproc.c
APP_SRC += ../src/mp3dec/lib/subband.c
APP_SRC += ../src/mp3dec/lib/dqchan.c
APP_SRC += ../src/mp3dec/lib/dct32.c
APP_SRC += ../src/mp3dec/lib/hufftabs.c
APP_SRC += ../src/mp3dec/lib/polyphase.c
APP_SRC += ../src/mp3dec/lib/trigtabs.c

# Set path to NEORV32 root directory
NEORV32_HOME ?= ../..

# Include the main NEORV32 makefile
include $(NEORV32_HOME)/sw/common/common.mk

# Use c++ compiler and define c++ standard
#override CC = $(RISCV_PREFIX)g++
#USER_FLAGS += -std=c++11

