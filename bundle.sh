#!/bin/sh
# Quick Mac build without Xcode (no iCloud sync). Usage: ./bundle.sh            (local, ad-hoc signed, this Mac's arch)
#                                                     ./bundle.sh release    (universal, Developer ID signed, hardened runtime)
set -e
VERSION=1.0.0
APP=build/Lexikos.app
if [ "$1" = "release" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Lexikos"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/Lexikos"
fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Lexikos.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lexikos</string>
<key>CFBundleDisplayName</key><string>Lexikos</string>
<key>CFBundleIdentifier</key><string>com.yixuanwu.lexikos</string>
<key>CFBundleExecutable</key><string>Lexikos</string>
<key>CFBundleIconFile</key><string>Lexikos</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.education</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [ "$1" = "release" ]; then
    codesign --force --options runtime --timestamp -s "${SIGN_ID:-Developer ID Application}" "$APP"
else
    codesign --force -s - "$APP"
fi
echo "$APP"
