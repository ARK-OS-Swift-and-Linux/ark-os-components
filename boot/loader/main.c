#include "../include/ark_boot.h"

EFI_STATUS
EFIAPI
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
  EFI_STATUS status;
  EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;

  InitializeLib(ImageHandle, SystemTable);

  serial_init();
  serial_print("[ARKBOOT] Stage A: ARK-OS UEFI Bootloader starting...\r\n");

  status = graphics_init(&gop);
  if (EFI_ERROR(status) || !gop) {
    serial_print("[ARKBOOT] Fatal: Failed to locate or initialize UEFI "
                 "Graphics Output Protocol.\r\n");
    serial_print("[ARKBOOT] Status code: ");
    serial_print_hex((UINT64)status);
    serial_print("\r\n");
    for (;;) {
      BS->Stall(1000000);
    }
  }

  serial_print("[ARKBOOT] GOP initialized successfully.\r\n");
  serial_print("[ARKBOOT] Resolution: ");
  serial_print_hex((UINT64)gop->Mode->Info->HorizontalResolution);
  serial_print(" x ");
  serial_print_hex((UINT64)gop->Mode->Info->VerticalResolution);
  serial_print(", Stride: ");
  serial_print_hex((UINT64)gop->Mode->Info->PixelsPerScanLine);
  serial_print("\r\n");
  serial_print("[ARKBOOT] FrameBuffer Base: ");
  serial_print_hex((UINT64)gop->Mode->FrameBufferBase);
  serial_print("\r\n");

  status = graphics_clear_screen(gop);
  if (EFI_ERROR(status)) {
    serial_print(
        "[ARKBOOT] Warning: Failed to clear framebuffer to black.\r\n");
  } else {
    serial_print("[ARKBOOT] Framebuffer cleared to black.\r\n");
  }

  status = graphics_draw_white_dot(gop);
  if (EFI_ERROR(status)) {
    serial_print("[ARKBOOT] Warning: Failed to draw centered white dot.\r\n");
  } else {
    serial_print("[ARKBOOT] Rendered centered solid white dot.\r\n");
  }

  serial_print("[ARKBOOT] Display holding stationary. \r\n");

  for (;;) {
    BS->Stall(1000000);
  }

  return EFI_SUCCESS;
}
