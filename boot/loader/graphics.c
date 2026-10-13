#include "../include/ark_boot.h"

EFI_STATUS graphics_init(EFI_GRAPHICS_OUTPUT_PROTOCOL **out_gop) {
    EFI_STATUS status;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;

    if (!out_gop) {
        return EFI_INVALID_PARAMETER;
    }

    status = LibLocateProtocol(&gEfiGraphicsOutputProtocolGuid, (VOID **)&gop);
    if (EFI_ERROR(status) || !gop) {
        return status;
    }

    if (!gop->Mode || !gop->Mode->Info) {
        return EFI_DEVICE_ERROR;
    }

    *out_gop = gop;
    return EFI_SUCCESS;
}

EFI_STATUS graphics_clear_screen(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop) {
    UINT32 width;
    UINT32 height;
    UINT32 stride;
    volatile UINT32 *fb;
    UINT32 total_pixels;
    UINT32 i;

    if (!gop || !gop->Mode || !gop->Mode->Info) {
        return EFI_INVALID_PARAMETER;
    }

    if (gop->Mode->FrameBufferBase == 0) {
        return EFI_DEVICE_ERROR;
    }

    width = gop->Mode->Info->HorizontalResolution;
    height = gop->Mode->Info->VerticalResolution;
    stride = gop->Mode->Info->PixelsPerScanLine;
    if (stride == 0) {
        stride = width;
    }

    fb = (volatile UINT32 *)(UINTN)gop->Mode->FrameBufferBase;
    total_pixels = stride * height;

    for (i = 0; i < total_pixels; i++) {
        fb[i] = 0x00000000;
    }

    return EFI_SUCCESS;
}

EFI_STATUS graphics_draw_white_dot(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop) {
    UINT32 width;
    UINT32 height;
    UINT32 stride;
    UINT32 cx;
    UINT32 cy;
    UINT32 white_pixel;
    volatile UINT32 *fb;
    INT32 r;
    INT32 dx;
    INT32 dy;

    if (!gop || !gop->Mode || !gop->Mode->Info) {
        return EFI_INVALID_PARAMETER;
    }

    if (gop->Mode->FrameBufferBase == 0) {
        return EFI_DEVICE_ERROR;
    }

    width = gop->Mode->Info->HorizontalResolution;
    height = gop->Mode->Info->VerticalResolution;
    stride = gop->Mode->Info->PixelsPerScanLine;
    if (stride == 0) {
        stride = width;
    }

    cx = width / 2;
    cy = height / 2;
    r = ARKBOOT_DOT_RADIUS;

    switch (gop->Mode->Info->PixelFormat) {
        case PixelRedGreenBlueReserved8BitPerColor:
        case PixelBlueGreenRedReserved8BitPerColor:
            white_pixel = 0x00FFFFFF;
            break;
        case PixelBitMask:
            white_pixel = gop->Mode->Info->PixelInformation.RedMask |
                          gop->Mode->Info->PixelInformation.GreenMask |
                          gop->Mode->Info->PixelInformation.BlueMask;
            break;
        default:
            white_pixel = 0x00FFFFFF;
            break;
    }

    fb = (volatile UINT32 *)(UINTN)gop->Mode->FrameBufferBase;

    for (dy = -r; dy <= r; dy++) {
        for (dx = -r; dx <= r; dx++) {
            if ((dx * dx + dy * dy) <= (r * r)) {
                INT32 px = (INT32)cx + dx;
                INT32 py = (INT32)cy + dy;

                if (px >= 0 && (UINT32)px < width && py >= 0 && (UINT32)py < height) {
                    fb[(UINT32)py * stride + (UINT32)px] = white_pixel;
                }
            }
        }
    }

    return EFI_SUCCESS;
}
