#!/usr/bin/env bash
# Package release assets (DMG and ZIP) signed with developer identity.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"

VERSION="${1:-1.4.0}"
VERSION="${VERSION#v}"

identity="${DOPISHI_SIGNING_IDENTITY:-${LANGSWITCHER_SIGNING_IDENTITY:-}}"
if [[ -z "$identity" ]]; then
    identity=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [[ -z "$identity" ]]; then
        identity=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    fi
fi

if [[ -z "$identity" ]]; then
    echo "Error: No valid code signing identity found." >&2
    exit 1
fi

echo "==> Packaging Dopishi v${VERSION} using identity: $identity"

build_dir="$project_root/build/release-dist"
rm -rf "$build_dir"
mkdir -p "$build_dir"

echo "==> Building Release Universal bundle..."
xcodebuild -project "$project_root/LangSwitcher.xcodeproj" \
    -scheme LangSwitcher \
    -configuration Release \
    -derivedDataPath "$build_dir" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-VSU327SFT6}" \
    build

built_app="$build_dir/Build/Products/Release/Dopishi.app"
if [[ ! -d "$built_app" ]]; then
    echo "Error: App bundle not found at $built_app" >&2
    exit 1
fi

echo "==> Embedding inference dependencies..."
bash "$script_dir/embed-inference.sh" "$built_app"

echo "==> Signing complete application bundle..."
DOPISHI_SIGNING_IDENTITY="$identity" bash "$script_dir/sign-app.sh" "$built_app"

dmg_name="Dopishi-${VERSION}-universal.dmg"
zip_name="Dopishi-${VERSION}-universal.zip"

echo "==> Creating DMG: $dmg_name..."
dmg_staging="$build_dir/dmg_contents"
rm -rf "$dmg_staging" "$project_root/$dmg_name"
mkdir -p "$dmg_staging"
ditto "$built_app" "$dmg_staging/Dopishi.app"
ln -s /Applications "$dmg_staging/Applications"

hdiutil create -volname "Dopishi" \
    -srcfolder "$dmg_staging" \
    -ov -format UDZO \
    "$project_root/$dmg_name"

rm -rf "$dmg_staging"

if [[ -n "$identity" && "$identity" != "-" ]]; then
    codesign --force --sign "$identity" "$project_root/$dmg_name" || true
fi

echo "==> Creating ZIP: $zip_name..."
rm -f "$project_root/$zip_name"
ditto -c -k --sequesterRsrc --keepParent "$built_app" "$project_root/$zip_name"

echo "==> Generating Sparkle appcast: appcast.xml..."
swift "$script_dir/generate-appcast.swift" "$VERSION" "v${VERSION}" "$project_root/$zip_name" "$project_root/appcast.xml"

echo "==> Calculating SHA256..."
dmg_sha=$(shasum -a 256 "$project_root/$dmg_name" | awk '{print $1}')
echo "DMG SHA256: $dmg_sha"

echo "==> Cleaning temporary build folder..."
rm -rf "$build_dir"

echo "==> Done! Release assets created:"
echo "    - $project_root/$dmg_name"
echo "    - $project_root/$zip_name"
echo "    - $project_root/appcast.xml"
echo ""
echo "==> To publish to GitHub Releases (REQUIRED for Sparkle auto-updates):"
echo "    gh release create v${VERSION} \\"
echo "        \"$project_root/$dmg_name\" \\"
echo "        \"$project_root/$zip_name\" \\"
echo "        \"$project_root/appcast.xml\" \\"
echo "        --title \"Dopishi v${VERSION}\" --notes-file <notes.md>"
echo ""
echo "==> Then sync Homebrew Tap:"
echo "    bash \"$script_dir/bump-cask.sh\" \"$VERSION\" \"$project_root/$dmg_name\""
