#!/bin/bash
set -e

echo "Setting up Native Libraries for CloudBeat..."

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JNI_DIR="$PROJECT_ROOT/android/app/src/main/jniLibs"
mkdir -p "$JNI_DIR/arm64-v8a"
mkdir -p "$JNI_DIR/armeabi-v7a"
mkdir -p "$JNI_DIR/x86_64"

# 1. Build host Linux library for local desktop testing & headless CI
if [ -d "$PROJECT_ROOT/go_core" ]; then
  echo "Building go_core for Linux host/tests..."
  (cd "$PROJECT_ROOT/go_core" && go build -buildmode=c-shared -o libcloudbeat_core.so cmd/cshared/main.go) || echo "Go host build failed or skipped"
fi

# 2. Locate Android NDK for cross-compilation
NDK_PATH=""
if [ -n "$ANDROID_NDK_LATEST_HOME" ] && [ -d "$ANDROID_NDK_LATEST_HOME" ]; then
  NDK_PATH="$ANDROID_NDK_LATEST_HOME"
elif [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
  NDK_PATH="$ANDROID_NDK_HOME"
elif [ -n "$ANDROID_NDK_ROOT" ] && [ -d "$ANDROID_NDK_ROOT" ]; then
  NDK_PATH="$ANDROID_NDK_ROOT"
elif [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/ndk" ]; then
  NDK_PATH=$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -n1)
elif [ -d "/usr/local/lib/android/sdk/ndk" ]; then
  NDK_PATH=$(ls -d /usr/local/lib/android/sdk/ndk/* 2>/dev/null | sort -V | tail -n1)
fi

if [ -n "$NDK_PATH" ] && [ -d "$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin" ]; then
  echo "Found Android NDK at: $NDK_PATH"
  TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin"

  CLANG_ARM64=$(ls "$TOOLCHAIN"/aarch64-linux-android*-clang 2>/dev/null | grep -E '[0-9]+-clang$' | sort -V | tail -n1)
  CLANG_ARMV7=$(ls "$TOOLCHAIN"/armv7a-linux-androideabi*-clang 2>/dev/null | grep -E '[0-9]+-clang$' | sort -V | tail -n1)
  CLANG_X86_64=$(ls "$TOOLCHAIN"/x86_64-linux-android*-clang 2>/dev/null | grep -E '[0-9]+-clang$' | sort -V | tail -n1)

  if [ -n "$CLANG_ARM64" ]; then
    echo "Cross-compiling for Android arm64-v8a with $CLANG_ARM64..."
    (cd "$PROJECT_ROOT/go_core" && CC="$CLANG_ARM64" CGO_ENABLED=1 GOOS=android GOARCH=arm64 go build -buildmode=c-shared -o "$JNI_DIR/arm64-v8a/libcloudbeat_core.so" cmd/cshared/main.go)
  fi

  if [ -n "$CLANG_ARMV7" ]; then
    echo "Cross-compiling for Android armeabi-v7a with $CLANG_ARMV7..."
    (cd "$PROJECT_ROOT/go_core" && CC="$CLANG_ARMV7" CGO_ENABLED=1 GOOS=android GOARCH=arm GOARM=7 go build -buildmode=c-shared -o "$JNI_DIR/armeabi-v7a/libcloudbeat_core.so" cmd/cshared/main.go)
  fi

  if [ -n "$CLANG_X86_64" ]; then
    echo "Cross-compiling for Android x86_64 with $CLANG_X86_64..."
    (cd "$PROJECT_ROOT/go_core" && CC="$CLANG_X86_64" CGO_ENABLED=1 GOOS=android GOARCH=amd64 go build -buildmode=c-shared -o "$JNI_DIR/x86_64/libcloudbeat_core.so" cmd/cshared/main.go)
  fi
else
  echo "Android NDK not detected in environment. Using existing/bundled jniLibs if available."
fi

echo "Native libraries status in $JNI_DIR:"
ls -lh "$JNI_DIR"/*/*.so 2>/dev/null || echo "No .so files currently in jniLibs (will be compiled during CI build)"
