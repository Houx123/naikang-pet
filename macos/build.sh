#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
APP_DIR="$ROOT_DIR/奶康.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ROOT_DIR/.module-cache"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Assets/PetIcon.icns" "$APP_DIR/Contents/Resources/PetIcon.icns"
cp "$ROOT_DIR/Assets/StatusIcon.png" "$APP_DIR/Contents/Resources/StatusIcon.png"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.module-cache" clang -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -fobjc-arc -O2 -framework Cocoa "$ROOT_DIR/Sources/main.m" -o "$APP_DIR/Contents/MacOS/QuotaPet"
codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
