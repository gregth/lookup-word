# <img src="docs/icon.png" width="44" height="44" alt="" align="top"> Lookup Word

Like Look Up, for people who live in more than one language. Select a word anywhere on your Mac, or just point at it, and
press the ⌥ Option key twice; or press ⌃⌘L and type it. You never say which language it is in. A card shows the word, its pronunciation, its translation into each of your other languages with a 🔈 to hear it, and the
full dictionary entries. Every word you look up is saved to a vocabulary file, so your word list builds itself from
what you actually read.

Everything runs on your Mac. It uses only the dictionaries in Apple's Dictionary.app: nothing you read is sent anywhere.
(The card's **Read more** links open a dictionary site in your browser, and only when you click one.)

![Select or point at a word, press ⌥ twice, and the card shows it in your other languages; the word is saved to your vocabulary](docs/demo.gif)

*The demo points at words; you can also select them. See [Use](#use).*

| English | Dutch | Greek |
|---|---|---|
| ![The card for "run": its pronunciation, the Dutch and Greek translations, and the Oxford entry](docs/card-english.png) | ![The card for "liep", found as "lopen", with English and Greek](docs/card-dutch.png) | ![The card for "είδε", found as "βλέπω", with English and Dutch](docs/card-greek.png) |

## Why I built it

Greek is my mother tongue. I work in English, and I live in the Netherlands, where everything around me is in Dutch.
Every day I try to improve both of those languages while I work, so I keep meeting words I only half know.

1. I used the Mac's Look Up. It shows every dictionary's entry, but I had to read through them for what I wanted at a
   glance, the word in my other languages (an English word in Greek, a Dutch word in English and Greek), and I
   couldn't hear the translations.
2. For that I opened online dictionaries such as WordReference: switch to the browser, type the word, pick the language
   pair, wait, and read through the page. Each lookup took long enough to break the flow of the work I was reading for.
3. And the word was gone afterwards. Neither Look Up nor the browser kept a list, so the words I looked up were tracked
   nowhere.
4. Yet that list is what I learn from: I turn my words into flashcards and practise them on my phone with spaced
   repetition, but a word I looked up only reached that list when I copied it there by hand.

So Lookup Word does it in one step: one keystroke shows the word in all my languages, offline and at once, and the word
lands in my vocabulary file without my doing anything. What I look up while working becomes tomorrow's flashcards.

## What it adds to Apple's Look Up

- **Each word in its own language.** Look Up shows the entry of every dictionary that has the word, whatever its
  language. Lookup Word works out the word's language from its alphabet, the text it is in and which of your
  dictionaries have it, and shows that language's entry: select *huis* in a Dutch text, *maison* in a French one or
  *σπίτι* anywhere, and each card comes up in that word's language, translated into all your others at once.
- **A box to type a word into.** Look Up takes only a word already on screen. Press **⌃⌘L** (or your own shortcut) in
  any app, type a word and press Return; a misspelling gets the spell checker's guess (*definately* → *definitely*).
  The box needs no permission.
- **It remembers.** Look Up keeps no list of the words you looked up. Lookup Word saves each word your dictionaries
  have, once and in its dictionary form (*went* as *go*), with its meaning and translations, to a Markdown or JSON
  file. Make that file a note in your Obsidian vault: Lookup Word only adds to it (a row per word, a section per
  language, a column for a language you turn on), so your own text in it stays.
- **The translation, at a glance.** Above the dictionary entries, the card has a row for each of your other languages,
  with up to three meanings: French *temps* is "weather · time", Dutch *weer · tijd*. A word in a language other than
  English is translated into your others through its English meaning.
- **Hear the word and its translations.** Look Up has no speaker. Lookup Word has one for the word and one for each
  row, each in that language's voice.
- **Inflected Greek words.** Apple's dictionaries find the base form of English, Dutch and French words (*went* →
  *go*, *liep* → *lopen*) and point to it for German and Spanish ones, but find almost no Greek ones; Lookup Word
  finds the base form (*είδε* → *βλέπω*).
- **Words Look Up can't read.** Look Up needs the app to hand it the text. With nothing selected and Screen Recording
  allowed, Lookup Word reads the word under the pointer off the screen, so it also works on text in an image in an
  app without Live Text, or on a remote desktop. macOS's text recognition doesn't read Greek, so this works for your
  other languages only.

## Ways to use it

- **Learning a language where you live.** Read your mail, the news and work documents in the language around you,
  and look up what stops you without leaving the page. What you looked up this week is your list to study.
- **School and university.** Students reading set texts in a second language keep one vocabulary file per course
  (choose it in Settings); a teacher can share a word list made the same way. The words come with their meaning and
  translations, so the list is ready to revise from.
- **Flashcards: Anki and others.** The vocabulary file is a plain Markdown table, one section per language. To turn
  one language's words into Anki cards (the word on the front, its translations on the back):

  ```bash
  awk -v want=Dutch '/^## /{lang=substr($0,4);next} lang!=want{next} /^\| Word /{n=split($0,head,"|");next} /^\| \*\*/{gsub(/\*\*/,"");split($0,c,"|");back="";for(i=3;i<n;i++){v=c[i];gsub(/^ +| +$/,"",v);h=head[i];gsub(/^ +| +$/,"",h);if(v!=""&&h!="Added")back=back (back==""?"":"<br>") h ": " v};w=c[2];gsub(/^ +| +$/,"",w);print w "\t" back}' "$HOME/Library/Application Support/Lookup Word/Vocabulary.md" > dutch.txt
  ```

  Then in Anki: **File → Import**, choose `dutch.txt`, field separator **Tab**, and tick **Allow HTML in fields**.
  Quizlet's import takes the same text (term and definition separated by a tab). For your own scripts, set the store
  to JSON instead.
- **Your notes.** Point the vocabulary file at a note in Obsidian, Logseq or any Markdown notes app, and the list
  lives with your other notes.
- **Subtitles, photos and slides.** Point at a word in a video, a screenshot or a shared screen: the card reads it off
  the screen, so words you can't select count too.

## Requirements

- macOS 14 or later.
- Apple's Command Line Tools, to build it: `xcode-select --install` (the full Xcode is not needed).
- The dictionaries for your languages. Lookup Word's Settings window turns them on for you: **Enable** next to a
  language, and macOS downloads its dictionaries in a minute or two. By hand: open Dictionary, choose **Dictionary →
  Settings…** (⌘,) and tick them: *Oxford Dictionary of English*, plus each language's own and its X - English
  dictionary (*Dutch* and *Dutch - English*, say).

Lookup Word reads the dictionaries through parts of Apple's Dictionary Services that Apple doesn't document
(`DCSCopyRecordsForSearchString`, `DCSRecordCopyData`, `DCSCopyAvailableDictionaries`). A future
macOS may change them and break lookups until Lookup Word is updated, and they keep it out of the Mac App Store.

## Install

```bash
git clone https://github.com/gregth/lookup-word.git
cd lookup-word
./install.sh
```

The script builds the app into `~/Applications/Lookup Word.app`, starts it at login, and lists which of your languages'
dictionaries are ready. Lookup Word then opens a welcome window with its two permissions, each with a button to the
setting, and the languages that are on:

- **Accessibility**, required: to notice the shortcut and read the selection.
- **Screen Recording**, optional: to point at a word without selecting it. You can skip it; pointing at a word later
  asks again.

Switch Lookup Word on, and the window notices by itself:

![The welcome window: Accessibility (required) and Screen Recording (optional), each with a button to its setting](docs/welcome.png)

The languages on at first are English and those of your Mac's preferred languages (System Settings → General →
Language & Region) that have a pack. If your Mac is set to English only, the card has no translations yet: turn on
your other languages in **Settings… → Languages** (the welcome window and the card link there).

