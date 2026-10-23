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

package_artifacts() {
    local app_dir="$1"
    local variant_suffix="$2" # "-universal", "-arm64", "-x86_64"
    local dmg_name="Dopishi-${VERSION}${variant_suffix}.dmg"
    local zip_name="Dopishi-${VERSION}${variant_suffix}.zip"
    local dmg_path="$project_root/$dmg_name"
    local zip_path="$project_root/$zip_name"

    echo "==> Creating DMG: $dmg_name..."
    local dmg_staging="$build_dir/dmg_staging_${variant_suffix}"
    rm -rf "$dmg_staging" "$dmg_path"
    mkdir -p "$dmg_staging"
    ditto "$app_dir" "$dmg_staging/Dopishi.app"
    ln -s /Applications "$dmg_staging/Applications"

    hdiutil create -volname "Dopishi" \
        -srcfolder "$dmg_staging" \
        -ov -format UDZO \
        "$dmg_path" >/dev/null

    rm -rf "$dmg_staging"

    if [[ -n "$identity" && "$identity" != "-" ]]; then
        codesign --force --sign "$identity" "$dmg_path" >/dev/null 2>&1 || true
    fi

    echo "==> Creating ZIP: $zip_name..."
    rm -f "$zip_path"
    ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"

    local dmg_sha
    dmg_sha=$(shasum -a 256 "$dmg_path" | awk '{print $1}')
    local dmg_size
    dmg_size=$(ls -lh "$dmg_path" | awk '{print $5}')
    local zip_size
    zip_size=$(ls -lh "$zip_path" | awk '{print $5}')
    echo "    Created $dmg_name ($dmg_size, SHA256: $dmg_sha)"
    echo "    Created $zip_name ($zip_size)"
}

thin_bundle() {
    local src_app="$1"
    local target_app="$2"
    local arch="$3" # "arm64" or "x86_64"

    echo "==> Thinning application bundle for ${arch}..."
    rm -rf "$target_app"
    ditto "$src_app" "$target_app"

    while IFS= read -r -d '' file; do
        if [[ ! -L "$file" && -f "$file" ]]; then
            local info
            info=$(lipo -info "$file" 2>/dev/null || true)
            if [[ "$info" =~ "Architectures in the fat file" && "$info" =~ "$arch" ]]; then
                lipo "$file" -thin "$arch" -output "$file"
            elif [[ "$info" =~ "Non-fat file" && ! "$info" =~ "$arch" ]]; then
                rm -f "$file"
            fi
        fi
    done < <(find "$target_app" -type f -print0)

    # Re-sign the thinned bundle
    DOPISHI_SIGNING_IDENTITY="$identity" bash "$script_dir/sign-app.sh" "$target_app" >/dev/null
}

# 1. Package Universal Assets
package_artifacts "$built_app" "-universal"

# 2. Thin & Package Apple Silicon (arm64) Assets
thin_bundle "$built_app" "$build_dir/Dopishi_arm64.app" "arm64"
package_artifacts "$build_dir/Dopishi_arm64.app" "-arm64"

# 3. Thin & Package Intel (x86_64) Assets
thin_bundle "$built_app" "$build_dir/Dopishi_x86_64.app" "x86_64"
package_artifacts "$build_dir/Dopishi_x86_64.app" "-x86_64"

# 4. Generate Sparkle appcast with ARM64 priority and Universal fallback
build_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$built_app/Contents/Info.plist" 2>/dev/null || echo "$VERSION")
echo "==> Generating Sparkle appcast: appcast.xml (version: $VERSION, build: $build_number)..."
swift "$script_dir/generate-appcast.swift" "$VERSION" "$build_number" "v${VERSION}" \
    "$project_root/Dopishi-${VERSION}-universal.zip" \
    "$project_root/Dopishi-${VERSION}-arm64.zip" \
    "$project_root/appcast.xml"

echo "==> Cleaning temporary build folder..."
rm -rf "$build_dir"

echo ""
echo "======================================================================"
echo "==> Done! Release assets ready for GitHub Release:"
echo "    • Dopishi-${VERSION}-arm64.dmg       (Apple Silicon: M1/M2/M3/M4)"
echo "    • Dopishi-${VERSION}-arm64.zip"
echo "    • Dopishi-${VERSION}-x86_64.dmg      (Intel Macs)"
echo "    • Dopishi-${VERSION}-x86_64.zip"
echo "    • Dopishi-${VERSION}-universal.dmg   (Universal: All Macs / Homebrew)"
echo "    • Dopishi-${VERSION}-universal.zip   (Universal: Sparkle Auto-Update)"
echo "    • appcast.xml                        (Sparkle Update Feed)"
echo "======================================================================"
echo ""
echo "==> To publish to GitHub Releases (REQUIRED: include all assets & appcast.xml):"
echo "    gh release create \"v${VERSION}\" \\"
echo "        \"$project_root/Dopishi-${VERSION}-arm64.dmg\" \\"
echo "        \"$project_root/Dopishi-${VERSION}-arm64.zip\" \\"
echo "        \"$project_root/Dopishi-${VERSION}-x86_64.dmg\" \\"
echo "        \"$project_root/Dopishi-${VERSION}-x86_64.zip\" \\"
echo "        \"$project_root/Dopishi-${VERSION}-universal.dmg\" \\"
echo "        \"$project_root/Dopishi-${VERSION}-universal.zip\" \\"
echo "        \"$project_root/appcast.xml\" \\"
echo "        --title \"Dopishi v${VERSION}\" --notes-file <notes.md>"
echo ""
echo "==> Then sync Homebrew Tap (uses Universal DMG):"
echo "    bash \"$script_dir/bump-cask.sh\" \"$VERSION\" \"$project_root/Dopishi-${VERSION}-universal.dmg\""
