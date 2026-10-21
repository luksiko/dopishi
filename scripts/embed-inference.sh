#!/bin/bash
# Embeds local AI inference engine and supporting libraries into the application bundle.
# Usage: bash scripts/embed-inference.sh /path/to/LangSwitcher.app
set -euo pipefail

APP_PATH="${1:?Usage: bash scripts/embed-inference.sh /path/to/LangSwitcher.app}"

if [[ ! -d "$APP_PATH/Contents" ]]; then
    echo "Error: invalid bundle at $APP_PATH" >&2
    exit 1
fi

HELPERS_DIR="$APP_PATH/Contents/Helpers"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"

chmod -R u+w "$APP_PATH/Contents" 2>/dev/null || true
mkdir -p "$HELPERS_DIR" "$FRAMEWORKS_DIR"

# 1. Embed llama-server executable
if [[ -f "/opt/homebrew/bin/llama-server" ]]; then
    rm -f "$HELPERS_DIR/llama-server"
    cp -fp /opt/homebrew/bin/llama-server "$HELPERS_DIR/"
fi

# 2. Embed supporting dylibs and libraries
if [[ -d "/opt/homebrew/lib" ]]; then
    cp -fp /opt/homebrew/lib/libllama*.dylib "$FRAMEWORKS_DIR/" 2>/dev/null || true
    cp -fp /opt/homebrew/lib/libggml*.dylib "$FRAMEWORKS_DIR/" 2>/dev/null || true
    cp -fp /opt/homebrew/lib/libmtmd*.dylib "$FRAMEWORKS_DIR/" 2>/dev/null || true
fi

if [[ -d "/opt/homebrew/opt/openssl@4/lib" ]]; then
    cp -fp /opt/homebrew/opt/openssl@4/lib/libssl*.dylib "$FRAMEWORKS_DIR/" 2>/dev/null || true
    cp -fp /opt/homebrew/opt/openssl@4/lib/libcrypto*.dylib "$FRAMEWORKS_DIR/" 2>/dev/null || true
fi

if [[ -f "/opt/homebrew/opt/libomp/lib/libomp.dylib" ]]; then
    cp -fp /opt/homebrew/opt/libomp/lib/libomp.dylib "$FRAMEWORKS_DIR/" 2>/dev/null || true
fi

LIBEXEC_SRC=$(find /opt/homebrew/Cellar/ggml -name "libexec" -type d 2>/dev/null | head -n 1 || true)
if [[ -n "$LIBEXEC_SRC" && -d "$LIBEXEC_SRC" ]]; then
    cp -R -p "$LIBEXEC_SRC" "$FRAMEWORKS_DIR/" 2>/dev/null || true
fi

# Symlink Contents/lib -> Frameworks for any relative lookups
if [[ ! -e "$APP_PATH/Contents/lib" ]]; then
    ln -s Frameworks "$APP_PATH/Contents/lib"
fi

echo "Embedded AI inference engine into $APP_PATH"
