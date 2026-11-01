# Lookup Word design

Lookup Word is a macOS background app (no Dock icon) in one Swift executable. A double-tap of a modifier key picks a
word, looks it up offline in the dictionaries enabled in Dictionary.app, shows a card like Look Up's with the word in
every language in force, and saves it to a vocabulary file. This document shows how the parts fit. The
[README](../README.md) covers use and settings; [CONTRIBUTING](../CONTRIBUTING.md) covers language packs.

## 1. Components

```mermaid
flowchart TD
  M["main.swift: shortcut, menu, CLI checks"]
  SC["Screen.swift: selection, screen reading"]
  MA["Matching.swift: reading vs. the app's text"]
  LU["Lookup.swift: language, entry"]
  DI["Dictionaries.swift: Dictionary.app, gloss, base forms"]
  PK["Packs.swift: packs, LanguageHooks"]
  PJ[("packs/*/pack.json, lemma lists")]
  GR["Greek.swift: GreekHooks"]
  ST["Store.swift: Markdown / JSON store"]
  CA["Card.swift: popover"]
  SE["Settings.swift: settings window, restart"]
  CF["Config.swift: config.json, Paths"]

  M --> SC
  M --> MA
  M --> LU
  M --> CA
  M --> ST
  M --> SE
  SC --> MA
  SC --> PK
  LU --> DI
  LU --> PK
  DI --> PK
  PK --> PJ
  PK <--> GR
  ST --> LU
  CA --> LU
  SE --> CF
  SE --> PK
  PK --> CF
```

- `main.swift` owns the flow: `onKey()` spots the double-tap, `lookUp()` picks the word, `show()` builds the entry,
  presents the card and hands the save to a serial `saves` queue.
- `Lookup.swift` builds an `Entry`; `Store.swift` and `Card.swift` only consume it. `Dictionaries.swift` holds the
  Dictionary.app calls (`define()`), the gloss extraction and the base-form search.
- `Packs.swift` loads `pack.json` per language and registers code hooks in `languageHooks`; `GreekHooks` is the only
  one, and it reads `packs` back. `Screen.swift` takes its Vision languages (`ocrLanguages`) from the packs.
- Not drawn, to keep it readable: almost every file reads `config`, `Paths` or `log()` from `Config.swift`, and the
  regex helpers `matches()`/`replacing()` and `fold()` from `Dictionaries.swift`.

## 2. A lookup, end to end

```mermaid
flowchart TD
  T["Double-tap: onKey() calls lookUp()"] --> S{"selection() via Accessibility?"}
  S -- "selected text" --> SH["show(word, rect, around)"]
  S -- nothing --> SR{"config.screenReading"}
  SR -- off --> M2["card: select a word first"]
  SR -- on --> O["byOCR(): ScreenCaptureKit capture, wordAt() reads it with Vision"]
  O --> X["textUnderPointer() + closest(): the app's own word, if any"]
  X --> SH
  SH --> LG["language(around): NaturalLanguage hint"]
  LG --> LE["lookUpEntry(): LanguageHooks candidates, then entry()"]
  LE --> BF["entry(): baseForm() for a word in a pack's script"]
  BF --> DF["define() in English and every X - English / X dictionary; pick the language"]
  DF --> TR["gloss() to English, via() to the others"]
  TR --> C["present(card(e)) with 'Saving…'"]
  C --> SV["saves queue: store.save(e)"]
  SV --> U["update(card) with the store's answer"]
```

- `lookUp()` first checks the Accessibility permission. With a selection, `selection()` returns the selected text,
  its bounds and up to 1000 characters of the element's value as context.
