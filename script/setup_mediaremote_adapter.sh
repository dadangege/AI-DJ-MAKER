#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
REPO_DIR="$VENDOR_DIR/mediaremote-adapter"

mkdir -p "$VENDOR_DIR"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone https://github.com/ungive/mediaremote-adapter.git "$REPO_DIR"
fi

if command -v cmake >/dev/null 2>&1; then
  cmake -S "$REPO_DIR" -B "$REPO_DIR/build"
  cmake --build "$REPO_DIR/build"
else
  FRAMEWORK_DIR="$REPO_DIR/build/MediaRemoteAdapter.framework"
  mkdir -p "$FRAMEWORK_DIR"
  clang -dynamiclib \
    -fobjc-arc \
    -fvisibility=default \
    -I"$REPO_DIR/include" \
    -I"$REPO_DIR/src" \
    -framework Foundation \
    -framework AppKit \
    -framework JavaScriptCore \
    -framework UniformTypeIdentifiers \
    "$REPO_DIR/src/adapter/env.m" \
    "$REPO_DIR/src/adapter/get.m" \
    "$REPO_DIR/src/adapter/globals.m" \
    "$REPO_DIR/src/adapter/keys.m" \
    "$REPO_DIR/src/adapter/now_playing.m" \
    "$REPO_DIR/src/adapter/repeat.m" \
    "$REPO_DIR/src/adapter/seek.m" \
    "$REPO_DIR/src/adapter/send.m" \
    "$REPO_DIR/src/adapter/shuffle.m" \
    "$REPO_DIR/src/adapter/speed.m" \
    "$REPO_DIR/src/adapter/stream.m" \
    "$REPO_DIR/src/adapter/test.m" \
    "$REPO_DIR/src/private/MediaRemote.m" \
    "$REPO_DIR/src/utility/Debounce.m" \
    "$REPO_DIR/src/utility/helpers.m" \
    -o "$FRAMEWORK_DIR/MediaRemoteAdapter"
  codesign --force --deep --sign - "$FRAMEWORK_DIR"
fi

echo "MediaRemote Adapter ready:"
echo "$REPO_DIR/build/MediaRemoteAdapter.framework"
