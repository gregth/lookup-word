#!/bin/zsh
# Builds Lookup Word from source into ~/Applications/Lookup Word.app and starts it at login (a launch agent), so
# double-tapping ⌥ works everywhere. Run it again after pulling changes.
#
#   ./install.sh                       # build, install, start
#   LOOKUP_SIGN_IDENTITY="My Cert" ./install.sh   # sign with your own code-signing certificate (remembered for the
#                                                 # next install and update.sh)
#
# Signing: with a code-signing certificate (yours, or a self-signed "Lookup Word Signing" one: Keychain Access →
# Certificate Assistant → Create a Certificate…, Self Signed Root, Code Signing), macOS keeps the permissions across
# rebuilds. Without one the app is signed ad hoc, which macOS treats as a new app after each build: its permissions are
# cleared, and the app asks for them again in its welcome window.
[ -n "${ZSH_VERSION:-}" ] || exec /bin/zsh "$0" "$@"  # run as sh or bash: the ${0:A:h} below is zsh
set -euo pipefail
here=${0:A:h}
# LOOKUP_LABEL, LOOKUP_APP_DIR, LOOKUP_SUPPORT and LOOKUP_LOGS install a second, separate copy (scripts/test-install.sh)
label=${LOOKUP_LABEL:-io.github.gregth.lookup-word}
apps=${LOOKUP_APP_DIR:-$HOME/Applications}
app="$apps/Lookup Word.app"
plist=$HOME/Library/LaunchAgents/$label.plist
logs=${LOOKUP_LOGS:-$HOME/Library/Logs/Lookup Word}
support=${LOOKUP_SUPPORT:-$HOME/Library/Application Support/Lookup Word}
config="$support/config.json"
env="<key>LOOKUP_AGENT</key><string>1</string>"  # marks the launch agent's copy, for its restart; and a test copy's folders

[[ -n ${LOOKUP_SUPPORT:-} ]] && env+="<key>LOOKUP_SUPPORT</key><string>$LOOKUP_SUPPORT</string>"
[[ -n ${LOOKUP_LOGS:-} ]] && env+="<key>LOOKUP_LOGS</key><string>$LOOKUP_LOGS</string>"
[[ -n ${LOOKUP_QUIET:-} ]] && env+="<key>LOOKUP_QUIET</key><string>1</string>"

# not command -v swift: /usr/bin/swift is there without the tools too, a stub that only offers to install them
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift is missing: install Apple's Command Line Tools with  xcode-select --install  and run this again." >&2
  exit 1
fi

echo "Building…"
swift build -c release --package-path "$here"
bin=$(swift build -c release --package-path "$here" --show-bin-path)/LookupWord

# the running copy stopped first, so nothing runs from files being replaced; bootout returns before it is gone, and
# loading it again before then fails ("Bootstrap failed: 5")
uid=$(id -u)
launchctl bootout gui/$uid/$label 2>/dev/null || true
for _ in {1..50}; do launchctl print gui/$uid/$label >/dev/null 2>&1 || break; sleep 0.1; done
if launchctl print gui/$uid/$label >/dev/null 2>&1; then
  echo "The running Lookup Word did not stop; run ./install.sh again." >&2
  exit 1
fi
# and a copy not started by the launch agent (opened from Finder, or by an earlier Restart): left running, it keeps
# the old build answering the shortcut, and the new copy quits on seeing it ("already running")
pkill -f "^$app/Contents/MacOS/LookupWord" 2>/dev/null || true  # (none running: status 1, which set -e would stop on)
for _ in {1..50}; do pgrep -f "^$app/Contents/MacOS/LookupWord" >/dev/null || break; sleep 0.1; done

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$logs" "${plist:h}"
# a new file, not the old one rewritten in place (macOS caches a running binary's signature by its file)
rm -f "$app/Contents/MacOS/LookupWord"
cp "$bin" "$app/Contents/MacOS/LookupWord"
rm -rf "$app/Contents/Resources/packs"
cp -R "$here/packs" "$app/Contents/Resources/packs"
cp "$here/docs/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
version=$(cat "$here/VERSION" 2>/dev/null || echo 0.1.0)
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Lookup Word</string>
  <key>CFBundleExecutable</key><string>LookupWord</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

adhoc=0
identity=${LOOKUP_SIGN_IDENTITY:-}
ids=$(security find-identity -p codesigning 2>/dev/null || true)  # captured first: grep -q in a pipe can cut it short
# the identity an earlier install was given, while the keychain still has it: an update without the variable signed
# ad hoc, which cleared the permissions
saved=$(cat "$support/signing-identity" 2>/dev/null || true)
[[ -z $identity && -n $saved && $ids == *"$saved"* ]] && identity=$saved
[[ -z $identity && $ids == *'"Lookup Word Signing"'* ]] && identity="Lookup Word Signing"
# the hardened runtime: without it dyld loads DYLD_INSERT_LIBRARIES into an app holding Accessibility and Screen
# Recording. No -v: a self-signed certificate is listed as not valid, yet signs.
if [[ -n $identity ]]; then
  codesign --force --options runtime --sign "$identity" "$app"
  [[ -n ${LOOKUP_SIGN_IDENTITY:-} ]] && { mkdir -p "$support"; print -r -- "$identity" > "$support/signing-identity"; }
else
  codesign --force --options runtime --sign - "$app"
  adhoc=1
fi

# KeepAlive only after a failure: the menu's Quit stops it until the next login
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/LookupWord</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardErrorPath</key><string>$logs/lookup.log</string>
  <key>EnvironmentVariables</key><dict>$env</dict>
</dict></plist>
EOF

# registered with macOS's app registry, so tccutil (below, and when uninstalling) finds it by its identifier
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"

# An ad hoc build is a new app to macOS: its old permissions no longer apply, and a stale entry would show switched on
# while doing nothing, so they are cleared. The app then asks for Accessibility itself, in its welcome window.
if (( adhoc )); then
  tccutil reset Accessibility $label >/dev/null 2>&1 || true
  tccutil reset ScreenCapture $label >/dev/null 2>&1 || true
fi
launchctl bootstrap gui/$uid "$plist"

others=$(pgrep -fl 'LookupWord$' | grep -v "$app" || true)
[[ -n $others ]] && echo "Note: another Lookup Word is running and will answer the same shortcut:\n$others"

echo "Lookup Word is installed and running. If it needs a permission, its window says so."
"$app/Contents/MacOS/LookupWord" --dictionaries
echo "Settings: $config  (menu bar → Settings…)"
