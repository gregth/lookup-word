// The dictionaries Look Up reads, offline: those enabled in Dictionary.app, by their short names ("English",
// "Dutch - English"). Listing them and their names takes two private calls (DCSCopyAvailableDictionaries,
// DCSDictionaryGetShortName), stable for years; the entry itself is the public DCSCopyTextDefinition, which also finds
// the headword of an inflected form (sessions → session, liep → lopen), though not of a Greek one.
import CoreServices
import Foundation

typealias AvailFn = @convention(c) () -> Unmanaged<CFSet>?
typealias NameFn = @convention(c) (AnyObject) -> Unmanaged<CFString>?
// Every dictionary in use, with its identifier and short name, in identifier order (the set has none).
let installedDictionaries: [(id: String, name: String, dictionary: AnyObject)] = {
    let h = dlopen(nil, RTLD_NOW)
    guard let a = dlsym(h, "DCSCopyAvailableDictionaries"), let n = dlsym(h, "DCSDictionaryGetShortName"),
          let i = dlsym(h, "DCSDictionaryGetIdentifier"),
          let set = unsafeBitCast(a, to: AvailFn.self)()?.takeRetainedValue() else { return [] }
    let name = unsafeBitCast(n, to: NameFn.self), id = unsafeBitCast(i, to: NameFn.self)
    return ((set as NSSet).allObjects as [AnyObject]).compactMap { d in
        guard let s = name(d)?.takeUnretainedValue() as String?, let k = id(d)?.takeUnretainedValue() as String? else { return nil }
        return (k, s, d)
    }.sorted { $0.id < $1.id }
}()
// By short name. Two can share one (the Oxford Dictionary of English and the New Oxford American Dictionary are both
// "English"): the one a pack names in its dictionaryIds wins, else the first by identifier, so every run reads the same.
let dictionaries: [String: AnyObject] = {
    let wanted = Set(packs.flatMap { $0.dictionaryIds ?? [] })
    var out: [String: AnyObject] = [:], chosen = Set<String>()
    for d in installedDictionaries where !chosen.contains(d.name) && (out[d.name] == nil || wanted.contains(d.id)) {
        out[d.name] = d.dictionary
        if wanted.contains(d.id) { chosen.insert(d.name) }
    }
    return out
}()

func define(_ word: String, in name: String?, follow: Bool = true) -> String? {
    guard !word.isEmpty, let name, let d = dictionaries[name] else { return nil }
    let s = word as NSString
    let t = DCSCopyTextDefinition(unsafeBitCast(d, to: DCSDictionary.self), s, CFRange(location: 0, length: s.length))?
        .takeRetainedValue() as String?
    guard follow, let t else { return t }
    // an entry that only points elsewhere ("ρωτώ ▶ → ΕΡΩΤΩ", "πάω vi ▶ → πηγαίνω", "größer ▶ groß",
    // "estoy ▶ see estar 1", "children ▶ plural of child"): the entry it points to, once
    if t.count < 80, let target = group(t, #"▶\s*(?:→|see|ver|(?:plural|past tense|past participle) of)?\s*([^\s,.;\d]+)"#) {
        return pointed(target.lowercased(), from: t, in: name) ?? t
    }
    // an inflected form's stub that names its verb ("ging | ɡɪŋ | 1.u. 3. Pers.Sg.Prät. v. gehen", "gemacht A
    // 2. Part. v. machen B adjective"): that verb's entry
    if let target = stubVerb(t) { return pointed(target, from: t, in: name) ?? t }
    return t
}

