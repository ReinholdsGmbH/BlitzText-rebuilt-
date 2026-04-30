#!/usr/bin/env bash
# Baut ein verteilbares DMG aus build/BlitzText.app.
# Inhalt: BlitzText.app, Symlink zu /Applications (Drag-and-Drop-Install),
# LIESMICH.txt mit Gatekeeper-Hinweis.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BlitzText.app"

if [ ! -d "$APP" ]; then
  echo "✗ build/BlitzText.app fehlt. Erst './Scripts/build.sh' ausführen."
  exit 1
fi

# Version aus Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.1.0")
DMG_NAME="BlitzText-$VERSION.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
STAGING="$ROOT/dist/_dmg-staging"

mkdir -p "$ROOT/dist"
rm -rf "$DMG_PATH" "$STAGING"
mkdir -p "$STAGING"

echo "→ Stage: kopiere App, lege Symlink an, schreibe LIESMICH"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/LIESMICH.txt" <<'EOF'
BlitzText — Installation
=========================

1. BlitzText.app per Drag-and-Drop in den Applications-Ordner ziehen.

2. Beim ersten Start kommt ggf. die Warnung
   "BlitzText kann nicht geöffnet werden, da der Entwickler nicht verifiziert ist"
   → Rechtsklick auf BlitzText.app → "Öffnen" → im Dialog nochmal "Öffnen".
   Macht ihr das einmal, merkt macOS sich das.

   Alternative im Terminal:
       xattr -dr com.apple.quarantine /Applications/BlitzText.app

3. macOS fragt beim ersten Start nach
   - Mikrofon (Aufnahme)        → Erlauben
   - Bedienungshilfen (Hotkey)  → in System-Settings den Toggle aktivieren,
                                  dann BlitzText einmal beenden und neu starten.

4. In den Einstellungen (Menubar-Icon → Zahnrad) entweder
   - OpenAI-API-Key hinterlegen (Cloud-Whisper, gpt-4o-mini)
   - Oder ein lokales Modell laden (Whisper bzw. Parakeet)

Bei Fragen: Thomas Raba.
EOF

echo "→ Baue DMG → $DMG_PATH"
hdiutil create \
  -volname "BlitzText $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')

echo ""
echo "✓ DMG fertig: $DMG_PATH ($SIZE)"
echo ""
echo "Teilen mit Kollegen:"
echo "  - Datei senden"
echo "  - Sie folgen der LIESMICH im DMG (Rechtsklick → Öffnen beim ersten Start)"
echo ""
echo "Achtung: Self-Signed-Build, NICHT notarisiert. Für saubere Distribution"
echo "ohne Gatekeeper-Hinweis bräuchtest du ein Apple-Developer-ID-Zertifikat (\$99/Jahr)"
echo "und Notarization via 'xcrun notarytool submit'."
