#!/bin/zsh
# Builds BambuLight.app (menu bar app, no Dock icon).
# The bundle is assembled and signed on the local disk, then installed to ~/Applications:
# codesign rejects the metadata that network volumes (SMB) attach to files.
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-1.0.0}      # marketing version; override with VERSION=1.1.0 ./build.sh
BUILD=$(date +%y%m%d%H%M)       # build number, increases with every build
# Build products live on the local disk: the project folder is on a network share where SwiftPM's caches break.
SCRATCH=${BAMBULIGHT_BUILD_DIR:-$HOME/Library/Caches/BambuLight/build}
swift build -c release --scratch-path "$SCRATCH"
BIN=$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)

DEST=~/Applications/BambuLight.app
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP=$STAGE/BambuLight.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp Resources/AppIcon.icns $APP/Contents/Resources/
cp "$BIN/BambuLight" $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BambuLight</string>
<key>CFBundleDisplayName</key><string>Bambu Light</string>
<key>CFBundleIdentifier</key><string>local.bambulight</string>
<key>CFBundleExecutable</key><string>BambuLight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Talks to your Bambu Lab printer on the local network.</string>
</dict></plist>
PL
xattr -cr $APP 2>/dev/null || true
# A stable signing identity keeps Keychain access grants across rebuilds (ad-hoc signatures change every build).
# Override with SIGN_ID="<identity>"; falls back to ad-hoc if no certificate is installed.
SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p;' | head -1)}
if [[ -n "$SIGN_ID" ]]; then echo "Signing with: $SIGN_ID"; else echo "No signing certificate found; using ad-hoc signature"; fi
codesign --force --sign "${SIGN_ID:--}" $APP

pkill -x BambuLight 2>/dev/null || true
mkdir -p ~/Applications
rm -rf $DEST
ditto --norsrc --noextattr --noqtn $APP $DEST
codesign -v $DEST
echo "Built $DEST"