Lookup Word isn't signed with an Apple Developer ID, so there is no download to install, only this build from source.
macOS doesn't quarantine an app built on your own Mac, so it opens without a Gatekeeper warning. To keep your
permissions across rebuilds, create a self-signed code-signing certificate named "Lookup Word Signing" (Keychain Access
→ Certificate Assistant → Create a Certificate…, Self Signed Root, Code Signing) before running the script, or pass
your own with `LOOKUP_SIGN_IDENTITY` (remembered for the next install and update). Either way the app is signed with
the hardened runtime.

### Update

```bash
cd lookup-word
./update.sh
```

`update.sh` pulls the latest version and reinstalls it (it needs a git clone, not a ZIP download); your settings and
words stay as they are. Each new build is a
new app to macOS unless it is signed with the same certificate, so create the "Lookup Word Signing" certificate once
(see above) to keep your permissions across updates; without it, the welcome window asks for them again.

### Uninstall

To remove it: menu bar icon → **Uninstall Lookup Word…**, or `./uninstall.sh`. Your settings, backups and logs stay;
tick **Also delete my settings…**, or add `--purge`, to delete them too, with the vocabulary in Lookup Word's own
folder and its preferences and cache. A vocabulary file you keep elsewhere is never deleted.

## Use

There are three ways to look up a word. The first two end the same way: press the **⌥ Option** key twice, quickly,
and the card appears; the third is a box to type into. To close it, click anywhere else or press any key (with VoiceOver on, Escape, so its keys can read the card, which
VoiceOver announces); it also closes by itself after 30 seconds.

