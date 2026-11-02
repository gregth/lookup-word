// A word's entry: its language, headword and pronunciation, the word in every other language in force, and each
// dictionary's text, as Look Up lists them.
import AppKit
import NaturalLanguage

struct Entry {
    var lang: String, word: String, ipa: String
    var tr: [(String, String)]  // the other languages: [(code, words)], English first
    var sections: [(String, String)]  // (dictionary, entry text)
    var meaning: String  // English's own definition for an English word; the English translation for any other
    func value(_ column: String) -> String {  // a vocabulary column: "meaning" or a language code
        column == "meaning" ? meaning : tr.first { $0.0 == column }?.1 ?? ""
    }
}

// The text's language among the packs', so a word two languages spell the same (want, die, ring) is looked up in
// the one being read. English when NaturalLanguage cannot tell.
func language(_ text: String) -> String {
    let known = packs.compactMap { p in p.recognizer.map { (p.code, NLLanguage(rawValue: $0)) } }
    let r = NLLanguageRecognizer()
    r.languageConstraints = known.map(\.1)
    r.processString(text)
    return known.first { $0.1 == r.dominantLanguage }?.0 ?? "en"
}

// A reading no dictionary has (underground read as "unaurground"): the spell checker's corrections in the text's
// language, offline, the first one a dictionary has.
func corrected(_ word: String, hint: String) -> Entry? {
    let lang = pack(hint)?.spellChecker ?? "en"
    let guesses = NSSpellChecker.shared.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                                                language: lang, inSpellDocumentWithTag: 0) ?? []
    for g in guesses.prefix(4) { if let e = entry(g, hint: hint) { log("  corrected to \(g)"); return e } }
    return nil
}

func lookUpEntry(_ raw: String, hint: String) -> Entry? {
    let w0 = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    for p in packs {  // a reading that is plainly one language's (Cyrillic look-alikes for Greek): only its candidates
        if let tries = p.hooks?.readingCandidates(w0) {
            for c in tries { if let e = entry(c, hint: hint) { return e } }
            return nil
        }
    }
    if let e = entry(w0, hint: hint) { return e }
    for p in packs {
        for c in p.hooks?.fallbackCandidates(w0, hint: hint) ?? [] { if let e = entry(c, hint: hint) { return e } }
    }
    // a Latin-script language whose dictionaries do not lemmatise: its lemma list
    for p in packs where p.script == nil && p.lemmas != nil {
        if let l = lemma(w0, p), fold(l) != fold(w0), let e = entry(l, hint: p.code) { return e }
    }
    return nil
}

