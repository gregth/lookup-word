// Where looked-up words are saved: a Markdown file of tables, one per language (readable anywhere, and a note in
// Obsidian or any notes app when the path points into a vault), or a JSON list. Each save answers with one status
// line for the card.
import Foundation

protocol VocabularyStore {
    var url: URL? { get }
    func save(_ e: Entry) -> String
}

func makeStore(_ c: StoreConfig) -> VocabularyStore {
    if configBroken { return BrokenStore() }
    switch c.type {
    case "json": return JSONStore(url: URL(fileURLWithPath: expand(c.path ?? Paths.support.appendingPathComponent("vocabulary.json").path)))
    case "none": return NoStore()
    default: return MarkdownStore(c)
    }
}

struct NoStore: VocabularyStore {
    var url: URL? { nil }
    func save(_ e: Entry) -> String { "" }
}

struct BrokenStore: VocabularyStore {
    var url: URL? { nil }
    func save(_ e: Entry) -> String { "Not saved: config.json is not valid JSON. Fix it (menu bar → Open Settings), then restart." }
}

// --- JSON: [{word, language, meaning, translations: {code: words}, added}] ----------------------------------------

struct JSONStore: VocabularyStore {
    struct Word: Codable { var word, language, meaning: String; var translations: [String: String]; var added: String }
    let file: URL
    init(url: URL) { file = url }
    var url: URL? { file }

    func save(_ e: Entry) -> String {
        var list: [Word] = []
        if let data = try? Data(contentsOf: file) {
            guard let l = try? JSONDecoder().decode([Word].self, from: data) else { return "Not saved: \(file.lastPathComponent) is not a word list." }
            list = l
        }
        if list.contains(where: { $0.language == e.lang && $0.word.lowercased() == e.word.lowercased() }) { return "Already in your vocabulary." }
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        list.append(Word(word: e.word, language: e.lang, meaning: e.meaning,
                         translations: Dictionary(e.tr.filter { !$0.1.isEmpty }, uniquingKeysWith: { a, _ in a }), added: day))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(list).write(to: file, options: .atomic)
        } catch { return "Not saved: \(error.localizedDescription)" }
        return "Saved to your vocabulary."
    }
}

// --- Markdown: | Word | <columns> | tables, one per language ---------------------------------------------------------
// Safe against another program writing the same file (a notes app syncing it, an editor saving it): a save reads
// until the file is whole (its prefix and required text, a minimum size), writes only if the file still holds what
// it read, writes through a temporary file renamed over it, and first copies the file to backups/ in the support
// folder. Each save changes one row (and makes that language's section, once); nothing else in the file changes.

struct MarkdownStore: VocabularyStore {
    let c: StoreConfig
    let file: URL
    init(_ c: StoreConfig) {
        self.c = c
        file = URL(fileURLWithPath: expand(c.path ?? Paths.support.appendingPathComponent("Vocabulary.md").path))
    }
    var url: URL? { file }

    // this language's ## heading ("" for the table at the top) and its columns after Word
    func heading(_ code: String) -> String { c.sections?[code]?.heading ?? pack(code)?.name ?? code }
    func columns(_ code: String) -> [String] {
        if let cols = c.sections?[code]?.columns, !cols.isEmpty { return cols }
        return code == "en" ? ["meaning"] + others.map(\.code) : ["en"] + others.map(\.code).filter { $0 != code }
    }
    func columnName(_ col: String) -> String { col == "meaning" ? "Meaning" : pack(col)?.name ?? col }
    func place(_ code: String) -> String { heading(code).isEmpty ? "Vocabulary" : heading(code) }

    // why a read is not the whole file, or nil when it is
    func incomplete(_ text: String?) -> String? {
        guard let text else { return "\(file.lastPathComponent) is not readable as UTF-8 text" }
        if text.isEmpty { return "\(file.lastPathComponent) is empty (another app saving it?)" }
        if let p = c.requirePrefix, !text.hasPrefix(p) { return "\(file.lastPathComponent) does not start with “\(p)” (another app saving it?)" }
        if let missing = (c.requireText ?? []).first(where: { !text.contains($0) }) {
            return "\(file.lastPathComponent) lacks “\(missing.trimmingCharacters(in: .whitespacesAndNewlines))” (another app saving it?)"
        }
        if let n = c.minBytes, text.utf8.count < n { return "\(file.lastPathComponent) is shorter than \(n) bytes (another app saving it?)" }
        return nil
    }

