NIMC=nim
CFLAGS=--verbosity:0 c
SOURCE=objects.nim querying.nim
BINS=main test

all: $(BINS)

main: $(SOURCE) main.nim
	$(NIMC) $(CFLAGS) main.nim

test: $(SOURCE) test.nim
	$(NIMC) $(CFLAGS) test.nim

clean: $(BINS)
	rm $(BINS)
