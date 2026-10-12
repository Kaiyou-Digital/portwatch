#!/bin/bash
# Builds, signs and notarizes the arm64 release binary and packs it for the
# Homebrew formula. Does NOT tag, push or publish anything.
#
# Required environment:
#   SIGNING_IDENTITY  e.g. "Developer ID Application: Kaiyou Digital Limited (55HLHAU65Q)"
#   KEYCHAIN_PROFILE  the notarytool keychain profile name
#
# A bare command-line binary can be notarized but not stapled: Gatekeeper
# looks the ticket up online instead.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY}"
: "${KEYCHAIN_PROFILE:?set KEYCHAIN_PROFILE}"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Error: uncommitted changes to tracked files; release builds must come from a clean tree." >&2
  exit 1
fi

VERSION=$(sed -n 's/^let version = "\(.*\)"$/\1/p' Sources/portwatch/main.swift)
[ -n "$VERSION" ] || { echo "Error: could not read version from main.swift" >&2; exit 1; }
echo "==> Building portwatch ${VERSION} (arm64)..."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/portwatch"

echo "==> Signing (hardened runtime)..."
codesign --sign "$SIGNING_IDENTITY" --options runtime --timestamp --force "$BIN"
codesign --verify --strict --verbose=2 "$BIN"

# No `| grep -q` under pipefail: capture first.
reported=$("$BIN" --version)
if [ "$reported" != "$VERSION" ]; then
  echo "Error: binary reports '${reported}', expected '${VERSION}'." >&2
  exit 1
fi

OUT="dist"
rm -rf "$OUT" && mkdir -p "$OUT/stage"
cp "$BIN" "$OUT/stage/portwatch"

echo "==> Notarizing (this may take a few minutes)..."
ditto -c -k --keepParent "$OUT/stage/portwatch" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$KEYCHAIN_PROFILE" --wait
rm "$OUT/notarize.zip"

TAR="portwatch-${VERSION}-arm64.tar.gz"
tar -czf "$OUT/$TAR" -C "$OUT/stage" portwatch
rm -rf "$OUT/stage"

echo ""
echo "==> Done: $OUT/$TAR"
shasum -a 256 "$OUT/$TAR"
