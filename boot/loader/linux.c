#include "../include/ark_boot.h"

static UINT64 boot_gdt[4] __attribute__((aligned(16))) = {
    0,                          /* 0x00: null descriptor */
    0,                          /* 0x08: unused / reserved */
    0x00af9a000000ffffULL,      /* 0x10: 64-bit code segment (exec/read, L=1, D=0) */
    0x00cf92000000ffffULL       /* 0x18: 64-bit data segment (read/write, D=1, L=0) */
};

struct gdtr_t {
    UINT16 limit;
    UINT64 base;
} __attribute__((packed));

static void parse_color_mask(UINT32 mask, UINT8 *pos, UINT8 *size) {
    UINT8 p = 0;
    UINT8 s = 0;
    if (mask == 0) {
        *pos = 0;
        *size = 0;
        return;
    }
    while ((mask & 1) == 0) {
        p++;
        mask >>= 1;
    }
    while ((mask & 1) == 1) {
        s++;
        mask >>= 1;
    }
    *pos = p;
    *size = s;
}

static void linux_setup_screen_info(struct boot_params *bp, EFI_GRAPHICS_OUTPUT_PROTOCOL *gop) {
    UINT32 stride;

    if (!bp || !gop || !gop->Mode || !gop->Mode->Info) {
        return;
    }

    stride = gop->Mode->Info->PixelsPerScanLine;
    if (stride == 0) {
        stride = gop->Mode->Info->HorizontalResolution;
    }

    bp->screen_info.orig_video_isVGA = VIDEO_TYPE_EFI;
    bp->screen_info.flags = VIDEO_FLAGS_NOCURSOR;
    bp->screen_info.capabilities = VIDEO_CAPABILITY_64BIT_BASE;

    bp->screen_info.lfb_base = (UINT32)gop->Mode->FrameBufferBase;
    bp->screen_info.ext_lfb_base = (UINT32)(gop->Mode->FrameBufferBase >> 32);

    bp->screen_info.lfb_width = (UINT16)gop->Mode->Info->HorizontalResolution;
    bp->screen_info.lfb_height = (UINT16)gop->Mode->Info->VerticalResolution;
    bp->screen_info.lfb_depth = 32;
    bp->screen_info.lfb_linelength = (UINT16)(stride * 4);
    bp->screen_info.lfb_size = (UINT32)(gop->Mode->FrameBufferSize ? 
                                       gop->Mode->FrameBufferSize : 
                                       (stride * 4 * gop->Mode->Info->VerticalResolution));

    switch (gop->Mode->Info->PixelFormat) {
        case PixelBlueGreenRedReserved8BitPerColor:
            bp->screen_info.blue_pos = 0;
            bp->screen_info.blue_size = 8;
            bp->screen_info.green_pos = 8;
            bp->screen_info.green_size = 8;
            bp->screen_info.red_pos = 16;
            bp->screen_info.red_size = 8;
            bp->screen_info.rsvd_pos = 24;
            bp->screen_info.rsvd_size = 8;
            break;
        case PixelRedGreenBlueReserved8BitPerColor:
            bp->screen_info.red_pos = 0;
            bp->screen_info.red_size = 8;
            bp->screen_info.green_pos = 8;
            bp->screen_info.green_size = 8;
            bp->screen_info.blue_pos = 16;
            bp->screen_info.blue_size = 8;
            bp->screen_info.rsvd_pos = 24;
            bp->screen_info.rsvd_size = 8;
            break;
        case PixelBitMask:
            parse_color_mask(gop->Mode->Info->PixelInformation.RedMask,
                             &bp->screen_info.red_pos, &bp->screen_info.red_size);
            parse_color_mask(gop->Mode->Info->PixelInformation.GreenMask,
                             &bp->screen_info.green_pos, &bp->screen_info.green_size);
            parse_color_mask(gop->Mode->Info->PixelInformation.BlueMask,
                             &bp->screen_info.blue_pos, &bp->screen_info.blue_size);
            parse_color_mask(gop->Mode->Info->PixelInformation.ReservedMask,
                             &bp->screen_info.rsvd_pos, &bp->screen_info.rsvd_size);
            break;
        default:
            bp->screen_info.blue_pos = 0;
            bp->screen_info.blue_size = 8;
            bp->screen_info.green_pos = 8;
            bp->screen_info.green_size = 8;
            bp->screen_info.red_pos = 16;
            bp->screen_info.red_size = 8;
            bp->screen_info.rsvd_pos = 24;
            bp->screen_info.rsvd_size = 8;
            break;
    }
}

