BUILD_DIR16     = work16
BUILD_DIR25     = work25

PROJECT_A       = karabas_megabuzz
PROJECT_A1      = karabas_megabuzz_a1
PROJECT_A2      = karabas_megabuzz_a2

TARGET_PART16   = xc6slx16-2-ftg256
TARGET_PART25   = xc6slx25-2-ftg256

CONSTRAINTS_A   = karabas-megabuzz.ucf
CONSTRAINTS_A1  = karabas-megabuzz-a1.ucf
CONSTRAINTS_A2  = karabas-megabuzz-a2.ucf

VERILOG_SOURCES_COMMON= ../rtl/dac/pcm5102.v\
                        ../rtl/sound/gs_top.v\
                        ../rtl/sound/gs.v\
                        ../rtl/sound/audio_mixer.v\
                        ../rtl/sound/turbosound.v\
                        ../rtl/sound/ym2149.v\
                        ../rtl/sound/opl3.v\
                        ../rtl/sound/soundrive.v\
                        ../rtl/sound/beeper.v\
                        ../rtl/sound/saa1099_new.v\
                        ../rtl/sound/clk_div_8mhz.v\
                        ../rtl/sound/midi_tx_sensor.v\
                        ../rtl/sound/audio_mute.v\
                        ../rtl/sound/audio_resample.v\
                        ../rtl/sound/jt12/jt03.v\
                        ../rtl/sound/jt12/jt12_top.v\
                        ../rtl/sound/jt12/jt12_rst.v\
                        ../rtl/sound/jt12/jt12_dout.v\
                        ../rtl/sound/jt12/jt12_mmr.v\
                        ../rtl/sound/jt12/jt12_timers.v\
                        ../rtl/sound/jt12/jt03_acc.v\
                        ../rtl/sound/jt12/jt12_acc.v\
                        ../rtl/sound/jt12/jt12_csr.v\
                        ../rtl/sound/jt12/jt12_div.v\
                        ../rtl/sound/jt12/jt12_eg.v\
                        ../rtl/sound/jt12/jt12_eg_cnt.v\
                        ../rtl/sound/jt12/jt12_eg_comb.v\
                        ../rtl/sound/jt12/jt12_eg_ctrl.v\
                        ../rtl/sound/jt12/jt12_eg_final.v\
                        ../rtl/sound/jt12/jt12_eg_pure.v\
                        ../rtl/sound/jt12/jt12_eg_step.v\
                        ../rtl/sound/jt12/jt12_exprom.v\
                        ../rtl/sound/jt12/jt12_kon.v\
                        ../rtl/sound/jt12/jt12_lfo.v\
                        ../rtl/sound/jt12/jt12_logsin.v\
                        ../rtl/sound/jt12/jt12_mod.v\
                        ../rtl/sound/jt12/jt12_op.v\
                        ../rtl/sound/jt12/jt12_pcm_interpol.v\
                        ../rtl/sound/jt12/jt12_pg.v\
                        ../rtl/sound/jt12/jt12_pg_comb.v\
                        ../rtl/sound/jt12/jt12_pg_dt.v\
                        ../rtl/sound/jt12/jt12_pg_inc.v\
                        ../rtl/sound/jt12/jt12_pg_sum.v\
                        ../rtl/sound/jt12/jt12_pm.v\
                        ../rtl/sound/jt12/jt12_reg.v\
                        ../rtl/sound/jt12/jt12_reg_ch.v\
                        ../rtl/sound/jt12/jt12_sh.v\
                        ../rtl/sound/jt12/jt12_sh_rst.v\
                        ../rtl/sound/jt12/jt12_single_acc.v\
                        ../rtl/sound/jt12/jt12_sumch.v\
                        ../rtl/pll/pll.v\
                        ../rtl/vu/vu_meter.v\
                        ../rtl/resetter.v\
                        ../rtl/sd/zc_dicmmc.v\
                        ../rtl/ram/sprom.v\
                        ../rtl/ram/spram.v\
                        ../rtl/ram/dprom.v\
                        ../rtl/ram/dpram.v