func entry(_ raw: String, hint: String) -> Entry? {
    var w = raw
    let scripted = packs.first { $0.writes(w) }  // a word in a script only one pack writes is that language's
    if let p = scripted { w = baseForm(w, p) }  // an inflected form: its dictionary form
    wanted = w
    guard !w.isEmpty, w.count <= 60 else { return nil }
    let en = define(w, in: english.monolingual)
    var bil: [String: String] = [:], mono: [String: String] = [:], bilX: [String: String] = [:]
    for p in others {
        bil[p.code] = define(w, in: p.bilingual)
        // (a one-letter word: only its own entry, not one the letter is a symbol in, I's "iodine … jodium"; its own
        // may be capitalised or numbered, "Y | waɪ |", "I1, i")
        if w.count == 1, let t = bil[p.code], group(t, #"^([^\s|,\d]+)"#)?.lowercased() != w.lowercased() { bil[p.code] = nil }
        bilX[p.code] = ownEntry(w, bil[p.code], p)
        mono[p.code] = define(w, in: p.monolingual)
    }
    // a word of language X: its own dictionary has it, or X - English has it as an X headword (no pronunciation)
    func has(_ p: Pack) -> Bool { p.isEnglish ? en != nil : mono[p.code] != nil || bilX[p.code] != nil }
    let lang: Pack
    if let p = scripted {
        guard bil[p.code] != nil || mono[p.code] != nil else { return nil }
        lang = p
    } else {
        // the text's language first, then English, then the others in the settings' order
        // (a word in a language whose dictionaries are missing is English only as its own headword: Dutch huis is not
        // "hui", house is house)
        if let h = pack(hint), !h.isEnglish, [h.monolingual, h.bilingual].allSatisfy({ $0.map { dictionaries[$0] == nil } ?? true }),
           en.map({ fold(replacing(headword($0), #"\d+$"#, "")) != fold(w) }) ?? true { return nil }
        let latin = packs.filter { $0.script == nil }
        let order = latin.filter { $0.code == hint && !$0.isEnglish } + [english] + latin.filter { !$0.isEnglish && $0.code != hint }
        guard let p = order.first(where: has) else { return nil }
        lang = p
    }
    // its main entry: for a language with its own script, its X - English entry whatever it holds (a Greek letter's
    // entry carries a pronunciation, | κάπα |); for the others, that entry only when it is for the X word
    let ownBil = lang.script != nil ? bil[lang.code] : bilX[lang.code]
    guard let main = lang.isEnglish ? en : ownBil ?? mono[lang.code] ?? bil[lang.code] else { return nil }
    // the headword as the dictionary spells it ("sessions" finds session; "run1" is run)
    var word = matches(main.lowercased(), "^" + NSRegularExpression.escapedPattern(for: w.lowercased()) + #"\b"#)
        ? String(main.prefix(w.count)) : replacing(String(main.prefix { !$0.isWhitespace && $0 != "|" }), #"\d+$"#, "")
    word = replacing(word, #"\[[^\]]*\]"#, "").trimmingCharacters(in: .punctuationCharacters)  // μεταφέρ[ν]ω, φοβούμαι,
    if word.isEmpty { word = w }
    let ipa = main.range(of: #"\| ([^|]+) \|"#, options: .regularExpression).map {
        String(main[$0]).trimmingCharacters(in: .init(charactersIn: "| "))
    } ?? ""
    let title = { (name: String) in name.replacingOccurrences(of: " - ", with: " – ") }
    if lang.isEnglish {
        // an entry that only names its base ("seen | siːn | verb past participle of see1"): the base's
        if let base = en.flatMap({ group(String($0.prefix(120)), #"^[^|]+\|[^|]+\|\s*(?:verb |noun )?(?:past participle|past tense|plural) of (\p{L}+)"#) }),
           fold(base) != fold(w), let e = entry(base, hint: "en") { return e }
        // an irregular form's stub ("children … zie: child", "went ▶ go1 A, B", "▶ plural of child"): the headword's entry
        if fold(word) != fold(w) {
            for p in others where (bil[p.code]?.count ?? 0) < 120 { bil[p.code] = define(word, in: p.bilingual) ?? bil[p.code] }
        }
        // each other language from its X - English entry for the English word (its verb part, for a verb)
        let verb = isVerb(w, english, en)
        let noun = en.map { matches($0, #"^[^|]+\|[^|]+\|\s*noun\b"#) } ?? false  // Oxford's first part of speech
        let intransitive = verb && firstSenseIntransitive(en)
        let tr = others.map { p -> (String, String) in
            guard let t = bil[p.code], englishSide(t, in: p.bilingual) else { return (p.code, "") }
            // (the entries searched by the dictionary's headword: "stopped" is stop's)
            // the English word's other numbered entries there (bank 2 after bank 1), for their first translation
            let numbered = #"^([\p{L}'-]+) ?\d+(?=[\s,|])"#
            let others = verb ? [] : records(word, in: p.bilingual).filter {
                $0 != t && englishSide($0, in: p.bilingual) && group($0, numbered) != nil && group($0, numbered) == group(t, numbered)
            }
            var part = verb ? verbEntry(t, word, p, intransitive: intransitive) : mainPart(t, p, firstPart(en))
            // (a verb section whose sense 1 holds no translation: the next one, before its own sense 2 could lead)
            if verb, gloss(part, target: p, from: p).isEmpty, let next = laterVerbParts(part, p).first(where: { !gloss($0, target: p, from: p).isEmpty }) {
                part = next
            }
            let row = senses(part, target: p, from: p, noun: noun, others: others)
            return (p.code, row.joined(separator: " · "))
        }
        let sections = [(english.monolingual ?? "English", en)] + others.map { p in (title(p.bilingual ?? p.name), bil[p.code]) }
        return Entry(lang: "en", word: word, ipa: ipa, tr: tr, sections: sections.compactMap { n, t in t.map { (n, $0) } },
                     meaning: gloss(en, list: false))
    }
    // another language: English from its X - English entry, then each of the rest through that English
    let b = bilX[lang.code]
    var shown = Set<String>()  // (an item once in the row, after its hints go: huis "house, home · home")
    // the word's other numbered entries in its own dictionary (Bank 2, the money's, after Bank 1, the bench), but not
    // one the dictionary marks informal or regional (perro 1, rotten)
    let numbered = #"^([\p{L}'-]+) ?\d+(?=[\s,|])"#
    let homographs = b.flatMap { e in group(e, numbered).map { stem in
        records(stem, in: lang.bilingual).filter { $0 != e && !englishSide($0, in: lang.bilingual) && group($0, numbered) == stem &&
            !matches(String($0.prefix(70)), #"\((?:informal|colloquial|slang|vulgar|dated|Latin America|Spain|Mexico|Chile|Argentina)"#) }
    } } ?? []
    // a noun homograph first and an adjective one after (καλός1 nm "good guy", καλός2 adj "good"): the adjective leads,
    // as the word's everyday sense
    let adj = b.flatMap { e in matches(String(e.prefix(40)), #"^[\p{L}'-]+ ?1 n[mfn]?\b"#)
        ? homographs.firstIndex { matches(String($0.prefix(40)), #"^[\p{L}'-]+ ?\d+ adj\b"#) } : nil }
    let lead = adj.map { homographs[$0] } ?? b
    let rest = adj.map { i in [b!] + homographs.enumerated().filter { $0.offset != i }.map(\.element) } ?? homographs
    var inEnglish = senses(lead, from: lang, others: rest).enumerated().map { i, sense in
        let items = (lang.stripHints == true ? withoutHints(sense, lang) : sense).components(separatedBy: ", ").filter { i == 0 || !shown.contains($0.lowercased()) }
        items.forEach { shown.insert($0.lowercased()) }
        return items.joined(separator: ", ")
    }.filter { !$0.isEmpty }.joined(separator: " · ")
    // a word whose entry opens with uses and examples, not a translation ("aller A auxiliary verb … je vais partir
    // I'm leaving"): the pack says it
    if let t = lang.translations?[word.lowercased()] { inEnglish = t }
    let verb = isVerb(word, lang, lang.script == nil ? lead : bil[lang.code])
    // a noun in its own dictionary (boek: "znw boek"), so the English word's noun part is the one to translate
    let noun = !verb && (lead.map(opensAsNoun) ?? false), describing = !verb && (lead.map(opensAsDescribing) ?? false)
    let tr = [("en", inEnglish)] + others.filter { $0.code != lang.code }.map { p in
        (p.code, viaSenses(inEnglish, in: p, verb: verb, noun: noun, describing: describing))
    }
    let sections = [(title(lang.bilingual ?? lang.name), b), (lang.monolingual ?? lang.name, mono[lang.code])]
    return Entry(lang: lang.code, word: word, ipa: ipa, tr: tr, sections: sections.compactMap { n, t in t.map { (n, $0) } },
                 meaning: inEnglish)
}
