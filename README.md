<p align="center"><img src="docs/icon.png" width="128" height="128" alt="Lookup Word's icon: a magnifier over the letters Aa"></p>

# Lookup Word

Look Up for people who live in more than one language. Select a word anywhere on your Mac and double-tap ⌥: a card
shows the word, its pronunciation, its translation into each of your other languages with a 🔈 to hear it, and the
full dictionary entries. Every word you look up is saved to a vocabulary file, so your word list builds itself from
what you actually read.

Everything runs on your Mac. It uses only the dictionaries in Apple's Dictionary.app: nothing you read is sent anywhere.

![Select or point at a word, double-tap ⌥, and the card shows it in your other languages; the word is saved to your vocabulary](docs/demo.gif)

| English | Dutch | Greek |
|---|---|---|
| ![The card for "run": its pronunciation, the Dutch and Greek translations, and the Oxford entry](docs/card-english.png) | ![The card for "liep", found as "lopen", with English and Greek](docs/card-dutch.png) | ![The card for "είδε", found as "βλέπω", with English and Dutch](docs/card-greek.png) |

## Why I built it

Greek is my mother tongue. I work in English, and I live in the Netherlands, where everything around me is in Dutch.
Every day I try to improve both of those languages while I work, so I keep meeting words I only half know.

1. I used the Mac's Look Up. It showed one dictionary's entry, when what I wanted at a glance was the word in my other
   languages: an English word in Greek, a Dutch word in English and Greek.
2. For that I opened online dictionaries such as WordReference: switch to the browser, type the word, pick the language
   pair, wait, and read through the page. Each lookup took long enough to break the flow of the work I was reading for.
3. And the word was gone afterwards. Neither Look Up nor the browser kept a list, so the words I looked up were tracked
   nowhere.
4. Yet that list is what I learn from: I turn my words into flashcards and practise them on my phone with spaced
   repetition, but a word I looked up only reached that list when I copied it there by hand.

So Lookup Word does it in one step: one keystroke shows the word in all my languages, offline and at once, and the word
lands in my vocabulary file without my doing anything. What I look up while working becomes tomorrow's flashcards.

## What it adds to Apple's Look Up

- **It remembers.** Look Up keeps no history. Lookup Word saves each word, with its meaning and translations, to a
  Markdown or JSON file you own. Point it at a notes vault (Obsidian, Logseq…) and the list is a note.
- **All your languages at once.** The translations sit at the top of the card, one line per language, instead of inside
  separate dictionary entries. Languages without a dictionary between them (Dutch and Greek, say) translate through
  English.
- **Hear every word**, each in its own language's voice.
- **Inflected Greek words.** Apple's dictionaries find the base form of English and Dutch words (*went* → *go*,
  *liep* → *lopen*) but not of Greek ones; Lookup Word adds that (*είδε* → *βλέπω*).
- **Optional: the word under the pointer, in any app.** With screen reading on, it reads the word under the pointer
  off the screen, so it also works where you cannot select text or where Look Up does not reach (Chrome, canvas apps,
  remote desktops, playing video).

## Requirements

- macOS 14 or later.
- Apple's Command Line Tools, to build it: `xcode-select --install` (the full Xcode is not needed).
- The dictionaries for your languages, enabled in **Dictionary.app → Settings**. For the default languages: *Oxford
  Dictionary of English*, *Dutch*, *Dutch - English*, *Greek*, *Greek - English*. macOS downloads each one when you
  tick it.

## Install

```bash
git clone https://github.com/gregth/lookup-word.git
cd lookup-word
./install.sh
```

The script builds the app into `~/Applications/Lookup Word.app`, starts it at login, and lists which of your languages'
dictionaries are ready. It then asks you to allow Lookup Word in **System Settings → Privacy & Security →
Accessibility**, which it needs to read the selection and to notice the shortcut.

Lookup Word isn't signed with an Apple Developer ID, so there is no download to install, only this build from source.
macOS doesn't quarantine an app built on your own Mac, so it opens without a Gatekeeper warning. To keep your
permissions across rebuilds, create a self-signed code-signing certificate named "Lookup Word Signing" (Keychain Access
→ Certificate Assistant → Create a Certificate…, Self Signed Root, Code Signing) before running the script, or pass
your own with `LOOKUP_SIGN_IDENTITY`.

To remove it: menu bar icon → **Uninstall Lookup Word…**, or `./uninstall.sh` (add `--purge` to delete your settings and the vocabulary in its own folder too). A vocabulary file you keep elsewhere is never deleted.

## Use

