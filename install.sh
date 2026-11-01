#!/bin/zsh
# Builds Lookup Word from source into ~/Applications/Lookup Word.app and starts it at login (a launch agent), so
# double-tapping ⌥ works everywhere. Run it again after pulling changes.
#
#   ./install.sh                       # build, install, start
#   LOOKUP_SIGN_IDENTITY="My Cert" ./install.sh   # sign with your own code-signing certificate
#
# Signing: with a code-signing certificate (yours, or a self-signed "Lookup Word Signing" one: Keychain Access →
# Certificate Assistant → Create a Certificate…, Self Signed Root, Code Signing), macOS keeps the permissions across
# rebuilds. Without one the app is signed ad hoc, which macOS treats as a new app after each build: this script then
# resets its permissions and walks you through granting them again.
set -euo pipefail
here=${0:A:h}
label=io.github.gregth.lookup-word
apps=${LOOKUP_APP_DIR:-$HOME/Applications}
app="$apps/Lookup Word.app"
plist=$HOME/Library/LaunchAgents/$label.plist
logs="$HOME/Library/Logs/Lookup Word"
config="$HOME/Library/Application Support/Lookup Word/config.json"

if ! command -v swift >/dev/null; then
  echo "Swift is missing: install Apple's Command Line Tools with  xcode-select --install  and run this again." >&2
  exit 1
fi

echo "Building…"
swift build -c release --package-path "$here"
bin=$(swift build -c release --package-path "$here" --show-bin-path)/LookupWord

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$logs"
cp "$bin" "$app/Contents/MacOS/LookupWord"
rm -rf "$app/Contents/Resources/packs"
cp -R "$here/packs" "$app/Contents/Resources/packs"
version=$(cat "$here/VERSION" 2>/dev/null || echo 0.1.0)
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Lookup Word</string>
  <key>CFBundleExecutable</key><string>LookupWord</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

adhoc=0
identity=${LOOKUP_SIGN_IDENTITY:-}
if [[ -z $identity ]] && security find-identity -p codesigning | grep -q '"Lookup Word Signing"'; then
  identity="Lookup Word Signing"
fi
if [[ -n $identity ]]; then
  codesign --force --sign "$identity" "$app"  # no -v: a self-signed certificate is listed as not valid, yet signs
else
  codesign --force --sign - "$app"
  adhoc=1
fi

# KeepAlive only after a failure: the menu's Quit stops it until the next login, its Restart brings it straight back
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/LookupWord</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardErrorPath</key><string>$logs/lookup.log</string>
</dict></plist>
EOF

uid=$(id -u)
launchctl bootout gui/$uid/$label 2>/dev/null || true
# bootout returns before the old one is gone; loading it again before then fails ("Bootstrap failed: 5")
for _ in {1..50}; do launchctl print gui/$uid/$label >/dev/null 2>&1 || break; sleep 0.1; done

# screen reading is off by default; Screen Recording is only needed when the settings turn it on
screen=0
[[ -f $config ]] && grep -Eq '"screenReading"[[:space:]]*:[[:space:]]*true' "$config" && screen=1

if (( adhoc )); then
  tccutil reset Accessibility $label >/dev/null 2>&1 || true
  tccutil reset ScreenCapture $label >/dev/null 2>&1 || true
fi
launchctl bootstrap gui/$uid "$plist"

if (( adhoc )) && [[ -t 0 ]]; then
  open -R "$app"  # Finder shows the app, to drag into the lists or find with +
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  read "?Accessibility: add Lookup Word (+, or drag it from Finder) and switch it on, then press Enter… "
  if (( screen )); then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    read "?Screen & System Audio Recording: the same, then press Enter… "
  fi
  launchctl kickstart -k gui/$uid/$label
fi

others=$(pgrep -fl 'LookupWord$' | grep -v "$app" || true)
[[ -n $others ]] && echo "Note: another Lookup Word is running and will answer the same shortcut:\n$others"

echo "Lookup Word is running: select a word and double-tap ⌥."
"$app/Contents/MacOS/LookupWord" --dictionaries
echo "Settings: $config  (menu bar → Open Settings; Restart to apply)"
