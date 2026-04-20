PROJECT = karabas_megabuzz
BIT_FILE = $(PROJECT).bit
SVF_FILE = $(PROJECT).svf
IMPACT_BATCH = impact_cmd.txt

IMPACT = /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/impact
JTAG = jtag

all: $(SVF_FILE)

# 1. Make SVF from .bit file using iMPACT
$(SVF_FILE): $(BIT_FILE)
	@echo "setMode -bs" > $(IMPACT_BATCH)
	@echo "setCable -port svf -file $(SVF_FILE)" >> $(IMPACT_BATCH)
	@echo "addDevice -p 1 -file $(BIT_FILE)" >> $(IMPACT_BATCH)
	@echo "program -p 1" >> $(IMPACT_BATCH)
	@echo "quit" >> $(IMPACT_BATCH)
	$(IMPACT) -batch $(IMPACT_BATCH)
	rm $(IMPACT_BATCH)

# 2. Program SPI Flash via urJTAG using USB Blaster
flash: $(SVF_FILE)
	@echo "cable usbblaster" > urjtag_cmd.txt
	@echo "detect" >> urjtag_cmd.txt
	@echo "svf $(SVF_FILE) stop progress" >> urjtag_cmd.txt
	@echo "quit" >> urjtag_cmd.txt
	sudo $(JTAG) urjtag_cmd.txt
	rm urjtag_cmd.txt

clean:
	rm -f $(SVF_FILE) $(IMPACT_BATCH) urjtag_cmd.txt

