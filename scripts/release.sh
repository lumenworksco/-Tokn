#!/usr/bin/env bash
# Usage: ./scripts/release.sh <version>  e.g. ./scripts/release.sh 1.0.6
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
TAG="v${VERSION}"
DMG="Tokn-${VERSION}.dmg"
STAGING="/tmp/tokn_release_staging"
ICNS_DIR="/tmp/tokn_dmg_icons.iconset"

echo "→ Building Tokn ${VERSION}..."
xcodebuild \
  -project Tokn.xcodeproj \
  -scheme Tokn \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "^(Build|CompileSwift|error:|warning: |\\*\\*)" | grep -v "^warning: " || true

BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/Tokn-*/Build/Products/Release/Tokn.app \
  -maxdepth 0 2>/dev/null | head -1)
[[ -z "$BUILT_APP" ]] && { echo "✗ Build failed — app not found"; exit 1; }
echo "✓ Built: $BUILT_APP"

echo "→ Creating volume icon..."
mkdir -p "$ICNS_DIR"
for size in 16 32 64 128 256 512 1024; do
  SRC="Tokn/Assets.xcassets/AppIcon.appiconset/icon_${size}x${size}.png"
  [[ -f "$SRC" ]] && cp "$SRC" "${ICNS_DIR}/icon_${size}x${size}.png"
  [[ -f "$SRC" ]] && cp "$SRC" "${ICNS_DIR}/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICNS_DIR" -o /tmp/Tokn.icns
echo "✓ Volume icon ready"

echo "→ Staging app..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$BUILT_APP" "${STAGING}/Tokn.app"
xattr -cr "${STAGING}/Tokn.app"
echo "✓ Staging ready"

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - \
  --entitlements "Tokn/Tokn.entitlements" \
  "${STAGING}/Tokn.app"
echo "✓ Ad-hoc signed (unidentified developer — right-click → Open to bypass)"

echo "→ Building DMG..."
rm -f "/tmp/${DMG}"
create-dmg \
  --volname "Tokn" \
  --volicon /tmp/Tokn.icns \
  --window-pos 200 140 \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "Tokn.app" 150 190 \
  --hide-extension "Tokn.app" \
  --app-drop-link 390 190 \
  --no-internet-enable \
  "/tmp/${DMG}" \
  "$STAGING/"
echo "✓ DMG: /tmp/${DMG} ($(du -sh "/tmp/${DMG}" | cut -f1))"
echo "  sha256: $(shasum -a 256 "/tmp/${DMG}" | cut -d' ' -f1)"
echo "  (the in-app updater verifies this against the digest GitHub computes for the uploaded asset)"

echo ""
echo "→ Next: commit the version bump, tag, and upload"
echo "   git add Tokn/Info.plist && git commit -m 'chore: bump to ${VERSION}'"
echo "   git tag ${TAG} && git push && git push origin ${TAG}"
echo "   gh release create ${TAG} /tmp/${DMG} --title 'Tokn ${VERSION}' --notes '...'"
