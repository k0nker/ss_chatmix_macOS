#!/bin/bash

# SSChatMix Complete Distribution Build Script
# Builds App + Plugin, creates DMG + PKG, notarizes, and generates Sparkle signatures
# Run this script to prepare everything for distribution

set -e

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${PROJECT_DIR}/build"
DIST_DIR="${BUILD_DIR}/dist"
EXPORT_DIR="${BUILD_DIR}/export"
ARCHIVE_PATH="${BUILD_DIR}/SSChatMixApp.xcarchive"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-sschatmix-notary}"
TEAM_ID="69SD3NQCD8"
APP_NAME="SSChatMix"

# Extract version from Xcode project
APP_VERSION=$(xcodebuild -project "${PROJECT_DIR}/SSChatMix.xcodeproj" -showBuildSettings 2>/dev/null | grep "MARKETING_VERSION" | head -1 | awk '{print $3}')
PLUGIN_VERSION=$(grep -A1 "CFBundleShortVersionString" "${PROJECT_DIR}/SSChatMixPlugin/Info.plist" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "═════════════════════════════════════════════════════════════"
echo -e "${BLUE}SSChatMix Complete Distribution Build${NC}"
echo "═════════════════════════════════════════════════════════════"
echo -e "  App Version:    ${GREEN}${APP_VERSION}${NC}"
echo -e "  Plugin Version: ${GREEN}${PLUGIN_VERSION}${NC}"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Cleanup old build
echo -e "${YELLOW}[1/9]${NC} Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${DIST_DIR}"

# Compile uninstaller binary BEFORE Xcode build
echo "   Compiling uninstaller binary..."
swiftc -O -o "${PROJECT_DIR}/SSChatMixApp/uninstall" "${PROJECT_DIR}/uninstaller/main.swift"
chmod +x "${PROJECT_DIR}/SSChatMixApp/uninstall"

# =====================================================================
# BUILD APP
# =====================================================================

echo ""
echo -e "${YELLOW}[2/9]${NC} Building SSChatMix App (Release)..."
xcodebuild archive \
  -project "${PROJECT_DIR}/SSChatMix.xcodeproj" \
  -scheme SSChatMix \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -quiet

if [ ! -d "${ARCHIVE_PATH}" ]; then
  echo -e "${RED}✗ App archive failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ App archived (with embedded uninstaller)${NC}"

echo -e "${YELLOW}[3/9]${NC} Exporting and signing app..."
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${PROJECT_DIR}/ExportOptions.plist" \
  -exportPath "${EXPORT_DIR}" \
  -quiet

APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
  echo -e "${RED}✗ App export failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ App exported${NC}"

# =====================================================================
# MANUAL CODE SIGNING (bypass Xcode's sandbox injection)
# =====================================================================

echo "   Applying correct entitlements (no sandbox)..."

# Find Developer ID Application certificate
DEV_ID_CERT=$(security find-identity -v -p codesigning | grep "Developer ID Application" | sed 's/.*"\(.*\)"/\1/' | head -1) || true

if [ -z "$DEV_ID_CERT" ]; then
  echo -e "${RED}✗ No Developer ID Application certificate found!${NC}"
  echo "   Please install a valid Developer ID Application certificate."
  exit 1
else
  echo "   Using certificate: $DEV_ID_CERT"
  SIGN_IDENTITY="$DEV_ID_CERT"
fi

codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements "${PROJECT_DIR}/SSChatMixApp.entitlements" \
  --deep \
  "${APP_PATH}"

# Verify sandbox is NOT present
if codesign -d --entitlements :- "${APP_PATH}" 2>&1 | grep -q "com.apple.security.app-sandbox"; then
  echo -e "${RED}✗ Sandbox still present after manual signing!${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Manual code signing complete (sandbox removed)${NC}"

# Clean up compiled uninstaller from source tree (build artifact)
rm -f "${PROJECT_DIR}/SSChatMixApp/uninstall"

# =====================================================================
# BUILD PLUGIN
# =====================================================================

echo ""
echo -e "${YELLOW}[4/9]${NC} Building SSChatMixPlugin (Release)..."
xcodebuild \
  -project "${PROJECT_DIR}/SSChatMix.xcodeproj" \
  -scheme SSChatMixPlugin \
  -configuration Release \
  clean build \
  CONFIGURATION_BUILD_DIR="${BUILD_DIR}/plugin" \
  -quiet

PLUGIN_PATH="${BUILD_DIR}/plugin/SSChatMixPlugin.driver"
if [ ! -d "${PLUGIN_PATH}" ]; then
  echo -e "${RED}✗ Plugin build failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Plugin built${NC}"

# =====================================================================
# CREATE PLUGIN PKG
# =====================================================================

echo ""
echo -e "${YELLOW}[5/9]${NC} Creating plugin installer package..."

PKG_ROOT="${BUILD_DIR}/pkg_root"
SCRIPTS_DIR="${PROJECT_DIR}/installer/scripts"
PLUGIN_INSTALL_PATH="Library/Audio/Plug-Ins/HAL"
PKG_NAME="SSChatMixPlugin-${PLUGIN_VERSION}.pkg"
PKG_PATH="${DIST_DIR}/${PKG_NAME}"

mkdir -p "${PKG_ROOT}/${PLUGIN_INSTALL_PATH}"
cp -R "${PLUGIN_PATH}" "${PKG_ROOT}/${PLUGIN_INSTALL_PATH}/"
find "${PKG_ROOT}" -name ".DS_Store" -delete

pkgbuild \
  --root "${PKG_ROOT}" \
  --scripts "${SCRIPTS_DIR}" \
  --identifier "com.k0nker.sschatmix.plugin" \
  --version "${PLUGIN_VERSION}" \
  --install-location "/" \
  "${BUILD_DIR}/component.pkg" > /dev/null

productbuild \
  --package "${BUILD_DIR}/component.pkg" \
  "${PKG_PATH}" > /dev/null

rm "${BUILD_DIR}/component.pkg"

# Sign the PKG
echo "   Signing package..."

# Check if Developer ID Installer certificate exists
INSTALLER_CERT=$(security find-identity -v -p basic | grep "Developer ID Installer" | head -1 | awk -F'"' '{print $2}')

if [ -z "$INSTALLER_CERT" ]; then
  echo -e "${YELLOW}⚠ Warning: No 'Developer ID Installer' certificate found${NC}"
  echo "   The PKG will be unsigned. To sign packages, you need:"
  echo "   1. Go to: https://developer.apple.com/account/resources/certificates/list"
  echo "   2. Create a 'Developer ID Installer' certificate"
  echo "   3. Download and install it in your keychain"
  echo ""
  echo "   For now, continuing with unsigned PKG..."
else
  productsign \
    --sign "$INSTALLER_CERT" \
    "${PKG_PATH}" \
    "${PKG_PATH}.signed"
  
  mv "${PKG_PATH}.signed" "${PKG_PATH}"
  echo "   ✓ PKG signed with: $INSTALLER_CERT"
fi

if [ -f "${PKG_PATH}" ]; then
  PKG_SIZE=$(du -h "${PKG_PATH}" | cut -f1)
  echo -e "${GREEN}✓ Plugin PKG created: ${PKG_NAME} (${PKG_SIZE})${NC}"
else
  echo -e "${RED}✗ Plugin PKG creation failed${NC}"
  exit 1
fi

# =====================================================================
# NOTARIZE APP
# =====================================================================

echo ""
echo -e "${YELLOW}[6/9]${NC} Notarizing app with Apple..."
echo "   (This may take a few minutes...)"

# Zip the app for notarization
APP_ZIP="${BUILD_DIR}/SSChatMix.zip"
ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP}"

