SRC=$(shell find . -type f -iname "*.asm")
ENTRY=src/mp3.asm
BINARY=mp3

all: $(BINARY)

$(BINARY): $(SRC)
	sjasmplus $(ENTRY)

clean:
	rm $(BINARY)
