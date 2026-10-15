#!/bin/bash
# Installs the latest F99 Mood into /Applications and opens it:
#   curl -fsSL https://joharapurkar.com/f99/install | bash
# The disk image is checked against the release's SHA-256 checksum, and the
# app's signature is checked, before anything is copied.
set -euo pipefail

BASE="https://github.com/papihaj/aula-f99-mood/releases/latest/download"
APP="F99 Mood.app"
TMP=$(mktemp -d)
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
fail() { echo "F99 Mood wasn't installed: $1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "it only runs on a Mac."

echo "Downloading F99 Mood…"
curl -fsSL -o "$TMP/F99-Mood.dmg" "$BASE/F99-Mood.dmg" || fail "the download didn't work. Check your internet connection and try again."
curl -fsSL -o "$TMP/F99-Mood.dmg.sha256" "$BASE/F99-Mood.dmg.sha256" || fail "the checksum file couldn't be downloaded."

expected=$(awk '{print $1}' "$TMP/F99-Mood.dmg.sha256")
actual=$(shasum -a 256 "$TMP/F99-Mood.dmg" | awk '{print $1}')
[[ "$expected" =~ ^[0-9a-f]{64}$ && "$expected" == "$actual" ]] \
  || fail "the download doesn't match its checksum, so it may be damaged. Try again."

MOUNT=$(hdiutil attach -nobrowse -readonly -noautoopen "$TMP/F99-Mood.dmg" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')
[[ -d "$MOUNT/$APP" ]] || fail "the disk image doesn't contain $APP."
codesign --verify --deep --strict "$MOUNT/$APP" 2>/dev/null || fail "the app's signature isn't valid."

# Quit a running copy, so the new one replaces it cleanly.
osascript -e 'tell application id "local.f99mood" to quit' >/dev/null 2>&1 || true
sleep 1

echo "Installing into /Applications…"
DEST="/Applications/$APP"
if [[ -w /Applications ]]; then
  rm -rf "$DEST" && ditto "$MOUNT/$APP" "$DEST"
else
  echo "Your Mac needs your password to write to /Applications."
  sudo rm -rf "$DEST" && sudo ditto "$MOUNT/$APP" "$DEST"
fi

open "$DEST"
echo "Done. F99 Mood is in your Applications folder."
