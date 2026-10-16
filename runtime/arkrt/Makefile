CC ?= musl-gcc
SWIFTC ?= swiftc
TARGET_CC ?= clang

CFLAGS = -O2 -static -Wall -Wextra -Werror -I include
SWIFTFLAGS = -O -static-stdlib -I include

SWIFT_SRCS = main.swift Service.swift Supervisor.swift

# Default host-glibc build
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

# ==============================================================================
# Target Build Configuration (x86_64-swift-linux-musl)
# Uses official Swift Static Linux SDK and linkable mimalloc object.
# All paths are overridable via environment or command-line arguments.
# ==============================================================================
TARGET_TRIPLE ?= x86_64-swift-linux-musl
SWIFT_SDKS_DIR ?= $(HOME)/.swiftpm/swift-sdks
SWIFT_SDK_BUNDLE ?= $(firstword $(wildcard $(SWIFT_SDKS_DIR)/*static-linux*.artifactbundle))
TARGET_SYSROOT ?= $(firstword $(wildcard $(SWIFT_SDK_BUNDLE)/*/swift-linux-musl/musl-1.2.5.sdk/x86_64))
TARGET_RES_DIR ?= $(TARGET_SYSROOT)/usr/lib/swift_static

# Path to the verified mimalloc object (configurable)
SYSROOT ?= ../../boot/build/sysroot
MIMALLOC_OBJ ?= $(SYSROOT)/lib/mimalloc.o

TARGET_CFLAGS = -target $(TARGET_TRIPLE) --sysroot=$(TARGET_SYSROOT) -O2 -Wall -Wextra -Werror -I include
TARGET_LDFLAGS ?= -static
TARGET_SWIFTFLAGS = -target $(TARGET_TRIPLE) \
  -sdk $(TARGET_SYSROOT) \
  -resource-dir $(TARGET_RES_DIR) \
  -Xfrontend -use-static-resource-dir \
  -static-stdlib \
  -Xlinker -lswift_RegexParser \
  -O -I include

TARGET_OUTPUT ?= arkrt-swift-target

signals.target.o: signals.c include/signals.h
	@test -d "$(TARGET_SYSROOT)" || { echo "Error: TARGET_SYSROOT not found. Install Swift Static Linux SDK or set TARGET_SYSROOT."; exit 1; }
	$(TARGET_CC) $(TARGET_CFLAGS) -c $< -o $@

starter.target: starter.c
	@test -d "$(TARGET_SYSROOT)" || { echo "Error: TARGET_SYSROOT not found at $(TARGET_SYSROOT)."; exit 1; }
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) $< -o $@

$(TARGET_OUTPUT): $(SWIFT_SRCS) signals.target.o include/module.modulemap
	@test -d "$(TARGET_SYSROOT)" || { echo "Error: TARGET_SYSROOT not found at $(TARGET_SYSROOT). Install Swift Static Linux SDK or set TARGET_SYSROOT."; exit 1; }
	@test -f "$(MIMALLOC_OBJ)" || { echo "Error: MIMALLOC_OBJ not found at $(MIMALLOC_OBJ). Specify valid MIMALLOC_OBJ=<path>."; exit 1; }
	@echo "Linking $(TARGET_OUTPUT) with mimalloc object: $(MIMALLOC_OBJ)"
	$(SWIFTC) $(TARGET_SWIFTFLAGS) $(SWIFT_SRCS) signals.target.o "$(MIMALLOC_OBJ)" -o $@

target: $(TARGET_OUTPUT)

test_supervisor.target: test_supervisor.swift Service.swift Supervisor.swift signals.target.o include/module.modulemap
	@test -d "$(TARGET_SYSROOT)" || { echo "Error: TARGET_SYSROOT not found at $(TARGET_SYSROOT). Install Swift Static Linux SDK or set TARGET_SYSROOT."; exit 1; }
	@test -f "$(MIMALLOC_OBJ)" || { echo "Error: MIMALLOC_OBJ not found at $(MIMALLOC_OBJ). Specify valid MIMALLOC_OBJ=<path>."; exit 1; }
	@echo "Linking test_supervisor.target with mimalloc object: $(MIMALLOC_OBJ)"
	$(SWIFTC) $(TARGET_SWIFTFLAGS) test_supervisor.swift Service.swift Supervisor.swift signals.target.o "$(MIMALLOC_OBJ)" -o $@

test-target: test_supervisor.target
	./test_supervisor.target

clean:
	rm -f starter arkrt-swift test_supervisor signals.o signals.target.o $(TARGET_OUTPUT) starter.target test_supervisor.target

.PHONY: all clean test target test-target