VERILOG_SOURCES_A  =    ../rtl/top.v\
                        $(VERILOG_SOURCES_COMMON)

VERILOG_SOURCES_A1 =    ../rtl/top_a1.v\
                        $(VERILOG_SOURCES_COMMON)

VERILOG_SOURCES_A2 =    ../rtl/top_a2.v\
                        $(VERILOG_SOURCES_COMMON)

VHDL_SOURCES    =       ../rtl/T80/T80.vhd\
                        ../rtl/T80/T80_ALU.vhd\
                        ../rtl/T80/T80_MCode.vhd\
                        ../rtl/T80/T80_Pack.vhd\
                        ../rtl/T80/T80_Reg.vhd\
                        ../rtl/T80/T80s.vhd\
	                    ../rtl/adc/i2s_transceiver.vhd\
                        ../rtl/flash/flash.vhd\
                        ../rtl/loader/loader.vhd\
                        ../rtl/flash/spi_master.vhd

XILINX_DIR   = /opt/Xilinx/14.7/ISE_DS
XILINX       = $(XILINX_DIR)/ISE
ISE_BIN      = $(XILINX)/bin/lin64
ISE_ENV      = XILINX=$(XILINX) LD_LIBRARY_PATH=$(XILINX)/lib/lin64 PATH=$(ISE_BIN):$$PATH
OPENOCD_BIN = /usr/bin/openocd

GS_ROM = ../rtl/sound/gs105b.rom
CFG1_ROM = cfg1.rom
CFG2_ROM = cfg2.rom

# ----------------------------------------------

.PHONY: all25_a2 all25_a1 all25_a all16_a2 all16_a1 all16_a clean

all16_a: $(BUILD_DIR16)/$(PROJECT_A).bit
all16_a1: $(BUILD_DIR16)/$(PROJECT_A1).bit
all16_a2: $(BUILD_DIR16)/$(PROJECT_A2).bit
all25_a: $(BUILD_DIR25)/$(PROJECT_A).bit
all25_a1: $(BUILD_DIR25)/$(PROJECT_A1).bit
all25_a2: $(BUILD_DIR25)/$(PROJECT_A2).bit


# 1. PRJ
$(BUILD_DIR16)/$(PROJECT_A).prj: | $(BUILD_DIR16)
	@echo "=== GENERATING PRJ FILE ==="
	@rm -f $@
	$(foreach f,$(VHDL_SOURCES),echo "vhdl work ../$(f)" >> $@;)
	$(foreach f,$(VERILOG_SOURCES_A),echo "verilog work ../$(f)" >> $@;)

$(BUILD_DIR16)/$(PROJECT_A1).prj: | $(BUILD_DIR16)
	@echo "=== GENERATING PRJ FILE ==="
	@rm -f $@
	$(foreach f,$(VHDL_SOURCES),echo "vhdl work ../$(f)" >> $@;)
	$(foreach f,$(VERILOG_SOURCES_A1),echo "verilog work ../$(f)" >> $@;)

$(BUILD_DIR16)/$(PROJECT_A2).prj: | $(BUILD_DIR16)
	@echo "=== GENERATING PRJ FILE ==="
	@rm -f $@
	$(foreach f,$(VHDL_SOURCES),echo "vhdl work ../$(f)" >> $@;)
	$(foreach f,$(VERILOG_SOURCES_A2),echo "verilog work ../$(f)" >> $@;)

$(BUILD_DIR25)/$(PROJECT_A).prj: | $(BUILD_DIR25)
	@echo "=== GENERATING PRJ FILE ==="
	@rm -f $@
	$(foreach f,$(VHDL_SOURCES),echo "vhdl work ../$(f)" >> $@;)
	$(foreach f,$(VERILOG_SOURCES_A),echo "verilog work ../$(f)" >> $@;)

