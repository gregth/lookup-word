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
    case "json": return JSONStore(c)
    case "none": return NoStore()
    default: return MarkdownStore(c)
    }
}

// the path in the settings, nil when unset or blank (the default file then)
func storePath(_ c: StoreConfig) -> String? { c.path.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } }

// the vocabulary file: a relative path is in the home folder, not wherever the app was started (the launch agent
// starts it in /); a symlinked file is saved where it points, not replaced by a plain file
func storeFile(_ c: StoreConfig, _ name: String) -> URL {
    let path = expand(storePath(c) ?? Paths.support.appendingPathComponent(name).path)
    let home = FileManager.default.homeDirectoryForCurrentUser
    return (path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)).resolvingSymlinksInPath()
}

struct NoStore: VocabularyStore {
    var url: URL? { nil }
    func save(_ e: Entry) -> String { "" }
}

struct BrokenStore: VocabularyStore {
    var url: URL? { nil }
    func save(_ e: Entry) -> String { "Not saved: config.json is not valid JSON. Fix it (menu bar → Settings…), then restart." }
}

// --- JSON: [{word, language, meaning, translations: {code: words}, added}] ----------------------------------------
// Each entry is kept as the file has it, so a key the user or another tool added (notes, tags) survives a save.

struct JSONStore: VocabularyStore {
    let saveDate: Bool, file: URL
    init(_ c: StoreConfig) {
        saveDate = c.saveDate
        file = storeFile(c, "vocabulary.json")
    }
    var url: URL? { file }

    func save(_ e: Entry) -> String {
        var list: [[String: Any]] = []
        // an empty file (just made in another app) is an empty list
        if let data = try? Data(contentsOf: file), !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let l = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return "Not saved: \(file.lastPathComponent) is not a word list." }
            list = l
        }
        if list.contains(where: { $0["language"] as? String == e.lang && ($0["word"] as? String)?.lowercased() == e.word.lowercased() }) { return "Already saved to your vocabulary." }
        var word: [String: Any] = ["word": e.word, "language": e.lang, "meaning": e.meaning,
                                   "translations": Dictionary(e.tr.filter { !$0.1.isEmpty }, uniquingKeysWith: { a, _ in a })]
        if saveDate { word["added"] = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]) }
        list.append(word)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: file, options: .atomic)
        } catch { return "Not saved: \(error.localizedDescription)" }
        return "Saved to your vocabulary."
    }
}

// --- Markdown: one "## Language" section per language, each a | Word | … | table -----------------------------------
// The file is meant to be read and synced by other apps (a notes vault), so a save never writes over a read that may
// be half of the file: it reads until the file is whole, writes only if the file still holds what it read, writes
// through a temporary file renamed over it, and keeps the last 30 versions in backups/ in the support folder. Each save
// adds one row (and, the first time, that language's section at the end; for a language added since, a column at the
// end of its table); nothing else in the file changes.

struct MarkdownStore: VocabularyStore {
    let file: URL, saveDate: Bool
    init(_ c: StoreConfig) {
        saveDate = c.saveDate
        file = storeFile(c, "Vocabulary.md")
    }
    var url: URL? { file }
    var name: String { file.lastPathComponent }

    // a new table's columns after Word: English's own meaning, then the other languages; another language's English
    // first, then the rest
    func columns(_ code: String) -> [String] {
        (code == "en" ? ["meaning"] + others.map(\.code) : ["en"] + others.map(\.code).filter { $0 != code }) + (saveDate ? ["added"] : [])
    }
    func columnName(_ col: String) -> String { col == "meaning" ? "Meaning" : col == "added" ? "Added" : pack(col)?.name ?? col }
    // an existing table's column, by its header: "Meaning", a language's name or code; "" for one this app does not fill
    func column(_ header: String) -> String {
        let h = header.trimmingCharacters(in: .whitespaces).lowercased()
        if h == "meaning" || h == "added" { return h }
        return packs.first { $0.name.lowercased() == h || $0.code == h }?.code ?? ""
    }
    func heading(_ code: String) -> String { pack(code)?.name ?? code }
    // a table row's cells, split at unescaped pipes, the empty pieces outside the outer pipes dropped
    func cells(_ line: String) -> [String] {
        var parts = line.components(separatedBy: "|").reduce(into: [String]()) { out, piece in
            if let last = out.last, last.hasSuffix("\\") { out[out.count - 1] = last + "|" + piece } else { out.append(piece) }
        }
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts
    }

