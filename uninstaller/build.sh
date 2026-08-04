#!/bin/bash

# Compile the uninstaller binary

echo "Compiling uninstaller..."
swiftc -O -o uninstaller/uninstall uninstaller/main.swift

if [ $? -eq 0 ]; then
    echo "✓ Uninstaller compiled successfully"
    echo "  Binary: uninstaller/uninstall"
    echo ""
    echo "This binary will be included in SSChatMix.app/Contents/Resources/"
    echo "during the build process."
else
    echo "✗ Failed to compile uninstaller"
    exit 1
fi
