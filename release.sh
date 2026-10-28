#!/bin/sh
# Build a signed, notarized Lexikos-<version>.dmg in dist/.
# Needs a "Developer ID Application" certificate and a notarytool keychain profile:
#   xcrun notarytool store-credentials lexikos-notary --apple-id <id> --team-id <team>
set -e
PROFILE="${NOTARY_PROFILE:-lexikos-notary}"
./bundle.sh release
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Lexikos.app/Contents/Info.plist)
DMG="dist/Lexikos-$VERSION.dmg"
mkdir -p dist && rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R build/Lexikos.app "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Lexikos" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp -s "${SIGN_ID:-Developer ID Application}" "$DMG"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
else
    echo "warning: no notarytool profile '$PROFILE'; $DMG is signed but not notarized" >&2
fi
(cd dist && shasum -a 256 "Lexikos-$VERSION.dmg" > "Lexikos-$VERSION.dmg.sha256")
echo "$DMG"
