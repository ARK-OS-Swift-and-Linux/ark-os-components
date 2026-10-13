#ifndef ARK_BOOT_H
#define ARK_BOOT_H

#include <efi.h>
#include <efilib.h>

#define ARKBOOT_VERSION "0.2.0"
#define ARKBOOT_DOT_RADIUS 15

/* Linux Setup Header / Boot Protocol Constants */
#define SETUP_BOOT_FLAG             0xAA55
#define SETUP_HDR_MAGIC             0x53726448  /* "HdrS" */
#define SETUP_MIN_VERSION           0x0200      /* Minimum supported protocol 2.00 */
#define XLF_KERNEL_64               (1 << 0)    /* 64-bit entry point available */
#define LOADED_HIGH                 (1 << 0)
#define EFI64_LOADER_SIGNATURE      0x34364c45  /* "EL64" */
#define E820_MAX_ENTRIES_ZEROPAGE   128

#define VIDEO_TYPE_EFI              0x70
#define VIDEO_FLAGS_NOCURSOR        (1 << 0)
#define VIDEO_CAPABILITY_64BIT_BASE (1 << 1)

/* Linux Screen Info (Offset 0x000 in boot_params) */
struct screen_info {
    UINT8  orig_x;              /* 0x00 */
    UINT8  orig_y;              /* 0x01 */
    UINT16 ext_mem_k;           /* 0x02 */
    UINT16 orig_video_page;     /* 0x04 */
    UINT8  orig_video_mode;     /* 0x06 */
    UINT8  orig_video_cols;     /* 0x07 */
    UINT8  flags;               /* 0x08 */
    UINT8  unused2;             /* 0x09 */
    UINT16 orig_video_ega_bx;   /* 0x0a */
    UINT16 unused3;             /* 0x0c */
    UINT8  orig_video_lines;    /* 0x0e */
    UINT8  orig_video_isVGA;    /* 0x0f */
    UINT16 orig_video_points;   /* 0x10 */
    UINT16 lfb_width;           /* 0x12 */
    UINT16 lfb_height;          /* 0x14 */
    UINT16 lfb_depth;           /* 0x16 */
    UINT32 lfb_base;            /* 0x18 */
    UINT32 lfb_size;            /* 0x1c */
    UINT16 cl_magic;            /* 0x20 */
    UINT16 cl_offset;           /* 0x22 */
    UINT16 lfb_linelength;      /* 0x24 */
    UINT8  red_size;            /* 0x26 */
    UINT8  red_pos;             /* 0x27 */
    UINT8  green_size;          /* 0x28 */
    UINT8  green_pos;           /* 0x29 */
    UINT8  blue_size;           /* 0x2a */
    UINT8  blue_pos;            /* 0x2b */
    UINT8  rsvd_size;           /* 0x2c */
    UINT8  rsvd_pos;            /* 0x2d */
    UINT16 vesapm_seg;          /* 0x2e */
    UINT16 vesapm_off;          /* 0x30 */
    UINT16 pages;               /* 0x32 */
    UINT16 vesa_attributes;     /* 0x34 */
    UINT32 capabilities;        /* 0x36 */
    UINT32 ext_lfb_base;        /* 0x3a */
    UINT8  _reserved[2];        /* 0x3e */
} __attribute__((packed));

/* Linux EFI Info (Offset 0x1c0 in boot_params) */
struct efi_info {
    UINT32 efi_loader_signature;
    UINT32 efi_systab;
    UINT32 efi_memdesc_size;
    UINT32 efi_memdesc_version;
    UINT32 efi_memmap;
    UINT32 efi_memmap_size;
    UINT32 efi_systab_hi;
    UINT32 efi_memmap_hi;
} __attribute__((packed));

