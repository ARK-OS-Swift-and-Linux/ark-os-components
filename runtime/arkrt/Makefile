CC = musl-gcc
SWIFTC = swiftc

CFLAGS = -O2 -static -Wall -Wextra -Werror
SWIFTFLAGS = -O -static-stdlib -I include -Xcc -I/usr/lib/musl/include

SWIFT_SRCS = main.swift Service.swift Supervisor.swift

all: starter arkrt-swift

starter: starter.c
	$(CC) $(CFLAGS) $< -o $@

arkrt-swift: $(SWIFT_SRCS) include/module.modulemap
	$(SWIFTC) $(SWIFTFLAGS) $(SWIFT_SRCS) -o $@

test: test_supervisor
	./test_supervisor

test_supervisor: test_supervisor.swift Service.swift Supervisor.swift include/module.modulemap
	$(SWIFTC) $(SWIFTFLAGS) test_supervisor.swift Service.swift Supervisor.swift -o $@

clean:
	rm -f starter arkrt-swift test_supervisor

.PHONY: all clean test
