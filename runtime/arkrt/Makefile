CC = musl-gcc
SWIFTC = swiftc

CFLAGS = -O2 -static -Wall -Wextra -Werror -I include
SWIFTFLAGS = -O -static-stdlib -I include -Xcc -I/usr/lib/musl/include -Xcc -Iinclude

SWIFT_SRCS = main.swift Service.swift Supervisor.swift

all: starter arkrt-swift

signals.o: signals.c include/signals.h
	$(CC) $(CFLAGS) -c $< -o $@

starter: starter.c
	$(CC) $(CFLAGS) $< -o $@

arkrt-swift: $(SWIFT_SRCS) signals.o include/module.modulemap
	$(SWIFTC) $(SWIFTFLAGS) $(SWIFT_SRCS) signals.o -o $@

test: test_supervisor
	./test_supervisor

test_supervisor: test_supervisor.swift Service.swift Supervisor.swift signals.o include/module.modulemap
	$(SWIFTC) $(SWIFTFLAGS) test_supervisor.swift Service.swift Supervisor.swift signals.o -o $@

clean:
	rm -f starter arkrt-swift test_supervisor signals.o

.PHONY: all clean test
