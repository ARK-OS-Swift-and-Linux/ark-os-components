CC = musl-gcc
SWIFTC = swiftc

CFLAGS = -O2 -static -Wall -Wextra -Werror
SWIFTFLAGS = -O -static-stdlib -I include -Xcc -I/usr/lib/musl/include

all: starter arkrt-swift

starter: starter.c
	$(CC) $(CFLAGS) $< -o $@

arkrt-swift: main.swift include/module.modulemap
	$(SWIFTC) $(SWIFTFLAGS) $< -o $@

clean:
	rm -f starter arkrt-swift

.PHONY: all clean
