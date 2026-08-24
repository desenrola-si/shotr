#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Shotr"
BUNDLE_ID="com.ximenes.shotr"
VERSION="1.0"
DEST="${1:-$HOME/Applications}"
APP="$DEST/$APP_NAME.app"

echo "▸ compilando (release)…"
ARCH_FLAGS="--arch arm64 --arch x86_64"
if ! swift build -c release $ARCH_FLAGS >/dev/null 2>&1; then
  echo "  (binário universal falhou; compilando só para esta máquina)"
  ARCH_FLAGS=""
  swift build -c release
fi
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/$APP_NAME"

echo "▸ gerando ícone…"
rm -rf .build/icon.iconset
swift Tools/make-icon.swift .build/icon.iconset >/dev/null
iconutil -c icns .build/icon.iconset -o .build/Shotr.icns

echo "▸ montando bundle em ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp .build/Shotr.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>Uso pessoal</string>
</dict>
</plist>
PLIST

SIGN_NAME="Shotr Local Signing"
if security find-certificate -c "$SIGN_NAME" >/dev/null 2>&1; then
  echo "▸ assinando com \"$SIGN_NAME\" (identidade estável entre builds)…"
  codesign --force --deep --sign "$SIGN_NAME" --identifier "$BUNDLE_ID" "$APP"
else
  echo "▸ assinando ad-hoc — rode Tools/setup-signing.sh para parar de reautorizar a cada build"
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "✓ pronto: $APP"
echo "  abrir com:  open \"$APP\""
