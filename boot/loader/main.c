#include "../include/ark_boot.h"

EFI_STATUS
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS status;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;
    EFI_FILE_HANDLE root = NULL;
    VOID *kernel_buf = NULL;
    UINT64 kernel_size = 0;
    VOID *initrd_buf = NULL;
    UINT64 initrd_size = 0;
    const char *cmdline = "console=ttyS0 earlyprintk=serial,0x3f8,115200 loglevel=8 ignore_loglevel rdinit=/sbin/arkrt panic=-1";

    InitializeLib(ImageHandle, SystemTable);

    serial_init();
    serial_print("[ARKBOOT] ARK-OS UEFI Bootloader v" ARKBOOT_VERSION " initializing...\r\n");

    /* Stage A: Initialize Graphics Output Protocol */
    status = graphics_init(&gop);
    if (EFI_ERROR(status) || !gop) {
        serial_print("[ARKBOOT] Fatal: Failed to locate or initialize UEFI Graphics Output Protocol.\r\n");
        serial_print("[ARKBOOT] Status code: ");
        serial_print_hex((UINT64)status);
        serial_print("\r\n");
        for (;;) {
            BS->Stall(1000000);
        }
    }

    serial_print("[ARKBOOT] GOP initialized successfully.\r\n");
    serial_print("[ARKBOOT] Resolution: ");
    serial_print_dec((UINT64)gop->Mode->Info->HorizontalResolution);
    serial_print(" x ");
    serial_print_dec((UINT64)gop->Mode->Info->VerticalResolution);
    serial_print(", Stride: ");
    serial_print_dec((UINT64)gop->Mode->Info->PixelsPerScanLine);
    serial_print("\r\n");
    serial_print("[ARKBOOT] FrameBuffer Base: ");
    serial_print_hex((UINT64)gop->Mode->FrameBufferBase);
    serial_print("\r\n");

    /* Clear screen to solid black */
    status = graphics_clear_screen(gop);
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Warning: Failed to clear framebuffer to black.\r\n");
    } else {
        serial_print("[ARKBOOT] Framebuffer cleared to black.\r\n");
    }

    /* Render centered solid white dot (radius 15px) */
    status = graphics_draw_white_dot(gop);
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Warning: Failed to draw centered white dot.\r\n");
    } else {
        serial_print("[ARKBOOT] Rendered centered solid white dot (radius 15px).\r\n");
    }

    /* Open the EFI System Partition root volume */
    status = fs_open_volume(ImageHandle, &root);
    if (EFI_ERROR(status) || !root) {
        serial_print("[ARKBOOT] Fatal: Failed to open EFI boot volume.\r\n");
        for (;;) {
            BS->Stall(1000000);
        }
    }

    /* Locate and load kernel artifact (bzImage) */
    serial_print("[ARKBOOT] Loading Linux kernel artifact...\r\n");
    status = fs_read_file(root, L"EFI\\BOOT\\bzImage", &kernel_buf, &kernel_size);
    if (EFI_ERROR(status)) {
        status = fs_read_file(root, L"\\EFI\\BOOT\\bzImage", &kernel_buf, &kernel_size);
    }
    if (EFI_ERROR(status)) {
        status = fs_read_file(root, L"bzImage", &kernel_buf, &kernel_size);
    }
    if (EFI_ERROR(status)) {
        status = fs_read_file(root, L"\\bzImage", &kernel_buf, &kernel_size);
    }

    if (EFI_ERROR(status) || !kernel_buf || kernel_size == 0) {
        serial_print("[ARKBOOT] Fatal: Failed to locate or load bzImage from boot volume.\r\n");
        serial_print("[ARKBOOT] Status code: ");
        serial_print_hex((UINT64)status);
        serial_print("\r\n");
        for (;;) {
            BS->Stall(1000000);
        }
    }

    serial_print("[ARKBOOT] Kernel loaded successfully (");
    serial_print_dec(kernel_size);
    serial_print(" bytes).\r\n");

    /* Locate and load initramfs artifact */
    serial_print("[ARKBOOT] Loading initramfs artifact...\r\n");
    status = fs_read_file(root, L"EFI\\BOOT\\initramfs.cpio", &initrd_buf, &initrd_size);
    if (EFI_ERROR(status)) {
        status = fs_read_file(root, L"\\EFI\\BOOT\\initramfs.cpio", &initrd_buf, &initrd_size);
    }
    if (EFI_ERROR(status)) {
        status = fs_read_file(root, L"initramfs.cpio", &initrd_buf, &initrd_size);
    }
    if (EFI_ERROR(status)) {
        status = fs_read_file(root, L"\\initramfs.cpio", &initrd_buf, &initrd_size);
    }

    if (EFI_ERROR(status) || !initrd_buf || initrd_size == 0) {
        serial_print("[ARKBOOT] Notice: No initramfs found on boot volume. Booting kernel without initramfs.\r\n");
        initrd_buf = NULL;
        initrd_size = 0;
    } else {
        serial_print("[ARKBOOT] Initramfs loaded successfully (");
        serial_print_dec(initrd_size);
        serial_print(" bytes).\r\n");
    }

    /* Hand off execution to Linux kernel */
    serial_print("[ARKBOOT] Entering Linux kernel handoff...\r\n");
    status = linux_boot(ImageHandle, gop, kernel_buf, kernel_size, initrd_buf, initrd_size, cmdline);

    /* If linux_boot returns, handoff encountered a pre-ExitBootServices fatal failure */
    serial_print("[ARKBOOT] Fatal: linux_boot failed with status: ");
    serial_print_hex((UINT64)status);
    serial_print("\r\n");

    for (;;) {
        BS->Stall(1000000);
    }

    return status;
}
