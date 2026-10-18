#!/bin/zsh
# Builds "F99 Mood.app" into ./build and runs the tests first.
set -euo pipefail
cd "${0:A:h}"

mkdir -p build
echo "Running tests…"
swiftc -swift-version 5 -O Sources/F99.swift Sources/F99Layout.swift Sources/ConfigPage.swift Sources/Music.swift Sources/Keyboard.swift Sources/Settings.swift Sources/LiveEffects.swift Tests/main.swift -framework IOKit -framework Accelerate -o build/tests
./build/tests

APP="build/F99 Mood.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# The app icon; drawn by Tools/make_icon.swift if it isn't there yet.
[[ -f Resources/AppIcon.icns ]] || swift Tools/make_icon.swift Resources
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Typing sounds: recorded keystrokes (CC0, see Resources/Sounds/CREDITS.md).
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"

echo "Building app…"
# ARCHS="arm64 x86_64" builds one app for both Apple silicon and Intel Macs.
ARCH_LIST=(${=ARCHS:-$(uname -m)})
for arch in $ARCH_LIST; do
  swiftc -swift-version 5 -O -parse-as-library \
    -target "$arch-apple-macos13.0" \
    Sources/*.swift \
    -framework IOKit -framework Carbon -framework AppKit -framework SwiftUI \
    -framework CoreAudio -framework AVFoundation -framework Accelerate -framework SceneKit \
    -o "build/F99Mood-$arch"
done
lipo -create build/F99Mood-${^ARCH_LIST} -output "$APP/Contents/MacOS/F99Mood"
rm -f build/F99Mood-${^ARCH_LIST}

# macOS ties permissions (Input Monitoring, audio) to the app's signature. An
# ad-hoc signature changes on every build, which silently breaks them, so sign
# with a stable certificate when there is one: Tools/make_signing_identity.sh
# makes one, or set SIGN_IDENTITY to your own (e.g. a Developer ID).
IDENTITY="${SIGN_IDENTITY:-F99 Mood Local Signing}"
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
  # A release: the hardened runtime and a secure timestamp, which Apple's
  # notarization requires.
  codesign --force --options runtime --timestamp --entitlements Entitlements.plist \
    --sign "$IDENTITY" "$APP"
elif security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "note: signing ad-hoc; permissions will need re-granting after each build."
  echo "      Run Tools/make_signing_identity.sh once to fix that."
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
