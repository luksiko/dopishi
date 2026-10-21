# GEMINI.md — Dopishi Project Architecture & Developer Context

## Overview

**Dopishi** (formerly LangSwitcher, originally evolved from reg2005/langSwitcher) is a lightweight, privacy-focused open-source macOS menu bar utility written in Swift 5. It automatically or on-demand converts text accidentally typed in the wrong keyboard layout (e.g. `ghbdtn` ⇄ `привет`, `руддщ` ⇄ `hello`) and supports single-key system layout switching and real-time auto-correction.

- **Platform**: macOS 13.0+ (Ventura or newer)
- **Frameworks**: SwiftUI, AppKit, Carbon (`TIS`, `CGEvent`, Carbon HotKey APIs), ApplicationServices (`AXUIElement`), `NSSpellChecker`, direct C `sqlite3` API.
- **Dependencies**: Zero external package dependencies. Pure native Swift & macOS system libraries.
- **Detailed History & Knowledge Base**: For comprehensive session-by-session history, platform traps, and deep subsystem breakdowns, see [`PROJECT_KNOWLEDGE.md`](file:///Users/alexeyvassilyev/Sites/langSwitcher/PROJECT_KNOWLEDGE.md).

---

## Directory & File Structure

```
langSwitcher/
├── LangSwitcher.xcodeproj/          # Xcode project configuration
│   └── project.pbxproj             # Uses custom PBX ID format: E1000000XXXXXXXXXXXX
├── LangSwitcher/
│   ├── LangSwitcher.entitlements   # macOS app entitlements
│   ├── Info.plist                  # LSUIElement = YES (menu bar app, no dock icon by default)
│   ├── Resources/
│   │   └── Assets.xcassets         # App icons and status bar icons
│   └── Sources/
│       ├── App/
│       │   ├── LangSwitcherApp.swift   # App entry point (@main SwiftUI App)
│       │   ├── AppDelegate.swift       # NSApplicationDelegate, initializes core services & event monitors
│       │   └── StatusBarController.swift # NSStatusItem management, menu items, status bar icon
│       ├── Models/
│       │   ├── AutocompletionAcceptKey.swift # Autocompletion candidates & accept key options
│       │   ├── KeyboardLayout.swift    # KeyboardLayout model, layout IDs, names, localized labels
│       │   ├── LayoutSwitchKey.swift   # Single-key modifier options (rightOption, capsLock, etc.)
│       │   └── ConversionLog.swift     # SQLite log entry record & export structure
│       ├── Services/
│       │   ├── AccessibilityService.swift # AXUIElement text inspection & synthetic key event emission
│       │   ├── AutoCorrectionGate.swift   # Password/secure field and sensitive app filter
│       │   ├── AutoCorrectionService.swift# Real-time background typing monitor & inline corrector
│       │   ├── AutocompletionEngine.swift # Real-time prefix completion and cross-layout candidate generator
│       │   ├── AutocompletionOverlayController.swift # Floating candidate popup window manager
│       │   ├── ConversionLogStore.swift   # Direct C SQLite3 store for conversion history
│       │   ├── DoubleTapDetector.swift    # Generic modifier double-tap detection
│       │   ├── HotkeyManager.swift        # Global hotkey registration & Double-Shift tap detection
│       │   ├── KeyboardLayoutDetector.swift# Carbon TIS API wrapper for active/installed layouts
│       │   ├── LanguageWordlists.swift    # Offline word frequency lists for fast validation
│       │   ├── LayoutMapper.swift         # Character mapping matrix based on physical key positions
│       │   ├── SettingsManager.swift      # @MainActor ObservableObject wrapping UserDefaults
│       │   ├── SingleKeyLayoutSwitcher.swift # Dedicated single-key layout switching detector
│       │   ├── SpellCheckService.swift    # NSSpellChecker validation to minimize false positives
│       │   ├── TextConverter.swift        # Main conversion engine, wrong layout boundary heuristics
│       │   ├── ThoughtRecovery.swift      # Thought recovery buffer & post-switch candidate generator
│       │   ├── UserDictionary.swift       # User-defined dictionary words persistence
│       │   └── WordlistData.swift         # Compact embedded wordlist frequency data
│       ├── Views/
│       │   ├── AboutView.swift            # About dialog view (app info, links, donations)
│       │   ├── AutocompletionKeyRecorderView.swift # Custom key recording view for accept key
│       │   ├── AutocompletionPopupView.swift # Floating HUD candidate suggestions view
│       │   ├── ConversionLogView.swift    # SQLite history browser, rating, and JSON export view
│       │   ├── HotkeyRecorderView.swift   # Interactive key recording UI for custom shortcuts
│       │   ├── PermissionsView.swift      # Accessibility permission tutorial & status view
│       │   ├── RecoveryPreviewView.swift  # Floating non-activating candidate HUD preview
│       │   └── SettingsView.swift         # Multi-tab settings UI (General, Smart Mode, Keys, etc.)
│       └── Localization/
│           ├── LocalizationManager.swift  # Dynamic runtime string localization engine
│           ├── Strings_en.swift           # English translation catalog
│           └── Strings_ru.swift           # Russian translation catalog
├── LangSwitcherTests/
│   ├── AutoCorrectionGateTests.swift      # Password/app exclusion unit tests
│   ├── AutoCorrectionTests.swift          # End-to-end auto-correction tests
│   ├── HotkeyManagerTests.swift           # Shortcut and modifier timing tests
│   ├── KeyboardLayoutDetectorTests.swift  # Layout detection & parsing tests
│   ├── LanguageWordlistTests.swift        # Wordlist frequency and lookup tests
│   ├── LayoutMapperTests.swift            # Bidirectional character mapping tests across layouts
│   ├── SingleKeyLayoutSwitcherTests.swift # Modifier tap timing & combo-suppression unit tests
│   ├── SpellCheckServiceTests.swift       # NSSpellChecker & script isolation unit tests
│   ├── TextConverterTests.swift           # Greedy line boundary & gibberish detection tests
│   └── ThoughtRecoveryTests.swift         # Thought recovery candidates & candidate HUD tests
├── docs/                                  # Nuxt Content documentation site
├── scripts/
│   ├── grant-accessibility.sh             # Helper script to grant TCC permissions in local dev
│   └── verify-pbxproj.py                  # Xcode project PBX ID format verification script
├── AGENTS.md                              # Mandatory rules for AI agents and test requirements
├── PROJECT_KNOWLEDGE.md                   # Comprehensive knowledge base across all dev chats
└── README.md / README.ru.md               # User-facing documentation
```

---

## Core Systems & Architecture

### 1. Text Conversion Pipeline (`TextConverter.swift` & `LayoutMapper.swift`)
- **Key Positioning Mapping**: Uses physical key positions (QWERTY layout coordinate matrix) to map keys across Latin, Cyrillic, German (QWERTZ), French (AZERTY), Spanish, and Ukrainian layouts.
- **Auto-Detection**: Heuristically scores input text against character maps to determine the source layout (`LayoutMapper.detectSourceLayout`).
- **Gibberish Detection (`looksLikeWrongLayout`)**: Evaluates if the text appears to be typed in the incorrect script relative to the expected keyboard layout.
- **Smart Conversion Modes**:
  - `greedyLine`: Traverses backwards from cursor to the start of the current line, detects where the wrong layout started, and converts only that tail.
  - `lastWord`: Selects and converts only the trailing word.
  - `disabled`: Requires the user to explicitly highlight text before pressing the hotkey.

### 2. Single-Key System Layout Switching (`SingleKeyLayoutSwitcher.swift`)
- Intercepts lone modifier key presses (e.g., tap Right Option, Right Command, or Caps Lock).
- Distinguishes between a lone tap (switches layout) and a modifier used in a combination (e.g. `⌘+C` does NOT trigger layout switch).
- Uses `TISSelectInputSource` to cycle or switch between installed system layouts.

### 3. Real-Time Auto-Correction (`AutoCorrectionService.swift`)
- Listens to global key events via `CGEvent` tap.
- Accumulates characters into a word buffer.
- On delimiter (Space, Enter, punctuation), checks if the word matches wrong-layout patterns.
- Validates the converted candidate with `SpellCheckService` (`NSSpellChecker`) before replacing via synthetic backspaces and clipboard injection.

### 4. Accessibility & Text Replacement (`AccessibilityService.swift`)
- Primary method: macOS Accessibility API (`AXUIElementCopyAttributeValue` for `kAXSelectedTextAttribute` and `kAXSelectedTextRangeAttribute`).
- Fallback method: Synthetic `⌘C` (copy) -> convert on pasteboard -> synthetic `⌘V` (paste).
- Checks permissions via `AXIsProcessTrusted()`.

### 5. Custom Runtime Localization (`LocalizationManager.swift`)
- Does **not** use Apple `.lproj` / `.strings` files.
- Uses swift dictionary catalogs (`Strings_en.swift`, `Strings_ru.swift`).
- All user-facing strings must use `LocalizationManager.shared.t("key")`.
- Dynamic instant language switching without restarting the app.

---

## Critical Rules & Caveats

1. **Test Verification**:
   - Tests **must** be executed after modifying any Swift files:
     ```bash
     xcodebuild test \
       -project LangSwitcher.xcodeproj \
       -scheme LangSwitcher \
       -destination 'platform=macOS' \
       CODE_SIGN_IDENTITY="-" \
       CODE_SIGNING_REQUIRED=NO \
       CODE_SIGNING_ALLOWED=NO
     ```
   - All tests must pass before completing tasks.

2. **Xcode Project File (`project.pbxproj`)**:
   - All custom PBX IDs follow the 24-character hex format `E1000000XXXXXXXXXXXX`.
   - When adding files, remember to update `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase`.

3. **Substrings in Layout IDs**:
   - `"russian"` contains `"us"` as a substring. Pattern ordering in `LayoutCharacterMap.allMaps` is critical. Never reorder without verifying map resolution.

4. **Swift Concurrency / MainActor**:
   - `SettingsManager`, `TextConverter`, `AutoCorrectionService`, `ConversionLogStore`, and `LocalizationManager` are `@MainActor`.
   - Enum computed properties calling `LocalizationManager.shared.t()` must be annotated with `@MainActor`.

5. **Dual Localization**:
   - Whenever a string key is introduced, it must be added to **both** `Strings_en.swift` and `Strings_ru.swift`.
