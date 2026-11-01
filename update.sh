#!/bin/zsh
# Updates Lookup Word to the latest version on GitHub: pulls the source, then builds and reinstalls it with
# install.sh. Your settings and words stay where they are (~/Library/Application Support/Lookup Word).
#
#   ./update.sh
set -euo pipefail
here=${0:A:h}
before=$(cat "$here/VERSION" 2>/dev/null || echo "?")
if [[ -n $(git -C "$here" status --porcelain --untracked-files=no) ]]; then
  echo "You have local changes in $here; commit or stash them first (git -C \"$here\" stash), then run this again." >&2
  exit 1
fi
git -C "$here" pull --ff-only --quiet
after=$(cat "$here/VERSION" 2>/dev/null || echo "?")
if [[ $before == "$after" ]]; then echo "Lookup Word $after: rebuilding the latest source."; else echo "Lookup Word $before → $after"; fi
exec "$here/install.sh"