$(BUILD_DIR25)/$(PROJECT_A1).prj: | $(BUILD_DIR25)
	@echo "=== GENERATING PRJ FILE ==="
	@rm -f $@
	$(foreach f,$(VHDL_SOURCES),echo "vhdl work ../$(f)" >> $@;)
	$(foreach f,$(VERILOG_SOURCES_A1),echo "verilog work ../$(f)" >> $@;)

$(BUILD_DIR25)/$(PROJECT_A2).prj: | $(BUILD_DIR25)
	@echo "=== GENERATING PRJ FILE ==="
	@rm -f $@
	$(foreach f,$(VHDL_SOURCES),echo "vhdl work ../$(f)" >> $@;)
	$(foreach f,$(VERILOG_SOURCES_A2),echo "verilog work ../$(f)" >> $@;)

$(BUILD_DIR16)/$(PROJECT_A).xst: | $(BUILD_DIR16)
	@echo "run" > $@
	@echo "-ifn $(PROJECT_A).prj" >> $@
	@echo "-ofn $(PROJECT_A).ngc" >> $@
	@echo "-ofmt NGC" >> $@
	@echo "-p $(TARGET_PART16)" >> $@
	@echo "-top $(PROJECT_A)" >> $@
	@echo "-opt_mode Speed" >> $@
	@echo "-opt_level 1" >> $@
	@echo "-define {HW_A}" >> $@

$(BUILD_DIR16)/$(PROJECT_A1).xst: | $(BUILD_DIR16)
	@echo "run" > $@
	@echo "-ifn $(PROJECT_A1).prj" >> $@
	@echo "-ofn $(PROJECT_A1).ngc" >> $@
	@echo "-ofmt NGC" >> $@
	@echo "-p $(TARGET_PART16)" >> $@
	@echo "-top $(PROJECT_A1)" >> $@
	@echo "-opt_mode Speed" >> $@
	@echo "-opt_level 1" >> $@
	@echo "-define {HW_A1}" >> $@

$(BUILD_DIR16)/$(PROJECT_A2).xst: | $(BUILD_DIR16)
	@echo "run" > $@
	@echo "-ifn $(PROJECT_A2).prj" >> $@
	@echo "-ofn $(PROJECT_A2).ngc" >> $@
	@echo "-ofmt NGC" >> $@
	@echo "-p $(TARGET_PART16)" >> $@
	@echo "-top $(PROJECT_A2)" >> $@
	@echo "-opt_mode Speed" >> $@
	@echo "-opt_level 1" >> $@
	@echo "-define {HW_A2}" >> $@

$(BUILD_DIR25)/$(PROJECT_A).xst: | $(BUILD_DIR25)
	@echo "run" > $@
	@echo "-ifn $(PROJECT_A).prj" >> $@
	@echo "-ofn $(PROJECT_A).ngc" >> $@
	@echo "-ofmt NGC" >> $@
	@echo "-p $(TARGET_PART25)" >> $@
	@echo "-top $(PROJECT_A)" >> $@
	@echo "-opt_mode Speed" >> $@
	@echo "-opt_level 1" >> $@
	@echo "-define {HW_A}" >> $@

$(BUILD_DIR25)/$(PROJECT_A1).xst: | $(BUILD_DIR25)
	@echo "run" > $@
	@echo "-ifn $(PROJECT_A1).prj" >> $@
	@echo "-ofn $(PROJECT_A1).ngc" >> $@
	@echo "-ofmt NGC" >> $@
	@echo "-p $(TARGET_PART25)" >> $@
	@echo "-top $(PROJECT_A1)" >> $@
	@echo "-opt_mode Speed" >> $@
	@echo "-opt_level 1" >> $@
	@echo "-define {HW_A1}" >> $@

