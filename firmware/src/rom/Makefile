SRC=$(shell find . -type f -iname "*.asm")
ENTRY=src/main.asm
BINARY=megabuzz.rom
MEM=megabuzz.mem

all: $(BINARY) $(MEM)

$(MEM): $(BINARY)
	hexdump -v -e '1/1 "%02x\n"' $(BINARY) > $(MEM)

$(BINARY): $(SRC)
	sjasmplus $(ENTRY)

clean:
	rm $(BINARY) $(MEM)
