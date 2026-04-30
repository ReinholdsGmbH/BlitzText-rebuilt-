#!/usr/bin/env bash
# Installiert BlitzText.app aus build/ in /Applications.
# Bei laufender App wird sie vorher beendet.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BlitzText.app"
DEST="/Applications/BlitzText.app"

if [ ! -d "$APP" ]; then
  echo "✗ build/BlitzText.app fehlt. Erst './Scripts/build.sh' ausführen."
  exit 1
fi

echo "→ Beende laufende BlitzText-Instanz (falls offen)"
pkill -f "BlitzText.app/Contents/MacOS/BlitzText" 2>/dev/null || true
sleep 0.5

echo "→ Entferne alte Installation (falls vorhanden)"
rm -rf "$DEST"

echo "→ Kopiere $APP → $DEST"
cp -R "$APP" "$DEST"

echo "→ Quarantäne-Attribut entfernen (Gatekeeper-freundlicher Start)"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo ""
echo "✓ Installiert: $DEST"
echo ""
echo "Starten mit:  open '$DEST'"
echo ""
echo "Hinweis: Beim ersten Start aus /Applications fragt macOS evtl. nochmal nach"
echo "Mikrofon und Bedienungshilfen — die sind an den Bundle-Path gebunden."