$(BUILD_DIR25)/$(PROJECT_A2).xst: | $(BUILD_DIR25)
	@echo "run" > $@
	@echo "-ifn $(PROJECT_A2).prj" >> $@
	@echo "-ofn $(PROJECT_A2).ngc" >> $@
	@echo "-ofmt NGC" >> $@
	@echo "-p $(TARGET_PART25)" >> $@
	@echo "-top $(PROJECT_A2)" >> $@
	@echo "-opt_mode Speed" >> $@
	@echo "-opt_level 1" >> $@
	@echo "-define {HW_A2}" >> $@

# 2. XST
$(BUILD_DIR16)/$(PROJECT_A).ngc: $(BUILD_DIR16)/$(PROJECT_A).prj $(BUILD_DIR16)/$(PROJECT_A).xst $(VERILOG_SOURCES_A) $(VHDL_SOURCES)
	@echo "=== RUNNING XST ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) xst -ifn $(PROJECT_A).xst -ofn $(PROJECT_A).syr

$(BUILD_DIR16)/$(PROJECT_A1).ngc: $(BUILD_DIR16)/$(PROJECT_A1).prj $(BUILD_DIR16)/$(PROJECT_A1).xst $(VERILOG_SOURCES_A1) $(VHDL_SOURCES)
	@echo "=== RUNNING XST ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) xst -ifn $(PROJECT_A1).xst -ofn $(PROJECT_A1).syr

$(BUILD_DIR16)/$(PROJECT_A2).ngc: $(BUILD_DIR16)/$(PROJECT_A2).prj $(BUILD_DIR16)/$(PROJECT_A2).xst $(VERILOG_SOURCES_A2) $(VHDL_SOURCES)
	@echo "=== RUNNING XST ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) xst -ifn $(PROJECT_A2).xst -ofn $(PROJECT_A2).syr

$(BUILD_DIR25)/$(PROJECT_A).ngc: $(BUILD_DIR25)/$(PROJECT_A).prj $(BUILD_DIR25)/$(PROJECT_A).xst $(VERILOG_SOURCES_A) $(VHDL_SOURCES)
	@echo "=== RUNNING XST ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) xst -ifn $(PROJECT_A).xst -ofn $(PROJECT_A).syr

$(BUILD_DIR25)/$(PROJECT_A1).ngc: $(BUILD_DIR25)/$(PROJECT_A1).prj $(BUILD_DIR25)/$(PROJECT_A1).xst $(VERILOG_SOURCES_A1) $(VHDL_SOURCES)
	@echo "=== RUNNING XST ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) xst -ifn $(PROJECT_A1).xst -ofn $(PROJECT_A1).syr

$(BUILD_DIR25)/$(PROJECT_A2).ngc: $(BUILD_DIR25)/$(PROJECT_A2).prj $(BUILD_DIR25)/$(PROJECT_A2).xst $(VERILOG_SOURCES_A2) $(VHDL_SOURCES)
	@echo "=== RUNNING XST ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) xst -ifn $(PROJECT_A2).xst -ofn $(PROJECT_A2).syr

# 3. NGDBUILD
$(BUILD_DIR16)/$(PROJECT_A).ngd: $(BUILD_DIR16)/$(PROJECT_A).ngc $(CONSTRAINTS_A)
	@echo "=== RUNNING NGBUILD ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) ngdbuild -p $(TARGET_PART16) -uc ../$(CONSTRAINTS_A) $(PROJECT_A).ngc $(PROJECT_A).ngd

$(BUILD_DIR16)/$(PROJECT_A1).ngd: $(BUILD_DIR16)/$(PROJECT_A1).ngc $(CONSTRAINTS_A1)
	@echo "=== RUNNING NGBUILD ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) ngdbuild -p $(TARGET_PART16) -uc ../$(CONSTRAINTS_A1) $(PROJECT_A1).ngc $(PROJECT_A1).ngd

