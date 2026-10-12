#!/bin/bash
# One-time setup: symlink the vendored hooks into .git/hooks (which git does
# not track). Relative links, so a moved checkout keeps working.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

for hook in pre-commit pre-push; do
  chmod +x "Scripts/${hook}.sh"
  ln -sf "../../Scripts/${hook}.sh" ".git/hooks/${hook}"
  echo "Installed ${hook} hook -> Scripts/${hook}.sh"
done
