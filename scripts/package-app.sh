#!/bin/zsh

set -euo pipefail

APP_NAME="PluginSpector"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PKGINFO_PATH="$CONTENTS_DIR/PkgInfo"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS-arm64.zip"
PKG_PATH="$DIST_DIR/${APP_NAME}-Installer-arm64.pkg"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/$APP_NAME"

mkdir -p "$DIST_DIR"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR" "$ZIP_PATH" "$PKG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
printf 'APPL????' > "$PKGINFO_PATH"

cat > "$PLIST_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>PluginSpector</string>
  <key>CFBundleExecutable</key>
  <string>PluginSpector</string>
  <key>CFBundleIdentifier</key>
  <string>com.pluginspector.prototype</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PluginSpector</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  /usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if command -v pkgbuild >/dev/null 2>&1; then
  /usr/bin/pkgbuild --component "$APP_DIR" --install-location /Applications "$PKG_PATH" >/dev/null
fi

echo "Created:"
echo "  $APP_DIR"
echo "  $ZIP_PATH"
if [[ -f "$PKG_PATH" ]]; then
  echo "  $PKG_PATH"
fi