$(BUILD_DIR16)/$(PROJECT_A2).ngd: $(BUILD_DIR16)/$(PROJECT_A2).ngc $(CONSTRAINTS_A2)
	@echo "=== RUNNING NGBUILD ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) ngdbuild -p $(TARGET_PART16) -uc ../$(CONSTRAINTS_A2) $(PROJECT_A2).ngc $(PROJECT_A2).ngd

$(BUILD_DIR25)/$(PROJECT_A).ngd: $(BUILD_DIR25)/$(PROJECT_A).ngc $(CONSTRAINTS_A)
	@echo "=== RUNNING NGBUILD ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) ngdbuild -p $(TARGET_PART25) -uc ../$(CONSTRAINTS_A) $(PROJECT_A).ngc $(PROJECT_A).ngd

$(BUILD_DIR25)/$(PROJECT_A1).ngd: $(BUILD_DIR25)/$(PROJECT_A1).ngc $(CONSTRAINTS_A1)
	@echo "=== RUNNING NGBUILD ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) ngdbuild -p $(TARGET_PART25) -uc ../$(CONSTRAINTS_A1) $(PROJECT_A1).ngc $(PROJECT_A1).ngd

$(BUILD_DIR25)/$(PROJECT_A2).ngd: $(BUILD_DIR25)/$(PROJECT_A2).ngc $(CONSTRAINTS_A2)
	@echo "=== RUNNING NGBUILD ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) ngdbuild -p $(TARGET_PART25) -uc ../$(CONSTRAINTS_A2) $(PROJECT_A2).ngc $(PROJECT_A2).ngd

# 4. MAP
$(BUILD_DIR16)/$(PROJECT_A)_mapped.ncd: $(BUILD_DIR16)/$(PROJECT_A).ngd
	@echo "=== RUNNING MAP ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) map -p $(TARGET_PART16) -w -ol high -detail -o $(PROJECT_A)_mapped.ncd $(PROJECT_A).ngd $(PROJECT_A).pcf

$(BUILD_DIR16)/$(PROJECT_A1)_mapped.ncd: $(BUILD_DIR16)/$(PROJECT_A1).ngd
	@echo "=== RUNNING MAP ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) map -p $(TARGET_PART16) -w -ol high -detail -o $(PROJECT_A1)_mapped.ncd $(PROJECT_A1).ngd $(PROJECT_A1).pcf

$(BUILD_DIR16)/$(PROJECT_A2)_mapped.ncd: $(BUILD_DIR16)/$(PROJECT_A2).ngd
	@echo "=== RUNNING MAP ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) map -p $(TARGET_PART16) -w -ol high -detail -o $(PROJECT_A2)_mapped.ncd $(PROJECT_A2).ngd $(PROJECT_A2).pcf

$(BUILD_DIR25)/$(PROJECT_A)_mapped.ncd: $(BUILD_DIR25)/$(PROJECT_A).ngd
	@echo "=== RUNNING MAP ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) map -p $(TARGET_PART25) -w -ol high -detail -o $(PROJECT_A)_mapped.ncd $(PROJECT_A).ngd $(PROJECT_A).pcf

$(BUILD_DIR25)/$(PROJECT_A1)_mapped.ncd: $(BUILD_DIR25)/$(PROJECT_A1).ngd
	@echo "=== RUNNING MAP ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) map -p $(TARGET_PART25) -w -ol high -detail -o $(PROJECT_A1)_mapped.ncd $(PROJECT_A1).ngd $(PROJECT_A1).pcf

$(BUILD_DIR25)/$(PROJECT_A2)_mapped.ncd: $(BUILD_DIR25)/$(PROJECT_A2).ngd
	@echo "=== RUNNING MAP ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) map -p $(TARGET_PART25) -w -ol high -detail -o $(PROJECT_A2)_mapped.ncd $(PROJECT_A2).ngd $(PROJECT_A2).pcf

# 5. PAR
$(BUILD_DIR16)/$(PROJECT_A).ncd: $(BUILD_DIR16)/$(PROJECT_A)_mapped.ncd
	@echo "=== RUNNING PAR ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) par -w -ol high $(PROJECT_A)_mapped.ncd $(PROJECT_A).ncd $(PROJECT_A).pcf

