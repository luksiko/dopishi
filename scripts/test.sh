#!/usr/bin/env bash
# Use a fully signed test host with an identity separate from the installed app.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$project_root/build/tests/Build/Products/Debug/Dopishi.app" 2>/dev/null || true
}
trap cleanup EXIT

xcodebuild test \
  -project "$project_root/LangSwitcher.xcodeproj" \
  -scheme LangSwitcher \
  -destination 'platform=macOS' \
  -derivedDataPath "$project_root/build/tests" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  PRODUCT_BUNDLE_IDENTIFIER=com.dopishi.testhost \
  "$@"
