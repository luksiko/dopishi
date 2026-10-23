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
- **Profanity / Curse Words Filtering (`ProfanityFilter.swift`)**:
  - By default (`autoCompletionSuggestProfanity = false`), offensive words, curses, and Slavic mat are excluded from all suggestion candidates (frequency lists, NSSpellChecker completions, user dictionary, adaptive bigrams, and cross-layout translations).
  - Uses comprehensive regular expressions and exact lookup tables for Slavic mat (`хуй*`, `пизд*`, `[её]б*`, `бляд*`), English obscenities, and Ukrainian/Polish forms with zero false positives on legitimate words (`оскорблять`, `рубля`, `хлеб`, `ребёнок`, `бляшка`, `художник`, `хулиган`, `cocktail`).
  - Users can explicitly enable suggesting profanity via the "Suggest profanity and curse words" toggle in Settings.

### Local AI Engine, Personalization & Multi-Word Continuation (Sprints 2 & 3)
- **Local Neural Inference Engine (`AIInferenceEngine.swift`)**:
  - Runs embedded `llama-server` on an ephemeral localhost port with full offline isolation (zero telemetry or cloud calls).
  - Dynamically starts and monitors daemon health with fast graceful lifecycle management.
  - Generates 2–4 word predictive text continuations with a 350 ms typing debounce.
- **Multi-Model Catalog (`RecommendedAIModel.swift`, `AIModelManager.swift`)**:
  - Curated lightweight models catalog:
    - *Qwen 2.5 0.5B Instruct* (~390 MB, recommended default).
    - *SmolLM2 360M Instruct* (~229 MB, ultra-lightweight).
    - *Qwen 2.5 1.5B Instruct* (~986 MB, high reasoning).
    - *Llama 3.2 1B Instruct* (~770 MB, Meta compact model).
  - 1-click download with speed/progress tracking, model deletion, and instant model switching.
- **Custom Instructions / Personalization**:
  - `aiCustomInstructions` in Settings allows users to define tone and guidelines (e.g. "I am a programmer, write concisely, keep technical terms in English").
  - Formatted into prompt via `[System: \(instructions)]\n\(context)`.
  - Preset quick-pills in UI ("Programmer", "Concise", "Business").
- **Extended Productivity Statistics**:
  - Persisted tracking of saved characters (`savedCharactersCount`), keystrokes/clicks (`savedClicksCount`), and corrections (`conversionCount`).
  - Integrated into autocompletion accept pipeline and autocorrection engine.
  - Reset statistics with confirmation dialog.
- **Battery-Saving Mode (`PowerService.swift`)**:
  - Real-time `IOPowerSources` monitoring to detect AC vs Battery power.
  - Automatically suspends local AI inference on battery power to conserve energy, falling back to instant offline dictionary mode.
- **Typing Flow & Multi-Word Prediction Fixes**:
  - Triggers AI debounce upon space boundary and punctuation, enabling immediate prediction of subsequent 2–3 words after finishing a word.
  - Context engine extracts rich sentence context from accessibility `textBeforeCaret` (up to 300 characters).
  - Seamless inline Ghost Text rendering and one-key acceptance for complete multi-word phrases.

---

## 7. Auto-Correction & Layout Switching Pipeline Hardening

### 1. Decoupled Layout Switching Settings
- **Problem**: Previously, "layout switch after conversion" setting description referred only to hotkey conversion ("после нажатия горячей клавиши"), confusing users who wanted language switching automatically after background auto-correction.
- **Solution**: Decoupled the settings:
  - `general.layoutSwitch` ("Переключение раскладки по горячей клавише") for explicit manual hotkey conversion (`layoutSwitchMode`: `.always`, `.ifLastWordConverted`, `.ifAnyWordConverted`, `.never`).
  - `general.autoCorrectionSwitchLayout` ("Переключать язык ввода после автоисправления") dedicated specifically to real-time auto-correction on word boundaries.

### 2. Elimination of Premature Traversal Failure in `AccessibilityService`
- **Problem**: `resolveFocusedTextNode` had a strict 128-node / 40ms limit followed by `guard pending.isEmpty else { return nil }`. In real apps with large DOM or widget trees (Chromium, Electron, JetBrains, complex WebViews), `pending` was never empty, causing the function to discard a valid focused editor and return `nil`.
- **Solution**:
  - If a confirmed editor (`result != nil`) is resolved, return it directly rather than dropping it due to unvisited sibling branches.
  - Expanded `AutoCorrectionGate.textInputRoles` to include `"AXSearchField"`, `"AXComboBox"`, and `"AXWebArea"`.
  - Added fallback direct query on `AXUIElementCreateSystemWide()` and frontmost application `AXUIElementCreateApplication(pid)` for `focusedFieldRole()` and `captureReplacementTarget()`.

### 3. Asynchronous Paste Completion & Layout Switch Race in `pasteVerifiedSuffix`
- **Problem**: For Web and Electron editors where direct AX attribute setting is rejected (`AXSelectedText`), `pasteVerifiedSuffix` dispatches synthetic `⌘V` and then waits for `kAXValueAttribute` to update via `PasteConfirmation` (20 attempts over 100ms). Web and Electron editors frequently do not support or do not update `kAXValueAttribute` within 100ms. As a result, `applied` was evaluated as `false`, the completion handler passed `false`, and `KeyboardLayoutDetector.switchToLayout(...)` was never called, leaving the keyboard layout in the wrong language even though the text had been visually replaced on screen.
- **Solution**:
  - Once verified selection is matched and `dispatchVerifiedPaste` dispatches `⌘V` (`sent == true`), notify `completion(true)` immediately.
  - Layout switching executes without lag before the next user keystroke arrives.
  - Added `kTISPropertyInputSourceIsSelectCapable` check in `KeyboardLayoutDetector.switchToLayout` to prevent selecting non-selectable input source components.

