SWIFTC = swiftc
SWIFTFLAGS = -O -static-stdlib -I ../../runtime/arkrt/include -Xcc -I/usr/lib/musl/include -Xcc -I../../runtime/arkrt/include

SIGNALS_O = ../../runtime/arkrt/signals.o

all: arkdiag

$(SIGNALS_O):
	$(MAKE) -C ../../runtime/arkrt signals.o

arkdiag: main.swift $(SIGNALS_O)
	$(SWIFTC) $(SWIFTFLAGS) main.swift $(SIGNALS_O) -o $@

clean:
	rm -f arkdiag

.PHONY: all clean