    // The size of the file after the last save, so a read that is much shorter (half a file, while another app writes
    // it) is caught: one small file per vocabulary file in the support folder, so two saves never overwrite each other's.
    var key: String { String(file.path.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }, radix: 16) }  // djb2: stable across runs
    var sizeFile: URL { Paths.support.appendingPathComponent("sizes/\(key).txt") }
    func lastSize() -> Int? { (try? String(contentsOf: sizeFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    func remember(_ size: Int?) {
        guard let size else { try? FileManager.default.removeItem(at: sizeFile); return }
        try? FileManager.default.createDirectory(at: sizeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(size)\n".write(to: sizeFile, atomically: true, encoding: .utf8)
    }

    // the file's text, read again until it looks whole; or why not, after a few tries
    func read() -> (String?, String) {
        if !FileManager.default.fileExists(atPath: file.path) {
            // gone since a save: moved, renamed, or a sync client mid-swap; making a new one would split the words
            if lastSize() != nil {
                remember(nil)  // look the word up again to start a new file there
                return (nil, "\(name) is no longer at \(file.deletingLastPathComponent().path). If you moved it, choose it again in Settings; to start a new one there, look the word up again")
            }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "# Vocabulary\n".write(to: file, atomically: true, encoding: .utf8)
            } catch { return (nil, "\(name) could not be made in \(file.deletingLastPathComponent().path): \(error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ".")))") }
        }
        var why = "", reads: [String?] = []
        for i in 0..<5 {
            let text = try? String(contentsOf: file, encoding: .utf8)
            if let text, !text.isEmpty, text.utf8.count * 2 >= (lastSize() ?? 0) { return (text, "") }
            // empty is whole only before the first save (a note just made in another app), and only once it stays
            // empty for three reads (not a note truncated for a moment); insert() then starts it
            if text == "", (lastSize() ?? 0) == 0, i >= 2, reads.suffix(2).allSatisfy({ $0 == "" }) { return ("", "") }
            reads.append(text)
            why = text == nil ? "\(name) is not readable as text" : text!.isEmpty ? "\(name) is empty (another app saving it?)"
                : "\(name) is much shorter than after the last save (another app saving it?)"
            if i < 4 { Thread.sleep(forTimeInterval: 0.3) }
        }
        // the same short text for over a second: shortened on purpose, most likely (another app's half-written file
        // keeps changing); the next save accepts it
        if let last = reads.last, let text = last, !text.isEmpty, reads.suffix(3).allSatisfy({ $0 == last }) {
            remember(text.utf8.count)
            why += ". If you shortened it yourself, look the word up again"
        }
        return (nil, why)
    }

    // the new text in place of the old, only if the file still holds exactly the old: through a temporary file renamed
    // over it, so no reader ever sees half of it, with the file's permissions kept. Each saved version is copied to
    // backups/<key>/ (the newest 30; one folder per vocabulary file, as sizes/), and the first save also keeps the
    // version it started from. A UTF-8 BOM the file starts with is kept. False when the file changed meanwhile.
    func write(_ old: String, _ new: String) -> Bool {
        let fm = FileManager.default, dir = Paths.support.appendingPathComponent("backups/\(key)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = file.deletingPathExtension().lastPathComponent
        let mine = { ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted() }
        let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; return f.string(from: Date()) }
        if mine().isEmpty { try? fm.copyItem(at: file, to: dir.appendingPathComponent("\(stem)-\(stamp())-before.md")) }
        guard (try? String(contentsOf: file, encoding: .utf8)) == old else { return false }
        let bom = Data([0xEF, 0xBB, 0xBF]), hasBOM = (try? Data(contentsOf: file))?.starts(with: bom) == true
        let tmp = file.deletingLastPathComponent().appendingPathComponent(".\(name).saving")
        guard (try? ((hasBOM ? bom : Data()) + Data(new.utf8)).write(to: tmp)) != nil else { return false }
        if let mode = (try? fm.attributesOfItem(atPath: file.path))?[.posixPermissions] {
            try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: tmp.path)
        }
        guard rename(tmp.path, file.path) == 0 else { try? fm.removeItem(at: tmp); return false }
        remember(new.utf8.count)
        try? new.write(to: dir.appendingPathComponent("\(stem)-\(stamp()).md"), atomically: true, encoding: .utf8)
        for stale in mine().dropLast(30) { try? fm.removeItem(at: dir.appendingPathComponent(stale)) }
        return true
    }

    // the line span of that language's section, from its heading ("## Dutch", "## dutch", "##Dutch", "## nl") to the
    // next ## heading; nil while it does not exist
    func section(_ lines: [String], _ code: String) -> Range<Int>? {
        let names = [heading(code).lowercased(), code]
        guard let i = lines.firstIndex(where: { line in
            guard line.hasPrefix("##"), !line.hasPrefix("###") else { return false }
            return names.contains(line.dropFirst(2).trimmingCharacters(in: .whitespaces).lowercased())
        }) else { return nil }
        return i..<(lines.indices.first { $0 > i && lines[$0].hasPrefix("##") && !lines[$0].hasPrefix("###") } ?? lines.count)
    }

    // the section's word table: its header line and its last row (the first run of | lines; a table further down the
    // section is the user's own)
    func table(_ lines: [String], _ span: Range<Int>) -> (header: Int, end: Int)? {
        guard let header = span.first(where: { lines[$0].hasPrefix("|") }) else { return nil }
        var end = header
        while end + 1 < span.upperBound, lines[end + 1].hasPrefix("|") { end += 1 }
        return (header, end)
    }

    // that table's words, lower-cased: each row's first cell, bold or not
    func known(_ lines: [String], _ t: (header: Int, end: Int)) -> Set<String> {
        guard t.end > t.header else { return [] }
        return Set(lines[(t.header + 1)...t.end].compactMap { line in
            cells(line).first.map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*")).lowercased() }
        }.filter { !$0.isEmpty && !$0.allSatisfy { "-: ".contains($0) } })
    }

    func save(_ e: Entry) -> String {
        guard !e.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Not saved: no word." }
        for _ in 0..<3 {  // again when another program changed the file between our read and our write
            let (text, why) = read()
            guard let old = text else { return "Not saved: \(why)." }
            // a JSON file (the path kept from the JSON store, after switching to Markdown) must not get tables appended
            if (try? JSONSerialization.jsonObject(with: Data(old.utf8))) != nil {
                return "Not saved: \(name) is a JSON file. Choose a Markdown file in Settings, or save words to a JSON file."
            }
            switch insert(old, e) {
            case .status(let s): return s
            case .text(let new, let note): if write(old, new) { return "Saved to \(heading(e.lang))." + note }
            }
        }
        return "Not saved: \(name) kept changing, or could not be written. Try again."
    }

    enum Change { case status(String), text(String, String) }

    // the text with the word's row in its language's table; or a status line when there is nothing to write
    func insert(_ text: String, _ e: Entry) -> Change {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "# Vocabulary\n" : text  // a new, empty note
        let eol = text.contains("\r\n") ? "\r\n" : "\n"  // the file's own line endings, kept
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if section(lines, e.lang) == nil {  // the first word in a language: its section, at the end of the file
            let names = columns(e.lang).map(columnName)
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += ["", "## \(heading(e.lang))", "", "| Word | " + names.joined(separator: " | ") + " |",
                      "|" + String(repeating: " --- |", count: names.count + 1), ""]
        }
        let span = section(lines, e.lang)!
        guard let t = table(lines, span) else { return .status("Not saved: the \(heading(e.lang)) section of \(name) has no table.") }
        if known(lines, t).contains(e.word.lowercased()) { return .status("Already saved to \(heading(e.lang)).") }
        // a language added in Settings since the table was made (or Added, once turned on): its column at the table's
        // end, each existing row given an empty cell after its own cells (padded to the old header first), so nothing
        // asks the user to edit the header. A row already as wide as the new header is left as it is. Meaning is not
        // put back: a table without it was made that way on purpose.
        var cols = cells(lines[t.header]).dropFirst().map { column($0) }
        let wanted = columns(e.lang).filter { $0 != "meaning" && !cols.contains($0) }
        if !wanted.isEmpty {
            let old = cells(lines[t.header]).count, width = old + wanted.count
            for i in t.header...t.end where i == t.header || cells(lines[i]).count < width {
                var line = lines[i]
                while line.last?.isWhitespace == true { line.removeLast() }
                if !line.hasSuffix("|") || line.hasSuffix("\\|") { line += " |" }
                let isRule = i == t.header + 1 && cells(line).allSatisfy { $0.trimmingCharacters(in: .whitespaces).allSatisfy { "-: ".contains($0) } }
                let filler = isRule ? " --- |" : " |"
                lines[i] = line + (i == t.header ? wanted.map { " \(columnName($0)) |" }.joined() : String(repeating: filler, count: max(0, old - cells(line).count) + wanted.count))
            }
            cols += wanted
        }
        let added = wanted.isEmpty ? "" : wanted.count == 1 ? " Added a \(columnName(wanted[0])) column to its table."
            : " Added \(wanted.map(columnName).joined(separator: " and ")) columns to its table."
        // the row follows the table's own header, so a table made before a language was added still lines up
        let cell = { (s: String) in replacing(s, #"\s+"#, " ").replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces) }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let value = { (col: String) in col.isEmpty ? "" : col == "added" ? f.string(from: Date()) : cell(e.value(col)) }
        lines.insert("| **\(cell(e.word))** | " + cols.map(value).joined(separator: " | ") + " |", at: t.end + 1)
        return .text(lines.joined(separator: eol), added)
    }
}

let store: VocabularyStore = makeStore(config.store)