$(BUILD_DIR16)/$(PROJECT_A1).ncd: $(BUILD_DIR16)/$(PROJECT_A1)_mapped.ncd
	@echo "=== RUNNING PAR ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) par -w -ol high $(PROJECT_A1)_mapped.ncd $(PROJECT_A1).ncd $(PROJECT_A1).pcf

$(BUILD_DIR16)/$(PROJECT_A2).ncd: $(BUILD_DIR16)/$(PROJECT_A2)_mapped.ncd
	@echo "=== RUNNING PAR ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) par -w -ol high $(PROJECT_A2)_mapped.ncd $(PROJECT_A2).ncd $(PROJECT_A2).pcf

$(BUILD_DIR25)/$(PROJECT_A).ncd: $(BUILD_DIR25)/$(PROJECT_A)_mapped.ncd
	@echo "=== RUNNING PAR ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) par -w -ol high $(PROJECT_A)_mapped.ncd $(PROJECT_A).ncd $(PROJECT_A).pcf

$(BUILD_DIR25)/$(PROJECT_A1).ncd: $(BUILD_DIR25)/$(PROJECT_A1)_mapped.ncd
	@echo "=== RUNNING PAR ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) par -w -ol high $(PROJECT_A1)_mapped.ncd $(PROJECT_A1).ncd $(PROJECT_A1).pcf

$(BUILD_DIR25)/$(PROJECT_A2).ncd: $(BUILD_DIR25)/$(PROJECT_A2)_mapped.ncd
	@echo "=== RUNNING PAR ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) par -w -ol high $(PROJECT_A2)_mapped.ncd $(PROJECT_A2).ncd $(PROJECT_A2).pcf

# 6. BITGEN: Генерация финальной прошивки (.bit)
$(BUILD_DIR16)/$(PROJECT_A).bit: $(BUILD_DIR16)/$(PROJECT_A).ncd
	@echo "=== GENERATING BITSTREAM ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) bitgen -w -g Binary:Yes -g StartupClk:Cclk $(PROJECT_A).ncd $(PROJECT_A).bit
	@echo "=== BUILD SUCCESSFULLY COMPLETED ==="

$(BUILD_DIR16)/$(PROJECT_A1).bit: $(BUILD_DIR16)/$(PROJECT_A1).ncd
	@echo "=== GENERATING BITSTREAM ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) bitgen -w -g Binary:Yes -g StartupClk:Cclk $(PROJECT_A1).ncd $(PROJECT_A1).bit
	@echo "=== BUILD SUCCESSFULLY COMPLETED ==="

$(BUILD_DIR16)/$(PROJECT_A2).bit: $(BUILD_DIR16)/$(PROJECT_A2).ncd
	@echo "=== GENERATING BITSTREAM ==="
	cd $(BUILD_DIR16) && $(ISE_ENV) bitgen -w -g Binary:Yes -g StartupClk:Cclk $(PROJECT_A2).ncd $(PROJECT_A2).bit
	@echo "=== BUILD SUCCESSFULLY COMPLETED ==="

$(BUILD_DIR25)/$(PROJECT_A).bit: $(BUILD_DIR25)/$(PROJECT_A).ncd
	@echo "=== GENERATING BITSTREAM ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) bitgen -w -g Binary:Yes -g StartupClk:Cclk $(PROJECT_A).ncd $(PROJECT_A).bit
	@echo "=== BUILD SUCCESSFULLY COMPLETED ==="

$(BUILD_DIR25)/$(PROJECT_A1).bit: $(BUILD_DIR25)/$(PROJECT_A1).ncd
	@echo "=== GENERATING BITSTREAM ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) bitgen -w -g Binary:Yes -g StartupClk:Cclk $(PROJECT_A1).ncd $(PROJECT_A1).bit
	@echo "=== BUILD SUCCESSFULLY COMPLETED ==="

