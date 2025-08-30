#!/bin/bash

# Build script for WhoNext using macOS 26 Speech APIs
# Requires Xcode-beta with Swift 6.2 and CommandLineTools SDK

echo "Building WhoNext with macOS 26 Speech APIs..."
echo "Using Swift 6.2 from Xcode-beta"
echo "Using SDK: /Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk"

# Set environment variables
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
export TOOLCHAIN_DIR=/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain

# Build command
$DEVELOPER_DIR/usr/bin/xcodebuild \
    -project WhoNext.xcodeproj \
    -scheme WhoNext \
    -configuration Debug \
    -sdk $SDKROOT \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build

echo "Build complete!"