NOTARIZE_RESULT=$(xcrun notarytool submit "${APP_ZIP}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait 2>&1 || echo "FAILED")

if [[ $NOTARIZE_RESULT == *"id: "* ]]; then
  echo -e "${GREEN}✓ App notarization successful${NC}"
  
  SUBMISSION_ID=$(echo "$NOTARIZE_RESULT" | grep "id:" | awk '{print $2}' | head -1)
  echo "   Submission ID: $SUBMISSION_ID"
  
  echo "   Stapling notarization ticket..."
  echo "   (Waiting for ticket to propagate...)"
  
  # Retry stapling with delays (Apple's servers need time to propagate)
  MAX_STAPLE_ATTEMPTS=5
  STAPLE_ATTEMPT=1
  STAPLE_SUCCESS=false
  
  while [ $STAPLE_ATTEMPT -le $MAX_STAPLE_ATTEMPTS ]; do
    if [ $STAPLE_ATTEMPT -gt 1 ]; then
      echo "   Retry attempt ${STAPLE_ATTEMPT}/${MAX_STAPLE_ATTEMPTS}..."
      sleep 10
    fi
    
    if xcrun stapler staple "${APP_PATH}" 2>&1 | grep -q "The staple and validate action worked"; then
      STAPLE_SUCCESS=true
      break
    fi
    
    STAPLE_ATTEMPT=$((STAPLE_ATTEMPT + 1))
  done
  
  if [ "$STAPLE_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ App notarization ticket stapled${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: Could not staple ticket (but notarization succeeded)${NC}"
    echo "   The app is notarized but users may need internet on first launch"
  fi
  
  # Clean up zip
  rm "${APP_ZIP}"
else
  echo -e "${RED}✗ App notarization failed${NC}"
  echo "$NOTARIZE_RESULT"
  exit 1
fi

# =====================================================================
# NOTARIZE PLUGIN PKG
# =====================================================================

echo ""
echo -e "${YELLOW}[7/9]${NC} Notarizing plugin package with Apple..."

PKG_NOTARIZE_RESULT=$(xcrun notarytool submit "${PKG_PATH}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait 2>&1 || echo "FAILED")

if [[ $PKG_NOTARIZE_RESULT == *"id: "* ]]; then
  echo -e "${GREEN}✓ Plugin PKG notarization successful${NC}"
  
  PKG_SUBMISSION_ID=$(echo "$PKG_NOTARIZE_RESULT" | grep "id:" | awk '{print $2}' | head -1)
  echo "   Submission ID: $PKG_SUBMISSION_ID"
  
  echo "   Stapling notarization ticket..."
  echo "   (Waiting for ticket to propagate...)"
  
  # Retry stapling with delays
  MAX_STAPLE_ATTEMPTS=5
  STAPLE_ATTEMPT=1
  STAPLE_SUCCESS=false
  
  while [ $STAPLE_ATTEMPT -le $MAX_STAPLE_ATTEMPTS ]; do
    if [ $STAPLE_ATTEMPT -gt 1 ]; then
      echo "   Retry attempt ${STAPLE_ATTEMPT}/${MAX_STAPLE_ATTEMPTS}..."
      sleep 10
    fi
    
    if xcrun stapler staple "${PKG_PATH}" 2>&1 | grep -q "The staple and validate action worked"; then
      STAPLE_SUCCESS=true
      break
    fi
    
    STAPLE_ATTEMPT=$((STAPLE_ATTEMPT + 1))
  done
  
  if [ "$STAPLE_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ Plugin PKG notarization ticket stapled${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: Could not staple ticket to PKG (but notarization succeeded)${NC}"
    echo "   The PKG is notarized but users may need internet on first install"
  fi
else
  echo -e "${RED}✗ Plugin PKG notarization failed${NC}"
  echo "$PKG_NOTARIZE_RESULT"
  exit 1
fi

# =====================================================================
# CREATE APP DMG
# =====================================================================

echo ""
echo -e "${YELLOW}[8/9]${NC} Creating app DMG installer..."
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

# Create staging directory for DMG with Applications symlink
DMG_STAGING="${BUILD_DIR}/dmg_staging"
mkdir -p "${DMG_STAGING}"

# Copy app to staging
cp -R "${APP_PATH}" "${DMG_STAGING}/"

# Create Applications symlink for drag-and-drop installation
ln -s /Applications "${DMG_STAGING}/Applications"

# Create DMG from staging directory
hdiutil create \
  -volname "${APP_NAME} ${APP_VERSION}" \
  -srcfolder "${DMG_STAGING}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${DMG_PATH}" > /dev/null

# Clean up staging
rm -rf "${DMG_STAGING}"

if [ -f "${DMG_PATH}" ]; then
  DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1)
  echo -e "${GREEN}✓ App DMG created: ${DMG_NAME} (${DMG_SIZE})${NC}"
else
  echo -e "${RED}✗ DMG creation failed${NC}"
  exit 1
fi

# =====================================================================
# GENERATE SPARKLE SIGNATURES
# =====================================================================

echo ""
echo -e "${YELLOW}[9/9]${NC} Generating Sparkle update signatures..."

SPARKLE_KEY="${HOME}/.sparkle_rsa"
if [ ! -f "${SPARKLE_KEY}" ]; then
  echo -e "${RED}✗ Sparkle private key not found at: ${SPARKLE_KEY}${NC}"
  echo "   Run ./generate_sparkle_keys.sh first"
  exit 1
fi

# For Ed25519 keys, use pkeyutl instead of dgst (OpenSSL 3.x compatibility)
DMG_SIGNATURE=$(openssl pkeyutl -sign -inkey "${SPARKLE_KEY}" -rawin -in "${DMG_PATH}" | openssl enc -base64 | tr -d '\n')
DMG_LENGTH=$(stat -f%z "${DMG_PATH}")

echo -e "${GREEN}✓ Sparkle signatures generated${NC}"

# =====================================================================
# SUMMARY
# =====================================================================

echo ""
echo "═════════════════════════════════════════════════════════════"
echo -e "${GREEN}✨ Build Complete!${NC}"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Distribution packages ready:${NC}"
echo -e "  📱 App DMG:    ${DIST_DIR}/${DMG_NAME}"
echo -e "  🔌 Plugin PKG: ${DIST_DIR}/${PKG_NAME}"
echo ""
echo -e "${BLUE}Sparkle Update Info (for appcast.xml):${NC}"
echo "  Version:      ${APP_VERSION}"
echo "  Length:       ${DMG_LENGTH}"
echo "  Signature:    ${DMG_SIGNATURE}"
echo ""
echo -e "${BLUE}GitHub Release Instructions:${NC}"
echo ""
echo "1. Create release on GitHub:"
echo "   - Go to: https://github.com/k0nker/ss_chatmix_macOS/releases"
echo "   - Click 'Create a new release'"
echo "   - Tag: v${APP_VERSION}"
echo "   - Title: Version ${APP_VERSION}"
echo ""
echo "2. Upload both files:"
echo "   - ${DMG_NAME}"
echo "   - ${PKG_NAME}"
echo ""
echo "3. Add to release notes:"
echo ""
echo "   ### Installation"
echo "   1. First install: [${PKG_NAME}](https://github.com/k0nker/ss_chatmix_macOS/releases/download/v${APP_VERSION}/${PKG_NAME})"
echo "   2. Then install: [${DMG_NAME}](https://github.com/k0nker/ss_chatmix_macOS/releases/download/v${APP_VERSION}/${DMG_NAME})"
echo ""
echo "4. Update appcast.xml with the Sparkle info above"
echo ""
echo "5. Commit and push appcast.xml to trigger auto-updates for users"
echo ""
echo "═════════════════════════════════════════════════════════════"
echo ""
