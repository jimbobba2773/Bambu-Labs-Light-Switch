#!/bin/zsh
# Builds a universal (Apple silicon + Intel) BambuLight.app and zips it to dist/ for sharing.
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-1.0.0}
export VERSION
ARCHS="arm64 x86_64" ./build.sh
mkdir -p dist
ZIP="dist/BambuLight-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle structure intact (plain `zip` can break it); metadata is stripped so no ._ files end up in the zip
ditto -c -k --norsrc --noextattr --noqtn --keepParent ~/Applications/BambuLight.app "$ZIP"
echo "Packaged $ZIP ($(du -h "$ZIP" | cut -f1))"
lipo -archs ~/Applications/BambuLight.app/Contents/MacOS/BambuLight | sed 's/^/Architectures: /'
