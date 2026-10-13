#include "../include/ark_boot.h"

EFI_STATUS fs_open_volume(EFI_HANDLE ImageHandle, EFI_FILE_HANDLE *out_root) {
    EFI_STATUS status;
    EFI_LOADED_IMAGE *loaded_image = NULL;
    EFI_FILE_HANDLE root = NULL;

    if (!out_root) {
        return EFI_INVALID_PARAMETER;
    }

    status = BS->HandleProtocol(ImageHandle, &gEfiLoadedImageProtocolGuid, (VOID **)&loaded_image);
    if (EFI_ERROR(status) || !loaded_image) {
        serial_print("[ARKBOOT] Error: Failed to locate LoadedImageProtocol on boot handle. Status: ");
        serial_print_hex((UINT64)status);
        serial_print("\r\n");
        return status;
    }

    root = LibOpenRoot(loaded_image->DeviceHandle);
    if (!root) {
        serial_print("[ARKBOOT] Error: LibOpenRoot failed on boot device handle.\r\n");
        return EFI_DEVICE_ERROR;
    }

    *out_root = root;
    return EFI_SUCCESS;
}

EFI_STATUS fs_read_file(EFI_FILE_HANDLE root, const CHAR16 *path, VOID **out_buf, UINT64 *out_size) {
    EFI_STATUS status;
    EFI_FILE_HANDLE file = NULL;
    EFI_FILE_INFO *info = NULL;
    UINT64 file_size = 0;
    UINTN pages = 0;
    EFI_PHYSICAL_ADDRESS alloc_addr = 0x3E000000;
    UINTN read_size = 0;

    if (!root || !path || !out_buf || !out_size) {
        return EFI_INVALID_PARAMETER;
    }

    status = root->Open(root, &file, (CHAR16 *)path, EFI_FILE_MODE_READ, 0);
    if (EFI_ERROR(status) || !file) {
        return status;
    }

    info = LibFileInfo(file);
    if (!info) {
        file->Close(file);
        return EFI_DEVICE_ERROR;
    }

    file_size = info->FileSize;
    FreePool(info);

    if (file_size == 0) {
        file->Close(file);
        return EFI_NOT_FOUND;
    }

    pages = (UINTN)((file_size + 0xFFF) / 4096);
    status = BS->AllocatePages(AllocateMaxAddress, EfiLoaderData, pages, &alloc_addr);
    if (EFI_ERROR(status)) {
        serial_print("[ARKBOOT] Error: Failed to allocate memory pages for file.\r\n");
        file->Close(file);
        return status;
    }

    read_size = (UINTN)file_size;
    status = file->Read(file, &read_size, (VOID *)(UINTN)alloc_addr);
    file->Close(file);

    if (EFI_ERROR(status) || read_size != file_size) {
        BS->FreePages(alloc_addr, pages);
        return EFI_DEVICE_ERROR;
    }

    *out_buf = (VOID *)(UINTN)alloc_addr;
    *out_size = file_size;
    return EFI_SUCCESS;
}

void fs_free_file(VOID *buf, UINT64 size) {
    if (buf && size > 0) {
        UINTN pages = (UINTN)((size + 0xFFF) / 4096);
        BS->FreePages((EFI_PHYSICAL_ADDRESS)(UINTN)buf, pages);
    }
}
