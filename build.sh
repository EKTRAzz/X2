#!/bin/bash
set -e

echo "=== Building SpatialConvolver.dylib for iOS (arm64 + arm64e) ==="

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "Using iOS SDK: $SDK_PATH"

clang -dynamiclib \
    -arch arm64 \
    -arch arm64e \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min=14.0 \
    -O3 \
    -fobjc-arc \
    -framework Foundation \
    -framework AudioToolbox \
    -framework Accelerate \
    SpatialConvolver.m fishhook.c \
    -o SpatialConvolver.dylib

echo "=== Build Complete ==="
lipo -info SpatialConvolver.dylib
echo "File size: $(ls -lh SpatialConvolver.dylib | awk '{print $5}')"