$(BUILD_DIR25)/$(PROJECT_A2).bit: $(BUILD_DIR25)/$(PROJECT_A2).ncd
	@echo "=== GENERATING BITSTREAM ==="
	cd $(BUILD_DIR25) && $(ISE_ENV) bitgen -w -g Binary:Yes -g StartupClk:Cclk $(PROJECT_A2).ncd $(PROJECT_A2).bit
	@echo "=== BUILD SUCCESSFULLY COMPLETED ==="

# 1. Синтез через Yosys (генерация EDIF)
#$(BUILD_DIR25)/$(PROJECT_A2).edf: $(SOURCES) | $(BUILD_DIR25)
#	@echo "=== RUNNING YOSYS SYNTHESIS ==="
#	yosys -m ghdl -p "\
#        verilog_defines -DHW_A2; \
#		read_verilog -lib +/xilinx/cells_sim.v; \
#		$(foreach f,$(VHDL_SOURCES),ghdl $(f);) \
#		$(foreach f,$(VERILOG_SOURCES_A2),read_verilog $(f);) \
#		hierarchy -top $(TOP_MODULE); \
#		synth_xilinx -family xc6s -ise; \
#		write_edif $@"

# 2. NGDBUILD: Слияние EDIF-нетлиста и файла ограничений UCF в формат NGD
#$(BUILD_DIR25)/$(PROJECT_A2).ngd: $(BUILD_DIR25)/$(PROJECT_A2).edf $(CONSTRAINTS_A2)
#	@echo "=== RUNNING NGDBUILD (ISE) ==="
#	cd $(BUILD_DIR25) && $(ISE_ENV) ngdbuild -p $(TARGET_PART25) -uc $(CONSTRAINTS_A2) $(PROJECT_A2).edf $(PROJECT_A2).ngd

# work dir
$(BUILD_DIR16):
	mkdir -p $(BUILD_DIR16)

$(BUILD_DIR25):
	mkdir -p $(BUILD_DIR25)

# Cleanup
clean:
	rm -rf $(BUILD_DIR25)
	rm -rf $(BUILD_DIR16)
	rm -f xilinx_device_details.xml

flash16: $(BUILD_DIR16)/$(PROJECT_A).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx16.bit; jtagspi_program $(BUILD_DIR16)/$(PROJECT_A).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG1_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash16_a1: $(BUILD_DIR16)/$(PROJECT_A1).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx16.bit; jtagspi_program $(BUILD_DIR16)/$(PROJECT_A1).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG1_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash16_a2: $(BUILD_DIR16)/$(PROJECT_A2).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx16.bit; jtagspi_program $(BUILD_DIR16)/$(PROJECT_A2).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG1_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash16_a2_nommc: $(BUILD_DIR16)/$(PROJECT_A2).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx16.bit; jtagspi_program $(BUILD_DIR16)/$(PROJECT_A2).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG2_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash25: $(BUILD_DIR25)/$(PROJECT_A).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx25.bit; jtagspi_program $(BUILD_DIR25)/$(PROJECT_A).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG1_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash25_a1: $(BUILD_DIR25)/$(PROJECT_A1).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx25.bit; jtagspi_program $(BUILD_DIR25)/$(PROJECT_A1).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG1_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash25_a2: $(BUILD_DIR25)/$(PROJECT_A2).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx25.bit; jtagspi_program $(BUILD_DIR25)/$(PROJECT_A2).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG1_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

flash25_a2_nommc: $(BUILD_DIR25)/$(PROJECT_A2).bin
	$(OPENOCD_BIN) -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx25.bit; jtagspi_program $(BUILD_DIR25)/$(PROJECT_A2).bin 0; jtagspi_program $(GS_ROM) 0x100000; jtagspi_program $(CFG2_ROM) 0x1F0000; xc6s_program xc6s.tap; exit"