### 1. Select the word

![Dragging across a word to select it, pressing ⌥ twice, and its card](docs/mode-selection.gif)

- Double-click the word, or drag over it, in any app. Then press ⌥ twice.
- Lookup Word needs the **Accessibility** permission for this: it lets it notice the two key presses and read the
  word you selected. The welcome window asks for it when you first open the app.

### 2. Or point at it

![Resting the pointer on a word without selecting it, pressing ⌥ twice, and the highlighted word with its card](docs/mode-screen.gif)

- Rest the mouse pointer on the word, without selecting anything. Then press ⌥ twice. Lookup Word finds the word,
  highlights it in yellow, and shows its card.
- This also works where you can't select text: pictures, videos, some apps and remote desktops.
- Lookup Word needs a second permission for this, which macOS calls **Screen Recording**. Don't let the name worry
  you: Lookup Word only takes a picture of a small area around the pointer, only when you press the keys, and never
  saves it or sends it anywhere (unless you turn on `"debug": true` for troubleshooting).
- This one is optional. The welcome window offers it; if you skip it, pointing at a word later shows a card that
  explains it again, with a button to allow it. Selecting words keeps working without it.

### 3. Or type it

![Pressing ⌃⌘L, typing "liep" in the box that opens and pressing Return, and the card for "lopen" below the box](docs/mode-type.gif)

- Press **⌃⌘L** (Control, Command and L together; in Settings you can record any other with two of ⌃, ⌥ and ⌘) in any app, or choose **Look Up a Word…** in the menu bar menu.
  A box opens near the top of the screen: type the word, in any of your languages, and press Return. Its card
  shows below the box, and the box keeps the keyboard, so you can type the next word straight away.
- **Escape** closes the card; press it again to close the box. A click anywhere else closes both.
- **The pin** (📌 at the box's right end) keeps the box open: with it on, clicking elsewhere leaves the box where it
  is, ready for the next word, and the card no longer closes by itself after 30 seconds. Escape still closes the
  card, then the box. Click the pin again to turn it off.
- **ⓧ** clears the word, and its card.
- **Drag the box** anywhere: its card moves with it, and the box opens there next time. To put it back in the middle, choose **Reset the Box's
  Position** in the menu bar menu, or in Settings.
- This needs no permission at all, so it works even before you allow the other two.

### On the card

- **Click the speaker** next to a word to hear it, in its own language's voice.
- **Click a language's code** (NL, EL…) to jump to that language's dictionary entry further down the card.
- **Click a dictionary's name** (▾) to fold its entry away, or **Collapse all**, at the right above the entries, to
  fold them all; the next cards open folded too, until you choose **Expand all**.
- **A language whose dictionaries are missing** gets a muted line instead of its translation, with a link to Settings,
  where **Enable** turns them on.
- **Read more** at the foot links to that language's dictionaries online: Cambridge, Merriam-Webster, Woorden.org,
  Τριανταφυλλίδη, Larousse, RAE, Duden, DWDS, WordReference and Wiktionary, two or three per language.
- **The menu bar icon** opens your vocabulary and the settings, and uninstalls the app.

## Settings

Menu bar icon → **Settings…**:

![The settings window: shortcut, the word under the pointer, menu bar icon, card timeout, languages, and where words are saved](docs/settings.png)

**Save and Restart** applies the changes. **Restore Defaults** puts a new user's settings in the window (applied by
Save and Restart too); where and how words are saved stays as it is. The settings are stored in
`~/Library/Application Support/Lookup Word/config.json`, written with the defaults on first launch. After editing that
file by hand, choose **Restart Lookup Word** in the menu. Every key is optional; a key it doesn't know (a misspelling) is ignored, with a
warning on the card. A file that isn't valid JSON leaves the defaults in force and saves no words until you fix it: the
Settings window says so and won't save over it.

