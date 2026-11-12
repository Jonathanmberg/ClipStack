#!/bin/bash
# Installs the latest ClipStack into /Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Jonathanmberg/ClipStack/main/install.sh | bash
#
# Files downloaded with curl aren't marked as "from the internet", so macOS doesn't
# show the "could not verify" warning that a browser download of an unsigned app gets.
set -euo pipefail

URL="https://github.com/Jonathanmberg/ClipStack/releases/latest/download/ClipStack.dmg"
APP="ClipStack.app"
DEST="${CLIPSTACK_DEST:-/Applications}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ClipStack is a Mac app." >&2
  exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 13 ]; then
  echo "ClipStack needs macOS 13 or later." >&2
  exit 1
fi

TMP=$(mktemp -d)
MNT="$TMP/mount"
cleanup() {
  hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "→ Downloading ClipStack"
curl -fsSL "$URL" -o "$TMP/ClipStack.dmg"
hdiutil attach "$TMP/ClipStack.dmg" -nobrowse -readonly -mountpoint "$MNT" -quiet

# Fall back to ~/Applications if /Applications isn't writable for this user.
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

echo "→ Installing to $DEST"
# Quit the copy being replaced (only that one) if it's running.
pkill -f "^$DEST/$APP/Contents/MacOS/ClipStack" 2>/dev/null || true
rm -rf "${DEST:?}/$APP"
ditto "$MNT/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

if [ -z "${CLIPSTACK_NO_OPEN:-}" ]; then
  open "$DEST/$APP"
fi

echo "✓ ClipStack is installed and running in your menu bar."
echo "  Copy as usual, then press ⌃⌥V anywhere to see your recent clips."
