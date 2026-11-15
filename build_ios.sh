#!/usr/bin/env bash
# Builds the Go archive, the unsigned iOS app, and packages wiiudownloader.ipa.
# Requires macOS with Xcode. bash 3.2 compatible.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
IPA="$ROOT/wiiudownloader.ipa"
APP="$ROOT/build/ios/iphoneos/Runner.app"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC_BIN="$(xcrun --sdk iphoneos --find clang)"

# --- Fetch the title database and build the Go archive --------------------
mkdir -p "$ROOT/ios/Runner/libs"
(
  cd "$ROOT/native_lib"
  python3 grabTitles.py

  export GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$CC_BIN"
  export CGO_CFLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=14.0"
  export CGO_LDFLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=14.0"
  go build -buildmode=c-archive -o "$ROOT/ios/Runner/libs/libwiiudownloader.a"
)
if [ ! -s "$ROOT/ios/Runner/libs/libwiiudownloader.a" ]; then
  echo "error: libwiiudownloader.a was not produced" >&2
  exit 1
fi

# --- Build the unsigned app -----------------------------------------------
flutter build ios --no-codesign --release
if [ ! -d "$APP" ]; then
  echo "error: expected app bundle not found at $APP" >&2
  exit 1
fi

# --- Package into an IPA without touching the build output ----------------
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir "$STAGING/Payload"
cp -R "$APP" "$STAGING/Payload/Runner.app"
rm -f "$IPA"
(cd "$STAGING" && zip -qry "$IPA" Payload)

if [ ! -s "$IPA" ]; then
  echo "error: $IPA was not created" >&2
  exit 1
fi
echo "Created $IPA"
