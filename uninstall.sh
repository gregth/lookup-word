#!/bin/zsh
# Stops Lookup Word and removes the app, its launch agent and its permissions. Your settings and backups stay in
# ~/Library/Application Support/Lookup Word, and its logs in ~/Library/Logs/Lookup Word, unless you pass --purge, which
# also removes its preferences and cache; a vocabulary file you keep elsewhere always stays.
#
#   ./uninstall.sh [--purge]
[ -n "${ZSH_VERSION:-}" ] || exec /bin/zsh "$0" "$@"  # run as sh or bash: the ${(j:, :)…} below is zsh
set -uo pipefail
# LOOKUP_LABEL, LOOKUP_APP_DIR, LOOKUP_SUPPORT and LOOKUP_LOGS name a second, separate copy (scripts/test-install.sh)
label=${LOOKUP_LABEL:-io.github.gregth.lookup-word}
app="${LOOKUP_APP_DIR:-$HOME/Applications}/Lookup Word.app"
support=${LOOKUP_SUPPORT:-$HOME/Library/Application Support/Lookup Word}
logs=${LOOKUP_LOGS:-$HOME/Library/Logs/Lookup Word}
failed=() note=""
launchctl bootout gui/$(id -u)/$label 2>/dev/null
for _ in {1..50}; do launchctl print gui/$(id -u)/$label >/dev/null 2>&1 || break; sleep 0.1; done
# a copy not started by the launch agent too, or it keeps running with the app gone
pkill -f "^$app/Contents/MacOS/LookupWord" 2>/dev/null || true
for _ in {1..50}; do pgrep -f "^$app/Contents/MacOS/LookupWord" >/dev/null || break; sleep 0.1; done
# the permissions before the app goes: tccutil finds the app by its identifier through macOS's app registry, which
# forgets it once the app is deleted ("No such bundle identifier")
if [[ -d $app ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
  tccutil reset Accessibility $label >/dev/null || failed+=("the Accessibility permission")
  tccutil reset ScreenCapture $label >/dev/null || failed+=("the Screen Recording permission")
else  # already uninstalled: macOS no longer knows the app, so only System Settings can clear a leftover entry
  note=" The app was already gone; if Lookup Word still shows in System Settings → Privacy & Security, remove it there with −."
fi
rm -f "$HOME/Library/LaunchAgents/$label.plist" || failed+=("the launch agent")
rm -rf "$app" || failed+=("the app")
if [[ ${1:-} == --purge ]]; then
  rm -rf "$support" "$logs" || failed+=("the settings or logs")
  # the card's remembered state (UserDefaults: collapsed sections, the type-a-word box's place) and the URL cache
  # DictionaryServices writes; defaults delete fails on a domain that is not there, which is not a failure here, and
  # leaves an empty file behind
  if defaults read "$label" >/dev/null 2>&1; then defaults delete "$label" >/dev/null || failed+=("the preferences"); fi
  rm -f "$HOME/Library/Preferences/$label.plist"
  rm -rf "$HOME/Library/Caches/$label" || failed+=("the cache")
  kept=" Settings, backups, logs, preferences and the vocabulary in $support deleted; a vocabulary file elsewhere is"
  kept+=" never touched."
else
  kept=" Settings and backups kept in $support, logs in $logs (./uninstall.sh --purge removes them); a vocabulary"
  kept+=" file elsewhere is never touched."
fi
if (( ${#failed} )); then
  echo "Lookup Word is partly uninstalled. Could not remove: ${(j:, :)failed}.$kept$note" >&2
  exit 1
fi
if [[ -n $note ]]; then echo "Removed what was left of Lookup Word.$kept$note"
else echo "Removed Lookup Word: the app, starting at login and its permissions.$kept"; fi
