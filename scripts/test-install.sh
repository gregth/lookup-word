#!/bin/zsh
# End-to-end check of install.sh, the app's own uninstall and uninstall.sh, on a separate test copy (its own label, app
# folder, settings and logs, in a temporary folder), so a real install is left alone; it checks that too at the end.
# The test copy runs for a few seconds without a menu bar icon or welcome window (LOOKUP_QUIET), saving off; its ⌥
# shortcut is live meanwhile.
#
#   ./scripts/test-install.sh
set -uo pipefail
root=${0:A:h:h}
tmp=$(mktemp -d)
# the app under the home folder: macOS's app registry skips temporary folders, and tccutil finds apps through it
export LOOKUP_QUIET=1 LOOKUP_LABEL=io.github.gregth.lookup-word.test LOOKUP_APP_DIR=$HOME/Library/Caches/lookup-word-test LOOKUP_SUPPORT=$tmp/support LOOKUP_LOGS=$tmp/logs
app="$LOOKUP_APP_DIR/Lookup Word.app" plist=$HOME/Library/LaunchAgents/$LOOKUP_LABEL.plist uid=$(id -u)
real_plist=$HOME/Library/LaunchAgents/io.github.gregth.lookup-word.plist
real_before=$(shasum "$real_plist" 2>/dev/null; pgrep -f "$HOME/Applications/Lookup Word.app/Contents/MacOS/LookupWord")
pass=0 fail=0
check() { if eval "$2"; then (( pass++ )); echo "ok    $1"; else (( fail++ )); echo "FAIL  $1"; fi }
running() { launchctl print gui/$uid/$LOOKUP_LABEL 2>/dev/null | grep -q 'state = running'; }
pid() { launchctl print gui/$uid/$LOOKUP_LABEL 2>/dev/null | awk '/^\tpid = /{print $3}'; }

mkdir -p $LOOKUP_SUPPORT
echo '{"menuBar": false, "store": {"type": "none"}}' > $LOOKUP_SUPPORT/config.json

echo "— install"
"$root/install.sh" </dev/null >$tmp/install.log 2>&1
check "install.sh succeeds" "[[ $? == 0 ]]"
check "the app is in place" "[[ -x '$app/Contents/MacOS/LookupWord' ]]"
check "its identifier is the test label" "[[ \$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '$app/Contents/Info.plist') == $LOOKUP_LABEL ]]"
check "its icon is bundled" "[[ -f '$app/Contents/Resources/AppIcon.icns' ]] && /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' '$app/Contents/Info.plist' >/dev/null"
check "its language packs are bundled" "[[ -f '$app/Contents/Resources/packs/en/pack.json' && -f '$app/Contents/Resources/packs/el/lemmas.tsv.xz' ]]"
check "it is signed" "codesign --verify '$app' 2>/dev/null"
check "its launch agent exists" "[[ -f $plist ]]"
check "the launch agent passes the test folders on" "grep -q '$LOOKUP_SUPPORT' $plist"
sleep 2
check "it is running" "running"
check "the installed app finds its packs" "'$app/Contents/MacOS/LookupWord' --dictionaries 2>/dev/null | grep -q '^el Greek'"
first=$(pid)

echo "— reinstall (an update)"
"$root/install.sh" </dev/null >>$tmp/install.log 2>&1
check "install.sh succeeds again" "[[ $? == 0 ]]"
sleep 2
check "it is running again, as a new process" "running && [[ \$(pid) != '$first' ]]"
check "the settings survive" "grep -q '\"menuBar\": false' $LOOKUP_SUPPORT/config.json"

echo "— reinstall with a copy running outside the launch agent (opened from Finder, or by an earlier Restart)"
launchctl bootout gui/$uid/$LOOKUP_LABEL 2>/dev/null; sleep 1
"$app/Contents/MacOS/LookupWord" >/dev/null 2>&1 &
stray=$!; sleep 2
"$root/install.sh" </dev/null >>$tmp/install.log 2>&1
check "install.sh succeeds" "[[ $? == 0 ]]"
sleep 2
check "the stray copy is gone" "! kill -0 $stray 2>/dev/null"
check "the launch agent's copy runs instead" "running"

echo "— the app's own uninstall (the menu's code)"
out=$("$app/Contents/MacOS/LookupWord" --uninstall 2>&1); code=$?
echo "$out" | sed 's/^/      /'
check "it reports success" "[[ $code == 0 ]] && print -r -- \"\$out\" | grep -q 'its permissions'"
check "the app is gone" "[[ ! -e '$app' ]]"
check "its launch agent file is gone" "[[ ! -e $plist ]]"
sleep 1
check "its launch agent is unloaded" "! launchctl print gui/$uid/$LOOKUP_LABEL >/dev/null 2>&1"
check "the settings stay" "[[ -f $LOOKUP_SUPPORT/config.json ]]"

echo "— install again, then uninstall.sh --purge"
"$root/install.sh" </dev/null >>$tmp/install.log 2>&1
sleep 2
check "it is running" "running"
out=$("$root/uninstall.sh" --purge 2>&1); code=$?
echo "$out" | sed 's/^/      /'
check "uninstall.sh reports success" "[[ $code == 0 ]]"
check "the app is gone" "[[ ! -e '$app' ]]"
check "its launch agent file is gone" "[[ ! -e $plist ]]"
check "its launch agent is unloaded" "! launchctl print gui/$uid/$LOOKUP_LABEL >/dev/null 2>&1"
check "the settings and logs are gone" "[[ ! -e $LOOKUP_SUPPORT && ! -e $LOOKUP_LOGS ]]"

echo "— the real install"
real_after=$(shasum "$real_plist" 2>/dev/null; pgrep -f "$HOME/Applications/Lookup Word.app/Contents/MacOS/LookupWord")
check "it is untouched (same launch agent file, same process)" "[[ '$real_before' == '$real_after' ]]"

launchctl bootout gui/$uid/$LOOKUP_LABEL 2>/dev/null; rm -f $plist  # in case a step failed midway
rm -rf "$LOOKUP_APP_DIR"
[[ $fail == 0 ]] && rm -rf $tmp || echo "Logs kept in $tmp"
echo "$pass passed, $fail failed"
(( fail == 0 ))
