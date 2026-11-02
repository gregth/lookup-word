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
        // each other language from its X - English entry for the English word (its verb part, for a verb)
        let verb = isVerb(w, english, en)
        let noun = en.map { matches($0, #"^[^|]+\|[^|]+\|\s*noun\b"#) } ?? false  // Oxford's first part of speech
        // Oxford's first verb sense takes no object: "[no object]" before any "[with object]"
        let intransitive = verb && (en.map { e in
            guard let no = e.range(of: "[no object]") else { return false }
            return e.range(of: "[with object]").map { no.lowerBound < $0.lowerBound } ?? true
        } ?? false)
        let tr = others.map { p -> (String, String) in
            guard let t = bil[p.code], englishSide(t, in: p.bilingual) else { return (p.code, "") }
            // (the entries searched by the dictionary's headword: "stopped" is stop's)
            return (p.code, gloss(verb ? verbEntry(t, word, p, intransitive: intransitive) : t, target: p, from: p, noun: noun))
        }
        let sections = [(english.monolingual ?? "English", en)] + others.map { p in (title(p.bilingual ?? p.name), bil[p.code]) }
        return Entry(lang: "en", word: word, ipa: ipa, tr: tr, sections: sections.compactMap { n, t in t.map { (n, $0) } },
                     meaning: gloss(en, list: false))
    }
    // another language: English from its X - English entry, then each of the rest through that English
    let b = bilX[lang.code]
    var inEnglish = gloss(b, from: lang)
    if lang.stripHints == true { inEnglish = withoutHints(inEnglish, lang) }
    // a word whose entry opens with uses and examples, not a translation ("aller A auxiliary verb … je vais partir
    // I'm leaving"): the pack says it
    if let t = lang.translations?[word.lowercased()] { inEnglish = t }
    let verb = isVerb(word, lang, lang.script == nil ? b : bil[lang.code])
    // a noun in its own dictionary (boek: "znw boek"), so the English word's noun part is the one to translate
    let noun = !verb && (b.map(opensAsNoun) ?? false), describing = !verb && (b.map(opensAsDescribing) ?? false)
    let tr = [("en", inEnglish)] + others.filter { $0.code != lang.code }.map { p in
        (p.code, via(inEnglish, in: p, verb: verb, noun: noun, describing: describing))
    }
    let sections = [(title(lang.bilingual ?? lang.name), b), (lang.monolingual ?? lang.name, mono[lang.code])]
    return Entry(lang: lang.code, word: word, ipa: ipa, tr: tr, sections: sections.compactMap { n, t in t.map { (n, $0) } },
                 meaning: inEnglish)
}
