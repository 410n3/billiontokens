#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="BillionTokens"
APP_BUNDLE="$DIR/$APP_NAME.app"

echo "==> Compiling Swift application..."
swiftc -O "$DIR/main.swift" -o "$DIR/$APP_NAME"

echo "==> Creating macOS App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy brand icon assets
if [ -d "$DIR/assets" ]; then
    cp -R "$DIR/assets/"* "$APP_BUNDLE/Contents/Resources/"
fi
cp "$DIR/collector.py" "$APP_BUNDLE/Contents/Resources/collector.py"

cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>BillionTokens</string>
    <key>CFBundleIdentifier</key>
    <string>app.billiontokens.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>BillionTokens</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

mkdir -p "$HOME/Applications"
cp -R "$APP_BUNDLE" "$HOME/Applications/"

echo "==> Successfully installed to $HOME/Applications/$APP_NAME.app!"
