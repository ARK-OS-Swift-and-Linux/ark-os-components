#!/usr/bin/env bash
# ==============================================================================
# ARK-OS Kernel Release Manager
#
# Automatically discovers, verifies, and downloads the latest kernel builds
# from the ARK-OS Kernel Compilation Station GitHub repository.
# Prompts the user before upgrading when a new release is detected.
# ==============================================================================

set -euo pipefail

KERNEL_DIR="${1:-build/kernel}"
REPO="${KERNEL_REPO:-ARK-OS-Swift-and-Linux/ark-os-kernel-compilation-station}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
FORCE_UPGRADE="${FORCE_UPGRADE:-0}"

# 1. Determine currently installed local version (if any)
LOCAL_TAG=""
if [ -f "${KERNEL_DIR}/boot/bzImage" ]; then
    if [ -f "${KERNEL_DIR}/boot/kernel-version.txt" ]; then
        LOCAL_TAG="$(tr -d '\r\n' < "${KERNEL_DIR}/boot/kernel-version.txt")"
    elif [ -f "${KERNEL_DIR}/version.txt" ]; then
        LOCAL_TAG="$(tr -d '\r\n' < "${KERNEL_DIR}/version.txt")"
    else
        LOCAL_TAG="unknown"
    fi
fi

if [ "${SKIP_KERNEL_CHECK:-0}" = "1" ] && [ -n "$LOCAL_TAG" ] && [ -f "${KERNEL_DIR}/boot/bzImage" ]; then
    echo "[KernelManager] SKIP_KERNEL_CHECK=1 set. Using local kernel (${LOCAL_TAG})."
    exit 0
fi

# 2. Query GitHub API for the latest release metadata
echo "[KernelManager] Checking for kernel updates from GitHub (${REPO})..."
RELEASE_JSON=""
if command -v curl >/dev/null 2>&1; then
    RELEASE_JSON="$(curl -sSL -H "Accept: application/vnd.github.v3+json" --connect-timeout 10 "$API_URL" || true)"
fi

REMOTE_TAG=""
if [ -n "$RELEASE_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
        REMOTE_TAG="$(echo "$RELEASE_JSON" | jq -r .tag_name 2>/dev/null || true)"
    elif command -v python3 >/dev/null 2>&1; then
        REMOTE_TAG="$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('tag_name', ''))" <<< "$RELEASE_JSON" 2>/dev/null || true)"
    fi
fi

# 3. Handle network / API connectivity failure
if [ -z "$REMOTE_TAG" ] || [ "$REMOTE_TAG" = "null" ]; then
    if [ -n "$LOCAL_TAG" ] && [ -f "${KERNEL_DIR}/boot/bzImage" ]; then
        echo "[KernelManager] Warning: Could not reach GitHub API to check for updates (offline or rate limited)."
        echo "[KernelManager] Proceeding with existing local kernel (${LOCAL_TAG})."
        exit 0
    else
        echo "[KernelManager] Error: Failed to fetch latest release metadata from GitHub, and no local kernel was found."
        echo "[KernelManager] Please check your internet connection or verify access to ${API_URL}."
        exit 1
    fi
fi

# 4. Compare remote version against local version
if [ -n "$LOCAL_TAG" ] && [ -f "${KERNEL_DIR}/boot/bzImage" ]; then
    if [ "$LOCAL_TAG" = "$REMOTE_TAG" ] && [ "$FORCE_UPGRADE" != "1" ]; then
        echo "[KernelManager] Kernel is up to date: ${LOCAL_TAG}."
        exit 0
    fi

    echo "[KernelManager] ------------------------------------------------------------"
    echo "[KernelManager] New kernel build available: ${REMOTE_TAG}"
    echo "[KernelManager] Currently installed:        ${LOCAL_TAG}"
    echo "[KernelManager] ------------------------------------------------------------"

    UPGRADE_CHOICE=""
    if [ "$FORCE_UPGRADE" = "1" ] || [ "${UPGRADE_KERNEL:-}" = "yes" ] || [ "${UPGRADE_KERNEL:-}" = "1" ]; then
        UPGRADE_CHOICE="y"
        echo "[KernelManager] Automatic upgrade requested via environment."
    elif [ "${UPGRADE_KERNEL:-}" = "no" ] || [ "${UPGRADE_KERNEL:-}" = "0" ]; then
        UPGRADE_CHOICE="n"
        echo "[KernelManager] Upgrade declined via UPGRADE_KERNEL=no."
    else
        # Interactive prompt to user
        USER_INPUT="n"
        if [ -t 0 ]; then
            read -r -p "[KernelManager] Do you want to upgrade to ${REMOTE_TAG}? [y/N]: " USER_INPUT || USER_INPUT="n"
        elif read -t 1 -r PIPED_INPUT 2>/dev/null; then
            USER_INPUT="${PIPED_INPUT}"
        elif [ -e /dev/tty ] && [ -r /dev/tty ] && [ -t 1 ] && [ -t 2 ]; then
            read -r -p "[KernelManager] Do you want to upgrade to ${REMOTE_TAG}? [y/N]: " USER_INPUT < /dev/tty || USER_INPUT="n"
        else
            echo "[KernelManager] Non-interactive environment detected. Keeping currently installed kernel."
            USER_INPUT="n"
        fi
        UPGRADE_CHOICE="${USER_INPUT:-n}"
    fi

    case "${UPGRADE_CHOICE}" in
        [yY]|[yY][eE][sS])
            echo "[KernelManager] Upgrading kernel to ${REMOTE_TAG}..."
            ;;
        *)
            echo "[KernelManager] Keeping current kernel (${LOCAL_TAG})."
            exit 0
            ;;
    esac
