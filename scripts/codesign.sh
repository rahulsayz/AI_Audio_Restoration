#!/bin/bash
# Recursive codesigning script for Sangeet AI app and bundled daemon binaries
# Implements strict inside-out signing required by Apple.
set -e

TARGET_PATH="$1"
SIGNING_IDENTITY="${2:--}" # Default to ad-hoc signing ("-")
ENTITLEMENTS_PATH="$3"     # Optional path to entitlements plist

if [ -z "$TARGET_PATH" ]; then
    echo "Usage: $0 <target_app_bundle_or_binary> [signing_identity] [entitlements_path]"
    exit 1
fi

if [ ! -d "$TARGET_PATH" ] && [ ! -f "$TARGET_PATH" ]; then
    echo "Error: Target path '$TARGET_PATH' does not exist."
    exit 1
fi

echo "=================================================="
echo "Sangeet AI Codesigning Pipeline"
echo "Target Path:   $TARGET_PATH"
echo "Identity:      $SIGNING_IDENTITY"
echo "Entitlements:  ${ENTITLEMENTS_PATH:-None}"
echo "=================================================="

# Helper function to sign a single library or binary
sign_item() {
    local item="$1"
    local is_exe="$2" # true or false
    
    # Check if target is a Mach-O file or directory bundle
    if [ -d "$item" ] || file "$item" | grep -qE "Mach-O|shared library|dynamically linked"; then
        echo "Signing item: $item"
        
        # Build base signing flags
        local flags=("--force" "--sign" "$SIGNING_IDENTITY")
        
        # If not ad-hoc, add hardened runtime and timestamp
        if [ "$SIGNING_IDENTITY" != "-" ]; then
            flags+=("--options" "runtime" "--timestamp")
        fi
        
        # If it is an executable and entitlements are provided, attach entitlements (only to the host app bundle or main host executable)
        if [ "$is_exe" = "true" ] && [ -n "$ENTITLEMENTS_PATH" ] && [ -f "$ENTITLEMENTS_PATH" ]; then
            if [[ "$item" == *".app" ]] || [[ "$item" == *"/Contents/MacOS/"* ]]; then
                flags+=("--entitlements" "$ENTITLEMENTS_PATH")
            fi
        fi
        
        # Run codesign
        codesign "${flags[@]}" "$item"
    fi
}

# Main signing flow
if [ -f "$TARGET_PATH" ]; then
    # If the target is a single file, determine if it's an executable
    is_executable="false"
    if file "$TARGET_PATH" | grep -q "executable"; then
        is_executable="true"
    fi
    sign_item "$TARGET_PATH" "$is_executable"
else
    # Target is a directory/bundle (.app)
    echo "Performing deep inside-out signing on bundle..."
    
    # 0. Sign nested pre-compiled framework/app bundles as single units inside-out
    echo "Step 0: Signing nested pre-compiled bundles..."
    find "$TARGET_PATH" \( -name "Sparkle.framework" -o -name "Updater.app" \) -mindepth 1 | sort -r | while read -r bundle; do
        if [ -d "$bundle" ]; then
            if [ -L "$bundle" ]; then
                echo "Skipping symlink bundle: $bundle"
                continue
            fi
            echo "Signing nested bundle: $bundle"
            sign_item "$bundle" "false"
        fi
    done
    
    # 1. Sign all .dylib and .so files first (deepest paths first), excluding pre-compiled Sparkle.framework files
    echo "Step 1: Signing dynamic libraries (.dylib, .so)..."
    find "$TARGET_PATH" -type f \( -name "*.dylib" -o -name "*.so" \) | grep -v "/Sparkle.framework/" | sort -r | while read -r lib; do
        sign_item "$lib" "false"
    done
    
    # 2. Sign helper executables inside _internal or Resources, excluding pre-compiled Sparkle.framework files
    echo "Step 2: Signing helper executables..."
    find "$TARGET_PATH" -type f ! -name "*.dylib" ! -name "*.so" | grep -v "/Sparkle.framework/" | while read -r binary; do
        # Exclude the main app executable (we sign it at the end via outer bundle)
        if [[ "$binary" == *"/Contents/MacOS/"* ]]; then
            continue
        fi
        if file "$binary" | grep -q "executable"; then
            sign_item "$binary" "true"
        fi
    done
    
    # 3. Sign the embedded main sangeet-inference binary specifically
    daemon_path="$TARGET_PATH/Contents/Resources/sangeet-inference"
    if [ -f "$daemon_path" ]; then
        echo "Step 3: Signing main sangeet-inference daemon executable..."
        sign_item "$daemon_path" "true"
    fi
    
    # 4. Sign the main app executable and outer bundle if it is a standard bundle type
    if [[ "$TARGET_PATH" == *".app" ]] || [[ "$TARGET_PATH" == *".framework" ]]; then
        echo "Step 4: Signing outer application bundle..."
        sign_item "$TARGET_PATH" "true"
    fi
fi

echo "=================================================="
echo "Codesigning completed successfully for $TARGET_PATH."
echo "=================================================="
