#include "../include/ark_boot.h"

#define COM1_PORT 0x3F8

static inline void outb(UINT16 port, UINT8 val) {
    __asm__ volatile ("outb %b0, %w1" : : "a"(val), "Nd"(port));
}

void serial_init(void) {
    /* COM1 port diagnostic initialization (compatible with firmware/QEMU) */
}

void serial_putc(char c) {
    outb(COM1_PORT, (UINT8)c);
}

void serial_print(const char *str) {
    if (!str) {
        return;
    }
    while (*str) {
        if (*str == '\n') {
            serial_putc('\r');
        }
        serial_putc(*str++);
    }
}

void serial_print_hex(UINT64 val) {
    const char hex_chars[] = "0123456789ABCDEF";
    serial_print("0x");
    for (int i = 60; i >= 0; i -= 4) {
        serial_putc(hex_chars[(val >> i) & 0xF]);
    }
}
