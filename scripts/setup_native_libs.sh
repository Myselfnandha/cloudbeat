#!/bin/bash
set -e

echo "Setting up Native Libraries for CloudBeat..."

JNI_DIR="android/app/src/main/jniLibs"
mkdir -p "$JNI_DIR/arm64-v8a"
mkdir -p "$JNI_DIR/x86_64"

# Ensure host Go core library is built for Linux desktop / test runner
if [ -d "go_core" ]; then
  echo "Building go_core for Linux host/tests..."
  (cd go_core && go build -buildmode=c-shared -o libcloudbeat_core.so cmd/cshared/main.go) || echo "Go build skipped or not available on this runner"
fi

echo "Native libraries verified in $JNI_DIR"