__attribute__((noreturn)) static void linux_jump_to_kernel(UINT64 entry_point, UINT64 boot_params_addr) {
    struct gdtr_t gdtr;
    gdtr.limit = sizeof(boot_gdt) - 1;
    gdtr.base = (UINT64)(UINTN)&boot_gdt[0];

    __asm__ volatile (
        "cli\n\t"
        "lgdt %0\n\t"
        "movw $0x18, %%ax\n\t"
        "movw %%ax, %%ds\n\t"
        "movw %%ax, %%es\n\t"
        "movw %%ax, %%ss\n\t"
        "movw %%ax, %%fs\n\t"
        "movw %%ax, %%gs\n\t"
        "pushq $0x10\n\t"
        "leaq 1f(%%rip), %%rax\n\t"
        "pushq %%rax\n\t"
        "lretq\n\t"
        "1:\n\t"
        "movq %1, %%rsi\n\t"
        "jmp *%2\n\t"
        :
        : "m"(gdtr), "r"(boot_params_addr), "r"(entry_point)
        : "rax", "rsi", "memory"
    );

    for (;;) {
        __asm__ volatile ("hlt");
    }
}

EFI_STATUS linux_boot(
    EFI_HANDLE ImageHandle,
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop,
    VOID *kernel_buf,
    UINT64 kernel_size,
    VOID *initrd_buf,
    UINT64 initrd_size,
    const char *cmdline
) {
    EFI_STATUS status;
    struct setup_header *hdr;
    UINT32 setup_sects;
    UINT64 setup_size;
    UINT32 init_size;
    UINTN kernel_pages;
    UINTN alloc_pages;
    EFI_PHYSICAL_ADDRESS kernel_alloc = 0xFFFFFFFF;
    EFI_PHYSICAL_ADDRESS kernel_aligned;
    EFI_PHYSICAL_ADDRESS initrd_addr = 0x7FFFFFFF;
    EFI_PHYSICAL_ADDRESS bp_addr = 0x7FFFFFFF;
    EFI_PHYSICAL_ADDRESS cmdline_addr = 0x7FFFFFFF;
    EFI_PHYSICAL_ADDRESS mmap_addr = 0xFFFFFFFF;
    struct boot_params *bp;
    UINTN mmap_size = 0;
    EFI_MEMORY_DESCRIPTOR *mmap = NULL;
    UINTN map_key = 0;
    UINTN desc_size = 0;
    UINT32 desc_version = 0;
    UINTN cmdline_len = 0;
    int retry;

    if (!kernel_buf || kernel_size < 1024) {
        serial_print("[ARKBOOT] Error: Invalid kernel buffer.\r\n");
        return EFI_INVALID_PARAMETER;
    }

    hdr = (struct setup_header *)((UINT8 *)kernel_buf + 0x1f1);

    if (hdr->boot_flag != SETUP_BOOT_FLAG) {
        serial_print("[ARKBOOT] Error: Invalid kernel boot flag magic (expected 0xAA55).\r\n");
        return EFI_UNSUPPORTED;
    }

    if (hdr->header != SETUP_HDR_MAGIC) {
        serial_print("[ARKBOOT] Error: Invalid kernel header signature (expected 'HdrS').\r\n");
        return EFI_UNSUPPORTED;
    }

    if (hdr->version < SETUP_MIN_VERSION) {
        serial_print("[ARKBOOT] Error: Kernel boot protocol version too old.\r\n");
        return EFI_UNSUPPORTED;
    }

    if (!(hdr->xloadflags & XLF_KERNEL_64)) {
        serial_print("[ARKBOOT] Error: Kernel does not support 64-bit boot protocol.\r\n");
        return EFI_UNSUPPORTED;
    }

    setup_sects = hdr->setup_sects ? hdr->setup_sects : 4;
    setup_size = (setup_sects + 1) * 512;

    if (kernel_size <= setup_size) {
        serial_print("[ARKBOOT] Error: Kernel size smaller than setup sectors.\r\n");
        return EFI_INVALID_PARAMETER;
    }

    init_size = hdr->init_size;
    if (init_size < (kernel_size - setup_size)) {
        init_size = (UINT32)(kernel_size - setup_size);
    }

    serial_print("[ARKBOOT] Kernel Protocol: ");
    serial_print_hex((UINT64)hdr->version);
    serial_print(", Setup Size: ");
    serial_print_dec(setup_size);
    serial_print(" bytes, Init Size: ");
    serial_print_dec((UINT64)init_size);
    serial_print(" bytes\r\n");

    /* Allocate runtime memory for kernel protected-mode code with 2MB alignment margin */
    kernel_pages = (init_size + 0xFFF) / 4096;
    alloc_pages = kernel_pages + 512; /* +2MB alignment buffer */

    status = BS->AllocatePages(AllocateMaxAddress, EfiLoaderData, alloc_pages, &kernel_alloc);
    if (EFI_ERROR(status)) {
        /* Fall back to AllocateAnyPages if AllocateMaxAddress fails */
        status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, alloc_pages, &kernel_alloc);
    }
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Error: Failed to allocate kernel execution memory.\r\n");
        return status;
    }

    kernel_aligned = (kernel_alloc + 0x1FFFFFULL) & ~0x1FFFFFULL;
    serial_print("[ARKBOOT] Kernel 2MB-aligned destination: ");
    serial_print_hex((UINT64)kernel_aligned);
    serial_print("\r\n");

    /* Copy protected-mode code into execution buffer */
    CopyMem((VOID *)(UINTN)kernel_aligned, (UINT8 *)kernel_buf + setup_size, kernel_size - setup_size);
    if (init_size > (kernel_size - setup_size)) {
        SetMem((VOID *)(UINTN)(kernel_aligned + (kernel_size - setup_size)),
               init_size - (kernel_size - setup_size), 0);
    }

    /* Allocate and copy initramfs if provided */
    if (initrd_buf && initrd_size > 0) {
        UINTN initrd_pages = (initrd_size + 0xFFF) / 4096;
        status = BS->AllocatePages(AllocateMaxAddress, EfiLoaderData, initrd_pages, &initrd_addr);
        if (EFI_ERROR(status)) {
            status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, initrd_pages, &initrd_addr);
        }
        if (EFI_ERROR(status)) {
            serial_print("[ARKBOOT] Error: Failed to allocate initramfs memory.\r\n");
            BS->FreePages(kernel_alloc, alloc_pages);
            return status;
        }
        CopyMem((VOID *)(UINTN)initrd_addr, initrd_buf, initrd_size);
        serial_print("[ARKBOOT] Initramfs loaded at: ");
        serial_print_hex((UINT64)initrd_addr);
        serial_print(" (");
        serial_print_dec(initrd_size);
        serial_print(" bytes)\r\n");
    } else {
        initrd_addr = 0;
        initrd_size = 0;
    }

    /* Allocate boot_params zero page */
    status = BS->AllocatePages(AllocateMaxAddress, EfiLoaderData, 1, &bp_addr);
    if (EFI_ERROR(status)) {
        status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, 1, &bp_addr);
    }
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Error: Failed to allocate zero page.\r\n");
        BS->FreePages(kernel_alloc, alloc_pages);
        return status;
    }
    SetMem((VOID *)(UINTN)bp_addr, 4096, 0);
    bp = (struct boot_params *)(UINTN)bp_addr;

    /* Allocate kernel command-line buffer */
    status = BS->AllocatePages(AllocateMaxAddress, EfiLoaderData, 1, &cmdline_addr);
    if (EFI_ERROR(status)) {
        status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, 1, &cmdline_addr);
    }
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Error: Failed to allocate command line buffer.\r\n");
        BS->FreePages(kernel_alloc, alloc_pages);
        BS->FreePages(bp_addr, 1);
        return status;
    }
    SetMem((VOID *)(UINTN)cmdline_addr, 4096, 0);

    if (cmdline) {
        while (cmdline[cmdline_len] && cmdline_len < 2047) {
            ((char *)(UINTN)cmdline_addr)[cmdline_len] = cmdline[cmdline_len];
            cmdline_len++;
        }
        ((char *)(UINTN)cmdline_addr)[cmdline_len] = '\0';
    }

    serial_print("[ARKBOOT] Kernel Cmdline: \"");
    serial_print((const char *)(UINTN)cmdline_addr);
    serial_print("\"\r\n");

    /* Populate setup header in boot_params */
    CopyMem(&bp->hdr, hdr, sizeof(struct setup_header));
    bp->hdr.type_of_loader = 0xFF; /* undefined / custom bootloader */
    bp->hdr.loadflags |= LOADED_HIGH;
    bp->hdr.code32_start = (UINT32)(UINTN)kernel_aligned;
    bp->hdr.cmd_line_ptr = (UINT32)(UINTN)cmdline_addr;
    bp->ext_cmd_line_ptr = (UINT32)((UINT64)(UINTN)cmdline_addr >> 32);

    if (initrd_size > 0) {
        bp->hdr.ramdisk_image = (UINT32)(UINTN)initrd_addr;
        bp->hdr.ramdisk_size = (UINT32)initrd_size;
        bp->ext_ramdisk_image = (UINT32)((UINT64)(UINTN)initrd_addr >> 32);
        bp->ext_ramdisk_size = (UINT32)((UINT64)initrd_size >> 32);
    }

    bp->sentinel = 0;

    /* Populate screen_info for framebuffer persistence */
    linux_setup_screen_info(bp, gop);

    /* Allocate buffer for memory map retrieval */
    status = BS->GetMemoryMap(&mmap_size, NULL, &map_key, &desc_size, &desc_version);
    mmap_size += 4096 * 4; /* Reserve generous slack space for allocations */
    status = BS->AllocatePages(AllocateMaxAddress, EfiLoaderData, (mmap_size + 0xFFF) / 4096, &mmap_addr);
    if (EFI_ERROR(status)) {
        status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, (mmap_size + 0xFFF) / 4096, &mmap_addr);
    }
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Error: Failed to allocate memory map buffer.\r\n");
        return status;
    }
    mmap = (EFI_MEMORY_DESCRIPTOR *)(UINTN)mmap_addr;

    serial_print("[ARKBOOT] Preparing ExitBootServices handoff...\r\n");

    /* ExitBootServices handoff loop */
    for (retry = 0; retry < 5; retry++) {
        UINTN cur_mmap_size = mmap_size;
        UINT8 *p;
        UINTN entries = 0;
        UINTN off;

        status = BS->GetMemoryMap(&cur_mmap_size, mmap, &map_key, &desc_size, &desc_version);
        if (EFI_ERROR(status)) {
            continue;
        }

        /* Populate efi_info */
        bp->efi_info.efi_loader_signature = EFI64_LOADER_SIGNATURE;
        bp->efi_info.efi_systab = (UINT32)(UINTN)ST;
        bp->efi_info.efi_systab_hi = (UINT32)((UINT64)(UINTN)ST >> 32);
        bp->efi_info.efi_memdesc_size = (UINT32)desc_size;
        bp->efi_info.efi_memdesc_version = (UINT32)desc_version;
        bp->efi_info.efi_memmap = (UINT32)(UINTN)mmap;
        bp->efi_info.efi_memmap_hi = (UINT32)((UINT64)(UINTN)mmap >> 32);
        bp->efi_info.efi_memmap_size = (UINT32)cur_mmap_size;

        /* Populate e820 memory map */
        p = (UINT8 *)mmap;
        for (off = 0; off < cur_mmap_size && entries < E820_MAX_ENTRIES_ZEROPAGE; off += desc_size) {
            EFI_MEMORY_DESCRIPTOR *desc = (EFI_MEMORY_DESCRIPTOR *)(p + off);
            UINT32 type = 2; /* E820_RESERVED */
            switch (desc->Type) {
                case EfiLoaderCode:
                case EfiLoaderData:
                case EfiBootServicesCode:
                case EfiBootServicesData:
                case EfiConventionalMemory:
                    type = 1; /* E820_RAM */
                    break;
                case EfiACPIReclaimMemory:
                    type = 3; /* E820_ACPI */
                    break;
                case EfiACPIMemoryNVS:
                    type = 4; /* E820_NVS */
                    break;
                case EfiUnusableMemory:
                    type = 5; /* E820_UNUSABLE */
                    break;
                default:
                    type = 2; /* E820_RESERVED */
                    break;
            }
            bp->e820_table[entries].addr = desc->PhysicalStart;
            bp->e820_table[entries].size = desc->NumberOfPages * 4096;
            bp->e820_table[entries].type = type;
            entries++;
        }
        bp->e820_entries = (UINT8)entries;

        status = BS->ExitBootServices(ImageHandle, map_key);
        if (!EFI_ERROR(status)) {
            break;
        }
    }

    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Fatal: ExitBootServices failed after multiple attempts.\r\n");
        return status;
    }

    serial_print("[ARKBOOT] ExitBootServices succeeded.\r\n");
    serial_print("[ARKBOOT] Transferring control to Linux 64-bit startup...\r\n");

    /* Transfer control to Linux startup_64 (offset 0x200 relative to protected-mode base) */
    linux_jump_to_kernel((UINT64)(UINTN)(kernel_aligned + 0x200), (UINT64)(UINTN)bp);

    return EFI_SUCCESS;
}
