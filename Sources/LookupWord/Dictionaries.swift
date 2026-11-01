// The dictionaries Look Up reads, offline: those enabled in Dictionary.app, by their short names ("English",
// "Dutch - English"). Listing them and their names takes two private calls (DCSCopyAvailableDictionaries,
// DCSDictionaryGetShortName), stable for years; the entry itself is the public DCSCopyTextDefinition, which also finds
// the headword of an inflected form (sessions → session, liep → lopen), though not of a Greek one.
import CoreServices
import Foundation

typealias AvailFn = @convention(c) () -> Unmanaged<CFSet>?
typealias NameFn = @convention(c) (AnyObject) -> Unmanaged<CFString>?
let dictionaries: [String: AnyObject] = {
    let h = dlopen(nil, RTLD_NOW)
    guard let a = dlsym(h, "DCSCopyAvailableDictionaries"), let n = dlsym(h, "DCSDictionaryGetShortName"),
          let set = unsafeBitCast(a, to: AvailFn.self)()?.takeRetainedValue() else { return [:] }
    let name = unsafeBitCast(n, to: NameFn.self)
    var out: [String: AnyObject] = [:]
    for d in (set as NSSet).allObjects as [AnyObject] {
        if let s = name(d)?.takeUnretainedValue() as String? { out[s] = d }
    }
    return out
}()

