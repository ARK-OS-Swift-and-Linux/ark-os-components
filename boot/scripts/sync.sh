#!/usr/bin/env bash
# ==============================================================================
# ARK-OS Artifact Synchronization Manager (`sync.sh`)
#
# Automatically discovers, verifies, downloads, and updates:
#   1. Linux Zen Kernel (from ark-os-kernel-compilation-station)
#   2. Target Sysroot (musl libc + mimalloc from ark-os-sysbuilts-compilation-station)
#
# Security & Reliability Invariants:
#   - Mandatory SHA-256 integrity checksum verification before extraction.
#   - Path traversal prevention against archive directory escape.
#   - Staging in temporary directory with post-extraction validation.
#   - Atomic promotion into place: never leaves corrupted or partial directories.
#   - Clean removal of stale files from previous versions.
#
# Usage:
#   sync.sh [all|kernel|sysbuilts|check] [target_directory]
# ==============================================================================

set -euo pipefail

MODE="${1:-all}"
CUSTOM_TARGET="${2:-}"

KERNEL_REPO="${KERNEL_REPO:-ARK-OS-Swift-and-Linux/ark-os-kernel-compilation-station}"
SYSBUILTS_REPO="${SYSBUILTS_REPO:-ARK-OS-Swift-and-Linux/ark-os-sysbuilts-compilation-station}"

BUILD_DIR_DEFAULT="build"
KERNEL_DIR="${CUSTOM_TARGET:-${BUILD_DIR_DEFAULT}/kernel}"
SYSROOT_DIR="${CUSTOM_TARGET:-${BUILD_DIR_DEFAULT}/sysroot}"

FORCE_UPGRADE="${FORCE_UPGRADE:-0}"

# Helper: query GitHub API for latest release JSON
fetch_latest_release_json() {
    local repo="$1"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -H "Accept: application/vnd.github.v3+json" --connect-timeout 10 "$api_url" || true
    fi
}

