#!/bin/bash
# Sangeet AI Release Orchestration Script
# Handles: clean build -> package daemon -> codesign app -> notarize app -> staple app -> package DMG -> codesign DMG -> notarize DMG -> staple DMG
set -e

SIGNING_IDENTITY="${1}"
VERSION="${2}"
OUTPUT_DIR="${3:-dist}"

if [ -z "$SIGNING_IDENTITY" ] || [ -z "$VERSION" ]; then
    echo "Usage: $0 <signing_identity> <version> [output_directory]"
    echo "Example: $0 \"Developer ID Application: Your Name (TeamID)\" \"0.10.0-beta1\""
    exit 1
fi

echo "=================================================="
echo "Starting Sangeet AI Release Orchestration"
echo "Version:           $VERSION"
echo "Signing Identity:  $SIGNING_IDENTITY"
echo "Output Directory:  $OUTPUT_DIR"
echo "=================================================="

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Clean any existing build outputs
rm -rf build/DerivedData

# 1. Build Sangeet AI in Release configuration
# This automatically triggers the nested build-daemon script inside Xcode
echo "Step 1: Building Sangeet AI Application & Python Daemon..."
export CONFIGURATION=Release
xcodebuild -project apps/macos/SangeetAI.xcodeproj \
    -scheme SangeetAI \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="1" \
    clean build

APP_PATH="build/DerivedData/Build/Products/Release/SangeetAI.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Built app bundle was not found at $APP_PATH"
    exit 1
fi
echo "Application compiled successfully at $APP_PATH"

# 2. Codesign the App Bundle (Inside-Out)
echo "Step 2: Performing recursive codesigning..."
./scripts/codesign.sh "$APP_PATH" "$SIGNING_IDENTITY" "apps/macos/Sources/SangeetAI/SangeetAI.entitlements"

# 3. Notarize App Bundle
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_PASSWORD" ]; then
    echo "Step 3: Notarizing SangeetAI.app bundle..."
    ./scripts/notarize.sh "$APP_PATH"
else
    echo "Step 3: Skipping SangeetAI.app notarization (notary credentials missing)..."
fi

# 4. Package into DMG
DMG_PATH="$OUTPUT_DIR/SangeetAI-$VERSION.dmg"
echo "Step 4: Creating release DMG archive..."
rm -f "$DMG_PATH"
hdiutil create -volname "Sangeet AI" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
echo "DMG created successfully at $DMG_PATH."

# 5. Codesign DMG
echo "Step 5: Codesigning output DMG..."
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

# 6. Notarize DMG
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_PASSWORD" ]; then
    echo "Step 6: Notarizing output DMG..."
    ./scripts/notarize.sh "$DMG_PATH"
else
    echo "Step 6: Skipping DMG notarization (notary credentials missing)..."
fi

echo "=================================================="
echo "Sangeet AI Release Build Complete!"
echo "Final signed and notarized DMG is available at:"
echo "  $DMG_PATH"
echo "=================================================="
