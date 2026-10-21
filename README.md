<p align="center">
  <img src="screenshots/icon.png" width="96" height="96" alt="Dopishi App Icon">
</p>

<h1 align="center">Dopishi</h1>

<p align="center">
  <strong>The intelligent, privacy-first macOS keyboard layout switcher and instant text converter.</strong>
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <a href="https://github.com/luksiko/dopishi/actions/workflows/build.yml"><img src="https://github.com/luksiko/dopishi/actions/workflows/build.yml/badge.svg" alt="Build Status"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-13%2B%20Ventura-brightgreen.svg" alt="macOS 13+"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/Swift-5-orange.svg" alt="Swift 5"></a>
  <img src="https://img.shields.io/badge/Dependencies-Zero-blue.svg" alt="Zero Dependencies">
  <img src="https://img.shields.io/badge/Privacy-100%25%20Offline-success.svg" alt="100% Offline">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-purple.svg" alt="License: MIT"></a>
</p>

---

<p align="center">
  <img src="screenshots/demo.gif" width="100%" alt="Dopishi in action — instant layout conversion">
</p>

---

## Quick Install

### Homebrew

Install with a single command via [Homebrew](https://brew.sh):

```bash
brew install --cask luksiko/tap/dopishi
```

*(To update: `brew upgrade --cask dopishi`)*

### Direct Download (DMG)

Prefer a standard macOS installer?

<p align="left">
  <a href="https://github.com/luksiko/dopishi/releases/latest">
    <img src="https://img.shields.io/badge/Download-Dopishi.dmg-100000?style=for-the-badge&logo=apple&logoColor=white" alt="Download Dopishi DMG">
  </a>
</p>

1. Download **[Dopishi.dmg](https://github.com/luksiko/dopishi/releases/latest)** for your Mac architecture (Apple Silicon M1/M2/M3/M4 or Intel).
2. Drag **Dopishi** to your **Applications** folder.
3. Launch Dopishi and allow **Accessibility** permissions when prompted.

---

## Why Dopishi?

We’ve all been there: you type a passionate paragraph or a quick code comment, only to look up and see `ghbdtn rfr ltkf` instead of `привет как дела`. 

Dopishi completely eliminates this friction. It runs quietly in your menu bar, consumes less than 30 MB of RAM, and respects your privacy above all else.

### ⚡ The 3 Superpowers

* **1. Real-Time Auto-Correction:**
  Type `ghbdtn ` and Dopishi automatically transforms it into `привет ` right under your cursor. Zero extra keystrokes.
* **2. Instant Smart Conversion (`⇧⇧` Double-Shift):**
  Typed a whole sentence in the wrong layout? Double-tap `Shift` (or your custom shortcut). Dopishi scans backwards to the start of the mistake and converts only the wrong-layout tail.
* **3. Single-Key Layout Switching:**
  Switch layouts effortlessly with a single tap of right `⌥ Option` or `⇪ Caps Lock`. Faster and much more responsive than the built-in macOS shortcut.

---

## 🔒 Privacy & Security by Design

Because keyboard utilities require macOS **Accessibility** permissions, trust is non-negotiable:

* **100% Offline:** Dopishi has **zero network permissions** and makes no internet requests.
* **Zero Keylogging:** Dopishi does not record or store what you type.
* **Secure Fields Protected:** Dopishi automatically detects password fields and secure inputs and completely shuts off text processing.
* **Local-Only SQLite Log:** Optional conversion logging is **disabled by default**. If enabled, records stay strictly on your local machine (`~/Library/Application Support/Dopishi/`) and can be cleared with one click.
* **Auditable Open Source:** Pure native Swift with zero third-party binary blobs.

---

## How It Works

Dopishi maps characters by their **physical key coordinates** (QWERTY layout matrix) rather than arbitrary transliteration tables.

```
Input:  "ghbdtn" (typed on US layout when Russian was intended)
1. Detect source layout: US QWERTY
2. Trace physical key positions: [g, h, b, d, t, n] -> [0x05, 0x04, 0x0B, 0x02, 0x11, 0x2D]
3. Map coordinates to active target layout: Russian ЙЦУКЕН
4. Output: "привет"
```

Punctuation (`?`, `!`, `/`, `@`) and numbers remain perfectly preserved.

### Supported Layouts

Dopishi automatically integrates with your active **System Settings > Keyboard > Input Sources**:
* 🇺🇸 **English** (U.S., ABC, QWERTY)
* 🇷🇺 **Russian** (ЙЦУКЕН)
* 🇺🇦 **Ukrainian**
* 🇩🇪 **German** (QWERTZ)
* 🇫🇷 **French** (AZERTY)
* 🇪🇸 **Spanish** (QWERTY)

---

## Settings & Customization

Dopishi lives unobtrusively in your macOS status bar. Press `⌘,` or click the menu bar icon to customize:

<p align="center">
  <img src="screenshots/general.png" width="650" alt="Dopishi Settings">
</p>

* **Smart Conversion Modes:**
  * **Greedy Line (Recommended):** Auto-detects where the layout switch began and converts just that tail.
  * **Last Word:** Auto-converts only the trailing word before the cursor.
  * **Selection Only:** Strictly converts only explicitly highlighted text.
* **Layout Switch Key:** Choose right `⌥ Option`, `⇪ Caps Lock`, right `⌘ Command`, or `Fn`.
* **Custom Shortcuts:** Record any key combination if you prefer not to use double-shift.
* **Sound & Notifications:** Subtle audio confirmation on conversion.

---

## Build from Source

### Prerequisites

* macOS 13.0 (Ventura) or later
* Xcode 15.0 or later

```bash
# 1. Clone the repository
git clone https://github.com/luksiko/dopishi.git
cd dopishi

# 2. Run unit tests (440+ tests verify layout mapping & heuristics)
bash scripts/test.sh

# 3. Build release universal binary
xcodebuild -project LangSwitcher.xcodeproj \
  -scheme LangSwitcher \
  -configuration Release \
  -derivedDataPath build \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# The built app bundle will be located at:
# build/Build/Products/Release/Dopishi.app
```

---

## Contributing

Contributions are warmly welcomed! Whether you want to add a new keyboard layout, refine dictionary heuristics, or improve localization:

1. Fork the repository and create your feature branch.
2. Ensure all tests pass via `bash scripts/test.sh`.
3. Open a Pull Request with a clear description of your changes.

---

## Acknowledgments & Gratitude

* **Origin:** Dopishi was proudly forked from [langSwitcher](https://github.com/reg2005/langSwitcher) created by [reg2005](https://github.com/reg2005). We express our deepest respect and gratitude to the original author for creating the foundation and inspiring this project.
* **Inspiration:** Inspired by legendary tools like [Caramba Switcher](https://caramba-switcher.com/mac) and [Punto Switcher](https://yandex.ru/soft/punto/), reimagined as an open-source, native, and privacy-respecting macOS utility.

---

## Support & Donations

Dopishi is completely free and open source. If it saves you time and frustration every day, consider supporting its development:

| Network | Address |
|:---|:---|
| **Ethereum / Arbitrum / Base** | `0x30c8b011AF68a963694Ce1E5f54A545442acFEfA` |
| **Bitcoin** | `bc1qtqm7rgma8dcgqc50lmzmyxn729yqrtf9zs7asx` |
| **Solana** | `A4jzTGxP7tbhyDFrcWJKdsA8v5xUwF6UzvC7RFmDRrfi` |
| **Tron (USDT)** | `TDAyNkS36eKyqv9s4KQpu4ebWciQ2bqdW3` |

---

## License

Released under the [MIT License](LICENSE). Free for personal and commercial use.
