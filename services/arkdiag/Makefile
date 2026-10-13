SWIFTC = swiftc
SWIFTFLAGS = -O -static-stdlib -I ../../runtime/arkrt/include -Xcc -I/usr/lib/musl/include

all: arkdiag

arkdiag: main.swift
	$(SWIFTC) $(SWIFTFLAGS) $< -o $@

clean:
	rm -f arkdiag

.PHONY: all clean
