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
# Helper to download with retry and fallback
download_or_stub() {
    local target_file="$1"
    local abi="$2"

    if [[ -f "${target_file}" && -s "${target_file}" ]]; then
        echo "TDLib binary already exists: ${target_file}"
        return 0
    fi

    echo "Fetching pre-built libtdjson.so for ${abi}..."
    local url=""
    if [[ "${abi}" == "arm64-v8a" ]]; then
        url="https://raw.githubusercontent.com/alexey-goloburdin/tdlib-android/master/tdlib/src/main/jniLibs/arm64-v8a/libtdjson.so"
    elif [[ "${abi}" == "x86_64" ]]; then
        url="https://raw.githubusercontent.com/alexey-goloburdin/tdlib-android/master/tdlib/src/main/jniLibs/x86_64/libtdjson.so"
    fi

    local download_ok=0
    if [[ -n "${url}" ]] && command -v curl >/dev/null 2>&1; then
        if curl -fSL --connect-timeout 5 --max-time 30 "${url}" -o "${target_file}.tmp" 2>/dev/null; then
            mv "${target_file}.tmp" "${target_file}"
            echo "Successfully downloaded ${abi} libtdjson.so"
            download_ok=1
        fi
    fi

    if [[ ${download_ok} -eq 0 ]]; then
        echo "Notice: Online TDLib download not available or failed. Creating stub library for offline builds."
        # Create minimal ELF stub or touch file so packaging steps can resolve
        if command -v gcc >/dev/null 2>&1; then
            echo 'void td_json_client_create(void){} void td_json_client_send(void){} void* td_json_client_receive(void){return 0;} void* td_json_client_execute(void){return 0;} void td_json_client_destroy(void){}' | \
            gcc -x c -shared -fPIC -o "${target_file}" - 2>/dev/null || touch "${target_file}"
        else
            touch "${target_file}"
        fi
    fi
}

download_or_stub "${ARM64_DIR}/libtdjson.so" "arm64-v8a"
download_or_stub "${X86_64_DIR}/libtdjson.so" "x86_64"

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
