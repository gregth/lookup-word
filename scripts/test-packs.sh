#!/bin/zsh
# Looks up each pack's test words and checks the entry: packs/<code>/tests.tsv, one line per word,
# word ⇥ hint ⇥ expected, where expected is text the --text output must contain (a translation, the headword), or,
# after a !, text it must not (a leaked example: !Cairo).
# Needs the dictionaries enabled in Dictionary.app. Run from anywhere: ./scripts/test-packs.sh [code…]
set -uo pipefail
root=${0:A:h:h}
swift build -c release --package-path "$root" >/dev/null || exit 1
bin=$(swift build -c release --package-path "$root" --show-bin-path)/LookupWord
support=$(mktemp -d)
codes=(${@:-${(f)"$(ls "$root/packs")"}})
echo "{\"languages\": [$(printf '"%s",' $codes | sed 's/,$//')]}" > "$support/config.json"
pass=0 fail=0
for code in $codes; do
  tests="$root/packs/$code/tests.tsv"
  [[ -f $tests ]] || { echo "$code: no tests.tsv"; continue; }
  while IFS=$'\t' read -r word hint expected; do
    [[ -z $word || $word == \#* ]] && continue
    out=$(LOOKUP_SUPPORT=$support "$bin" --text "$word" "$hint" 2>/dev/null)
    if [[ $expected == !* ]]; then
      if [[ $out != *"${expected#!}"* ]]; then (( pass++ )); else (( fail++ )); echo "FAIL $code: $word ($hint) has \"${expected#!}\""; echo "$out" | sed 's/^/     /'; fi
    elif [[ $out == *"$expected"* ]]; then (( pass++ )); else (( fail++ )); echo "FAIL $code: $word ($hint) lacks \"$expected\""; echo "$out" | sed 's/^/     /'; fi
  done < "$tests"
done
rm -rf "$support"
echo "$pass passed, $fail failed"
(( fail == 0 ))
