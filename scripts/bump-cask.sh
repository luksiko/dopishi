#!/usr/bin/env bash
# Update Casks/dopishi.rb with new version and sha256, and sync to luksiko/homebrew-tap
set -euo pipefail

VERSION="${1:?Usage: bash scripts/bump-cask.sh <version> [sha256|path-to-dmg]}"
SHA256="${2:-}"

# Strip leading 'v'
VERSION="${VERSION#v}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CASK_FILE="$REPO_ROOT/Casks/dopishi.rb"

if [[ -f "$SHA256" ]]; then
  echo "Calculating SHA256 of $SHA256..."
  SHA256="$(shasum -a 256 "$SHA256" | awk '{print $1}')"
fi

if [[ -z "$SHA256" ]]; then
  echo "Attempting to compute SHA256 from GitHub release asset..."
  DOWNLOAD_URL="https://github.com/luksiko/dopishi/releases/download/v${VERSION}/Dopishi-${VERSION}-universal.dmg"
  CURL_OUT="$(curl -sL "$DOWNLOAD_URL" | shasum -a 256 | awk '{print $1}')"
  if [[ "$CURL_OUT" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
    SHA256="$CURL_OUT"
  else
    SHA256=":no_check"
  fi
fi

echo "Updating $CASK_FILE for version $VERSION with sha256 $SHA256"

cat << EOF > "$CASK_FILE"
cask "dopishi" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/luksiko/dopishi/releases/download/v#{version}/Dopishi-#{version}-universal.dmg"
  name "Dopishi"
  desc "Smart keyboard layout switcher, inline auto-correction and text converter"
  homepage "https://github.com/luksiko/dopishi"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Dopishi.app"

  uninstall quit: "com.dopishi.app"

  zap trash: [
    "~/Library/Application Support/Dopishi",
    "~/Library/Application Support/LangSwitcher",
    "~/Library/Caches/com.dopishi.app",
    "~/Library/Preferences/com.dopishi.app.plist",
  ]
end
EOF

echo "✅ Casks/dopishi.rb updated."

# If gh or git has access to luksiko/homebrew-tap, sync it
TEMP_DIR="$(mktemp -d)"
if git clone https://github.com/luksiko/homebrew-tap.git "$TEMP_DIR" 2>/dev/null; then
  mkdir -p "$TEMP_DIR/Casks"
  cp "$CASK_FILE" "$TEMP_DIR/Casks/dopishi.rb"
  cd "$TEMP_DIR"
  git add Casks/dopishi.rb
  if git commit -m "bump(dopishi): v${VERSION}"; then
    git push origin main
    echo "✅ Successfully synced to luksiko/homebrew-tap!"
  else
    echo "ℹ️ No changes to commit in homebrew-tap."
  fi
  rm -rf "$TEMP_DIR"
fi
