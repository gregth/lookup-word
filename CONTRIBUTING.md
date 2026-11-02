# Contributing

## Add a language

A language is a folder in [packs/](packs/) named by its ISO 639-1 code, for example `packs/fr/`. Most languages need
only data; a few need a small Swift hook (see the end).

### 1. Check that macOS has its dictionaries

Enable the language's dictionaries in Dictionary.app → Settings, then list what Lookup Word can see:

```bash
swift build -c release
.build/release/LookupWord --dictionaries
```

The command prints the short names to use in `pack.json`, such as `French - English`. A language needs its X - English
dictionary: that is how it translates to English and, through English, to your other languages. Its own monolingual
dictionary is optional but improves the card.

### 2. Write `pack.json`

```json
{
  "code": "fr",
  "name": "French",
  "flag": "🇫🇷",
  "voice": "fr-FR",
  "monolingual": "French",
  "bilingual": "French - English",
  "dictionaryIds": ["com.apple.dictionary.fr.Multi", "com.apple.dictionary.OxfordFrench"],
  "recognizer": "fr",
  "ocr": ["fr-FR"],
  "spellChecker": "fr",
  "verb": { "entryPattern": "\\s(v|vtr|vi)\\b", "prefix": 60 },
  "verbLabels": ["vtr", "vi", "v"],
  "gloss": { "labels": ["nm", "nf", "adj"], "inner": [], "cuts": [] }
}
```

| Key | What it is |
|---|---|
| `code`, `name`, `flag` | The ISO 639-1 code, the English name, and the flag shown before the translation. |
| `voice` | The `AVSpeechSynthesisVoice` language for the 🔈. |
| `monolingual`, `bilingual` | Dictionary short names, exactly as `--dictionaries` prints them. |
| `dictionaryIds` | Their identifiers, for the Settings window's **Enable** button: `DictionaryIdentifier` in `/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS/*.xml` (`com.apple.dictionary.OxfordFrench`). |
| `script` | Only for a script no other pack writes (Greek, Cyrillic…): words in it are always this language's. |
| `recognizer` | The NaturalLanguage code, used to tell which language the text around a word is in. |
| `ocr` | Vision recognition languages for screen reading (see `supportedRecognitionLanguages`). |
| `spellChecker` | The `NSSpellChecker` language used to correct misread words. |
| `verb` | How to tell a verb: `entryPattern` (a regex on its entry, within `prefix` characters) or `endings`. |
| `verbLabels` | The labels that open the verb part of an English entry in this X - English dictionary. Lookup Word uses them to translate *can* the verb, not *can* the tin. |
| `intransitiveLabels` | Optional: of those, the intransitive one(s) (Dutch `onoverg`). Preferred when the English verb's first sense takes no object (*run* → *lopen*, not *laten lopen*). |
| `stripHints` | `true` when X - English translations start with X words as hints ("gaan walk"). |
| `lemmas` | A `form⇥lemma` list (`.tsv` or `.tsv.xz`) for languages whose dictionaries don't find base forms. [simplemma](https://github.com/adbar/simplemma) has lists for about 50 languages. Keep its licence notice next to the file. |
| `translations` | The English for the few words whose entry opens with uses and examples instead of a translation (`{"aller": "to go"}`). Keep it to those: the card shows the entry below. |
| `gloss` | Grammar labels to drop from translations: `labels` at the start, `inner` anywhere, `cuts` to stop at, `grammarNotes` (abbreviations ending in `.` before the meaning), `variants` (regex and replacement pairs). | `labels` and `inner` are shared by every pack in use (several Oxford dictionaries use the same English labels); `cuts`, `grammarNotes` and `variants` apply only to entries from this pack's dictionary, so one pack's rewrites never change another's.

### 3. Test it

Add the code to `languages` in a test config and look words up without the screen:

```bash
mkdir -p /tmp/lw && echo '{"languages": ["en", "fr"]}' > /tmp/lw/config.json
LOOKUP_SUPPORT=/tmp/lw .build/release/LookupWord --text maisons fr
LOOKUP_SUPPORT=/tmp/lw .build/release/LookupWord --text house en
```

Add a `tests.tsv` to the pack: one line per word, `word⇥hint⇥expected English`, covering nouns, verbs (including
irregular and inflected forms), adjectives and words that other languages spell the same way. Run
[scripts/test-packs.sh](scripts/test-packs.sh) before opening a pull request.

A new pack is marked **community** in the README until a native speaker has checked its test words.

### When data is not enough

Some languages need code: a script macOS's text recognition doesn't read, or base forms with no lemma list. Implement
`LanguageHooks` ([Sources/LookupWord/Packs.swift](Sources/LookupWord/Packs.swift)) and register it in
`languageHooks`. [Greek.swift](Sources/LookupWord/Greek.swift) is the example: it maps Cyrillic look-alike readings
back to Greek and lists the dictionary forms a regular ending points to.

## Code

- One file per concern in [Sources/LookupWord/](Sources/LookupWord/): settings, packs, dictionaries, screen reading,
  matching, lookup, card, store, the settings window, the welcome window, and `main.swift` (shortcut, menu,
  command-line checks).
  [docs/DESIGN.md](docs/DESIGN.md) draws how they fit.
- Comments say why, with the example that motivated a rule (*liep* → "gaan walk").
- Before a pull request, run [scripts/test-packs.sh](scripts/test-packs.sh) and, if you touched screen reading,
  `--pointer` on a few lines in each language.
