#!/bin/bash
# Builds dist/ClipStack.app and dist/ClipStack.dmg (universal: Apple Silicon + Intel).
#
# Optional, for a release that opens without Gatekeeper warnings:
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   → also notarize + staple
# Without these the app is ad-hoc signed, or signed with .signing/identity if present (see below).
set -euo pipefail
cd "$(dirname "$0")"

APP=ClipStack
DIST=dist
BUNDLE="$DIST/$APP.app"
DMG="$DIST/$APP.dmg"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "→ Compiling"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/$APP"

echo "→ Making icon"
# The artwork lives at Resources/AppIcon.png (square); it's placed on the macOS icon grid.
ART=Resources/AppIcon.png
if [ ! -f .build/AppIcon.icns ] || [ scripts/make-icon.swift -nt .build/AppIcon.icns ] \
   || { [ -f "$ART" ] && [ "$ART" -nt .build/AppIcon.icns ]; }; then
  ICONSET=.build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  if [ -f "$ART" ]; then
    swift scripts/make-icon.swift .build/icon-1024.png "$ART"
  else
    swift scripts/make-icon.swift .build/icon-1024.png
  fi
  for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) .build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o .build/AppIcon.icns
fi

echo "→ Assembling $BUNDLE"
rm -rf "$DIST" && mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp .build/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "→ Signing"
# Optional local identity, never committed: put the name of one of your certificates
# (from `security find-identity -v -p codesigning`) in .signing/identity. A fixed identity
# keeps macOS's Accessibility permission for ClipStack across rebuilds; ad-hoc doesn't.
LOCAL_ID=""
[ -f .signing/identity ] && LOCAL_ID=$(head -1 .signing/identity)
if [ "$IDENTITY" != "-" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BUNDLE"
  echo "  with CODESIGN_IDENTITY"
elif [ -n "$LOCAL_ID" ]; then
  codesign --force --sign "$LOCAL_ID" "$BUNDLE"
  echo "  with the identity in .signing/identity"
else
  codesign --force --sign - "$BUNDLE"
  echo "  ad-hoc"
fi

echo "→ Making DMG"
STAGE=$(mktemp -d)
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ "$IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    echo "→ Notarizing"
    xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "✓ Done: $DMG"