| Key | Default | What it does |
|---|---|---|
| `languages` | English, plus your Mac's preferred languages that have a pack | The language packs to use, from [packs/](packs/). English is the pivot and is always on. |
| `hotkey` | `"option"` | The key to press twice: `option`, `control`, `command` or `shift`. |
| `typeShortcut` | ⌃⌘L | The type-a-word box's shortcut: any key with two of ⌃, ⌥ and ⌘ (with ⌘ or ⌥ alone it would take that key from every app). Set it in **Settings…**: click the shortcut, then press the keys you want (Escape cancels); the ⓧ next to it turns it off, and it then reads **Record Shortcut**. Stored as `"key:<code>:<modifiers>:<key>"`, or `"none"`. |
| `menuBar` | `true` | Show the menu bar icon. **Hide Menu Bar Icon** in its menu sets this to `false`. With the icon hidden, open Lookup Word again from Applications for its settings. |
| `closeAfter` | `30` | Seconds before the card closes by itself; `0` keeps it open until a click or a key. |
| `debug` | `false` | Save each screen reading as `capture.png` in the support folder and log its coordinates. |
| `store` | Markdown | `{"type": "markdown" \| "json" \| "none", "path": "…", "saveDate": false}`: where looked-up words go, see below. A relative `path` is in your home folder. |

### Where words are saved

Saving is optional: in **Settings… → Save words to**, choose a Markdown file (the default), a JSON file, or nowhere.

- **Markdown:** one `## English`, `## Dutch`… section per language, each a table. A language's section is added at the
  end of the file the first time you look up a word in it; after that, each new word is one more row. Nothing else in
  the file changes (but a new language's column, below), so you can keep it in a notes vault (Obsidian, Logseq…) and write your own notes around the
  tables. Here is [a file after nine lookups](docs/sample-vocabulary.md), as a notes app shows it:

  ![A vocabulary file with English, Dutch and Greek tables: each word with its meaning or English, and its translations](docs/vocabulary.png)

- **JSON:** a list of `{word, language, meaning, translations}`, for your own scripts. Keys you add to a word (notes,
  tags) are kept (a number may be rewritten at full precision: 0.1 as 0.10000000000000001).
- **Also save the date and time** (off by default): an **Added** column, or an `added` field in JSON.

A language you add in Settings, or Added once you turn it on, gets its own column at the end of an existing table on
the next save, with an empty cell in the rows already there. Columns you reorder or rename to a language's name keep
working: rows follow the table's own header.

A save never writes over a file another app (a sync client, an editor) is in the middle of saving. It skips a read
that comes back empty (but a note that stays empty before its first save), unreadable or much shorter than after the last save, writes only if the file still holds what
it read, writes through a temporary file renamed over it, and keeps the last 30 saved versions in `backups/`, in a
folder per vocabulary file.

### Where things are

| What | Where |
|---|---|
| The app | `~/Applications/Lookup Word.app` |
| Settings | `~/Library/Application Support/Lookup Word/config.json` |
| Your words (default) | `~/Library/Application Support/Lookup Word/Vocabulary.md` (or `vocabulary.json`), unless you choose a file |
| Backups of the words file | `~/Library/Application Support/Lookup Word/backups/` |
| Log | `~/Library/Logs/Lookup Word/lookup.log`: it lists the words you look up, also with **Save words to: Nowhere**. Over 1 MB, Lookup Word cuts it to its last 256 KB when it starts. |
| Start at login | `~/Library/LaunchAgents/io.github.gregth.lookup-word.plist` |

## Languages

| Language | Tested by |
|---|---|
| 🇬🇧 English, always on: the others translate through it | its author's daily use |
| 🇳🇱 Dutch | its author's daily use |
| 🇬🇷 Greek | its author, a native speaker |
| 🇫🇷 French | **community**: test words only, no native speaker yet |
| 🇩🇪 German | **community**: test words only, no native speaker yet |
| 🇪🇸 Spanish | **community**: test words only, no native speaker yet |

A language is on at first when your Mac uses it; turn the others on in **Settings… → Languages**.

Each language is a folder in [packs/](packs/): a `pack.json` that names its dictionaries, voice and grammar labels,
plus an optional lemma list. A language can join when Dictionary.app has a dictionary between it and English. To add
one, see [CONTRIBUTING.md](CONTRIBUTING.md).

Screen reading uses macOS's text recognition, which reads some languages and not others (Greek among those it doesn't
read). For Greek, Lookup Word maps the look-alike letters it gets back to Greek, and checks the reading against the
app's own text where the app shares it (Chrome and Electron apps do).

