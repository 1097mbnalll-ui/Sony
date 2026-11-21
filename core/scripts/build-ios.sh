#!/usr/bin/env bash
# Builds the Tarjuman core (chiaki-ng + deps + bridge) as one static library
# for iOS arm64. Run on macOS with Xcode. Output: build/ios/lib/libtrjm_core.a
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/build/ios/cmake"
OUT="$ROOT/build/ios/lib"
SDK="${TRJM_SDK:-iphoneos}"
mkdir -p "$BUILD" "$OUT"

cmake -S "$ROOT/core" -B "$BUILD" -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DPython3_EXECUTABLE="$(command -v python3)" \
  -DCMAKE_C_FLAGS="-fvisibility=default"
cmake --build "$BUILD" -j "$(sysctl -n hw.ncpu)" --target trjm_bridge

LIBS=$(find "$BUILD" -name "*.a" \( -name "libtrjm_*.a" -o -name "libmbedcrypto.a" -o -name "libopus.a" \))
echo "Merging:"; echo "$LIBS"
libtool -static -o "$OUT/libtrjm_core.a" $LIBS
lipo -info "$OUT/libtrjm_core.a"
