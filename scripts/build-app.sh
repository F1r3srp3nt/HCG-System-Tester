#!/usr/bin/env bash
# Builds "HCG System Tester.app" from the Swift package — no Xcode project required.
#
#   scripts/build-app.sh                       release build for this Mac's architecture, ad-hoc signed
#   scripts/build-app.sh --universal           arm64 + x86_64
#   scripts/build-app.sh --configuration debug
#   scripts/build-app.sh --no-sign             skip code signing (CI)
#   scripts/build-app.sh --open                open the app when done
#
# Output: dist/HCG System Tester.app. Nothing is installed, published or notarised.
set -euo pipefail

CONFIG="release"
SIGN=1
UNIVERSAL=0
OPEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration) CONFIG="$2"; shift 2 ;;
    --no-sign) SIGN=0; shift ;;
    --universal) UNIVERSAL=1; shift ;;
    --open) OPEN=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCH_FLAGS=()
if [[ $UNIVERSAL -eq 1 ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "==> swift build -c $CONFIG --product HCGSystemTester ${ARCH_FLAGS[*]:-}"
swift build -c "$CONFIG" --product HCGSystemTester ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$ROOT/dist/HCG System Tester.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HCGSystemTester" "$APP/Contents/MacOS/HCGSystemTester"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ $SIGN -eq 1 ]]; then
  echo "==> Ad-hoc signing (local use only; not notarised)"
  codesign --force --options runtime --entitlements "$ROOT/App/Config/HCGSystemTester.entitlements" --sign - "$APP"
  codesign --verify --strict --verbose=1 "$APP"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "==> Built: $APP"
if [[ $OPEN -eq 1 ]]; then open "$APP"; fi