// the verb an inflected form's stub names, with its homograph number ("will | vɪl | 1.u. 3. Pers.Sg.Präsens v.
// wollen2": wollen2, the modal verb, not wollen1, woollen)
func stubVerb(_ t: String) -> String? {
    group(String(t.prefix(100)), #"\b(?:Pers|Part)\.[^▸]{0,40}?\bv\.\s+(\p{L}+\d*)(?:\s+B\s|\s*$)"#)
}

// The entry a pointer leads to. A pointer from the other language's word leads to that language's word, which an
// English one can hide: "fue ▶ ir" finds Ir (iridium) before ir (to go).
func pointed(_ target: String, from t: String, in name: String) -> String? {
    if let n = group(target, #"(\d+)$"#) {
        let stem = replacing(target, #"\d+$"#, "")
        let pattern = "^" + NSRegularExpression.escapedPattern(for: stem) + #" ?(\d+)(?=[\s,|])"#
        if let r = records(stem, in: name).first(where: { group($0, pattern) == n }) { return r }
        return pointed(stem, from: t, in: name)
    }
    let f = define(target, in: name, follow: false)
    guard let f, englishSide(f, in: name), !englishSide(t, in: name) else { return f }
    return records(target, in: name).first { !englishSide($0, in: name) && $0.lowercased().hasPrefix(target) } ?? f
}

// the first capture group of a pattern's first match
func group(_ s: String, _ pattern: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}

func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
func replacing(_ s: String, _ pattern: String, _ with: String) -> String {
    s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
}

// A bilingual dictionary's English headwords carry a pronunciation (| rʌn |); in Dutch - English and Greek - English
// its other language's do not. Oxford's French, German and Spanish ones mark the English pronunciation (| BrE haʊs,
// AmE haʊs |), and French and German give their own headwords one too (maison | mɛzɔ̃ |): in a dictionary whose
// "house" carries the mark, only the mark tells an English headword.
// Only the packs' X - English dictionaries are asked (never every installed one: Wikipedia's may go online).
let marksBrE: [String: Bool] = packs.compactMap(\.bilingual).filter { dictionaries[$0] != nil }.reduce(into: [:]) { out, name in
    out[name] = define("house", in: name, follow: false).map { matches($0, #"^[^|\n]{1,60}\| [^|]*\b(BrE|AmE)\b"#) } ?? false
}
func englishSide(_ t: String?, in dictionary: String?) -> Bool {
    guard let t else { return false }
    return matches(t, marksBrE[dictionary ?? ""] == true ? #"^[^|\n]{1,60}\| [^|]*\b(BrE|AmE)\b"# : #"^[^|\n]{1,60}\| [^|]+ \|"#)
}

var wanted: String?  // the word being looked up, for gloss's derivatives

// whether an entry's text, past its headword and pronunciation, opens with a noun label (znw, n, An, noun, masculine…)
func opensAsNoun(_ text: String) -> Bool {
    var t = text
    if let pron = t.range(of: #"\|[^|]*\|"#, options: .regularExpression), t.distance(from: t.startIndex, to: pron.lowerBound) < 60 {
        t = String(t[pron.upperBound...])
    } else { t = String(t.drop { !$0.isWhitespace }) }  // no pronunciation (Dutch headwords): past the headword
    let first = t.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
        .first { !$0.isEmpty && !($0.count == 1 && "ABCD".contains($0)) } ?? ""
    return nounLabels.contains(first) || nounLabels.contains(replacing(first, #"^[A-D](?=nn?$)"#, ""))
}
// whether an entry opens as an adjective or adverb (bn, bw, adj, adv, adjective, adverb)
func opensAsDescribing(_ text: String) -> Bool {
    var t = text
    if let pron = t.range(of: #"\|[^|]*\|"#, options: .regularExpression), t.distance(from: t.startIndex, to: pron.lowerBound) < 60 {
        t = String(t[pron.upperBound...])
    } else { t = String(t.drop { !$0.isWhitespace }) }  // no pronunciation (Dutch headwords): past the headword
    let first = t.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
        .first { !$0.isEmpty && !($0.count == 1 && "ABCD".contains($0)) } ?? ""
    return ["bn", "bw", "adj", "adv", "adjective", "adverb"].contains(replacing(first, #"^[A-D](?=adj$|adv$)"#, ""))
}
// whether a stretch of an entry holds a word that is not a label or a section letter: a translation
func hasTranslation(_ text: String, _ rules: GlossRuleSet) -> Bool {
    text.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }.contains { w in
        w.contains(where: \.isLetter) && !rules.labels.contains(w) && !nounLabels.contains(w) && !(w.count <= 2 && w.first?.isUppercase == true)
    }
}
// the labels a bilingual entry's noun part opens with: on the English side Dutch znw, Greek n or An, the Oxford ones'
// "noun"; on the other side a gender (Dutch "boek o", "m", "v"; Greek το, η, ο; the Oxford ones' masculine, feminine)
let nounLabels: Set = ["znw", "n", "nn", "noun", "masculine", "feminine", "neuter", "nm", "nf", "C", "U",
                       "o", "m", "v", "m/v", "το", "η", "ο", "ο/η"]
// The first sense of an entry as a short phrase: past the headword and pronunciation, before the first example (▸),
// sub-sense (•), sense 2 or section, without labels in <>, () or [], or grammar (the packs' labels). A list (a
// translation) keeps three items and stops at the first full stop; a meaning keeps the sense and stops at its colon.
// `target` is the language the phrase is in, when it is a translation into a language with its own script: words
// before its first word in that script go.
// `from` is the pack whose dictionary the entry comes from (nil: English's own), for its rules. `noun`: the word is a
// noun, so an entry that opens with its noun part keeps that part rather than jump to a later numbered one.
func gloss(_ entry: String?, list: Bool = true, target: Pack? = nil, from: Pack? = nil, noun: Bool = false) -> String {
    guard var s = entry else { return "" }
    let rules = glossRules(from ?? target)
    // an entry for another headword ("alignment" finds align): the word's own line under DERIVATIVES, when it has one
    if let word = wanted, !s.lowercased().hasPrefix(word.lowercased()),
       let r = s.range(of: #"(?<=\s)"# + NSRegularExpression.escapedPattern(for: word) + #"\s+(n|nn|adj|adv|v|vt|vi|znw|bn|bw|ww)\b"#,
                       options: [.regularExpression, .caseInsensitive]) {
        s = String(s[r.lowerBound...])
    }
    for (pattern, with) in rules.variants { s = replacing(s, pattern, with) }  // "αδελφός, καίαδερφός Anm …": the variant goes
    // past the pronunciations: the last one near the top, since an irregular word lists its forms first, each with its
    // own (say | seɪ | … says | sez | … said | sed | λέγω) — a chain: from the first, on to the next only while it
    // follows within 40 characters (not a derivative's, further on)
    let prons = s.ranges(of: #/\|[^|]*\|/#)
    if var last = prons.first {
        for r in prons.dropFirst() where s.distance(from: last.upperBound, to: r.lowerBound) <= 40 { last = r }
        s = String(s[last.upperBound...])
    } else { s = String(s.drop { !$0.isWhitespace }) }
    // a usage note in sentences before the part of speech (French - English we: "In standard French, we is translated
    // by nous but … see this entry. pronoun nous;", few: "When few is used as an adjective …"): the entry starts after it,
    // when a translation follows before its first example (they: "pronoun ▸ they have …" has none, so the note stays)
    let pos = #"(?:[A-D] )?(?:(?:masculine|feminine|transitive|intransitive|auxiliary|modal|plural) )?(?:pronoun|noun|adjective|adverb|verb|determiner|preposition|conjunction|exclamation|article|quantifier)\b"#
    if from ?? target != nil, let r = s.range(of: #"^\s*\p{Lu}[^▸]{20,}?[.!]\s*(?="# + pos + ")", options: .regularExpression),
       matches(String(s[r.upperBound...].prefix { $0 != "▸" }), "^" + pos + #"[^\p{L}]*\p{L}"#) {
        s = " " + s[r.upperBound...]
    }
    // grammar notes before sense 1 (μεταφέρ[ν]ω vt μετέφερα αόρ., … 1carry): the meaning starts at the 1; but not for a
    // noun whose entry opens with its noun part, unnumbered, as then the 1 opens a later part of speech (tree: "znw
    // boom ▸ … overg 1 in een boom jagen", book: "An C βιβλίο ▸ … Bvt 1εγγράφω")
    // (only when that noun part holds a translation before its first example: "small | A noun ▸ the small of the back"
    // holds none, so its adjective's 1 is the translation)
    let opensWithNoun = noun && opensAsNoun(s) && hasTranslation(String(s.prefix { $0 != "▸" }), rules)
    // (a 1 right after "~" counts too: Greek - English run2 "pp ~1τρέχω")
    if let r = s.range(of: #"(?<=[\s.~])1(?=\s?[\p{L}\[(<])"#, options: .regularExpression), s.distance(from: s.startIndex, to: r.lowerBound) < 200,
       !(opensWithNoun && s[..<r.lowerBound].contains("▸")) {
        s = String(s[r.upperBound...])
    } else if !rules.notes.isEmpty,
              let r = s.prefix(240).range(of: #"(?s).*\b("# + rules.notes.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")\."#, options: .regularExpression) {
        s = String(s[r.upperBound...])  // no sense numbers: the meaning starts after the last grammar note (πήγα αόρ., … μτχ. παρακ.)
    }
    // a suffix variant in brackets (gelijk(-heid)), a ~ grammar note (γάλα "~ τος gen"), then a bracketed label
    // between two translations ("potato (sl) spud")
    if let r = s.range(of: #"^\s*\([^)]*\.\)[^▸]*?▸?.*?\s2(?=\s?[\p{L}\[(<])"#, options: .regularExpression) {
        s = String(s[r.upperBound...])  // (γραμμ.) noun … 2name → name: a field-labelled first sense gives way to sense 2
    }
    s = replacing(s, #"\(\s*[-~][^)]*\)"#, "")
    s = replacing(s, #"~\s?\S*(\s+gen\b)?"#, " ")
    if !list { s = replacing(s, #"\((some(?:thing|one|body|where))\)"#, "$1") }  // "transfer the possession of (something) to (someone)"
    s = replacing(s, #"\([^)]*\)"#, list ? ", " : " ")
    for cut in rules.cuts + (list ? [] : [":"]) {
        if let r = s.range(of: cut) { s = String(s[..<r.lowerBound]) }
    }
    // the next sense, wherever its number stands ("calculating machine 2", "hangen 2, helling 3")
    if let r = s.range(of: #"\s\d{1,2}(?=\s|$|,|[\p{L}\[<])"#, options: .regularExpression) { s = String(s[..<r.lowerBound]) }
    // an optional part in brackets that opens a word goes, the word keeping its capital ("[Groß]stadt": Stadt)
    s = s.replacing(#/\[\p{Lu}[^\]\s]*\](\p{Ll})/#) { $0.output.1.uppercased() }
    s = replacing(s, #"<[^>]*>|\[[^\]]*\]|\bv\. \S+( &)?"#, " ")
    if list, let r = s.range(of: ". ") { s = String(s[..<r.lowerBound]) }
    var words = s.split(separator: " ").map(String.init)
    // a label, also with its section letter glued on (A + nm = "Anm", A + vt = "Avt")
    let label = { (w: String) in let x = w.trimmingCharacters(in: .punctuationCharacters); return rules.labels.contains(x) || rules.labels.contains(w) || (x.count > 1 && "ABCD".contains(x.first!) && rules.labels.contains(String(x.dropFirst()))) }
    while let f = words.first, label(f) || f.allSatisfy(\.isNumber) {
        words.removeFirst()
    }
    // labels inside a list too ("IRS znw belastingdienst", "ook:", "aux verb be")
    words = words.filter { !rules.inner.contains($0.trimmingCharacters(in: .punctuationCharacters)) }
    if let script = target?.script {
        let own = #"\p{"# + script + "}"
        if let i = words.firstIndex(where: { matches($0, own) }) { words.removeFirst(i) }  // "U έλλειψη", "A ) vi …"
        if let i = words.lastIndex(where: { $0.hasSuffix(")") }), i < words.count - 1 { words.removeFirst(i + 1) }  // "… υπερσυντέλικου) έχω"
    }
    s = replacing(replacing(words.joined(separator: " "), #"\s*&\s*(?=,|$)"#, ""), #"^\d+"#, "").trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ".,;:)")))  // (") an adult": a plural's pronunciation, "(plural women | ˈwɪmɪn |)")
    guard list else { return s }
    var seen = Set<String>()  // an item once ("lopen, lopen, rennen" from two senses)
    // not a sub-sense's letter ("fácil acceso, b, he prides …"), nor an example the dictionary gave no ▸ ("1
    // (reachability) the easy accessibility of the beach der leichte Zugang zum Strand"): three words or more with the
    // word itself in them (a single "hotel" in Dutch is the translation)
    let word = (wanted ?? "").lowercased()
    func example(_ item: String) -> Bool {
        let words = item.lowercased().split(separator: " ")
        return !word.isEmpty && words.count >= 3 && words.contains { $0.trimmingCharacters(in: .punctuationCharacters) == word }
    }
    // (one that starts with the word itself, run into its examples, keeps the word: Dutch winter "winter in de
    // winter stallen overwinteren")
    // an item without a label after it ("bouquin informal", "Fahrrad attrib"), its sub-sense letter or a stray mark
    // ("κεφάλι a", "mooi >"); an item that is only a label ("US", "in comb") goes. Not in English, where "formal" can be
    // the translation
    func unlabelled(_ item: String) -> String {
        var i = item
        for l in target.map({ $0.isEnglish ? [] : rules.trailing }) ?? [] where i == l || i.hasSuffix(" " + l) { i = String(i.dropLast(l.count)).trimmingCharacters(in: .whitespaces) }
        // (a sub-sense letter only after a word in the target's own script: Spanish "preguntarle a" keeps its a)
        let mark = target?.script == nil ? #"[^\p{L}\d\s]+"# : #"(?:[a-d]|[^\p{L}\d\s]+)"#
        return replacing(i, #"(?<=\p{L})\s+"# + mark + "$", "")
    }
    return s.split(separator: ",").map { unlabelled($0.trimmingCharacters(in: .whitespaces)) }
        .map { example($0) && $0.lowercased().hasPrefix(word + " ") ? String($0.prefix(word.count)) : $0 }
        .filter { $0.filter(\.isLetter).count > 1 && !example($0) && !repeated($0, seen) && seen.insert($0.lowercased()).inserted }.prefix(3)
        .joined(separator: ", ")
}

// An item that is an earlier one with an article or particle before it ("Mensch, der Mensch", "Frau · die Frau")
func repeated(_ item: String, _ seen: Set<String>) -> Bool {
    let w = item.lowercased().split(separator: " ")
    return w.count == 2 && w[0].count <= 3 && seen.contains(String(w[1]))
}

// Whether a word is the looked-up word or a regular English form of it (want: wanted, wants, wanting)
func ownForm(_ w: String, _ word: String) -> Bool {
    guard !word.isEmpty, w.hasPrefix(word) || (word.hasSuffix("e") && w.hasPrefix(word.dropLast())) else { return false }
    let base = w.hasPrefix(word) ? word : String(word.dropLast())
    return ["", "s", "es", "d", "ed", "ing"].contains(String(w.dropFirst(base.count)))
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
// `intransitive`: the verb's first sense takes no object (Oxford's "[no object]"), so the pack's intransitive part
// comes first where it has one (run: Dutch "onoverg … rennen, lopen", not "overg … laten lopen").
func verbPart(_ t: String, _ p: Pack, intransitive: Bool = false) -> String {
    guard let labels = p.verbLabels, !labels.isEmpty, let pron = t.range(of: #"\|[^|]*\|"#, options: .regularExpression) else { return t }
    let rest = t[pron.upperBound...]
    var preferred: Range<Substring.Index>?
    if intransitive, let own = p.intransitiveLabels, !own.isEmpty { preferred = verbLabel(rest, own) }
    guard let v = preferred ?? verbLabel(rest, labels) else { return t }
    return String(t[..<pron.upperBound]) + String(t[v.lowerBound...])
}

// where one of the labels opens a verb section, past the pronunciation (a section letter may lead it: "Bvt 1εγγράφω")
func verbLabel(_ rest: Substring, _ labels: [String]) -> Range<Substring.Index>? {
    rest.range(of: #"\s[A-D]?("# + labels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")(?=\s|\d|\[)"#, options: .regularExpression)
}

// Oxford's first part of speech in an English entry ("why | wʌɪ | interrogative adverb …": adverb).
func firstPart(_ en: String?) -> String? {
    guard let en, let pron = en.range(of: #"\|[^|]*\|"#, options: .regularExpression) else { return nil }
    let head = String(en[pron.upperBound...].prefix(40))
    return head.range(of: #"\b(noun|adjective|adverb|pronoun|conjunction|preposition|exclamation)\b"#, options: .regularExpression).map { String(head[$0]) }
}

// The part of an English entry in an X - English dictionary for the word's first part of speech in Oxford (why: Dutch
// "tsw 1 wel!, wel verdraaid! … bijw waarom", an adverb, so from bijw on), after the headword and pronunciation; the
// whole entry when the pack maps no labels for that part, the entry has none, or it opens with one (before its
// pronunciation too: "bow znw | bəʊ | 1 boog … znw | baʊ | 1 buiging").
func mainPart(_ t: String, _ p: Pack, _ pos: String?) -> String {
    guard let pos, let labels = p.partLabels?[pos], !labels.isEmpty,
          let pron = t.range(of: #"\|[^|]*\|"#, options: .regularExpression) else { return t }
    let rest = t[pron.upperBound...]
    let alts = labels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|"), own = "(" + alts + ")"
    if matches(String(t[..<pron.lowerBound]), #"\s"# + own + #"\s*$"#) || matches(String(rest), #"^\s*[A-D]?"# + own + #"(?=\s|\d|\[)"#) { return t }
    guard let v = rest.range(of: #"\s[A-D]?"# + own + #"(?=\s|\d|\[)"#, options: .regularExpression) else { return t }
    return String(t[..<pron.upperBound]) + String(t[v.lowerBound...])
}

// A verb's entry for an English word in an X - English dictionary. Greek - English keeps the noun and the verb of
// "run" as two entries (run1 n…, run2 vti…), and a lookup returns only the first: so the word's entry that opens with
// a verb label first, else the verb part of the first entry. `strict`: no entry opening as a verb and the first a
// numbered homograph opening as a noun gives "" (kunnen's can: "can 1 … noun" has a verb section, but it is to can food).
func verbEntry(_ t: String, _ word: String, _ p: Pack, intransitive: Bool = false, strict: Bool = false) -> String {
    let labels = p.verbLabels ?? []
    func opensAsVerb(_ r: String) -> Bool {
        guard let pron = r.range(of: #"\|[^|]*\|"#, options: .regularExpression) else { return false }
        // (past a section letter: German - English "rush 2 | … | A intransitive verb", Greek "Bvt")
        let rest = replacing(String(r[pron.upperBound...].prefix(40)), #"^\s*(?:[A-D] |[A-D](?=\p{Ll}))?"#, "")
        return labels.contains { rest.hasPrefix($0) && !matches(String(rest.dropFirst($0.count).prefix(1)), #"\p{L}"#) }
    }
    if !opensAsVerb(t), let r = records(word, in: p.bilingual).first(where: {
        $0 != t && englishSide($0, in: p.bilingual) && $0.lowercased().hasPrefix(word.lowercased()) && opensAsVerb($0)
    }) { return verbPart(r, p, intransitive: intransitive) }
    if strict, !opensAsVerb(t), opensAsNoun(t), matches(t, #"^[\p{L}'-]+ ?\d+(?=[\s,|])"#) { return "" }
    return verbPart(t, p, intransitive: intransitive)
}

// Oxford's first verb sense takes no object: "[no object]" before any "[with object]"
func firstSenseIntransitive(_ en: String?) -> Bool {
    guard let e = en, let no = e.range(of: "[no object]") else { return false }
    return e.range(of: "[with object]").map { no.lowerBound < $0.lowerBound } ?? true
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
// `describing`: the source word is an adjective or adverb, so an English item whose entry opens as a noun is tried last
// (gentil: "kind, nice"; kind's German entry opens with the noun Art, nice's gives nett).
func via(_ english: String, in p: Pack, verb: Bool = false, noun: Bool = false, describing: Bool = false) -> String {
    var later: [(String, String)] = []
    for item in english.split(separator: ",").prefix(3) {
        let w = replacing(String(item), #"^\s*(to|a|an|the)\s+"#, "").trimmingCharacters(in: .whitespaces)
        guard let t = define(w, in: p.bilingual), englishSide(t, in: p.bilingual), t.lowercased().hasPrefix(w.lowercased()) else { continue }
        // (only an entry with no adjective part at all: "mild | A noun … B adjective 1 léger" has one)
        if describing, !verb, opensAsNoun(t), !matches(t, #"\s[A-D]?(adjective|adj|bn|adverb|adv|bw)\b"#) { later.append((w, t)); continue }
        let en = define(w, in: pack("en")?.monolingual)
        // (a verb's intransitive part when its English takes no object first: τρέχω's run, Dutch lopen, not laten lopen)
        let part = verb ? verbEntry(t, w, p, intransitive: firstSenseIntransitive(en), strict: true) : mainPart(t, p, firstPart(en))
        // (for a verb, not an entry with no verb part: τρέχω's rush, German "rush 1 … noun (Botany) Binse")
        if verb, let labels = p.verbLabels, !labels.isEmpty,
           part.range(of: #"\|[^|]*\|"#, options: .regularExpression).map({ verbLabel(part[$0.upperBound...], labels) == nil }) ?? true { continue }
        let g = gloss(part, target: p, from: p, noun: noun)
        if !g.isEmpty { return g }
    }
    for (_, t) in later {
        let g = gloss(t, target: p, from: p, noun: noun)
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

// Every entry a dictionary has for the word, as text: DCSCopyTextDefinition returns one, and in French - English
// the English "pain" hides the French "pain" (bread). Private, like the listing: DCSCopyRecordsForSearchString and
// DCSRecordCopyData, whose version 3 is the same plain text.
typealias RecordsFn = @convention(c) (AnyObject, CFString, CFIndex, CFIndex) -> Unmanaged<CFArray>?
typealias RecordTextFn = @convention(c) (AnyObject, CFIndex) -> Unmanaged<CFString>?
func records(_ word: String, in name: String?) -> [String] {
    let h = dlopen(nil, RTLD_NOW)
    guard let name, let d = dictionaries[name], let r = dlsym(h, "DCSCopyRecordsForSearchString"), let c = dlsym(h, "DCSRecordCopyData"),
          let recs = unsafeBitCast(r, to: RecordsFn.self)(d, word as CFString, 0, 0)?.takeRetainedValue() as? [AnyObject] else { return [] }
    return recs.compactMap { unsafeBitCast(c, to: RecordTextFn.self)($0, 3)?.takeRetainedValue() as String? }
}

// X's own entry in its X - English dictionary for the word: the one DCSCopyTextDefinition gives when it is X's, else
// X's among all the word's records (its own headword first: "court" is short, not courir's form). An entry whose first
// section only points elsewhere ("blanche A adjective ▶ blanc A B feminine noun …", "vu A past participle vue ▶ voir
// B adjective …"): the entry it points to.
func ownEntry(_ word: String, _ t: String?, _ p: Pack) -> String? {
    guard let t, let bilingual = p.bilingual else { return nil }
    var own: String? = t
    if englishSide(t, in: bilingual) {
        // an English word's numbered homographs are all English, though only the first carries the pronunciation
        // ("will 1 | BrE wɪl |", "will 2 A noun … Wille")
        let all = records(word, in: bilingual)
        let numbered = #"^([\p{L}'-]+) ?\d+(?=[\s,|])"#
        let english = Set(all.filter { englishSide($0, in: bilingual) }.compactMap { group($0, numbered) })
        let xs = all.filter { !englishSide($0, in: bilingual) && !english.contains(group($0, numbered) ?? "") }
        own = xs.first { matches($0.lowercased(), "^" + NSRegularExpression.escapedPattern(for: word.lowercased()) + #"\b"#) } ?? xs.first
        // an inflected form's stub among them ("war | vaːɐ̯ | 1.u. 3. Pers.Sg.Prät. v. sein1"): the verb's entry
        if let e = own, let target = stubVerb(e) { own = pointed(target, from: e, in: bilingual) ?? e }
    }
    // numbered homographs, the first not always the word's main use: a verb before the rest ("vivir 1 masculine noun
    // life", "vivir 2 A intransitive verb to be alive"), and past a first one the dictionary marks informal or
    // regional ("perro 1 adjective (perra) 1 (informal) rotten", "gente 1 adjective (Latin America) respectable");
    // otherwise the dictionary's order (bonito 1 pretty before bonito 2 tuna, Greek's ιθαγενής1 first)
    if let e = own, let stem = group(e, #"^([\p{L}'-]+) ?\d+(?=[\s,])"#) {
        let same = records(stem, in: bilingual).filter {
            !englishSide($0, in: bilingual) && group($0, #"^([\p{L}'-]+) ?\d+(?=[\s,])"#) == stem
        }
        func marked(_ r: String) -> Bool {
            let label = #"(?:informal|colloquial|slang|vulgar|dated|Latin America|[A-Z][a-z]+ America|Spain|Mexico|Chile|Argentina|Andes|River Plate|Caribbean)"#
            return matches(String(r.prefix(70)), #"\("# + label + #"(?:, "# + label + #")*\)"#)
        }
        if !isVerb(stem, p, e), let v = same.first(where: { isVerb(stem, p, $0) }) { own = v }
        else if marked(e), let u = same.first(where: { $0 != e && !marked($0) }) { own = u }
    }
    if let e = own, let target = group(String(e.prefix(120)), #"^[^|▶]{1,40}(?:\|[^|]*\|)?\s*(?:A )?(?:(?:masculine|feminine) )?(?:plural )?(?:adjective|past participle|noun)(?: \p{L}+)?(?: \|[^|]*\|)? ▶ ([\p{L}œ'-]+)"#),
       let f = define(target, in: bilingual), !englishSide(f, in: bilingual) {
        return f
    }
    return own
}

// The word's first senses for the card's top row, not the first alone, as a dictionary may put the main one second
// (a word with several translations would otherwise show only one): sense 1 as
// gloss gives it, then the first item of senses 2 and 3 of the same part of speech, and of the word's other numbered
// entries (`others`: Oxford's bank 1, the river's, and bank 2, the money's). A later item counts only when it is a
// translation, not an example or the word's forms: three words at most, no digits, not the word itself, and in the
// target's script when it has one.
func senses(_ entry: String?, target: Pack? = nil, from: Pack? = nil, noun: Bool = false, others: [String] = []) -> [String] {
    let first = gloss(entry, target: target, from: from, noun: noun)
    guard let e = entry else { return [] }
    var out = first.isEmpty ? [] : [first]  // (none: sense 1 was all example, and sense 2 leads)
    var seen = Set(first.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    let word = (wanted ?? "").lowercased()
    func add(_ g: String) {
        guard out.count < 3, let item = g.split(separator: ",").first.map({ $0.trimmingCharacters(in: .whitespaces) }), !item.isEmpty,
              item.split(separator: " ").count <= 3, !item.contains(where: { $0.isNumber || $0 == "/" }),  // (an example's "tierra/nieve")
              word.isEmpty || !item.lowercased().split(separator: " ").contains(Substring(word)),
              !item.contains("≈"), !repeated(item, seen),  // (not an approximate equivalent: city "(US) ≈ Stadtgemeinde")
              target?.script.map({ matches(item, #"\p{"# + $0 + "}") }) ?? true,
              target.map({ t in t.isEnglish || t.script != nil || define(item, in: t.monolingual) != nil || define(item, in: english.monolingual) == nil }) ?? true,
              // (English from another language's dictionary: an English word, not a hint left in that language, huis "geslacht")
              target != nil || from == nil || (define(String(item.split(separator: " ")[0]), in: english.monolingual) != nil &&
                                               define(item, in: from?.monolingual) == nil),  // (nor one the other language has too: waarom "om")
              seen.insert(item.lowercased()).inserted else { return }
        out.append(item)
    }
    // the other numbered entries first, each usually a meaning of its own (the money's bank 2 before the river's
    // bank 1 sense 2)
    // (another part of speech's entry adds nothing to a noun's row: bank 3, the verb, peraltar)
    let verbish = #"^[^▸]{0,80}?\b(?:verb|vt|vi|ww|overg|onoverg)\b"#
    for o in others where matches(e, verbish) == matches(o, verbish) { add(gloss(o, target: target, from: from, noun: noun)) }
    let number = { (n: Int) in #"(?<=[\s.~;])"# + String(n) + #"(?=\s?[\p{L}\[(<])"# }
    // (a new part of speech ends the senses: "A noun 1 … B transitive verb 1 …", Greek's "Bvt 1…")
    let part = #"\s[B-D](?:\s|(?=vt|vi|v\b|n\b|adj|adv))"#
    if let one = e.range(of: number(1), options: .regularExpression), e.distance(from: e.startIndex, to: one.lowerBound) < 200 {
        let head = String(e[..<one.lowerBound])
        var after = one.upperBound
        for n in 2...3 {
            guard let r = e[after...].range(of: number(n), options: .regularExpression),
                  !matches(String(e[after..<r.lowerBound]), part) else { break }
            after = r.upperBound
            let rest = e[r.upperBound...].drop { $0.isWhitespace }
            if matches(String(rest.prefix(12)), #"^[<(](?:vulg|vulgar|sl|slang)\b"#) { continue }  // not head's "3 <vulg> orale seks"
            // nor a sense that opens with the word itself, a phrase or an example the dictionary gave no ▸ (want:
            // "3 wanted [by the police] [polizeilich] gesucht", man: "3 a (representative, employee) our man in Cairo …")
            let opening = replacing(replacing(String(rest.prefix(120).prefix { $0 != "▸" }), #"\([^)]*\)|\[[^\]]*\]|<[^>]*>|‹[^›]*›"#, " "), #"^\s*[a-d]\s"#, "")
            if opening.split(separator: " ").prefix(3).contains(where: { ownForm($0.lowercased().trimmingCharacters(in: .punctuationCharacters), word) }) { continue }
            add(gloss(head + "1 " + rest, target: target, from: from, noun: noun))
        }
    }
    return out
}

// The English senses (" · " between them) into another language, one by one, each sense's first words through via
func viaSenses(_ english: String, in p: Pack, verb: Bool = false, noun: Bool = false, describing: Bool = false) -> String {
    var seen = Set<String>()
    // (after the first, its first item alone, when short and new to the row: not an example caught as a translation,
    // "she rushed after him corrió tras él", nor σπίτι again, nor what is left of "banco (de trabajo)" once banco is)
    return english.components(separatedBy: " · ").enumerated().map { i, sense in
        let items = via(sense, in: p, verb: verb, noun: noun, describing: describing).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let kept = i == 0 ? items : Array(items.prefix(1).filter { item in
            item.split(separator: " ").count <= 3 && !item.contains(where: { $0.isNumber || $0 == "." }) && !seen.contains(item.lowercased()) &&
            (p.script.map { matches(item, #"^[^\p{L}]*\p{"# + $0 + "}") } ?? (define(item, in: p.monolingual) != nil || define(item, in: pack("en")?.monolingual) == nil))
        })
        kept.forEach { seen.insert($0.lowercased()) }
        return kept.joined(separator: ", ")
    }.filter { !$0.isEmpty }.joined(separator: " · ")
}

// The entry from each verb section after the first, its head kept: for an English verb whose first one holds no
// translation (Dutch - English do: "hulpww … 1 <gebruikt om een vraag … te vormen>", then "overg … 1 doen")
func laterVerbParts(_ t: String, _ p: Pack) -> [String] {
    guard let labels = p.verbLabels, !labels.isEmpty, let pron = t.range(of: #"\|[^|]*\|"#, options: .regularExpression) else { return [] }
    let head = String(t[..<pron.upperBound]), rest = String(t[pron.upperBound...])
    let own = labels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    guard let re = try? Regex(#"\s[A-D]?("# + own + #")(?=\s|\d|\[)"#) else { return [] }
    let starts = rest.ranges(of: re).map(\.lowerBound)
    return starts.dropFirst().map { head + rest[$0...] }
}
