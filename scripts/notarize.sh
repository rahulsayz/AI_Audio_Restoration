#!/bin/bash
# Submits signed Sangeet AI app bundle or DMG to Apple Notarization Service using environment credentials
set -e

TARGET_PATH="$1"

if [ -z "$TARGET_PATH" ]; then
    echo "Usage: $0 <path_to_SangeetAI.app_or_SangeetAI.dmg>"
    exit 1
fi

if [ ! -d "$TARGET_PATH" ] && [ ! -f "$TARGET_PATH" ]; then
    echo "Error: Target path '$TARGET_PATH' does not exist."
    exit 1
fi

# Ensure environment variables are set
if [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
    echo "=================================================="
    echo "WARNING: Notarization credentials not configured."
    echo "Ensure these environment variables are exported:"
    echo "  export APPLE_ID=\"your-apple-id@email.com\""
    echo "  export APPLE_TEAM_ID=\"your-team-id\""
    echo "  export APPLE_APP_PASSWORD=\"app-specific-password\""
    echo "=================================================="
    echo "Skipping Notarization..."
    exit 0
fi

echo "=================================================="
echo "Sangeet AI Apple Notarization Pipeline"
echo "Target Path: $TARGET_PATH"
echo "Apple ID:    $APPLE_ID"
echo "Team ID:     $APPLE_TEAM_ID"
echo "=================================================="

SUBMISSION_FILE=""
CLEANUP_REQUIRED="false"

# Check if target is a directory (.app) or a file (.dmg)
if [ -d "$TARGET_PATH" ]; then
    # Directory (.app): zip it up for submission
    SUBMISSION_FILE="/tmp/SangeetAI_Submission.zip"
    rm -f "$SUBMISSION_FILE"
    
    echo "Packaging app bundle into zip archive..."
    ditto -c -k --keepParent "$TARGET_PATH" "$SUBMISSION_FILE"
    echo "Archive created at $SUBMISSION_FILE."
    CLEANUP_REQUIRED="true"
else
    # File (.dmg): submit directly
    SUBMISSION_FILE="$TARGET_PATH"
    echo "Submitting DMG file directly..."
fi

# Submit for Notarization and wait for response
echo "Submitting to Apple Notarization Service (this might take a few minutes)..."
xcrun notarytool submit "$SUBMISSION_FILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

# Staple the ticket on success
echo "Notarization successful! Stapling ticket to original bundle..."
xcrun stapler staple "$TARGET_PATH"

# Cleanup temporary zip if created
if [ "$CLEANUP_REQUIRED" = "true" ] && [ -f "$SUBMISSION_FILE" ]; then
    rm -f "$SUBMISSION_FILE"
fi

echo "=================================================="
echo "Sangeet AI Notarization and Stapling Complete!"
echo "=================================================="
