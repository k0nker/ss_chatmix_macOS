#!/bin/bash
# Build script for SSChatMix macOS app and HAL plugin

set -e  # Exit on error

echo "=========================================="
echo "SSChatMix Build Script"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "SSChatMix.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}Error: SSChatMix.xcodeproj not found${NC}"
    echo "Run this script from the project root directory"
    exit 1
fi

# Configuration
CONFIGURATION="${1:-Release}"
echo -e "${YELLOW}Building in ${CONFIGURATION} mode${NC}"
echo ""

# Build the HAL plugin
echo "=========================================="
echo "1/2: Building HAL Plugin"
echo "=========================================="
xcodebuild \
    -project SSChatMix.xcodeproj \
    -target SSChatMixPlugin \
    -configuration "${CONFIGURATION}" \
    clean build \
    SYMROOT="$(pwd)/build"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ HAL Plugin built successfully${NC}"
    echo "   Location: build/${CONFIGURATION}/SSChatMixPlugin.driver"
else
    echo -e "${RED}✗ HAL Plugin build failed${NC}"
    exit 1
fi
echo ""

# Build the Swift app
echo "=========================================="
echo "2/2: Building macOS App"
echo "=========================================="
xcodebuild \
    -project SSChatMix.xcodeproj \
    -scheme SSChatMix \
    -configuration "${CONFIGURATION}" \
    clean build \
    SYMROOT="$(pwd)/build"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ macOS App built successfully${NC}"
    echo "   Location: build/${CONFIGURATION}/SSChatMix.app"
else
    echo -e "${RED}✗ macOS App build failed${NC}"
    exit 1
fi
echo ""

# Summary
echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "Plugin: build/${CONFIGURATION}/SSChatMixPlugin.driver"
echo "App:    build/${CONFIGURATION}/SSChatMix.app"
echo ""
echo "To install the plugin:"
echo "  sudo cp -R build/${CONFIGURATION}/SSChatMixPlugin.driver /Library/Audio/Plug-Ins/HAL/"
echo "  sudo killall coreaudiod"
echo ""
echo "To run the app:"
echo "  open build/${CONFIGURATION}/SSChatMix.app"
echo ""