# Helper: extract tag name from release JSON
extract_tag_from_json() {
    local json="$1"
    if [ -z "$json" ]; then
        echo ""
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r .tag_name 2>/dev/null || echo ""
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('tag_name', ''))" <<< "$json" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Helper: prompt user for upgrade confirmation
prompt_upgrade() {
    local item_name="$1"
    local local_ver="$2"
    local remote_ver="$3"
    local env_var="$4"

    echo "[SyncManager] ------------------------------------------------------------"
    echo "[SyncManager] New ${item_name} build available: ${remote_ver}"
    echo "[SyncManager] Currently installed:              ${local_ver}"
    echo "[SyncManager] ------------------------------------------------------------"

    if [ "$FORCE_UPGRADE" = "1" ] || [ "${!env_var:-}" = "yes" ] || [ "${!env_var:-}" = "1" ]; then
        echo "[SyncManager] Automatic upgrade requested via environment."
        return 0
    elif [ "${!env_var:-}" = "no" ] || [ "${!env_var:-}" = "0" ]; then
        echo "[SyncManager] Upgrade declined via ${env_var}=no."
        return 1
    fi

    local user_input="n"
    if [ -t 0 ]; then
        read -r -p "[SyncManager] Do you want to upgrade ${item_name} to ${remote_ver}? [y/N]: " user_input || user_input="n"
    elif read -t 1 -r piped_input 2>/dev/null; then
        user_input="${piped_input}"
    elif [ -e /dev/tty ] && [ -r /dev/tty ] && [ -t 1 ] && [ -t 2 ]; then
        read -r -p "[SyncManager] Do you want to upgrade ${item_name} to ${remote_ver}? [y/N]: " user_input < /dev/tty || user_input="n"
    else
        echo "[SyncManager] Non-interactive environment detected. Keeping currently installed ${item_name}."
        user_input="n"
    fi

    case "${user_input:-n}" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            echo "[SyncManager] Keeping current ${item_name} (${local_ver})."
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Sync Kernel
# ------------------------------------------------------------------------------
sync_kernel() {
    local target_dir="${1:-${KERNEL_DIR}}"
    echo "[SyncManager] === Synchronizing Linux Zen Kernel ==="

    local local_tag=""
    if [ -f "${target_dir}/boot/bzImage" ]; then
        if [ -f "${target_dir}/boot/kernel-version.txt" ]; then
            local_tag="$(tr -d '\r\n' < "${target_dir}/boot/kernel-version.txt")"
        elif [ -f "${target_dir}/version.txt" ]; then
            local_tag="$(tr -d '\r\n' < "${target_dir}/version.txt")"
        else
            local_tag="unknown"
        fi
    fi

    if [ "${SKIP_KERNEL_CHECK:-0}" = "1" ] && [ -n "$local_tag" ] && [ -f "${target_dir}/boot/bzImage" ]; then
        echo "[SyncManager] SKIP_KERNEL_CHECK=1 set. Using local kernel (${local_tag})."
        return 0
    fi

    echo "[SyncManager] Checking for kernel updates from GitHub (${KERNEL_REPO})..."
    local release_json
    release_json="$(fetch_latest_release_json "$KERNEL_REPO")"
    local remote_tag
    remote_tag="$(extract_tag_from_json "$release_json")"

    if [ -z "$remote_tag" ] || [ "$remote_tag" = "null" ]; then
        if [ -n "$local_tag" ] && [ -f "${target_dir}/boot/bzImage" ]; then
            echo "[SyncManager] Warning: Could not reach GitHub API for kernel updates (offline or rate limited)."
            echo "[SyncManager] Proceeding with existing local kernel (${local_tag})."
            return 0
        else
            echo "[SyncManager] Error: Failed to fetch kernel release metadata, and no local kernel was found."
            return 1
        fi
    fi

    if [ -n "$local_tag" ] && [ -f "${target_dir}/boot/bzImage" ]; then
        if [ "$local_tag" = "$remote_tag" ] && [ "$FORCE_UPGRADE" != "1" ]; then
            echo "[SyncManager] Kernel is up to date: ${local_tag}."
            return 0
        fi

        if ! prompt_upgrade "Kernel" "$local_tag" "$remote_tag" "UPGRADE_KERNEL"; then
            return 0
        fi
        echo "[SyncManager] Upgrading kernel to ${remote_tag}..."
    else
        echo "[SyncManager] No local kernel detected. Downloading latest kernel build (${remote_tag})..."
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d "${target_dir}.download_XXXXXX" 2>/dev/null || mktemp -d -t ark_kernel_XXXXXX)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    declare -a asset_names=()
    declare -a asset_urls=()

    if command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r name url; do
            [ -n "$name" ] && [ -n "$url" ] && asset_names+=("$name") && asset_urls+=("$url")
        done < <(echo "$release_json" | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)"')
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r name url; do
            [ -n "$name" ] && [ -n "$url" ] && asset_names+=("$name") && asset_urls+=("$url")
        done < <(python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for a in data.get('assets', []):
    print(f\"{a['name']}\t{a['browser_download_url']}\")
" <<< "$release_json")
    fi

    local downloaded=0
    for idx in "${!asset_names[@]}"; do
        local name="${asset_names[$idx]}"
        local url="${asset_urls[$idx]}"
        if [[ "$name" =~ ^img_ ]] || [ "$name" = "SHA256SUMS.txt" ] || [ "$name" = "kernel.tar.xz" ]; then
            echo "[SyncManager] Downloading ${name}..."
            curl -fSL --progress-bar "$url" -o "${tmp_dir}/${name}"
            downloaded=$((downloaded + 1))
        fi
    done

    if [ "$downloaded" -eq 0 ]; then
        echo "[SyncManager] Error: No kernel assets found in release ${remote_tag}."
        rm -rf "${tmp_dir}"
        return 1
    fi

    # Mandatory Checksum Verification
    if [ ! -f "${tmp_dir}/SHA256SUMS.txt" ]; then
        echo "[SyncManager] Error: Mandatory SHA256SUMS.txt missing from release assets! Aborting."
        rm -rf "${tmp_dir}"
        return 1
    fi
    echo "[SyncManager] Verifying SHA-256 integrity checksums..."
    if ! (cd "${tmp_dir}" && sha256sum -c SHA256SUMS.txt); then
        echo "[SyncManager] Error: SHA-256 integrity checksum verification failed! Aborting."
        rm -rf "${tmp_dir}"
        return 1
    fi
    echo "[SyncManager] Checksum verification passed."

    local archive_file="${tmp_dir}/kernel.tar.xz"
    if [ ! -f "$archive_file" ]; then
        echo "[SyncManager] Reassembling split kernel archive..."
        cat "${tmp_dir}"/img_* > "$archive_file"
    fi

    # Path traversal security check
    if tar -tf "$archive_file" | grep -E '(^|/)\.\.(/|$)' >/dev/null 2>&1; then
        echo "[SyncManager] Security Error: Archive contains path traversal components (..)! Aborting."
        rm -rf "${tmp_dir}"
        return 1
    fi

    # Stage extraction in a clean temporary directory
    local tmp_stage
    tmp_stage="$(mktemp -d "${target_dir}.stage_XXXXXX" 2>/dev/null || mktemp -d -t ark_kstage_XXXXXX)"
    echo "[SyncManager] Extracting kernel artifacts to staging directory..."
    tar -xf "$archive_file" -C "${tmp_stage}"

    # Post-extraction validation
    if [ ! -f "${tmp_stage}/boot/bzImage" ]; then
        echo "[SyncManager] Error: Staged kernel missing boot/bzImage! Aborting promotion."
        rm -rf "${tmp_stage}" "${tmp_dir}"
        return 1
    fi

    echo "${remote_tag}" > "${tmp_stage}/boot/kernel-version.txt"
    echo "${remote_tag}" > "${tmp_stage}/version.txt"

    # Atomic promotion
    echo "[SyncManager] Promoting staged kernel to ${target_dir}..."
    local backup_dir="${target_dir}.old_$$"
    if [ -d "${target_dir}" ]; then
        mv "${target_dir}" "${backup_dir}"
    fi
    mkdir -p "$(dirname "${target_dir}")"
    mv "${tmp_stage}" "${target_dir}"
    rm -rf "${backup_dir}" "${tmp_dir}"
    trap - EXIT

    echo "[SyncManager] Successfully installed kernel ${remote_tag} ($(wc -c < "${target_dir}/boot/bzImage") bytes)."
}

# ------------------------------------------------------------------------------
# Sync Sysbuilts (musl libc + mimalloc)
# ------------------------------------------------------------------------------
sync_sysbuilts() {
    local target_dir="${1:-${SYSROOT_DIR}}"
    echo "[SyncManager] === Synchronizing Target Sysroot (musl + mimalloc) ==="

    local local_tag=""
    if [ -f "${target_dir}/lib/libc.a" ] || [ -f "${target_dir}/lib/libc.so" ]; then
        if [ -f "${target_dir}/version.txt" ]; then
            local_tag="$(tr -d '\r\n' < "${target_dir}/version.txt")"
        else
            local_tag="unknown"
        fi
    fi

    if [ "${SKIP_SYSBUILTS_CHECK:-0}" = "1" ] && [ -n "$local_tag" ]; then
        echo "[SyncManager] SKIP_SYSBUILTS_CHECK=1 set. Using local sysroot (${local_tag})."
        return 0
    fi

    echo "[SyncManager] Checking for sysbuilts updates from GitHub (${SYSBUILTS_REPO})..."
    local release_json
    release_json="$(fetch_latest_release_json "$SYSBUILTS_REPO")"
    local remote_tag
    remote_tag="$(extract_tag_from_json "$release_json")"

    if [ -z "$remote_tag" ] || [ "$remote_tag" = "null" ]; then
        if [ -n "$local_tag" ]; then
            echo "[SyncManager] Warning: Could not reach GitHub API for sysbuilts updates (offline or rate limited)."
            echo "[SyncManager] Proceeding with existing local sysroot (${local_tag})."
            return 0
        else
            echo "[SyncManager] Warning: No sysbuilts release currently found in ${SYSBUILTS_REPO}."
            echo "[SyncManager] Note: The compilation station may be waiting for its initial CI build."
            return 0
        fi
    fi

    if [ -n "$local_tag" ]; then
        if [ "$local_tag" = "$remote_tag" ] && [ "$FORCE_UPGRADE" != "1" ]; then
            echo "[SyncManager] Target sysroot is up to date: ${local_tag}."
            return 0
        fi

        if ! prompt_upgrade "Sysbuilts" "$local_tag" "$remote_tag" "UPGRADE_SYSBUILTS"; then
            return 0
        fi
        echo "[SyncManager] Upgrading target sysroot to ${remote_tag}..."
    else
        echo "[SyncManager] No local sysroot detected. Downloading latest sysbuilts (${remote_tag})..."
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d "${target_dir}.download_XXXXXX" 2>/dev/null || mktemp -d -t ark_sys_XXXXXX)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    declare -a asset_names=()
    declare -a asset_urls=()

    if command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r name url; do
            [ -n "$name" ] && [ -n "$url" ] && asset_names+=("$name") && asset_urls+=("$url")
        done < <(echo "$release_json" | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)"')
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r name url; do
            [ -n "$name" ] && [ -n "$url" ] && asset_names+=("$name") && asset_urls+=("$url")
        done < <(python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for a in data.get('assets', []):
    print(f\"{a['name']}\t{a['browser_download_url']}\")
" <<< "$release_json")
    fi

    local downloaded=0
    for idx in "${!asset_names[@]}"; do
        local name="${asset_names[$idx]}"
        local url="${asset_urls[$idx]}"
        if [[ "$name" =~ ^sysbuilts.*\.tar\.xz$ ]] || [ "$name" = "SHA256SUMS.txt" ]; then
            echo "[SyncManager] Downloading ${name}..."
            curl -fSL --progress-bar "$url" -o "${tmp_dir}/${name}"
            downloaded=$((downloaded + 1))
        fi
    done

    if [ "$downloaded" -eq 0 ]; then
        echo "[SyncManager] Error: No sysbuilt assets found in release ${remote_tag}."
        rm -rf "${tmp_dir}"
        return 1
    fi

    # Mandatory Checksum Verification
    if [ ! -f "${tmp_dir}/SHA256SUMS.txt" ]; then
        echo "[SyncManager] Error: Mandatory SHA256SUMS.txt missing from release assets! Aborting."
        rm -rf "${tmp_dir}"
        return 1
    fi
    echo "[SyncManager] Verifying SHA-256 integrity checksums..."
    if ! (cd "${tmp_dir}" && sha256sum -c SHA256SUMS.txt); then
        echo "[SyncManager] Error: SHA-256 integrity checksum verification failed! Aborting."
        rm -rf "${tmp_dir}"
        return 1
    fi
    echo "[SyncManager] Checksum verification passed."

    local archive_file
    archive_file="$(find "${tmp_dir}" -name "sysbuilts*.tar.xz" | head -n1)"
    if [ -z "$archive_file" ] || [ ! -f "$archive_file" ]; then
        echo "[SyncManager] Error: sysbuilts archive not found in downloaded assets!"
        rm -rf "${tmp_dir}"
        return 1
    fi

    # Path traversal security check
    if tar -tf "$archive_file" | grep -E '(^|/)\.\.(/|$)' >/dev/null 2>&1; then
        echo "[SyncManager] Security Error: Archive contains path traversal components (..)! Aborting."
        rm -rf "${tmp_dir}"
        return 1
    fi

    # Stage extraction in clean temporary directory
    local tmp_stage
    tmp_stage="$(mktemp -d "${target_dir}.stage_XXXXXX" 2>/dev/null || mktemp -d -t ark_sstage_XXXXXX)"
    echo "[SyncManager] Extracting sysroot to staging directory..."
    tar -xf "$archive_file" -C "${tmp_stage}"

    # Post-extraction validation on critical sysroot artifacts
    echo "[SyncManager] Validating staged sysroot artifacts..."
    local validation_failed=0
    for req in "lib/libc.a" "include/stdio.h" "include/mimalloc.h"; do
        if [ ! -f "${tmp_stage}/${req}" ]; then
            echo "[SyncManager] Error: Staged sysroot missing required artifact: ${req}"
            validation_failed=1
        fi
    done

    if [ "$validation_failed" -eq 1 ]; then
        echo "[SyncManager] Error: Staged sysroot failed validation! Aborting promotion."
        rm -rf "${tmp_stage}" "${tmp_dir}"
        return 1
    fi

    echo "${remote_tag}" > "${tmp_stage}/version.txt"

    # Atomic promotion
    echo "[SyncManager] Promoting staged sysroot to ${target_dir}..."
    local backup_dir="${target_dir}.old_$$"
    if [ -d "${target_dir}" ]; then
        mv "${target_dir}" "${backup_dir}"
    fi
    mkdir -p "$(dirname "${target_dir}")"
    mv "${tmp_stage}" "${target_dir}"
    rm -rf "${backup_dir}" "${tmp_dir}"
    trap - EXIT

    echo "[SyncManager] Successfully installed sysroot ${remote_tag} in ${target_dir}."
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------
case "${MODE}" in
    kernel)
        sync_kernel "${CUSTOM_TARGET:-${KERNEL_DIR}}"
        ;;
    sysbuilts)
        sync_sysbuilts "${CUSTOM_TARGET:-${SYSROOT_DIR}}"
        ;;
    all)
        sync_kernel "${KERNEL_DIR}"
        sync_sysbuilts "${SYSROOT_DIR}"
        ;;
    check)
        echo "[SyncManager] Checking remote statuses..."
        k_json="$(fetch_latest_release_json "$KERNEL_REPO")"
        s_json="$(fetch_latest_release_json "$SYSBUILTS_REPO")"
        echo "Latest Kernel Tag:   $(extract_tag_from_json "$k_json")"
        echo "Latest Sysbuilt Tag: $(extract_tag_from_json "$s_json")"
        ;;
    *)
        echo "Usage: $0 [all|kernel|sysbuilts|check] [target_dir]"
        exit 1
        ;;
esac