- With screen reading on, `byOCR()` captures a 640×90 pt region around the pointer (excluding the app's own windows).
  `wordAt()` finds the line and word with `VNDetectTextRectanglesRequest`, reads the word's crop three ways and keeps the
  surest, and reads up to four neighbours a side. `closest(_:in:)` then picks the word of the element's real text that
  best fits the reading and its neighbours (look-alike letters folded by `shape()`). Without element text, the raw
  reading is used; with no reading at all, the card asks for Screen Recording or says no word was found.
- `show()` falls back to `corrected()` (spell-checker guesses in the hint language) when `lookUpEntry()` finds nothing.
  The card appears at once; the store's answer replaces "Saving…" only if no newer lookup started (`shown == mine`).

## 3. Translation through English

English is the pivot: each language needs only its X - English dictionary. A word of language X gets its English from
its own X - English entry, and every other language from the English side of that language's X - English dictionary.

```mermaid
flowchart LR
  W["liep, hint nl"] --> D1["Dutch - English: Dutch headword entry (lopen)"]
  D1 --> G1["gloss(), withoutHints()"]
  G1 --> EN["English: walk, go"]
  EN --> D2["Greek - English: English headword entry for walk"]
  D2 --> G2["gloss(target: Greek), verbPart() for a verb"]
  G2 --> EL["Greek translation"]

  NLJ[("nl/pack.json: bilingual, stripHints, verb, gloss")] -.-> D1
  NLJ -.-> G1
  ELJ[("el/pack.json: bilingual, script, verbLabels, gloss")] -.-> D2
  ELJ -.-> G2
  HK["GreekHooks: readingCandidates, fallbackCandidates, baseForms"] -.->|"only when Greek is the source word"| BF["lookUpEntry() / baseForm()"]
```

- `entry()` tells the two sides of a bilingual dictionary apart with `englishSide()`: English headwords carry a
  pronunciation (`| rʌn |`), the other language's do not. `via()` accepts only an English-side entry whose headword
  starts with the English word.
- For an English word, `entry()` skips the first hop: each language's translation is the gloss of its X - English entry
  for that word (`verbPart()` when `isVerb()` says it is a verb).
- Data in `pack.json` covers most of a language: dictionary names, `script`, `recognizer`, `ocr`, `spellChecker`,
  verb rules, `stripHints`, `lemmas` and gloss labels. Code in `LanguageHooks` covers what data cannot: Greek maps
  Cyrillic/Latin look-alike readings back to Greek letters and lists the dictionary forms a regular ending points to,
  which `deeperBase()` tries after the lemma list.

## 4. The Markdown store's safe write

The vocabulary file may live in a notes vault that another app syncs or saves at the same moment. `MarkdownStore.save()`
therefore never writes over a file it has not read whole, or one that changed since it read it.

```mermaid
flowchart TD
  A["store.save(e) on the saves queue"] --> R["read(): up to 5 tries, 0.3 s apart"]
  R --> W{"incomplete()? empty, requirePrefix, requireText, minBytes"}
  W -- "never whole" --> N1["Not saved: the reason"]
  W -- whole --> K{"word already in that language's table?"}
  K -- yes --> N2["Already in that table"]
  K -- no --> I["insert(): make the section if new, add the row after the table's last row"]
  I --> B["write(): copy the file to backups/, keep the newest 30"]
  B --> CAS{"file still equals what read() got?"}
  CAS -- "changed: retry, 3 attempts" --> R
  CAS -- same --> TR["write .Vocabulary.md.saving, rename() over the file"]
  TR --> OK["Saved to that table"]
  CAS -- "changed 3 times" --> N3["Not saved: kept changing"]
```

- A missing file is created with its title line, unless `requireText` or `minBytes` is set: then the store expects an
  existing note and refuses to start a new one.
- The backup is taken before the compare, so even a lost race leaves a copy; `store.backups: 0` turns backups off.
- The compare-and-swap is "re-read, compare, rename": a writer between the compare and the `rename()` can still lose,
  but no reader ever sees a half-written file, and the `saves` queue keeps the app's own saves in order.
- `JSONStore` is simpler: decode the list, append, one atomic write; no backups or compare.

## 5. Settings and restart

```mermaid
flowchart TD
  IS["install.sh"] --> APP["~/Applications/Lookup Word.app, packs in Resources"]
  IS --> PL["launch agent plist: RunAtLoad, KeepAlive SuccessfulExit false"]
  PL -->|"launchctl bootstrap, and each login"| P["LookupWord process"]
  CF[("config.json")] -->|"read once at launch: let config"| P
  P -->|"menu Settings…, or reopening the app"| SW["showSettings(): SettingsModel reads the file"]
  SW -->|"Save and Restart: save() merges its keys"| CF
  SW --> RS["restart()"]
  P -->|"menu: Restart to Apply Settings"| RS
  RS -->|"under launchd: exit(1)"| LD["launchd restarts it after the failure exit"]
  LD --> P
  RS -->|"started otherwise: sh 'sleep 1; open -n', exit(0)"| P
  P -->|"Quit: exit(0)"| STOP["stopped until the next login"]
```

- `config` is read once per process. Each key decodes on its own (`lenient()`): a bad value keeps its default and adds a
  warning to the card's status line; a file that is not JSON sets `configBroken`, and the store becomes `BrokenStore`,
  which saves nothing until it is fixed. A missing file is written out with the defaults.
- `SettingsModel.save()` and `setSetting()` rewrite only their own keys and keep every other key, so the advanced store
  options ("Edit Advanced Settings…" opens the file) survive.
- `restart()` exits with status 1 when `XPC_SERVICE_NAME` names the launch agent: `KeepAlive` with `SuccessfulExit`
  false makes launchd start a new process, which reads the new settings. Quit exits 0, so launchd leaves it stopped.
- `install.sh` builds a release binary, assembles and signs the app (its own certificate if there is one, else ad hoc,
  which resets the permissions), writes `~/Library/LaunchAgents/io.github.gregth.lookup-word.plist` with stderr to
  `~/Library/Logs/Lookup Word/lookup.log`, then `bootout` and `bootstrap` reload it.
