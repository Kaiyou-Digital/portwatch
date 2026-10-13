#!/bin/bash
# Pre-push gate (the real one): whole-repo format check, strict lint, and the
# test suite in Debug AND Release (optimiser-only bugs pass every Debug test).
#
# Skips when the push touches no Swift/package/tooling files. Fails closed: if
# it can't work out what changed, it runs everything.
# Bypass once with: SKIP_PREPUSH=1 git push

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ "${SKIP_PREPUSH:-}" = "1" ]; then
  echo "pre-push: skipped (SKIP_PREPUSH=1)."
  exit 0
fi

zero="0000000000000000000000000000000000000000"
needs_run=0
saw_ref=0

while read -r local_ref local_sha remote_ref remote_sha; do
  saw_ref=1
  [ "$local_sha" = "$zero" ] && continue # deleting a ref

  if [ "$remote_sha" = "$zero" ] || ! git cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
    base=$(git merge-base "$local_sha" origin/main 2>/dev/null || true)
  else
    base="$remote_sha"
  fi

  if [ -z "$base" ]; then
    needs_run=1 # can't tell what changed
    break
  fi

  while IFS= read -r -d '' file; do
    case "$file" in
      *.swift | Package.swift | Package.resolved | .swiftformat | .swiftlint.yml | Scripts/*) needs_run=1 ;;
    esac
  done < <(git diff -z --name-only "$base" "$local_sha")
done

[ "$saw_ref" = "0" ] && needs_run=1

if [ "$needs_run" = "0" ]; then
  echo "pre-push: no Swift changes, skipping checks."
  exit 0
fi

echo "pre-push: format check..."
swiftformat Sources Tests --lint --quiet

echo "pre-push: lint (strict)..."
swiftlint lint --strict --quiet

echo "pre-push: tests (debug)..."
swift test --quiet

echo "pre-push: tests (release)..."
swift test -c release --quiet -Xswiftc -enable-testing

echo "pre-push: smoke test (release binary in a pty)..."
swift build -c release --quiet
python3 -I Scripts/smoke.py .build/release/portwatch

echo "pre-push: passed."
