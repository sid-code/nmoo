NIMC=nim
CFLAGS=--verbosity:0 c
SOURCE=main.nim test.nim objects.nim querying.nim
BINS=main test

all: $(BINS)

main: $(SOURCE)
	$(NIMC) $(CFLAGS) main.nim

test: $(SOURCE)
	$(NIMC) $(CFLAGS) test.nim

clean: $(BINS)
	rm $(BINS)
