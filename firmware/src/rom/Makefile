SRC=$(shell find . -type f -iname "*.asm")
ENTRY=src/main.asm
BINARY=megabuzz.rom

all: $(BINARY)

$(BINARY): $(SRC)
	sjasmplus $(ENTRY)

clean:
	rm $(BINARY)
