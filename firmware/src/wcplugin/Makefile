SRC=$(wildcard src/*.asm)
BINARY=MEGABUZZ.WMF
EMU=MEGABUZZ_EMU.WMF
# python with the z80 and mutagen packages, e.g. a venv: make test PYTHON=venv/bin/python
PYTHON?=python3

all: $(BINARY) $(EMU)

$(BINARY): $(SRC)
	sjasmplus --nologo --msg=war --inc=src src/main.asm

# no Megabuzz needed: software FIFO, for trying the UI on any TSConf host
$(EMU): $(SRC)
	sjasmplus --nologo --msg=war --inc=src -DEMU_MODE src/main.asm

test: $(BINARY) $(EMU)
	test/gen.sh
	cd test && $(PYTHON) run_tests.py ../$(BINARY)
	cd test && $(PYTHON) behave.py ../$(BINARY)
	cd test && $(PYTHON) more.py ../$(BINARY) ../$(EMU)

clean:
	rm -f $(BINARY) $(EMU)

.PHONY: all test clean