## Limits

- Names and very new words are often missing from the dictionaries (*λάπτοπ*).
- Languages without a dictionary between them translate through English, so a translation can be off: the English
  word has meanings of its own, and the other language may pick one the original never had (Dutch *zetten* → *set,
  put* → Greek *κάνω, προκαλώ*, "make, cause"). Check the entry when it matters.
- Hyphenated compounds and numbers read off the screen come back as one token.
- Screen reading needs readable contrast; tiny or stylised text may misread.
- Dictionary.app's list of dictionaries, and every entry for a word (French *pain* is also English *pain*), come
  through private calls (stable for years, but undocumented), which also keeps the app out of the Mac App Store.

## Troubleshooting

```bash
"$HOME/Applications/Lookup Word.app/Contents/MacOS/LookupWord" --dictionaries
```

The command lists the available dictionaries and which ones each language still needs.

- `--text WORD [en|nl|el]`: prints the entry it would show, without the screen.
- `--pointer "SOME TEXT" [size] [bold] [dark] [spread]`: tests screen reading on rendered text.
- Logs go to `~/Library/Logs/Lookup Word/lookup.log`. It lists the words you looked up, and a selection it found no
  entry for when it looks like a word (anything else, such as a password, only by its length): before attaching it to an issue, keep only the lines about the
  problem.
- A security problem: report it privately, as [SECURITY.md](SECURITY.md) says, not in a public issue.

## How it works

[docs/DESIGN.md](docs/DESIGN.md) has diagrams of the parts, a lookup from end to end, translation through English,
the vocabulary file's safe write, and how settings are applied.

## Disclaimer

Lookup Word is a personal project, shared as is, with no warranty and no support commitment. I'm not responsible for
any loss or damage from using it, including lost or changed notes: keep your own backups of anything you point it at.
It isn't affiliated with Apple or with any dictionary publisher. The dictionary content it shows comes from the
dictionaries installed on your Mac and belongs to their publishers. The [licence](LICENSE) states the legal terms.

The screenshots, GIFs and [sample vocabulary](docs/sample-vocabulary.md) show short excerpts of macOS's dictionaries,
to illustrate what the app does. Their copyright stays with their publishers:

- *Oxford Dictionary of English*: © 2010, 2025 Oxford University Press.
- *Prisma woordenboek Nederlands* (© 2010, 2023) and *Prisma Handwoordenboek Engels* (© 2010, 2013): Uitgeverij
  Unieboek | Het Spectrum bv, under licence to Oxford University Press.
- *Λεξικό της κοινής νεοελληνικής* (Dictionary of Standard Modern Greek): © 2010, 2022 Aristotle University of
  Thessaloniki, under licence to Oxford University Press.
- *Stavropoulos Oxford Greek-English Learner's Dictionary*: © 1989, 2008, 2023 Nikolaos Stavropoulos, under licence to
  Oxford University Press.

If you hold rights to any of it and want an image changed or removed, open an issue.

## Licence

The code is under the [MIT License](LICENSE). The Greek lemma list in [packs/el/](packs/el/) is derived from simplemma
and keeps its sources' share-alike terms: see [packs/el/LICENSE.md](packs/el/LICENSE.md).
