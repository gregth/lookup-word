# <img src="docs/icon.png" width="44" height="44" alt="" align="top"> Lookup Word

Look Up for people who live in more than one language. Select a word anywhere on your Mac and double-tap ⌥: a card
shows the word, its pronunciation, its translation into each of your other languages with a 🔈 to hear it, and the
full dictionary entries. Every word you look up is saved to a vocabulary file, so your word list builds itself from
what you actually read.

Everything runs on your Mac. It uses only the dictionaries in Apple's Dictionary.app: nothing you read is sent anywhere.

![Select or point at a word, double-tap ⌥, and the card shows it in your other languages; the word is saved to your vocabulary](docs/demo.gif)

*The demo uses screen reading, which is optional; with the default settings you select the word first. See [Two ways to pick a word](#two-ways-to-pick-a-word).*

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

### Update

```bash
cd lookup-word
./update.sh
```

`update.sh` pulls the latest version and reinstalls it; your settings and words stay as they are. Each new build is a
new app to macOS unless it is signed with the same certificate, so create the "Lookup Word Signing" certificate once
(see above) to keep your permissions across updates; without it, the script walks you through granting them again.

### Uninstall

To remove it: menu bar icon → **Uninstall Lookup Word…**, or `./uninstall.sh` (add `--purge` to delete your settings and the vocabulary in its own folder too). A vocabulary file you keep elsewhere is never deleted.

## Use

- **Select a word and double-tap ⌥** (two quick taps of Option alone). A click elsewhere, a key or 30 seconds close the card.
- **Click 🔈** to hear a word.
- **The menu bar icon** opens your vocabulary and the settings, and uninstalls the app.
- **With screen reading on**, double-tap ⌥ with nothing selected to look up the word under the pointer.

## Two ways to pick a word

### Selection: always on

![Dragging across a word to select it, double-tapping ⌥, and its card](docs/mode-selection.gif)

- Select a word in any app, then double-tap ⌥.
- Needs **Accessibility**, to read the selection and to notice the shortcut.
- Works wherever text can be selected.

### Screen reading: optional

![Pointing at a word with nothing selected, double-tapping ⌥, and the highlighted word with its card](docs/mode-screen.gif)

- Point at a word, with nothing selected, then double-tap ⌥. Lookup Word reads the word off the screen and highlights it.
- Also works where text can't be selected: images, video, canvas apps, remote desktops.
- Needs **Screen Recording** as well. Lookup Word captures a strip of the screen around the pointer only when you
  double-tap, never sends it anywhere, and saves it to a file only with `"debug": true`.

Screen reading is off by default. Turn it on in **Settings… → Read the word under the pointer**, and allow Screen
Recording when macOS asks. While it's off, a double-tap with nothing selected only asks you to select the word.

## Settings

Menu bar icon → **Settings…**:

![The settings window: shortcut, screen reading, menu bar icon, card timeout, languages, and where words are saved](docs/settings.png)

**Save and Restart** applies the changes. They are stored in `~/Library/Application Support/Lookup Word/config.json`,
written with the defaults on first launch. After editing that file by hand, choose **Restart to Apply Settings** in
the menu. Every key is optional.

| Key | Default | What it does |
|---|---|---|
| `languages` | `["en", "nl", "el"]` | The language packs to use, from [packs/](packs/). English is the pivot and is always on. |
| `hotkey` | `"option"` | The modifier to double-tap: `option`, `control`, `command` or `shift`. |
| `screenReading` | `false` | Read the word under the pointer when nothing is selected. Needs **Screen Recording** permission. |
| `menuBar` | `true` | Show the menu bar icon. **Hide Menu Bar Icon** in its menu sets this to `false`. With the icon hidden, open Lookup Word again from Applications for its settings. |
| `closeAfter` | `30` | Seconds before the card closes by itself; `0` keeps it open until a click or a key. |
| `debug` | `false` | Save each screen reading as `capture.png` in the support folder and log its coordinates. |
| `store` | Markdown | `{"type": "markdown" \| "json" \| "none", "path": "…", "saveDate": false}`: where looked-up words go, see below. |

### Where words are saved

Saving is optional: in **Settings… → Save words to**, choose a Markdown file (the default), a JSON file, or nowhere.

- **Markdown:** one `## English`, `## Dutch`… section per language, each a table. A language's section is added at the
  end of the file the first time you look up a word in it; after that, each new word is one more row. Nothing else in
  the file changes, so you can keep it in a notes vault (Obsidian, Logseq…) and write your own notes around the
  tables. Here is [a file after nine lookups](docs/sample-vocabulary.md), as a notes app shows it:

  ![A vocabulary file with English, Dutch and Greek tables: each word with its meaning or English, and its translations](docs/vocabulary.png)

- **JSON:** a list of `{word, language, meaning, translations}`, for your own scripts.
- **Also save the date and time** (off by default): an **Added** column in new tables, or an `added` field in JSON.
  To add it to an existing table, add an `Added` column to its header: rows follow the table's own columns.

A save never writes over a file another app (a sync client, an editor) is in the middle of saving. It skips a read
that comes back empty, unreadable or much shorter than after the last save, writes only if the file still holds what
it read, writes through a temporary file renamed over it, and keeps the last 30 saved versions in `backups/`.

### Where things are

| What | Where |
|---|---|
| The app | `~/Applications/Lookup Word.app` |
| Settings | `~/Library/Application Support/Lookup Word/config.json` |
| Your words (default) | `~/Library/Application Support/Lookup Word/Vocabulary.md` (or `vocabulary.json`), unless you choose a file |
| Backups of the words file | `~/Library/Application Support/Lookup Word/backups/` |
| Log | `~/Library/Logs/Lookup Word/lookup.log` |
| Start at login | `~/Library/LaunchAgents/io.github.gregth.lookup-word.plist` |

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

## How it works

[docs/DESIGN.md](docs/DESIGN.md) has diagrams of the parts, a lookup from end to end, translation through English,
the vocabulary file's safe write, and how settings are applied.

## Disclaimer

Lookup Word is a personal project, shared as is, with no warranty and no support commitment. I'm not responsible for
any loss or damage from using it, including lost or changed notes: keep your own backups of anything you point it at.
It isn't affiliated with Apple or with any dictionary publisher. The dictionary content it shows comes from the
dictionaries installed on your Mac and belongs to their publishers. The [licence](LICENSE) states the legal terms.

## Licence

The code is under the [MIT License](LICENSE). The Greek lemma list in [packs/el/](packs/el/) is derived from simplemma
and keeps its sources' share-alike terms: see [packs/el/LICENSE.md](packs/el/LICENSE.md).