else
    echo "[KernelManager] No local kernel detected."
    echo "[KernelManager] Automatically downloading latest kernel build (${REMOTE_TAG})..."
fi

# 5. Download, verify, and install release artifacts
TMP_DIR="${KERNEL_DIR}/.download_tmp_$$"
mkdir -p "${TMP_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "[KernelManager] Fetching asset download links for ${REMOTE_TAG}..."
declare -a ASSET_NAMES=()
declare -a ASSET_URLS=()

if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r name url; do
        if [ -n "$name" ] && [ -n "$url" ]; then
            ASSET_NAMES+=("$name")
            ASSET_URLS+=("$url")
        fi
    done < <(echo "$RELEASE_JSON" | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)"')
elif command -v python3 >/dev/null 2>&1; then
    while IFS=$'\t' read -r name url; do
        if [ -n "$name" ] && [ -n "$url" ]; then
            ASSET_NAMES+=("$name")
            ASSET_URLS+=("$url")
        fi
    done < <(python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for a in data.get('assets', []):
    print(f\"{a['name']}\t{a['browser_download_url']}\")
" <<< "$RELEASE_JSON")
fi

DOWNLOAD_COUNT=0
for idx in "${!ASSET_NAMES[@]}"; do
    NAME="${ASSET_NAMES[$idx]}"
    URL="${ASSET_URLS[$idx]}"
    if [[ "$NAME" =~ ^img_ ]] || [ "$NAME" = "SHA256SUMS.txt" ]; then
        echo "[KernelManager] Downloading ${NAME}..."
        curl -fSL --progress-bar "$URL" -o "${TMP_DIR}/${NAME}"
        DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
    fi
done

if [ "$DOWNLOAD_COUNT" -eq 0 ]; then
    echo "[KernelManager] Error: No kernel image assets (img_* or SHA256SUMS.txt) found in release ${REMOTE_TAG}."
    exit 1
fi

# 6. Verify checksums
if [ -f "${TMP_DIR}/SHA256SUMS.txt" ]; then
    echo "[KernelManager] Verifying SHA256 checksums..."
    (cd "${TMP_DIR}" && sha256sum -c SHA256SUMS.txt)
    echo "[KernelManager] Checksum verification passed."
else
    echo "[KernelManager] Warning: SHA256SUMS.txt not present in release. Skipping checksum validation."
fi

# 7. Reassemble split parts
echo "[KernelManager] Reassembling split kernel archive..."
cat "${TMP_DIR}"/img_* > "${TMP_DIR}/kernel.tar.xz"

# 8. Extract into target kernel directory
echo "[KernelManager] Extracting kernel artifacts to ${KERNEL_DIR}..."
mkdir -p "${KERNEL_DIR}"
tar -xf "${TMP_DIR}/kernel.tar.xz" -C "${KERNEL_DIR}"

# 9. Record version
echo "${REMOTE_TAG}" > "${KERNEL_DIR}/boot/kernel-version.txt"
echo "${REMOTE_TAG}" > "${KERNEL_DIR}/version.txt"

# 10. Verify bzImage exists
if [ ! -f "${KERNEL_DIR}/boot/bzImage" ]; then
    echo "[KernelManager] Error: bzImage not found in ${KERNEL_DIR}/boot/ after extraction!"
    exit 1
fi

echo "[KernelManager] Successfully installed kernel ${REMOTE_TAG} ($(wc -c < "${KERNEL_DIR}/boot/bzImage") bytes)."
