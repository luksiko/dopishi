#!/usr/bin/env bash
# Build, sign with a persistent certificate, install to /Applications/Dopishi.app, and clean build artifacts.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"

identity="${DOPISHI_SIGNING_IDENTITY:-${LANGSWITCHER_SIGNING_IDENTITY:-}}"
if [[ -z "$identity" ]]; then
    # Auto-detect Apple Development or Developer ID certificate from Keychain
    identity=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [[ -z "$identity" ]]; then
        identity=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    fi
fi

if [[ -z "$identity" ]]; then
    echo "Error: No valid code signing identity found in keychain." >&2
    echo "Please set DOPISHI_SIGNING_IDENTITY='<Identity Name>' or install an Apple Development certificate." >&2
    exit 1
fi

echo "==> Using code signing identity: $identity"

build_dir="$project_root/build/local-release"
rm -rf "$build_dir"
mkdir -p "$build_dir"

# Reuse cached packages if available to avoid redownloading over network
if [[ -d "$project_root/build/tests/SourcePackages" ]]; then
    echo "==> Reusing SPM package cache from build/tests..."
    cp -R "$project_root/build/tests/SourcePackages" "$build_dir/"
fi

echo "==> Building Dopishi (Release)..."
xcodebuild -project "$project_root/LangSwitcher.xcodeproj" \
    -scheme LangSwitcher \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$build_dir" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    build

built_app="$build_dir/Build/Products/Release/Dopishi.app"
if [[ ! -d "$built_app" ]]; then
    echo "Error: Build succeeded but app not found at $built_app" >&2
    exit 1
fi

echo "==> Installing to /Applications/Dopishi.app..."
DOPISHI_SIGNING_IDENTITY="$identity" bash "$script_dir/install-local.sh" "$built_app"

echo "==> Cleaning temporary build artifacts to avoid duplicate LaunchServices registrations..."
rm -rf "$build_dir"
rm -rf "$project_root"/build/release/*.app "$project_root"/dmg_contents/*.app 2>/dev/null || true

echo "==> Dopishi successfully built, signed, and installed!"
