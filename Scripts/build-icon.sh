#!/usr/bin/env bash
# Generiert AppIcon.icns aus dem Master-PNG.
# 1) Master @1024 via SwiftUI rendern
# 2) Alle benötigten Größen via sips
# 3) Mit iconutil zu .icns bündeln
# 4) Ins Asset-Set kopieren

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "→ Rendere Master-PNG @ 1024x1024"
chmod +x "$ROOT/Scripts/make-icon.swift"
swift "$ROOT/Scripts/make-icon.swift" "$TMP/icon-1024.png"

echo "→ Skaliere auf alle benötigten Auflösungen"
SIZES="16 32 64 128 256 512 1024"
for S in $SIZES; do
  sips -z "$S" "$S" "$TMP/icon-1024.png" --out "$TMP/icon-$S.png" >/dev/null
done

# iconset-Konvention: <name>.png = @1x, <name>@2x.png = doppelte px
cp "$TMP/icon-16.png"   "$ICONSET/icon_16x16.png"
cp "$TMP/icon-32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$TMP/icon-32.png"   "$ICONSET/icon_32x32.png"
cp "$TMP/icon-64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$TMP/icon-128.png"  "$ICONSET/icon_128x128.png"
cp "$TMP/icon-256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$TMP/icon-256.png"  "$ICONSET/icon_256x256.png"
cp "$TMP/icon-512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$TMP/icon-512.png"  "$ICONSET/icon_512x512.png"
cp "$TMP/icon-1024.png" "$ICONSET/icon_512x512@2x.png"

echo "→ Bündle zu .icns"
ASSETS="$ROOT/BlitzText/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ASSETS"

iconutil -c icns "$ICONSET" -o "$ROOT/BlitzText/Resources/AppIcon.icns"

# Außerdem Single-Image für AppIcon-AssetCatalog (macOS 13+ unterstützt das)
cp "$TMP/icon-1024.png" "$ASSETS/icon-1024.png"
cat > "$ASSETS/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "mac",
      "platform" : "macOS",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

cat > "$ROOT/BlitzText/Resources/Assets.xcassets/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo ""
echo "✓ App-Icon fertig"
echo "  $ROOT/BlitzText/Resources/AppIcon.icns"
echo "  $ASSETS/icon-1024.png"
