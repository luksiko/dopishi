# AGENTS.md — Instructions for AI Agents and Contributors

## Testing Requirements

**Tests MUST be run after every edit that modifies Swift source files.**

### Running Tests Locally

```bash
bash scripts/test.sh
```

The script uses a complete ad-hoc signature and the separate
`com.dopishi.testhost` identifier, so the installed app can remain running.
Do not disable code signing for the test host: LaunchServices can reject the
resulting bundle before XCTest starts. The production app has
`LSMultipleInstancesProhibited=true`, so using its identifier for tests also
conflicts with an already running installed copy.

### Rules

1. **After every code change**: Run the full test suite before considering the task complete.
2. **All tests must pass**: Do not commit or push code with failing tests.
3. **New functionality requires tests**: Any new feature, bug fix, or behavioral change must include corresponding unit tests.
4. **CI enforces tests**: GitHub Actions runs `xcodebuild test` on every push and pull request. Merges are blocked if tests fail.

### Test Structure

- Test target: `LangSwitcherTests`
- Test files are in `LangSwitcherTests/`
- Tests use `XCTest` framework
- `LayoutMapper` and `TextConverter` are the primary units under test
- `SettingsManager` is `@MainActor` — tests that use it need `@MainActor` context
- `TextConverter` is `@MainActor` — also needs main actor context in tests

### What to Test

- `LayoutMapper.convert()` — character mapping between all supported layout pairs (EN, RU, UK, DE, FR, ES)
- `LayoutMapper.detectSourceLayout()` — layout detection from text content
- `LayoutCharacterMap.characterMap(for:)` — correct pattern matching for layout IDs
- `TextConverter.looksLikeWrongLayout()` — gibberish detection (script-switch heuristic)
- `TextConverter.findWrongLayoutBoundary()` — greedy line boundary detection
- `TextConverter.convertLineGreedy()` — greedy conversion of wrong-layout tails
- `TextConverter.convertSelectedText()` — full conversion pipeline
- Tokenization edge cases (punctuation, mixed scripts, empty strings)

### Important Notes

- The Xcode project uses hand-crafted PBX IDs in the format `E1000000XXXXXXXXXXXX`. New entries must follow this pattern.
- LSP cross-file errors ("Cannot find in scope") are expected and NOT real errors — they resolve at Xcode build time.
- `"russian"` contains `"us"` as a substring — pattern ordering in `allMaps` is critical. Do not reorder.

## Localization Guidelines

LangSwitcher uses a custom runtime localization system (NOT Apple `.lproj`/`.strings`). All UI strings go through `LocalizationManager`.

### Rules

1. **All new user-facing strings** must use `LocalizationManager.shared.t("key")` — never hardcode UI text.
2. **String keys use namespace prefixes**: `menu.*`, `settings.*`, `general.*`, `smartMode.*`, `layoutSwitchMode.*`, `layouts.*`, `hotkey.*`, `hotkeyRecorder.*`, `permissions.*`, `log.*`, `about.*`, `alert.*`, `common.*`.
3. **When adding a new string key**: Add it to **both** `Strings_en.swift` and `Strings_ru.swift` (and any other `Strings_xx.swift` files).
4. **`LocalizationManager` is `@MainActor`** — it is used as `@EnvironmentObject` in SwiftUI views. Any code that calls `LocalizationManager.shared.t()` must run on the main actor.
5. **Enum computed properties** (e.g. `SmartConversionMode.displayName`) that call `t()` must be annotated with `@MainActor`.
6. **Adding a new language**: Copy `Strings_en.swift` → `Strings_xx.swift`, translate values, register in `LangSwitcherApp.swift`, add to `availableLanguages` in `LocalizationManager.swift`, add to `project.pbxproj`. See README for detailed steps.
7. **Fallback**: If a key is missing in the current language, `t()` falls back to English, then returns the raw key.

### File Structure

```
LangSwitcher/Sources/Localization/
├── LocalizationManager.swift   # ObservableObject, t() lookup, language persistence
├── Strings_en.swift            # English strings (~113 keys)
└── Strings_ru.swift            # Russian translations
```


## Local Installation and Signing

