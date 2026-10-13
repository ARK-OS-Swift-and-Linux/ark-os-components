#ifndef ARK_BOOT_H
#define ARK_BOOT_H

#include <efi.h>
#include <efilib.h>

#define ARKBOOT_VERSION "0.1.0"
#define ARKBOOT_DOT_RADIUS 15

/* Graphics Subsystem Prototypes */
EFI_STATUS graphics_init(EFI_GRAPHICS_OUTPUT_PROTOCOL **out_gop);
EFI_STATUS graphics_clear_screen(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop);
EFI_STATUS graphics_draw_white_dot(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop);

/* Serial Diagnostics Prototypes (headless, COM1/0x3F8) */
void serial_init(void);
void serial_putc(char c);
void serial_print(const char *str);
void serial_print_hex(UINT64 val);

#endif /* ARK_BOOT_H */
