#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ xcodegen fehlt. Installation: brew install xcodegen"
  exit 1
fi

echo "→ Generiere Xcode-Projekt"
xcodegen generate

echo "→ Build (Debug)"
# arm64-only erzwingen: macOS 26 ist arm64-only, Intel wird nicht unterstützt.
# Diese Flags MÜSSEN als Command-Line-Override gesetzt werden — `EXCLUDED_ARCHS`
# aus der project.yml greift NICHT auf die SwiftPM-Dependency-Targets (FluidAudio
# nutzt Float16, das auf x86_64-macOS nicht existiert → Build-Fehler).
xcodebuild \
  -project BlitzText.xcodeproj \
  -scheme BlitzText \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build > /tmp/blitztext-build.log 2>&1 || {
    echo "✗ Build fehlgeschlagen — Log:"
    grep -E "error:|warning:" /tmp/blitztext-build.log | head -30
    exit 1
  }

APP_SRC=$(awk '/ BUILT_PRODUCTS_DIR =/ {print $3}' < <(xcodebuild -project BlitzText.xcodeproj -showBuildSettings -scheme BlitzText -configuration Debug 2>/dev/null))/BlitzText.app

mkdir -p build
rm -rf build/BlitzText.app
cp -R "$APP_SRC" build/

# Stabile Signing-Identity, damit TCC-Berechtigungen (Mikrofon/Bedienungshilfen)
# über Builds hinweg erhalten bleiben. Wenn das lokale Cert fehlt, fällt es
# auf Ad-hoc zurück (dann promptet macOS halt jedes Mal neu).
SIGN_IDENTITY="BlitzText Local Dev"
if security find-identity -v -p codesigning login.keychain 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "→ Signiere mit '$SIGN_IDENTITY'"
  # KEIN --options runtime — Hardened Runtime + Library Validation blockiert
  # den von Xcode generierten BlitzText.debug.dylib (anderer TeamID).
  codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements BlitzText/BlitzText.entitlements \
    build/BlitzText.app
else
  echo "→ Ad-hoc Signatur (kein Local-Cert gefunden — './Scripts/create-signing-cert.sh' für stabile TCC)"
  codesign --force --deep --sign - build/BlitzText.app
fi

echo ""
echo "✓ Build fertig"
echo "  $ROOT/build/BlitzText.app"
echo ""
echo "Starten mit:  open build/BlitzText.app"
