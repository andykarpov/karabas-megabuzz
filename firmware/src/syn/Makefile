PROJECT16 = work16/karabas_megabuzz
BIT_FILE16 = $(PROJECT16).bit

PROJECT16_A1 = work16/karabas_megabuzz_a1
BIT_FILE16_A1 = $(PROJECT16_A1).bit

PROJECT25 = work25/karabas_megabuzz
BIT_FILE25 = $(PROJECT25).bit

PROJECT25_A1 = work25/karabas_megabuzz_a1
BIT_FILE25_A1 = $(PROJECT25_A1).bit

OPENFPGA_LOADER = /usr/bin/openFPGALoader
PART16 = xc6slx16ftg256
PART25 = xc6slx25ftg256
CABLE = usb-blaster

flash: $(BIT_FILE16)
	$(OPENFPGA_LOADER) -c $(CABLE) --fpga-part $(PART16) -f $(BIT_FILE16)

flash_a1: $(BIT_FILE16_A1)
	$(OPENFPGA_LOADER) -c $(CABLE) --fpga-part $(PART16) -f $(BIT_FILE16_A1)

flash25: $(BIT_FILE25)
	$(OPENFPGA_LOADER) -c $(CABLE) --fpga-part $(PART25) -f $(BIT_FILE25)

flash25_a1: $(BIT_FILE25_A1)
	$(OPENFPGA_LOADER) -c $(CABLE) --fpga-part $(PART25) -f $(BIT_FILE25_A1)
