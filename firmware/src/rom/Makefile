SRC=$(shell find . -type f -iname "*.asm")
ENTRY=src/main.asm
BINARY=megabuzz.rom
DEBUG=debug.rom
MEM=megabuzz.mem

all: $(BINARY) $(DEBUG) $(MEM)

$(MEM): $(BINARY)
	hexdump -v -e '1/1 "%02x\n"' $(BINARY) > $(MEM)

$(BINARY): $(SRC)
	sjasmplus -DDEBUG_MODE=1 $(ENTRY) --raw=$(BINARY)

$(DEBUG): $(SRC)
	sjasmplus -DEMU_MODE=1 -DDEBUG_MODE=1 $(ENTRY) --raw=$(DEBUG)

clean:
	rm $(BINARY) $(MEM) $(DEBUG)
