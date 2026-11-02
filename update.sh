#!/bin/zsh
# Updates Lookup Word to the latest version on GitHub: pulls the source, then builds and reinstalls it with
# install.sh. Your settings and words stay where they are (~/Library/Application Support/Lookup Word).
#
#   ./update.sh
[ -n "${ZSH_VERSION:-}" ] || exec /bin/zsh "$0" "$@"  # run as sh or bash: the ${0:A:h} below is zsh
set -euo pipefail
here=${0:A:h}
before=$(cat "$here/VERSION" 2>/dev/null || echo "?")
if [[ $(git -C "$here" rev-parse --show-toplevel 2>/dev/null) != "$here" ]]; then  # (not a folder in another repo)
  echo "$here is not a git clone (a ZIP download?), so it cannot pull; get a clone with" \
    "git clone https://github.com/gregth/lookup-word.git and run its ./install.sh." >&2
  exit 1
fi
if [[ -n $(git -C "$here" status --porcelain --untracked-files=no) ]]; then
  echo "You have local changes in $here; commit or stash them first (git -C \"$here\" stash), then run this again." >&2
  exit 1
fi
if ! git -C "$here" symbolic-ref -q HEAD >/dev/null || ! git -C "$here" rev-parse -q --verify '@{u}' >/dev/null; then
  echo "$here is not on a branch that follows a remote one; check one out first (git -C \"$here\" checkout main)." >&2
  exit 1
fi
if ! git -C "$here" pull --ff-only --quiet; then
  echo "Could not pull. If git says it cannot fast-forward, your branch has commits of its own; put them on top of" \
    "the new ones with  git -C \"$here\" pull --rebase  and run this again." >&2
  exit 1
fi
after=$(cat "$here/VERSION" 2>/dev/null || echo "?")
if [[ $before == "$after" ]]; then echo "Lookup Word $after: rebuilding the latest source."; else echo "Lookup Word $before → $after"; fi
exec "$here/install.sh"
