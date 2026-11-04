#!/usr/bin/env bash
# Build the gts9u-X910ZCU5CYDA-merged payload.
#
# Prerequisites:
#   ANDROID_NDK_HOME  pointing at NDK r26+ (r27c tested); must provide
#                     toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang
#   a checkout of BuSung-dev/Root-My-Galaxy-Payloads with PR #343 applied
#   (or any tree that already contains src/targets/gts9uwifi-X910XXS6EZH3)
#
# Usage:
#   ./build.sh /path/to/Root-My-Galaxy-Payloads
set -euo pipefail

REPO_DIR="${1:?usage: build.sh <path-to-payloads-repo>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET=gts9u-X910ZCU5CYDA-merged

: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"

mkdir -p "$REPO_DIR/src/targets/$TARGET"
cp "$HERE/target/target.h"            "$REPO_DIR/src/targets/$TARGET/target.h"
cp "$HERE/target/p0_fingerprint.h"    "$REPO_DIR/src/targets/$TARGET/p0_fingerprint.h"

if ! grep -q "$TARGET" "$REPO_DIR/Makefile"; then
  python3 - "$REPO_DIR/Makefile" "$TARGET" <<'PY'
import sys
path, target = sys.argv[1], sys.argv[2]
block = (f"ifeq ($(TARGET),{target})\n"
         "APP_TARGET_CFLAGS := -DSLIDE_STACK_WRITER=1\n"
         "endif\n")
text = open(path, encoding='utf-8').read()
anchor = "ifeq ($(TARGET),dm1q-S911U1UES6DYI3)"
if anchor not in text:
    sys.exit("Makefile anchor not found")
text = text.replace(anchor, block + anchor, 1)
open(path, 'w', encoding='utf-8').write(text)
print(f"patched Makefile for {target}")
PY
fi

cd "$REPO_DIR"
make "TARGET=$TARGET"
ls -lh "build/$TARGET/"
