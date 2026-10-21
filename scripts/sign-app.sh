#!/bin/bash
# Sign a complete LangSwitcher bundle after building/staging, before installation.
# Usage: bash scripts/sign-app.sh /path/to/LangSwitcher.app
# Use the same Developer ID identity for releases; '-' is local ad-hoc only.
set -euo pipefail

APP_PATH="${1:?Usage: bash scripts/sign-app.sh /path/to/LangSwitcher.app}"
SIGNING_IDENTITY="${LANGSWITCHER_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Set LANGSWITCHER_SIGNING_IDENTITY to the same signing certificate for every update." >&2
    echo "Use '-' explicitly only for disposable builds; ad-hoc updates can lose Accessibility consent." >&2
    exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")
if [[ "$BUNDLE_ID" != "com.langswitcher.app" ]]; then
    echo "Refusing to sign unexpected bundle identifier: $BUNDLE_ID" >&2
    exit 1
fi
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    find "$APP_PATH/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -exec /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" {} + 2>/dev/null || true
fi
if [[ -d "$APP_PATH/Contents/Helpers" ]]; then
    find "$APP_PATH/Contents/Helpers" -type f -perm +111 -exec /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" {} + 2>/dev/null || true
fi
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
DETAILS=$(/usr/bin/codesign --display --verbose=2 "$APP_PATH" 2>&1)
if [[ "$DETAILS" != *"Identifier=$BUNDLE_ID"* || "$DETAILS" == *"Info.plist=not bound"* || "$DETAILS" == *"Sealed Resources=none"* ]]; then
    echo "Bundle signature is incomplete; do not install this app." >&2
    exit 1
fi
printf '%s\n' "$DETAILS"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Local ad-hoc signature: macOS may require renewed Accessibility consent after a rebuild."
fi
