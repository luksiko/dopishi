# PROJECT_KNOWLEDGE.md — LangSwitcher Comprehensive Knowledge Base

> **Purpose**: This document aggregates all critical context, architectural decisions, feature implementations, macOS platform quirks, and troubleshooting insights across all development sessions (chats) of the LangSwitcher project.

---

## 1. Executive Summary

- **Repository**: `luksiko/langSwitcher` (macOS menu bar utility for automatic and on-demand keyboard layout switching and text conversion).
- **Current Version**: `v1.2.1` (Build 4).
- **Target OS**: macOS 13.0+ (Ventura or newer).
- **Core Stack**: Swift 5, SwiftUI, AppKit, Carbon (`TIS`, `CGEvent`), ApplicationServices (`AXUIElement`), `NSSpellChecker`, direct C `sqlite3` API.
- **Dependencies**: Zero external package dependencies. Pure native Swift & system frameworks.

---

## 2. Chronology of Development Sessions (Chat History)

### Session 1: Context & Governance Bootstrap
- **Conversation ID**: `c248f057-7dd5-43b3-b4b7-5e9e4e2705a3`
- **Objective**: Establish foundational project documentation, developer guidelines, and architecture context for AI pair programming.
- **Key Outcomes**:
  - Authored [`AGENTS.md`](file:///Users/alexeyvassilyev/Sites/langSwitcher/AGENTS.md) with strict requirements: mandatory test execution on every Swift change, dual localization (`en` + `ru`), and `E1000000XXXXXXXXXXXX` PBX ID formatting.
  - Authored [`GEMINI.md`](file:///Users/alexeyvassilyev/Sites/langSwitcher/GEMINI.md) defining system architecture, memory model, and concurrency rules.

### Session 2: Single-Key Layout Switching
- **Conversation ID**: `a9942ce1-1a4f-4612-ae9d-995b23e5a9a7`
- **Objective**: Enable switching system keyboard layouts via a single modifier key tap (e.g. Right Option, Left Control, Caps Lock).
- **Key Outcomes**:
  - Implemented [`SingleKeyLayoutSwitcher.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Services/SingleKeyLayoutSwitcher.swift) and [`LayoutSwitchKey.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Models/LayoutSwitchKey.swift).
  - Built `SingleKeyDetector` with combo-suppression logic (differentiates between lone tap and modifier held during shortcuts like `⌘C`).
  - Added dedicated tests in `SingleKeyLayoutSwitcherTests.swift`.

### Session 3: Fork Ecosystem Analysis
- **Conversation ID**: `a0bf6dc2-492c-4d34-a2af-8ae8d84f61c5`
- **Objective**: Audit open-source macOS forks and related projects to discover high-value enhancements.
- **Key Outcomes**:
  - Analyzed Samuel Kutsenko's fork (`Samuel-Ku/langSwitcher`, branch `remotes/samuel/main`).
  - Identified major candidate features: Thought Recovery, AutoCorrection Gate (sensitive app/input filtering), Offline Frequency Wordlists, and User Dictionary.

### Session 4: Menu Bar Icon Language Badge
- **Conversation ID**: `12b78279-6e6d-4681-80ce-b8b69f8d6b6a`
- **Objective**: Display the current active language code (e.g. `RU`, `EN`) inside a framed badge directly on the menu bar icon.
- **Key Outcomes**:
  - Updated [`StatusBarController.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/App/StatusBarController.swift) with dynamic bitmap rendering for framed badges using `NSGraphicsContext`.
  - Added setting toggle `showLanguageBadge` with instant status bar refresh on input source change (`kTISNotifySelectedKeyboardInputSourceChanged`).
  - Committed as `4f85a78`.

### Session 5: Real-Time Auto-Correction, TCC Permissions & v1.2.1 Bugfixes
- **Conversation ID**: `4ca25087-48f1-44cf-9f7a-0f64e5285941` (Current Session)
- **Objective**: Implement real-time wrong layout auto-correction on Space/Punctuation, diagnose why Double Shift stopped working, and fix macOS TCC permission traps.
- **Key Outcomes**:
  - **Auto-Correction Engine**: Created [`AutoCorrectionService.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Services/AutoCorrectionService.swift) using `.defaultTap` `CGEventTap` on `.keyDown`.
  - **NSSpellChecker Script Isolation Bug**: Fixed a bug where Cyrillic strings (`фгещ`) in `NSSpellChecker` English checks returned `NSNotFound` (false positive "valid word"). Implemented `matchesExpectedScript()` in [`SpellCheckService.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Services/SpellCheckService.swift).
  - **TCC Permission Invalidation**: Diagnosed why ad-hoc macOS builds lose Accessibility trust when updated in `/Applications`. Documented resolution (minus button `[-]` reset).
  - **Smart Conversion Whitespace Handling**: Improved `selectAndReplaceLastWord` in [`AccessibilityService.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Services/AccessibilityService.swift) to step left over trailing spaces.
  - **Settling Delay**: Added 50ms pause in [`AppDelegate.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/App/AppDelegate.swift) before smart conversion.
  - **Tagged & Released**: Tagged `v1.2.1` (`9835dc1`) and published GitHub release.

### Session 6: Deep Integration of Samuel Kutsenko's Fork (Thought Recovery)
- **Conversation ID**: `cf9f2cd8-a86b-4c94-80ac-b8965fb8a155`
- **Objective**: Port senior-level architectural modules from `remotes/samuel/main`.
- **Key Outcomes**:
  - **AutoCorrectionGate**: Context-aware exclusion of password fields, secure text fields, and sensitive apps (Terminal, Xcode, IDEs, games).
  - **Thought Recovery**: Buffers recently typed words, identifies wrong-layout phrases post-switch, and presents candidates via floating HUD overlay ([`RecoveryPreviewView.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Views/RecoveryPreviewView.swift)).
  - **Offline Frequency Wordlists**: High-performance embedded wordlists ([`WordlistData.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Services/WordlistData.swift), [`LanguageWordlists.swift`](file:///Users/alexeyvassilyev/Sites/langSwitcher/LangSwitcher/Sources/Services/LanguageWordlists.swift)) for EN, RU, UK, and PL.
  - **User Dictionary**: Local persistence of user-added dictionary words.
  - **Test Suite Expansion**: Total tests grew to **222 unit tests** with 100% pass rate.

---

## 3. Core Architectural Subsystems

```
┌────────────────────────────────────────────────────────────────────────┐
│                          LangSwitcher App                              │
└──────┬──────────────────┬──────────────────┬───────────────────┬───────┘
       │                  │                  │                   │
┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐     ┌──────▼──────┐
│ Text Conv.  │    │ AutoCorrect │    │ Thought Rec.│     │ Single-Key  │
│  Pipeline   │    │   Service   │    │   Engine    │     │   Switch    │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘     └──────┬──────┘
       │                  │                  │                   │
┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐     ┌──────▼──────┐
│LayoutMapper │    │AutoCorrGate │    │WordlistData │     │SingleKeyDet.│
│TextConverter│    │SpellCheck   │    │LanguageLists│     │DoubleTapDet.│
└─────────────┘    └─────────────┘    └─────────────┘     └─────────────┘
```

### A. Text Conversion Pipeline
- **Physical Matrix Mapping (`LayoutMapper.swift`)**: Uses QWERTY matrix coordinates to map keys across Latin (US/ABC), Cyrillic (Russian, Russian-PC, Ukrainian), German (QWERTZ), French (AZERTY), and Spanish.
- **Conversion Modes (`TextConverter.swift`)**:
  - `greedyLine`: Traverses backwards from cursor to beginning of line, finds wrong-layout boundary, and converts only the erroneous tail.
  - `lastWord`: Selects and converts only the trailing word.
  - `disabled`: Manual conversion requiring highlighted text.

### B. Real-Time Auto-Correction
- **Keystroke Interception (`AutoCorrectionService.swift`)**:
  - Runs a `.defaultTap` `CGEventTap` on `keyDown`.
  - Accumulates characters in a buffer.
  - On boundary key (Space, punctuation), verifies candidate using `TextConverter.looksLikeWrongLayout` and `SpellCheckService`.
  - Dispatches replacement via backspaces + clipboard injection tagged with `syntheticEventMarker` (`0x4C535749` / `'LSWI'`).
- **Gatekeeper (`AutoCorrectionGate.swift`)**:
  - Checks `AXUIElement` attributes (`kAXIsPasswordUIElementAttribute`, `kAXRoleAttribute == "AXTextField"` with secure subrole).
  - Excludes terminal emulators (`com.apple.Terminal`, `com.googlecode.iterm2`, `net.kovidgoyal.kitty`, `alacritty`) and IDEs to prevent corrupting code or CLI inputs.

### C. Thought Recovery Engine
- **Concept (`ThoughtRecovery.swift`)**: When a user switches layout because they realize they've typed gibberish, Thought Recovery identifies the trailing wrong-layout text and offers instant replacement.
- **HUD Preview (`RecoveryPreviewView.swift`)**: Floating non-activating AppKit window that displays converted text candidate and can be applied via key press or clicked.
- **Offline Wordlists (`WordlistData.swift`, `LanguageWordlists.swift`)**: Embedded frequency lists for instantaneous validation without IPC overhead of `NSSpellChecker`.

### D. Single-Key Layout Switching
- **Lone Modifier Detection (`SingleKeyLayoutSwitcher.swift`, `SingleKeyDetector.swift`)**:
  - Intercepts modifier key events (`flagsChanged`).
  - Measures press duration (10ms jitter threshold to 450ms max tap).
  - Cancels trigger if any other key was pressed during hold (`comboUsed = true`).
  - Cycles system input sources via `TISSelectInputSource`.

---

## 4. Critical macOS Platform Traps & Proven Solutions

### 1. Ad-Hoc Code Signing & TCC Accessibility Invalidation
- **Problem**: When LangSwitcher is compiled with `CODE_SIGN_IDENTITY="-"`, macOS generates an ad-hoc signature. Every time the binary is rebuilt, its code directory hash (`CDHash`) changes.
- **Symptom**: In System Settings → Privacy & Security → Accessibility, LangSwitcher appears checked/ON, but `AXIsProcessTrusted()` returns `false`. All `CGEvent.post()` calls are silently dropped by WindowServer, and `CGEvent.tapCreate()` returns `nil`.
- **Permanent Solution**:
  1. Open **System Settings → Privacy & Security → Accessibility**.
  2. Select **LangSwitcher** and click the **minus `[-]` button** to completely remove the entry.
  3. Re-launch the app and click "Open System Settings" to grant permission cleanly.
  4. (Optional CLI reset): `tccutil reset Accessibility com.langswitcher.app`.

### 2. `NSSpellChecker` Cross-Script False Positives
- **Problem**: `NSSpellChecker.shared.checkSpelling(of:startingAt:language:)` only inspects words matching the script of the requested language. When passed a string in an unrelated script (e.g. Cyrillic `фгещ` in an English check), it skips checking and returns `location = NSNotFound`.
- **Symptom**: Code treating `location == NSNotFound` as "valid word" concluded that `фгещ` was valid English, causing auto-correction to abort.
- **Permanent Solution**:
  - Added `SpellCheckService.matchesExpectedScript(word:language:)` to ensure letters match Unicode ranges (`0x0400...0x052F` for Cyrillic, Latin code blocks for EN/DE/FR/ES) *before* querying `NSSpellChecker`.

### 3. Physical Key Release Collisions on Hotkey Trigger
- **Problem**: When triggering Double Shift or regular hotkeys, the physical modifier key release event is dispatched by WindowServer concurrently with synthetic keystrokes.
- **Symptom**: Synthetic `Shift+Option+Left` or `⌘C` events merge with lingering physical Shift states, corrupting text selection in target apps.
- **Permanent Solution**:
  - Added a 50ms pause (`usleep(50_000)` / `DispatchQueue.main.asyncAfter`) before smart conversion to ensure the system event queue stabilizes.

### 4. Trailing Whitespace in Smart Selection
- **Problem**: When typing `word ` and triggering conversion, Shift+Option+Left selects only the trailing space.
- **Symptom**: `TextConverter.looksLikeWrongLayout(" ")` returns false; conversion aborts.
- **Permanent Solution**:
  - Updated `selectAndReplaceLastWord` to detect pure whitespace selections and perform an additional Shift+Option+Left step leftwards, capturing the actual word along with the trailing space.

### 5. Custom PBX IDs in `project.pbxproj`
- **Rule**: All PBX IDs in `LangSwitcher.xcodeproj/project.pbxproj` MUST follow the 24-character hexadecimal format `E1000000XXXXXXXXXXXX`.
- **Verification Script**: Use `python3 scripts/verify-pbxproj.py` to ensure project file integrity and prevent build breaks.

### 6. `LSMultipleInstancesProhibited` and Test Runner Conflicts
- **Problem**: `Info.plist` includes `<key>LSMultipleInstancesProhibited</key><true/>` and `AppDelegate` enforces single-instance locking via `instance.lock`.
- **Symptom**: If `/Applications/LangSwitcher.app` is already running when `xcodebuild test` runs, LaunchServices rejects launching the test runner app with `IDELaunchServicesLauncher: Code: 20` ("The LaunchServices launcher has returned an error").
- **Permanent Solution**: Terminate any running app instance (`killall LangSwitcher`) before launching `xcodebuild test`.

---

## 5. Mandatory Verification & Test Rules

1. **Test Verification**:
   ```bash
   xcodebuild test \
     -project LangSwitcher.xcodeproj \
     -scheme LangSwitcher \
     -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY="-" \
     CODE_SIGNING_REQUIRED=NO \
     CODE_SIGNING_ALLOWED=NO
   ```
2. **All 238 tests must pass** prior to committing any Swift file modification.
3. **Dual Localization**: Every new UI string key must be registered in both `Strings_en.swift` and `Strings_ru.swift`.
4. **MainActor Context**: Views, `SettingsManager`, `LocalizationManager`, `TextConverter`, and `AutoCorrectionService` require `@MainActor` annotations.

---

## 6. Word Autocompletion System (Stage 2)

- **Engine (`AutocompletionEngine.swift`)**:
  - Scores prefix matches from `UserDictionary` (1000 pts), embedded frequency wordlists (100–500 pts), system `SpellCheckService.completions` (50 pts), and cross-layout translations via `LayoutMapper.convert` (40–400 pts).
  - Cross-layout completions automatically detect opposite layouts (e.g. `ghbd` → `привет`, `рудд` → `hello`).
- **Overlay Controller & Popup (`AutocompletionOverlayController.swift`, `AutocompletionPopupView.swift`)**:
  - Floating non-activating `NSPanel` (.popUpMenu level) positioned relative to the text caret via `AccessibilityService.caretScreenRect()`.
  - Number badges (`1`–`5`), cross-layout tags (`RU ⇄ EN`), smooth selection highlight, and key hints.
- **Configurable Accept Key & Custom Key Recording (`AutocompletionAcceptKey.swift`, `AutocompletionKeyRecorderView.swift`)**:
  - Accept options: Tab (`⇥`), Space (`␣`), Enter (`↩`), Right Arrow (`→`), or Custom Key.
  - Interactive key recorder captures any single key or key+modifier combo.
  - Number keys `1`–`5` directly insert candidate without extra navigation.
  - Dedicated event interception in `AutoCorrectionService` event tap guarantees keys are swallowed (`return nil`) without leaking to the host app.

### Autocompletion Enhancements (Bigrams, Adaptive Store, Ghost Text, Excluded Apps)
- **Contextual Bigrams & N-Grams**:
  - `AutocompletionAdaptiveStore` provides built-in high-frequency bigram pairs for Russian and English (e.g., `добрый` -> `день`/`вечер`, `pull` -> `request`, `git` -> `status`).
  - Preceding word tracking (`previousWord`) in `AutoCorrectionService` allows `AutocompletionEngine` to boost scores (+800 bonus) and suggest likely next words on prefix match.
- **Adaptive Personal Frequency**:
  - Automatically records word usage count and bigram transitions when candidates are accepted.
  - Frequently selected words receive an adaptive frequency boost up to +1500 points, naturally prioritizing them to position #1.
  - Added "Reset Learned Vocabulary" button in Settings for user privacy control.
- **Inline Ghost Text**:
  - `GhostTextOverlayController` and `GhostTextPreviewView` display a semi-transparent text continuation directly adjacent to the caret.
  - `ignoresMouseEvents = true` enables seamless clicking through the ghost text into the active document.
  - Configurable `AutocompletionDisplayMode` (`.popup`, `.ghostText`, `.both`).
  - Pressing the configured Accept key (Tab, Space, Enter, etc.) inserts the ghost text candidate even when the popup HUD is not active.
- **Application Exclusion List**:
  - `ExcludedAppsSettingsView` allows users to disable autocompletion and auto-correction in sensitive or developer applications (Terminal, iTerm, Figma, games, etc.).
  - Supports quick addition from running applications menu or selecting an `.app` from disk.
  - Enforced via `AutoCorrectionGate.allowsAutoCorrection(role:subrole:bundleID:excludedBundleIDs:)`.