- **Select a word and double-tap ⌥** (two quick taps of Option alone). A click elsewhere, a key or 30 seconds close the card.
- **Click 🔈** to hear a word.
- **The menu bar icon** opens your vocabulary and the settings, and uninstalls the app.
- **With screen reading on**, double-tap ⌥ with nothing selected to look up the word under the pointer.

## Settings

`~/Library/Application Support/Lookup Word/config.json`, written with the defaults on first launch (menu bar → Open
Settings). After editing it, choose **Restart to Apply Settings**. Every key is optional.

| Key | Default | What it does |
|---|---|---|
| `languages` | `["en", "nl", "el"]` | The language packs to use, from [packs/](packs/). English is the pivot and is always on. |
| `hotkey` | `"option"` | The modifier to double-tap: `option`, `control`, `command` or `shift`. |
| `screenReading` | `false` | Read the word under the pointer when nothing is selected. Needs **Screen Recording** permission. |
| `menuBar` | `true` | Show the menu bar icon. **Hide Menu Bar Icon** in its menu sets this to `false`; open Lookup Word again from Applications to bring the icon back. |
| `closeAfter` | `30` | Seconds before the card closes by itself; `0` keeps it open until a click or a key. |
| `debug` | `false` | Save each screen reading as `capture.png` in the support folder and log its coordinates. |
| `store` | Markdown | Where looked-up words go: see below. |

### Where words are saved

- **Markdown (default):** `Vocabulary.md` in the support folder, one `## Language` section per language with a
  `| Word | … |` table. Rows are only ever added, and the file is written safely (see below).
- **JSON:** `{"store": {"type": "json"}}` saves a list of `{word, language, meaning, translations, added}`.
- **Nowhere:** `{"store": {"type": "none"}}`.

Markdown options:

- `path`: the file, anywhere, for example a note in your vault.
- `sections`: per language, the table's `heading` (`""` for a table at the top of the file, before any `##` heading)
  and its `columns` after Word (`"meaning"` or a language code).
- `insertBefore`: a new language section goes before the line that starts with this, instead of at the end.
- `requirePrefix`, `requireText`, `minBytes`: Lookup Word writes only when the file it read starts with this, holds
  each of these and is at least this long. This protects a file that another app (a sync client, an editor) may be
  saving at that moment.
- `backups`: how many copies to keep in `backups/` before writes (default 30).

Lookup Word writes only when the file still holds what it read, through a temporary file renamed over it, so a
reader never sees half a file.

Example: words saved into an existing note in a vault, English in the note's top table.

```json
{
  "languages": ["en", "nl", "el"],
  "screenReading": true,
  "store": {
    "type": "markdown",
    "path": "~/Notes/Vocabulary.md",
    "requirePrefix": "# Vocabulary",
    "insertBefore": "## Corrections log",
    "sections": {
      "en": { "heading": "", "columns": ["meaning", "el"] },
      "nl": { "heading": "Dutch", "columns": ["en", "el"] },
      "el": { "heading": "Greek", "columns": ["en", "nl"] }
    }
  }
}
```

## Languages

English, Dutch and Greek are tested. Each language is a folder in [packs/](packs/): a `pack.json` that names its
dictionaries, voice and grammar labels, plus an optional lemma list. A language can join when Dictionary.app has a
dictionary between it and English. To add one, see [CONTRIBUTING.md](CONTRIBUTING.md).

Screen reading uses macOS's text recognition, which reads some languages and not others (Greek among those it doesn't
read). For Greek, Lookup Word maps the look-alike letters it gets back to Greek, and checks the reading against the
app's own text where the app shares it (Chrome and Electron apps do).

## Limits

- Names and very new words are often missing from the dictionaries (*λάπτοπ*).
- Hyphenated compounds and numbers read off the screen come back as one token.
- Screen reading needs readable contrast; tiny or stylised text may misread.
- Dictionary.app's list of dictionaries comes through two private calls (stable for years, but undocumented), which
  also keeps the app out of the Mac App Store.

## Troubleshooting

```bash
"$HOME/Applications/Lookup Word.app/Contents/MacOS/LookupWord" --dictionaries
```

The command lists the available dictionaries and which ones each language still needs.

- `--text WORD [en|nl|el]`: prints the entry it would show, without the screen.
- `--pointer "SOME TEXT" [size] [bold] [dark]`: tests screen reading on rendered text.
- Logs go to `~/Library/Logs/Lookup Word/lookup.log`.

## Licence

The code is under the [MIT License](LICENSE). The Greek lemma list in [packs/el/](packs/el/) is derived from simplemma
and keeps its sources' share-alike terms: see [packs/el/LICENSE.md](packs/el/LICENSE.md).
