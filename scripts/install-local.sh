#!/usr/bin/env bash
# Install a complete, consistently signed bundle; keep backups outside LaunchServices scans.
set -euo pipefail

source_app="${1:?Usage: bash scripts/install-local.sh /path/to/built/LangSwitcher.app}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
identity="${LANGSWITCHER_SIGNING_IDENTITY:-}"
if [[ -z "$identity" || "$identity" == "-" ]]; then
    echo "Local updates require LANGSWITCHER_SIGNING_IDENTITY with a stable signing certificate." >&2
    exit 1
fi
if [[ ! -d "$source_app/Contents/MacOS" ]]; then
    echo "A complete built application bundle is required: $source_app" >&2
    exit 1
fi

installed_app="/Applications/LangSwitcher.app"
backup_dir="$HOME/Library/Application Support/LangSwitcher/Backups"
staging_dir="$(mktemp -d /Applications/.LangSwitcher-install.XXXXXX)"
cleanup() {
    result=$?
    # Restore the old bundle if replacement failed after moving it aside.
    if [[ -d "$staging_dir/previous.app" && ! -e "$installed_app" ]]; then
        mv -- "$staging_dir/previous.app" "$installed_app" || true
    fi
    rm -rf -- "$staging_dir"
    exit "$result"
}
trap cleanup EXIT

# Sign and verify before touching the installed application or its process.
ditto "$source_app" "$staging_dir/LangSwitcher.app"
bash "$script_dir/embed-inference.sh" "$staging_dir/LangSwitcher.app"
bash "$script_dir/sign-app.sh" "$staging_dir/LangSwitcher.app"
if [[ -d "$installed_app" ]]; then
    # Require the same designated identity for certificate-signed updates.
    # Migration from ad-hoc signing needs fresh Accessibility consent once.
    signature="$(codesign --display --verbose=2 "$installed_app" 2>&1)"
    if [[ "$signature" != *"Signature=adhoc"* ]]; then
        requirement="$(codesign --display --requirements - "$installed_app" 2>&1 | sed -n 's/^designated => //p')"
        if [[ -z "$requirement" ]]; then
            echo "Cannot read the installed application's signing requirement." >&2
            exit 1
        fi
        codesign --verify --strict -R "=$requirement" "$staging_dir/LangSwitcher.app"
    else
        echo "Migrating from ad-hoc signing: renew Accessibility consent after this installation."
    fi
    mkdir -p "$backup_dir"
    backup="$backup_dir/LangSwitcher-$(date +%Y%m%d-%H%M%S)-$$.app.zip"
    ditto -c -k --sequesterRsrc --keepParent "$installed_app" "$backup"
    echo "Backup: $backup"
fi

# Stop only the installed copy, never unrelated development/test hosts.
while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill -TERM "$pid"
done < <(pgrep -f '^/Applications/LangSwitcher[.]app/Contents/MacOS/LangSwitcher$' || true)
for ((attempt = 0; attempt < 50; attempt++)); do
    if ! pgrep -f '^/Applications/LangSwitcher[.]app/Contents/MacOS/LangSwitcher$' >/dev/null; then
        break
    fi
    sleep 0.2
done
if pgrep -f '^/Applications/LangSwitcher[.]app/Contents/MacOS/LangSwitcher$' >/dev/null; then
    echo "LangSwitcher has not quit; installation cancelled." >&2
    exit 1
fi
if [[ -e "$installed_app" ]]; then
    mv -- "$installed_app" "$staging_dir/previous.app"
fi
mv -- "$staging_dir/LangSwitcher.app" "$installed_app"
open "$installed_app"
echo "Installed and launched: $installed_app"
