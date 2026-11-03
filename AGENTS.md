# Agent notes for Lookup Word

A macOS menu bar app in Swift that looks a word up in Apple's dictionaries and saves it. [README.md](README.md) says
what it does, [docs/DESIGN.md](docs/DESIGN.md) how the parts fit, [CONTRIBUTING.md](CONTRIBUTING.md) how to add a
language and the code conventions. Read those; this file only adds what an agent needs on top.

## Constraints

- No dependencies: [Package.swift](Package.swift) has one target and no packages; don't add one.
- Apple's Command Line Tools only, macOS 14 or later (`SCScreenshotManager`): no Xcode project, no higher deployment
  target.
- Lookups go through undocumented Dictionary Services calls (`DCSCopyRecordsForSearchString`, `DCSRecordCopyData`,
  `DCSCopyAvailableDictionaries`); there is no public API to switch to. A lookup bug may be a macOS change.

## Build and check

- `swift build -c release`, then `.build/release/LookupWord --text <word> <hint>` looks a word up without the screen.
- CI ([.github/workflows/build.yml](.github/workflows/build.yml)) only builds and checks that every pack loads. These
  need a real Mac session, so run them yourself before calling a change done:
  - [scripts/test-packs.sh](scripts/test-packs.sh) `[code…]` after any change to lookup, matching, glosses or a pack.
  - [scripts/test-install.sh](scripts/test-install.sh) after any change to `install.sh`, `uninstall.sh`, `update.sh`
    or the launch agent.
  - `--pointer` on a few lines in each language after any change to screen reading.
- A change to a pack adds the word that motivated it to that pack's `tests.tsv`.

## Leave the real install alone

The user's own copy runs from `~/Applications/Lookup Word.app` with its words in
`~/Library/Application Support/Lookup Word/`. Never write there or restart it. Point test runs at a temporary folder
with `LOOKUP_SUPPORT`, `LOOKUP_LOGS` and `LOOKUP_QUIET=1`, as the scripts do.

## Docs and images

- Every claim in the README is checked against the app; keep it that way when behaviour changes, and update
  [docs/DESIGN.md](docs/DESIGN.md) when a component's job changes.
- Re-render images rather than editing them: `--render`, `--render-welcome`, `--render-settings` and the scripts in
  [scripts/](scripts/).
- GitHub Actions stay pinned to a commit SHA with the version in a comment.

## Commits

Subject as `Area: what changed, in plain words` (`Card: a wrapped translation indented`), no conventional-commit
prefixes.