/* Linux Setup Header (Offset 0x1f1 in boot_params) */
struct setup_header {
    UINT8  setup_sects;
    UINT16 root_flags;
    UINT32 syssize;
    UINT16 ram_size;
    UINT16 vid_mode;
    UINT16 root_dev;
    UINT16 boot_flag;
    UINT16 jump;
    UINT32 header;
    UINT16 version;
    UINT32 realmode_swtch;
    UINT16 start_sys_seg;
    UINT16 kernel_version;
    UINT8  type_of_loader;
    UINT8  loadflags;
    UINT16 setup_move_size;
    UINT32 code32_start;
    UINT32 ramdisk_image;
    UINT32 ramdisk_size;
    UINT32 bootsect_kludge;
    UINT16 heap_end_ptr;
    UINT8  ext_loader_ver;
    UINT8  ext_loader_type;
    UINT32 cmd_line_ptr;
    UINT32 initrd_addr_max;
    UINT32 kernel_alignment;
    UINT8  relocatable_kernel;
    UINT8  min_alignment;
    UINT16 xloadflags;
    UINT32 cmdline_size;
    UINT32 hardware_subarch;
    UINT64 hardware_subarch_data;
    UINT32 payload_offset;
    UINT32 payload_length;
    UINT64 setup_data;
    UINT64 pref_address;
    UINT32 init_size;
    UINT32 handover_offset;
    UINT32 kernel_info_offset;
} __attribute__((packed));

/* Linux E820 Memory Entry */
struct boot_e820_entry {
    UINT64 addr;
    UINT64 size;
    UINT32 type;
} __attribute__((packed));

/* Linux x86 Boot Parameters ("zero page", 4096 bytes) */
struct boot_params {
    struct screen_info screen_info;                     /* 0x000 */
    UINT8  _pad1[0x0c0 - sizeof(struct screen_info)];
    UINT32 ext_ramdisk_image;                           /* 0x0c0 */
    UINT32 ext_ramdisk_size;                            /* 0x0c4 */
    UINT32 ext_cmd_line_ptr;                            /* 0x0c8 */
    UINT8  _pad2[0x1c0 - 0x0cc];
    struct efi_info efi_info;                           /* 0x1c0 */
    UINT8  _pad3[0x1e8 - (0x1c0 + sizeof(struct efi_info))];
    UINT8  e820_entries;                                /* 0x1e8 */
    UINT8  eddbuf_entries;                              /* 0x1e9 */
    UINT8  edd_mbr_sig_buf_entries;                     /* 0x1ea */
    UINT8  kbd_status;                                  /* 0x1eb */
    UINT8  secure_boot;                                 /* 0x1ec */
    UINT8  _pad4[2];                                    /* 0x1ed */
    UINT8  sentinel;                                    /* 0x1ef */
    UINT8  _pad5[1];                                    /* 0x1f0 */
    struct setup_header hdr;                            /* 0x1f1 */
    UINT8  _pad6[0x2d0 - (0x1f1 + sizeof(struct setup_header))];
    struct boot_e820_entry e820_table[E820_MAX_ENTRIES_ZEROPAGE]; /* 0x2d0 */
    UINT8  _pad7[4096 - (0x2d0 + sizeof(struct boot_e820_entry) * E820_MAX_ENTRIES_ZEROPAGE)];
} __attribute__((packed));

/* Graphics Subsystem Prototypes */
EFI_STATUS graphics_init(EFI_GRAPHICS_OUTPUT_PROTOCOL **out_gop);
EFI_STATUS graphics_clear_screen(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop);
EFI_STATUS graphics_draw_white_dot(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop);

/* Serial Diagnostics Prototypes (headless COM1/0x3F8) */
void serial_init(void);
void serial_putc(char c);
void serial_print(const char *str);
void serial_print_hex(UINT64 val);
void serial_print_dec(UINT64 val);

/* File System Subsystem Prototypes */
EFI_STATUS fs_open_volume(EFI_HANDLE ImageHandle, EFI_FILE_HANDLE *out_root);
EFI_STATUS fs_read_file(EFI_FILE_HANDLE root, const CHAR16 *path, VOID **out_buf, UINT64 *out_size);
void fs_free_file(VOID *buf, UINT64 size);

/* Linux Handoff Prototypes */
EFI_STATUS linux_boot(
    EFI_HANDLE ImageHandle,
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop,
    VOID *kernel_buf,
    UINT64 kernel_size,
    VOID *initrd_buf,
    UINT64 initrd_size,
    const char *cmdline
);

#endif /* ARK_BOOT_H */