---

## 8. Rebranding to Dopishi & Homebrew Tap Setup

### 1. Rebranding & Architectural Cohesion
- Renamed application to **Dopishi** (macOS bundle: `Dopishi.app`, binary: `Dopishi`).
- `PRODUCT_NAME = Dopishi` configured in Xcode project build settings, while maintaining `SWIFT_MODULE_NAME = LangSwitcher` and internal PBX structure to preserve zero-friction compatibility with all 441 unit tests.
- Updated `PRODUCT_BUNDLE_IDENTIFIER = com.dopishi.app` and test host bundle identifier to `com.dopishi.testhost`.
- Graceful persistence migration: automatically migrates Application Support directories, logs (`conversion_log.sqlite`), user history (`user_text_history.sqlite`), and downloaded AI models (`Models/`) from `~/Library/Application Support/LangSwitcher` to `~/Library/Application Support/Dopishi`.
- Credited original upstream fork ([langSwitcher by reg2005](https://github.com/reg2005/langSwitcher)) in `README.md`, `README.ru.md`, `AboutView.swift`, and runtime string catalogs.

### 2. GitHub Repository & Homebrew Tap
- GitHub repository renamed to `https://github.com/luksiko/dopishi` with local `git remote origin` updated.
- Created and initialized public tap repository `https://github.com/luksiko/homebrew-tap` with complete Cask definition `Casks/dopishi.rb`.
- Added `scripts/bump-cask.sh` for automated sha256 calculation and single-step synchronization between releases and the tap repository.
- Modern Cask syntax (`depends_on macos: :ventura`, `livecheck`, `zap trash`) verified with `brew info --cask dopishi`.

---

## Session 8: macOS Input Stability & Deadlock Prevention

### 1. The Anatomy of macOS WindowServer Deadlocks with CGEventTap
- **The Symptom**: Hardware mouse cursor continues moving smoothly, but mouse clicks, text selection, and window switching (`⌘+Tab`, `Escape`) stop functioning system-wide across all applications.
- **Root Cause**:
  1. Registering active event taps (`CGEvent.tapCreate(..., options: .defaultTap)`) halts WindowServer event dispatch until the tap's callback function returns.
  2. If the callback ever invokes `DispatchQueue.main.sync` while the main thread is executing synchronous Accessibility IPC (`AXUIElementCopyAttributeValue`), a distributed deadlock occurs: WindowServer waits for the tap callback, the tap callback waits for the main thread, and the main thread waits for Mach IPC from an external app.
  3. Including mouse events (`leftMouseDown`, `rightMouseDown`, `otherMouseDown`) in `.defaultTap` routes every click in the OS through the client process.
- **Strict Architecture Invariants**:
  1. **Never monitor mouse clicks via active `CGEventTap`**: Mouse clicks must be monitored passively and asynchronously using `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`. Global monitors live outside the WindowServer blocking queue and can never stall system clicks.
  2. **Never call `DispatchQueue.main.sync` in a `CGEventTap` callback**: Event tap callbacks must complete in <1ms without synchronous dispatches to other queues.
  3. **Strict Accessibility IPC Timeouts**: All cross-process `AXUIElement` queries must set `AXUIElementSetMessagingTimeout(element, 0.05)` (50ms). Unresponsive apps or system dialogs (like `System Settings`) must never block the client's main thread.
  4. **No Continuous Accessibility Polling Timers**: Never poll `AXUIElementCreateSystemWide()` on a short timer loop (e.g. 250ms). Refresh positions reactively on user typing or application focus notifications.
  5. **Background Floating HUDs (`LSUIElement`)**: Non-activating panels displayed by menu bar utilities while external apps are focused must use `orderFrontRegardless()` instead of `orderFront(nil)`.

---

## 9. Sparkle 2 Auto-Update Architecture & Release Protocol

### 1. Feed Resolution Mechanics
- `Info.plist` configures `SUFeedURL = https://github.com/luksiko/dopishi/releases/latest/download/appcast.xml`.
- When Sparkle makes a network request for update metadata, GitHub automatically returns HTTP 302 redirecting `releases/latest/download/appcast.xml` to `releases/download/<latest-tag>/appcast.xml`.
- **The Pitfall**: If a new release (e.g. `v1.5.0`) is published with only the `.dmg` and `.zip` binaries, but without `appcast.xml` attached to that release, GitHub answers the redirected request with `HTTP 404 Not Found`.
- **User Impact**: Sparkle reports: *"Update Error! An error occurred in retrieving update information. Please try again later."* to all installed copies worldwide.

### 2. Multi-Architecture Packaging with Universal Sparkle Updates
- To showcase how lightweight and native Dopishi is, GitHub releases provide dedicated architecture builds alongside the universal distribution:
  - `Dopishi-<version>-arm64.dmg` (~7.5 MB) for Apple Silicon Macs (M1/M2/M3/M4).
  - `Dopishi-<version>-x86_64.dmg` (~7.8 MB) for Intel Macs.
  - `Dopishi-<version>-universal.dmg` (~13 MB) for users desiring a single universal installer or Homebrew Cask.
- **Fail-Safe Auto-Updates**: In-app Sparkle updates (`appcast.xml`) always reference `Dopishi-<version>-universal.zip`. This ensures existing users never encounter architecture mismatch errors, while direct downloaders on GitHub benefit from the tiny 7.5 MB download.
- Packaging is automated via `bash scripts/package-release.sh <version>`:
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
- Always verify post-release:
  ```bash
  curl -ILs "https://github.com/luksiko/dopishi/releases/latest/download/appcast.xml"
  ```





