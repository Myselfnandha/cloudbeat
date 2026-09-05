#!/bin/bash
set -e

echo "Setting up Native Libraries for CloudBeat..."

JNI_DIR="android/app/src/main/jniLibs"
mkdir -p "$JNI_DIR/arm64-v8a"
mkdir -p "$JNI_DIR/x86_64"
mkdir -p "$JNI_DIR/armeabi-v7a"

# In a real environment, this would curl pre-compiled libtdjson.so from a release bucket
# For this scaffold, we'll create stub files if they don't exist
echo "Fetching libtdjson.so (mocking download)..."
touch "$JNI_DIR/arm64-v8a/libtdjson.so"
touch "$JNI_DIR/x86_64/libtdjson.so"
touch "$JNI_DIR/armeabi-v7a/libtdjson.so"

echo "Compiling libcloudbeat_core.so from Go source (mocking build)..."
touch "$JNI_DIR/arm64-v8a/libcloudbeat_core.so"
touch "$JNI_DIR/x86_64/libcloudbeat_core.so"
touch "$JNI_DIR/armeabi-v7a/libcloudbeat_core.so"

echo "Configuring libcloudbeat_lyrics.so..."
touch "$JNI_DIR/arm64-v8a/libcloudbeat_lyrics.so"
touch "$JNI_DIR/x86_64/libcloudbeat_lyrics.so"
touch "$JNI_DIR/armeabi-v7a/libcloudbeat_lyrics.so"

echo "Native libraries configured in $JNI_DIR"