    // the file's text, read again until it is whole (a writer elsewhere may hold it half-written for a moment); or
    // why not, after a few tries
    func read() -> (String?, String) {
        if !FileManager.default.fileExists(atPath: file.path) {
            // a first save makes the file, unless the settings expect something in it already; an empty one is left alone
            guard c.requireText == nil, c.minBytes == nil else { return (nil, "\(file.path) does not exist (check store.path in the settings)") }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? ((c.requirePrefix ?? "# Vocabulary") + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        var why = ""
        for i in 0..<5 {
            let text = try? String(contentsOf: file, encoding: .utf8)
            guard let reason = incomplete(text) else { return (text, "") }
            why = reason
            if i < 4 { Thread.sleep(forTimeInterval: 0.3) }
        }
        return (nil, why)
    }

    // the new text in place of the old, only if the file still holds exactly the old: a backup first, then a
    // temporary file renamed over it, so no reader ever sees half of it. False when the file changed meanwhile.
    func write(_ old: String, _ new: String) -> Bool {
        let keep = c.backups ?? 30
        if keep > 0 {
            let dir = Paths.support.appendingPathComponent("backups")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"  // two saves in a second keep two
            let stem = file.deletingPathExtension().lastPathComponent
            try? FileManager.default.copyItem(at: file, to: dir.appendingPathComponent("\(stem)-\(f.string(from: Date())).md"))
            let mine = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasPrefix(stem + "-") && $0.hasSuffix(".md") }.sorted()
            for stale in mine.dropLast(keep) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale)) }
        }
        guard (try? String(contentsOf: file, encoding: .utf8)) == old else { return false }
        let tmp = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).saving")
        guard (try? new.write(to: tmp, atomically: false, encoding: .utf8)) != nil else { return false }
        return rename(tmp.path, file.path) == 0
    }

    // the line span of that language's table: the top one from the start to the first ## heading, the others from
    // their heading to the next one; nil while that section does not exist
    func section(_ lines: [String], _ code: String) -> Range<Int>? {
        let heads = lines.indices.filter { lines[$0].hasPrefix("## ") }
        let h = heading(code)
        if h.isEmpty { return 0..<(heads.first ?? lines.count) }
        guard let i = lines.firstIndex(of: "## \(h)") else { return nil }
        return i..<(heads.first { $0 > i } ?? lines.count)
    }

    // that table's words, lower-cased
    func known(_ lines: [String], _ code: String) -> Set<String> {
        guard let span = section(lines, code) else { return [] }
        return Set(lines[span].compactMap { line in
            line.range(of: #"^\|\s*\*\*[^*]+\*\*\s*\|"#, options: .regularExpression).map {
                replacing(String(line[$0]), #"^\|\s*\*\*|\*\*\s*\|$"#, "").trimmingCharacters(in: .whitespaces).lowercased()
            }
        })
    }

    func save(_ e: Entry) -> String {
        guard !e.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Not saved: no word." }
        for _ in 0..<3 {  // again when another program changed the file between our read and our write
            let (text, why) = read()
            guard let old = text else { return "Not saved: \(why)." + (why.contains("another app") ? " Try again in a moment." : "") }
            switch insert(old, e) {
            case .status(let s): return s
            case .text(let new): if write(old, new) { return "Saved to \(place(e.lang))." }
            }
        }
        return "Not saved: \(file.lastPathComponent) kept changing. Try again."
    }

    enum Change { case status(String), text(String) }

    // the text with the word's row in its table; or a status line when there is nothing to write
    func insert(_ text: String, _ e: Entry) -> Change {
        var lines = text.components(separatedBy: "\n")
        if known(lines, e.lang).contains(e.word.lowercased()) { return .status("Already in \(place(e.lang)).") }
        let cols = columns(e.lang)
        if section(lines, e.lang) == nil {  // the first word in that language makes its section, before insertBefore
            let at = c.insertBefore.flatMap { b in lines.firstIndex { $0.hasPrefix(b) } } ?? lines.count
            let name = pack(e.lang)?.name ?? e.lang, names = cols.map(columnName)
            let rest = names.dropFirst().joined(separator: " and the ")
            let intro = cols.first == "meaning" ? "with their meaning" : "with their \(names.first ?? "") meaning"
            lines.insert(contentsOf: ["## \(heading(e.lang))", "", "\(name) words looked up, \(intro)\(rest.isEmpty ? "" : " and the \(rest)").", "",
                                      "| Word | " + names.joined(separator: " | ") + " |", "|" + String(repeating: " --- |", count: cols.count + 1), ""], at: at)
        }
        if heading(e.lang).isEmpty, let span = section(lines, e.lang), !span.contains(where: { lines[$0].hasPrefix("|") }) {
            // the top table, the first time: after the file's title line, when it has one
            let at = lines.first.map { $0.hasPrefix("# ") } == true ? 1 : 0
            let names = cols.map(columnName)
            lines.insert(contentsOf: ["", "| Word | " + names.joined(separator: " | ") + " |", "|" + String(repeating: " --- |", count: cols.count + 1)], at: at)
        }
        guard let span = section(lines, e.lang), let end = span.last(where: { lines[$0].hasPrefix("|") }) else {
            return .status("Not saved: no word table for \(place(e.lang)) in \(file.lastPathComponent).")
        }
        let cell = { (s: String) in replacing(s, #"\s+"#, " ").replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces) }
        lines.insert("| **\(cell(e.word))** | " + cols.map { cell(e.value($0)) }.joined(separator: " | ") + " |", at: end + 1)
        return .text(lines.joined(separator: "\n"))
    }
}

let store: VocabularyStore = makeStore(config.store)
