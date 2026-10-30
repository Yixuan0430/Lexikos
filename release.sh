#!/bin/sh
# Build a signed, notarized Lexikos-<version>.dmg in dist/, through Xcode so the CloudKit
# provisioning profile is embedded. Needs XcodeGen, a "Developer ID Application" certificate
# and a notarytool keychain profile:
#   xcrun notarytool store-credentials lexikos-notary --apple-id <id> --team-id BGM8P5U985
set -e
PROFILE="${NOTARY_PROFILE:-lexikos-notary}"
xcodegen generate -q
rm -rf build/Lexikos.xcarchive build/Lexikos.app
xcodebuild -project Lexikos.xcodeproj -scheme Lexikos-macOS -configuration Release \
    -destination 'generic/platform=macOS' -archivePath build/Lexikos.xcarchive -allowProvisioningUpdates -quiet archive
xcodebuild -exportArchive -archivePath build/Lexikos.xcarchive -exportOptionsPlist Config/ExportOptions-developer-id.plist \
    -exportPath build -allowProvisioningUpdates -quiet
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
