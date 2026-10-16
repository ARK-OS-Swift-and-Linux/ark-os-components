SWIFTC ?= swiftc
SWIFTFLAGS = -O -static-stdlib -I ../../runtime/arkrt/include

SIGNALS_O = ../../runtime/arkrt/signals.o

all: arkdiag

$(SIGNALS_O):
	$(MAKE) -C ../../runtime/arkrt signals.o

arkdiag: main.swift $(SIGNALS_O)
	$(SWIFTC) $(SWIFTFLAGS) main.swift $(SIGNALS_O) -o $@

# ==============================================================================
# Target Build Configuration (x86_64-swift-linux-musl)
# ==============================================================================
TARGET_TRIPLE ?= x86_64-swift-linux-musl
SWIFT_SDKS_DIR ?= $(HOME)/.swiftpm/swift-sdks
SWIFT_SDK_BUNDLE ?= $(firstword $(wildcard $(SWIFT_SDKS_DIR)/*static-linux*.artifactbundle))
TARGET_SYSROOT ?= $(firstword $(wildcard $(SWIFT_SDK_BUNDLE)/*/swift-linux-musl/musl-1.2.5.sdk/x86_64))
TARGET_RES_DIR ?= $(TARGET_SYSROOT)/usr/lib/swift_static
SYSROOT ?= ../../boot/build/sysroot
MIMALLOC_OBJ ?= $(SYSROOT)/lib/mimalloc.o

TARGET_SWIFTFLAGS = -target $(TARGET_TRIPLE) \
  -sdk $(TARGET_SYSROOT) \
  -resource-dir $(TARGET_RES_DIR) \
  -Xfrontend -use-static-resource-dir \
  -static-stdlib \
  -Xlinker -lswift_RegexParser \
  -O -I ../../runtime/arkrt/include

SIGNALS_TARGET_O = ../../runtime/arkrt/signals.target.o
TARGET_OUTPUT ?= arkdiag.target

$(SIGNALS_TARGET_O):
	$(MAKE) -C ../../runtime/arkrt signals.target.o TARGET_SYSROOT="$(TARGET_SYSROOT)"

$(TARGET_OUTPUT): main.swift $(SIGNALS_TARGET_O)
	@test -d "$(TARGET_SYSROOT)" || { echo "Error: TARGET_SYSROOT not found at $(TARGET_SYSROOT). Install Swift Static Linux SDK or set TARGET_SYSROOT."; exit 1; }
	@test -f "$(MIMALLOC_OBJ)" || { echo "Error: MIMALLOC_OBJ not found at $(MIMALLOC_OBJ). Specify valid MIMALLOC_OBJ=<path>."; exit 1; }
	@echo "Linking $(TARGET_OUTPUT) with mimalloc object: $(MIMALLOC_OBJ)"
	$(SWIFTC) $(TARGET_SWIFTFLAGS) main.swift $(SIGNALS_TARGET_O) "$(MIMALLOC_OBJ)" -o $@

target: $(TARGET_OUTPUT)

clean:
	rm -f arkdiag $(TARGET_OUTPUT)

.PHONY: all clean target
