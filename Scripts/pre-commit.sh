#!/bin/bash
# Pre-commit gate: format staged Swift files, block on lint errors (not
# warnings; pre-push and CI's --strict pass are the backstop), then run the
# fast unit tests.
#
# Written for macOS's stock /bin/bash (3.2): no `mapfile`, no associative
# arrays. NUL-delimited `git diff -z` + `read -r -d ''` works on every bash.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

staged=()
while IFS= read -r -d '' file; do
  staged+=("$file")
done < <(git diff -z --cached --name-only --diff-filter=ACM -- '*.swift')

if [ ${#staged[@]} -eq 0 ]; then
  exit 0
fi

echo "pre-commit: formatting ${#staged[@]} staged Swift file(s)..."
swiftformat --quiet "${staged[@]}"
git add "${staged[@]}"

echo "pre-commit: linting (errors block, warnings don't)..."
# SwiftLint exits non-zero only for errors when not --strict. Capture first,
# never pipe into grep under pipefail.
if ! swiftlint lint --quiet "${staged[@]}"; then
  echo "pre-commit: blocked by SwiftLint errors above. Fix them, or 'git commit --no-verify' to bypass (not recommended)." >&2
  exit 1
fi

echo "pre-commit: running unit tests..."
if ! swift test --quiet; then
  echo "pre-commit: blocked by failing unit tests." >&2
  exit 1
fi

echo "pre-commit: passed."
