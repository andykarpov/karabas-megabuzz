PROJECT = karabas_megabuzz
BIT_FILE = $(PROJECT).bit

OPENFPGA_LOADER = /usr/bin/openFPGALoader
PART = xc6slx16ftg256
CABLE = usb-blaster

flash: $(BIT_FILE)
	$(OPENFPGA_LOADER) -c $(CABLE) --fpga-part $(PART) -f $(BIT_FILE)