func define(_ word: String, in name: String?, follow: Bool = true) -> String? {
    guard !word.isEmpty, let name, let d = dictionaries[name] else { return nil }
    let s = word as NSString
    let t = DCSCopyTextDefinition(unsafeBitCast(d, to: DCSDictionary.self), s, CFRange(location: 0, length: s.length))?
        .takeRetainedValue() as String?
    // an entry that only points elsewhere ("ρωτώ ▶ → ΕΡΩΤΩ", "πάω vi ▶ → πηγαίνω"): the entry it points to, once
    if follow, let t, t.count < 80, let r = t.range(of: #"▶\s*→\s*([^\s,.;]+)"#, options: .regularExpression) {
        let target = String(t[r]).replacingOccurrences(of: #"^▶\s*→\s*"#, with: "", options: .regularExpression).lowercased()
        return define(target, in: name, follow: false) ?? t
    }
    return t
}

func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
func replacing(_ s: String, _ pattern: String, _ with: String) -> String {
    s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
}

// A bilingual dictionary's English headwords carry a pronunciation (| rʌn |); its other language's do not.
func englishSide(_ t: String?) -> Bool { t.map { matches($0, #"^[^|\n]{1,60}\| [^|]+ \|"#) } ?? false }

var wanted: String?  // the word being looked up, for gloss's derivatives

// The first sense of an entry as a short phrase: past the headword and pronunciation, before the first example (▸),
// sub-sense (•), sense 2 or section, without labels in <>, () or [], or grammar (the packs' labels). A list (a
// translation) keeps three items and stops at the first full stop; a meaning keeps the sense and stops at its colon.
// `target` is the language the phrase is in, when it is a translation into a language with its own script: words
// before its first word in that script go.
func gloss(_ entry: String?, list: Bool = true, target: Pack? = nil) -> String {
    guard var s = entry else { return "" }
    // an entry for another headword ("alignment" finds align): the word's own line under DERIVATIVES, when it has one
    if let word = wanted, !s.lowercased().hasPrefix(word.lowercased()),
       let r = s.range(of: #"(?<=\s)"# + NSRegularExpression.escapedPattern(for: word) + #"\s+(n|nn|adj|adv|v|vt|vi|znw|bn|bw|ww)\b"#,
                       options: [.regularExpression, .caseInsensitive]) {
        s = String(s[r.lowerBound...])
    }
    for (pattern, with) in glossVariants { s = replacing(s, pattern, with) }  // "αδελφός, καίαδερφός Anm …": the variant goes
    // past the pronunciations: the last one near the top, since an irregular word lists its forms first, each with its
    // own (say | seɪ | … says | sez | … said | sed | λέγω) — a chain: from the first, on to the next only while it
    // follows within 40 characters (not a derivative's, further on)
    let prons = s.ranges(of: #/\|[^|]*\|/#)
    if var last = prons.first {
        for r in prons.dropFirst() where s.distance(from: last.upperBound, to: r.lowerBound) <= 40 { last = r }
        s = String(s[last.upperBound...])
    } else { s = String(s.drop { !$0.isWhitespace }) }
    // grammar notes before sense 1 (μεταφέρ[ν]ω vt μετέφερα αόρ., … 1carry): the meaning starts at the 1
    if let r = s.range(of: #"(?<=[\s.])1(?=\s?[\p{L}\[(<])"#, options: .regularExpression), s.distance(from: s.startIndex, to: r.lowerBound) < 200 {
        s = String(s[r.upperBound...])
    } else if !glossNotes.isEmpty,
              let r = s.prefix(240).range(of: #"(?s).*\b("# + glossNotes.joined(separator: "|") + #")\."#, options: .regularExpression) {
        s = String(s[r.upperBound...])  // no sense numbers: the meaning starts after the last grammar note (πήγα αόρ., … μτχ. παρακ.)
    }
    // a suffix variant in brackets (gelijk(-heid)), a ~ grammar note (γάλα "~ τος gen"), then a bracketed label
    // between two translations ("potato (sl) spud")
    if let r = s.range(of: #"^\s*\([^)]*\.\)[^▸]*?▸?.*?\s2(?=\s?[\p{L}\[(<])"#, options: .regularExpression) {
        s = String(s[r.upperBound...])  // (γραμμ.) noun … 2name → name: a field-labelled first sense gives way to sense 2
    }
    s = replacing(s, #"\(\s*[-~][^)]*\)"#, "")
    s = replacing(s, #"~\s?\S*(\s+gen\b)?"#, " ")
    s = replacing(s, #"\([^)]*\)"#, list ? ", " : " ")
    for cut in glossCuts + (list ? [] : [":"]) {
        if let r = s.range(of: cut) { s = String(s[..<r.lowerBound]) }
    }
    // the next sense, wherever its number stands ("calculating machine 2", "hangen 2, helling 3")
    if let r = s.range(of: #"\s\d{1,2}(?=\s|$|,|[\p{L}\[<])"#, options: .regularExpression) { s = String(s[..<r.lowerBound]) }
    s = replacing(s, #"<[^>]*>|\[[^\]]*\]|\bv\. \S+( &)?"#, " ")
    if list, let r = s.range(of: ". ") { s = String(s[..<r.lowerBound]) }
    var words = s.split(separator: " ").map(String.init)
    // a label, also with its section letter glued on (A + nm = "Anm", A + vt = "Avt")
    let label = { (w: String) in let x = w.trimmingCharacters(in: .punctuationCharacters); return glossLabels.contains(x) || (x.count > 1 && "ABCD".contains(x.first!) && glossLabels.contains(String(x.dropFirst()))) }
    while let f = words.first, label(f) || f.allSatisfy(\.isNumber) {
        words.removeFirst()
    }
    // labels inside a list too ("IRS znw belastingdienst", "ook:", "aux verb be")
    words = words.filter { !glossInner.contains($0.trimmingCharacters(in: .punctuationCharacters)) }
    if let script = target?.script {
        let own = #"\p{"# + script + "}"
        if let i = words.firstIndex(where: { matches($0, own) }) { words.removeFirst(i) }  // "U έλλειψη", "A ) vi …"
        if let i = words.lastIndex(where: { $0.hasSuffix(")") }), i < words.count - 1 { words.removeFirst(i + 1) }  // "… υπερσυντέλικου) έχω"
    }
    s = replacing(replacing(words.joined(separator: " "), #"\s*&\s*(?=,|$)"#, ""), #"^\d+"#, "").trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ".,;:")))
    guard list else { return s }
    return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains(where: \.isLetter) }.prefix(3)
        .joined(separator: ", ")
}

// An X - English translation without the X hint before it (Dutch liep: "gaan walk, go"; mooie: "aantrekkelijk
// attractive"): each item loses its leading words that X's own dictionary has and English's does not, or that both
// have while a later word is still X ("van plan zijn shall/will"); never its last word.
func withoutHints(_ text: String, _ p: Pack) -> String {
    func own(_ w: String) -> Bool { define(w, in: p.monolingual) != nil }
    func eng(_ w: String) -> Bool { define(w, in: english.monolingual) != nil }
    let items = text.split(separator: ",").map { item -> String in
        var words = item.split(separator: " ").map(String.init), hint = false
        // once a hint has begun, its X words go even when English has them too (beschikken over have → have)
        while words.count > 1, own(words[0]) && (hint || !eng(words[0]) || words.dropFirst().contains { own($0) && !eng($0) }) {
            words.removeFirst(); hint = true
        }
        return words.joined(separator: " ")
    }.filter { !$0.isEmpty }
    // a whole item that is only an X word (bezitten, …) goes too, while something is left
    let kept = items.filter { !($0.split(separator: " ").count == 1 && own($0) && !eng($0)) }
    return (kept.isEmpty ? items : kept).joined(separator: ", ")
}

// A verb's part of an English entry in an X - English dictionary (θέλω → like gave Dutch "zoals", μπορώ → can gave
// "blik", a tin): from X's verb label (overg, onoverg, hulpww in Dutch - English; v, vt, vi in Greek - English; not a
// "v." usage note) on, after the headword and pronunciation; the whole entry when it has none.
func verbPart(_ t: String, _ p: Pack) -> String {
    guard let labels = p.verbLabels, !labels.isEmpty, let pron = t.range(of: #"\|[^|]*\|"#, options: .regularExpression),
          let v = t[pron.upperBound...].range(of: #"\s("# + labels.joined(separator: "|") + #")(?=\s|\d|\[)"#, options: .regularExpression)
    else { return t }
    return String(t[..<pron.upperBound]) + String(t[v.lowerBound...])
}

// Whether a word is a verb: by its pack's endings, or by its entry's label.
func isVerb(_ word: String, _ p: Pack, _ entry: String?) -> Bool {
    guard let v = p.verb else { return false }
    if let endings = v.endings { return endings.contains { word.lowercased().hasSuffix($0) } }
    guard let pattern = v.entryPattern, let entry else { return false }
    return matches(v.prefix.map { String(entry.prefix($0)) } ?? entry, pattern)
}

// The word's translation through its English meaning: the first of its English words ("to run" → run) that the
// target's X - English dictionary has as an English headword of its own (it answers "companionable" with companion's).
func via(_ english: String, in p: Pack, verb: Bool = false) -> String {
    for item in english.split(separator: ",").prefix(3) {
        let w = replacing(String(item), #"^\s*(to|a|an|the)\s+"#, "").trimmingCharacters(in: .whitespaces)
        guard let t = define(w, in: p.bilingual), englishSide(t), t.lowercased().hasPrefix(w.lowercased()) else { continue }
        let g = gloss(verb ? verbPart(t, p) : t, target: p)
        if !g.isEmpty { return g }
    }
    return ""
}

// --- base forms, for languages whose dictionaries do not lemmatise ------------------------------------------------

// accents and case dropped, and final ς as σ (case folding makes it σ anyway, so endings compare the same way)
func fold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "el")).replacingOccurrences(of: "ς", with: "σ")
}
func spelled(_ s: String) -> String { s.hasSuffix("σ") ? String(s.dropLast()) + "ς" : s }  // a folded word as a headword is written
func headword(_ entry: String) -> String {  // μεταφέρ[ν]ω; φοβούμαι, (a comma before a variant)
    replacing(String(entry.prefix { !$0.isWhitespace }), #"\[[^\]]*\]"#, "").trimmingCharacters(in: .punctuationCharacters)
}

// A pack's lemma list (form ⇥ lemma, e.g. simplemma's), read once, on first use.
var lemmaLists: [String: [String: String]] = [:]
func lemma(_ word: String, _ p: Pack) -> String? {
    guard let file = p.lemmas else { return nil }
    if lemmaLists[p.code] == nil {
        var list: [String: String] = [:]
        let url = p.dir.appendingPathComponent(file)
        let raw = file.hasSuffix(".xz") ? (try? (NSData(contentsOf: url) as NSData?)?.decompressed(using: .lzma)) as Data?
                                          : try? Data(contentsOf: url)
        if let raw, let text = String(data: raw, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let cols = line.split(separator: "\t", maxSplits: 1)
                if cols.count == 2 { list[fold(String(cols[0]))] = String(cols[1]) }
            }
        } else { log("no \(url.path)") }
        lemmaLists[p.code] = list
    }
    return lemmaLists[p.code]?[fold(word)]
}

// The headword a pack's dictionaries list for a word: one spelled exactly so (accents kept) first, then one equal
// without accents. The dictionaries ignore accents, so Greek παιδί alone can answer with παΐδι (rib).
func listed(_ word: String, _ p: Pack) -> String? {
    let exact = { (s: String) in s.lowercased().replacingOccurrences(of: "ς", with: "σ") }
    var loose: String?
    for dict in [p.bilingual, p.monolingual] {
        guard let t = define(word, in: dict) else { continue }
        if exact(headword(t)) == exact(word) { return headword(t) }
        if loose == nil, fold(headword(t)) == fold(word) { loose = headword(t) }
    }
    return loose
}

// The dictionary's headword for an inflected form: its lemma when a dictionary lists it, else the first base form its
// pack's hooks point to that a dictionary lists exactly.
func deeperBase(_ word: String, _ p: Pack) -> String? {
    if let l = lemma(word, p), let h = listed(l, p) { return h }
    for b in (p.hooks?.baseForms(word) ?? []).prefix(30) {
        for dict in [p.bilingual, p.monolingual] {
            if let t = define(b, in: dict), fold(headword(t)) == fold(b) { return headword(t) }
        }
    }
    return nil
}

// A word in a pack's own script, as its dictionaries list it: the lemma first, even when the form has a rarer entry
// of its own (Greek παιδιά gave "play", not children; καλή "right side"; νέες "news"), else its base form when a
// dictionary has that and not the form itself.
func baseForm(_ w: String, _ p: Pack) -> String {
    if let l = lemma(w, p), fold(l) != fold(w), let h = listed(l, p) { return h }
    let own = define(w, in: p.bilingual) ?? define(w, in: p.monolingual)
    if own.map({ fold(headword($0)) != fold(w) }) ?? true, let b = deeperBase(w, p) { return b }
    return w
}