- Never update `/Applications/Dopishi.app` by replacing only `Contents/MacOS/Dopishi` or copying a bare linker-signed executable. This repeatedly broke Accessibility and both keyboard event taps during local development.
- Prefer `DOPISHI_SIGNING_IDENTITY="<stable certificate>" bash scripts/install-local.sh /path/to/built/Dopishi.app` for local updates. It stages/signs, checks the existing designated requirement, archives a ZIP backup, stops the installed process and replaces the complete bundle. Do not install ad-hoc builds over the working app.
- For manual installation, build and stage the complete app bundle, then run `bash scripts/sign-app.sh /path/to/staged/Dopishi.app` before replacing the installed bundle. Stop the running app before replacement; preserve a recoverable backup. Install to `/Applications/Dopishi.app`, then relaunch that exact path.
- The signing script must pass. `codesign --verify` alone is insufficient: a bare linker signature can verify while reporting `Info.plist=not bound`, `Sealed Resources=none`, or the wrong signing identifier (`Dopishi` instead of `com.dopishi.app`).
- Prefer the same Developer ID identity across releases (`DOPISHI_SIGNING_IDENTITY`). Ad-hoc signatures do not guarantee permission persistence across rebuilds. If trust is lost, restore the existing app's Accessibility entry through System Settings and verify actual service startup; never edit the TCC database directly.
- Do not report working auto-correction from the Accessibility toggle alone. Verify the active process and enabled keyboard taps; a real typing test is required to establish end-to-end correction.

## Release Packaging & Sparkle Auto-Update Requirements

The application uses the **Sparkle 2** framework for automatic in-app updates.
The update feed URL configured in `Info.plist` is:
`https://github.com/luksiko/dopishi/releases/latest/download/appcast.xml`

### Critical Invariants

1. **`appcast.xml` MUST ALWAYS be attached to every GitHub release**:
   GitHub redirects `/releases/latest/download/appcast.xml` to `/releases/download/<latest-tag>/appcast.xml`. If the latest release lacks `appcast.xml`, all installed apps checking for updates receive **HTTP 404** and display *"Update Error! An error occurred in retrieving update information. Please try again later."*
2. **Always package via `scripts/package-release.sh`**:
   The packaging script builds the universal release bundle, signs it, and automatically generates all release assets:
   - `Dopishi-<version>-arm64.dmg` (Apple Silicon: ultra-lightweight ~7.5 MB for direct download)
   - `Dopishi-<version>-arm64.zip`
   - `Dopishi-<version>-x86_64.dmg` (Intel Macs: ~7.8 MB for direct download)
   - `Dopishi-<version>-x86_64.zip`
   - `Dopishi-<version>-universal.dmg` (Universal: All Macs & Homebrew Cask)
   - `Dopishi-<version>-universal.zip` (Universal: Sparkle in-place auto-update download)
   - `appcast.xml` (Sparkle RSS feed referencing the universal zip)
3. **Mandatory Multi-Asset Release Command**:
   When publishing a new release on GitHub, attach all packages plus `appcast.xml`:
   ```bash
   gh release create "v${VERSION}" \
       "Dopishi-${VERSION}-arm64.dmg" \
       "Dopishi-${VERSION}-arm64.zip" \
       "Dopishi-${VERSION}-x86_64.dmg" \
       "Dopishi-${VERSION}-x86_64.zip" \
       "Dopishi-${VERSION}-universal.dmg" \
       "Dopishi-${VERSION}-universal.zip" \
       "appcast.xml" \
       --title "Dopishi v${VERSION}" \
       --notes "..."
   ```
4. **Post-Release Verification**:
   Immediately verify the live appcast URL after creating the GitHub release:
   ```bash
   curl -ILs "https://github.com/luksiko/dopishi/releases/latest/download/appcast.xml" | grep -E "HTTP/|location:"
   ```
   The final status code **MUST** be `HTTP/2 200`.
5. **Sync Homebrew Tap**:
   After the release is live, update `Casks/dopishi.rb` and sync with `luksiko/homebrew-tap`:
   ```bash
   bash scripts/bump-cask.sh "${VERSION}" "Dopishi-${VERSION}-universal.dmg"
   ```
6. **Sparkle Version Comparison (`sparkle:version` vs `CFBundleVersion`)**:
   `sparkle:version` MUST always match the integer build number `CFBundleVersion` (`CURRENT_PROJECT_VERSION`), while `sparkle:shortVersionString` contains the marketing version (`1.5.1`). If `sparkle:version` is set to "1.5.1", Sparkle compares `"7"` (current build) against `"1.5.1"`, considers build 7 newer than 1.5.1, and reports *"You're up to date! Dopishi 1.5.1 is currently the newest version available (You are currently running version 1.5.0.)"*. `scripts/package-release.sh` extracts `CFBundleVersion` automatically.
