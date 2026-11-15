#!/usr/bin/env bash
# Builds libwiiudownloader.so for all four Android ABIs, then the release APK.
# Works on macOS and Linux runners (bash 3.2 compatible).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
API=21

# --- Locate the NDK -------------------------------------------------------
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ] && [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk" ]; then
  NDK="$(ls -d "$ANDROID_HOME"/ndk/*/ 2>/dev/null | sort | tail -n 1 || true)"
  NDK="${NDK%/}"
fi
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
  echo "error: Android NDK not found. Set ANDROID_NDK_HOME (or install it under \$ANDROID_HOME/ndk)." >&2
  exit 1
fi

# --- Detect the host toolchain directory ----------------------------------
PREBUILT_ROOT="$NDK/toolchains/llvm/prebuilt"
case "$(uname -s)" in
  Darwin) PREBUILT="darwin-x86_64" ;;  # NDK ships this for both Intel and Apple Silicon
  Linux)  PREBUILT="linux-x86_64" ;;
  *)      PREBUILT="" ;;
esac
if [ -z "$PREBUILT" ] || [ ! -d "$PREBUILT_ROOT/$PREBUILT" ]; then
  # Fall back to whatever single host directory the NDK actually contains.
  PREBUILT="$(ls "$PREBUILT_ROOT" 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$PREBUILT" ] || [ ! -d "$PREBUILT_ROOT/$PREBUILT" ]; then
  echo "error: no host toolchain found under $PREBUILT_ROOT" >&2
  exit 1
fi
BIN="$PREBUILT_ROOT/$PREBUILT/bin"
echo "Using NDK: $NDK"
echo "Using toolchain: $PREBUILT"

# --- Validate every compiler up front -------------------------------------
for compiler in \
  "aarch64-linux-android${API}-clang" \
  "armv7a-linux-androideabi${API}-clang" \
  "i686-linux-android${API}-clang" \
  "x86_64-linux-android${API}-clang"; do
  if [ ! -x "$BIN/$compiler" ]; then
    echo "error: compiler not found or not executable: $BIN/$compiler" >&2
    exit 1
  fi
done

# --- Fetch the title database ---------------------------------------------
(cd native_lib && python3 grabTitles.py)

# build <abi> <compiler> <goarch> [goarm]
build() {
  abi="$1"
  compiler="$2"
  goarch="$3"
  goarm="${4:-}"
  out="$ROOT/android/app/src/main/jniLibs/$abi"

  echo "==> Building $abi"
  mkdir -p "$out"
  (
    cd "$ROOT/native_lib"
    export CGO_ENABLED=1 GOOS=android GOARCH="$goarch" CC="$BIN/$compiler"
    if [ -n "$goarm" ]; then export GOARM="$goarm"; else unset GOARM; fi
    go build -buildmode=c-shared -ldflags="-s -w" -o "$out/libwiiudownloader.so"
  )
  if [ ! -s "$out/libwiiudownloader.so" ]; then
    echo "error: $out/libwiiudownloader.so was not produced" >&2
    exit 1
  fi
}

build arm64-v8a   "aarch64-linux-android${API}-clang"    arm64
build armeabi-v7a "armv7a-linux-androideabi${API}-clang" arm   7
build x86         "i686-linux-android${API}-clang"       386
build x86_64      "x86_64-linux-android${API}-clang"     amd64

# --- All four ABIs built; now the APK -------------------------------------
echo "==> Building APK"
flutter build apk --release
