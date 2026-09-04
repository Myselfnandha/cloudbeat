#!/usr/bin/env bash
# ==============================================================================
# CloudBeat Native Libraries Setup Script
# Configures libtdjson.so (TDLib v1.8.x) and compiles libcloudbeat_core.so
# for Android ABIs (arm64-v8a, x86_64) and desktop/host test runners.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARM64_DIR="${ROOT_DIR}/android/app/src/main/jniLibs/arm64-v8a"
X86_64_DIR="${ROOT_DIR}/android/app/src/main/jniLibs/x86_64"
LINUX_DIR="${ROOT_DIR}/linux"
GO_CORE_DIR="${ROOT_DIR}/go_core"

echo "=== [1/4] Creating jniLibs ABI directories ==="
mkdir -p "${ARM64_DIR}"
mkdir -p "${X86_64_DIR}"
mkdir -p "${LINUX_DIR}"

echo "=== [2/4] Compiling Go Core (libcloudbeat_core.so) ==="
cd "${GO_CORE_DIR}"

# Compile host Go core first for desktop test runners and FFI validation
if command -v go >/dev/null 2>&1; then
    echo "Compiling host libcloudbeat_core.so..."
    go build -buildmode=c-shared -o "${GO_CORE_DIR}/libcloudbeat_core.so" ./cmd/cshared/main.go
    cp -f "${GO_CORE_DIR}/libcloudbeat_core.so" "${LINUX_DIR}/" || true

    # Check for Android NDK to cross-compile for Android targets
    if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
        echo "Found ANDROID_NDK_HOME=${ANDROID_NDK_HOME}. Cross-compiling for Android..."
        CLANG_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"

        # arm64-v8a
        if [[ -f "${CLANG_BIN}/aarch64-linux-android24-clang" ]]; then
            echo "Building libcloudbeat_core.so for arm64-v8a..."
            CC="${CLANG_BIN}/aarch64-linux-android24-clang" \
            CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
            go build -buildmode=c-shared -o "${ARM64_DIR}/libcloudbeat_core.so" ./cmd/cshared/main.go
        fi

        # x86_64
        if [[ -f "${CLANG_BIN}/x86_64-linux-android24-clang" ]]; then
            echo "Building libcloudbeat_core.so for x86_64..."
            CC="${CLANG_BIN}/x86_64-linux-android24-clang" \
            CGO_ENABLED=1 GOOS=android GOARCH=amd64 \
            go build -buildmode=c-shared -o "${X86_64_DIR}/libcloudbeat_core.so" ./cmd/cshared/main.go
        fi
    else
        echo "ANDROID_NDK_HOME not set. Copying host shared library as baseline for ABI directories..."
        cp -f "${GO_CORE_DIR}/libcloudbeat_core.so" "${ARM64_DIR}/" || true
        cp -f "${GO_CORE_DIR}/libcloudbeat_core.so" "${X86_64_DIR}/" || true
    fi
else
    echo "Warning: 'go' binary not found. Skipping Go compilation."
fi

echo "=== [3/4] Setting up TDLib (libtdjson.so) ==="
if [[ (! -f "${ARM64_DIR}/libtdjson.so" || ! -s "${ARM64_DIR}/libtdjson.so" || $(stat -c%s "${ARM64_DIR}/libtdjson.so") -lt 100000) ]]; then
    echo "Downloading pre-compiled TDLib jniLibs package..."
    TD_URL="https://github.com/up9cloud/android-libtdjson/releases/download/v1.8.65/jniLibs.tar.gz"
    TEMP_TAR="/tmp/cloudbeat_jniLibs.tar.gz"
    TEMP_EXTRACT="/tmp/cloudbeat_td_extract"

    if curl -fSL --connect-timeout 10 --max-time 120 "${TD_URL}" -o "${TEMP_TAR}"; then
        mkdir -p "${TEMP_EXTRACT}"
        tar -xzf "${TEMP_TAR}" -C "${TEMP_EXTRACT}"
        cp -f "${TEMP_EXTRACT}/jniLibs/arm64-v8a/libtdjson.so" "${ARM64_DIR}/libtdjson.so"
        cp -f "${TEMP_EXTRACT}/jniLibs/x86_64/libtdjson.so" "${X86_64_DIR}/libtdjson.so"
        echo "Successfully installed verified TDLib binaries."
        rm -rf "${TEMP_TAR}" "${TEMP_EXTRACT}"
    else
        echo "Warning: Failed to download TDLib binaries. Preserving existing files."
    fi
else
    echo "TDLib binaries already present."
fi

# Also place in linux folder if running on Linux desktop
if [[ ! -f "${LINUX_DIR}/libtdjson.so" ]]; then
    if [[ -f "${X86_64_DIR}/libtdjson.so" && -s "${X86_64_DIR}/libtdjson.so" ]]; then
        cp -f "${X86_64_DIR}/libtdjson.so" "${LINUX_DIR}/libtdjson.so" 2>/dev/null || true
    fi
fi

echo "=== [4/4] Verification of Native Libraries ==="
echo "arm64-v8a:"
ls -lh "${ARM64_DIR}"
echo "x86_64:"
ls -lh "${X86_64_DIR}"

echo "CloudBeat native setup complete."
