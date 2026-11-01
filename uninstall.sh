#!/bin/zsh
# Stops Lookup Word and removes the app and its launch agent. Your settings and vocabulary stay in
# ~/Library/Application Support/Lookup Word unless you pass --purge.
set -euo pipefail
label=io.github.gregth.lookup-word
app="${LOOKUP_APP_DIR:-$HOME/Applications}/Lookup Word.app"
launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$app"
tccutil reset Accessibility $label >/dev/null 2>&1 || true
tccutil reset ScreenCapture $label >/dev/null 2>&1 || true
if [[ ${1:-} == --purge ]]; then
  rm -rf "$HOME/Library/Application Support/Lookup Word" "$HOME/Library/Logs/Lookup Word"
  echo "Removed Lookup Word, its settings, vocabulary and logs."
else
  echo "Removed Lookup Word. Settings and vocabulary kept in ~/Library/Application Support/Lookup Word."
fi
