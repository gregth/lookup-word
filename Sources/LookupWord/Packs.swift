// Language packs: one folder per language under packs/, with a pack.json (data) and, optionally, a lemma list.
// What a language needs beyond data lives in a LanguageHooks type registered by code below (only Greek has one).
// English is the pivot: every other language translates to English through its own X - English dictionary, and on
// to the others through theirs. See CONTRIBUTING.md.
import Foundation

struct VerbRule: Decodable {
    var entryPattern: String?  // a regex the word's entry matches when it is a verb…
    var prefix: Int?  // …within its first N characters
    var endings: [String]?  // or: the endings of a verb's dictionary form (Greek: ω, ώ, μαι)
}

struct GlossRules: Decodable {
    var labels: [String]?  // grammar labels dropped from the start of a translation (adj, znw, το)
    var inner: [String]?  // labels dropped anywhere in a translation (hulpww, aux)
    var cuts: [String]?  // a translation stops at these (zie:, DERIVATIVES)
    var grammarNotes: [String]?  // abbreviations ending in "." that come before the meaning (αόρ, μτχ)
    var variants: [[String]]?  // [regex, replacement] applied first, e.g. a spelling variant after the headword
}

struct Pack: Decodable {
    var code: String  // ISO 639-1
    var name: String  // in English: "Dutch"
    var flag: String?
    var voice: String  // AVSpeechSynthesisVoice language: "nl-NL"
    var monolingual: String?  // Dictionary.app short names: "Dutch"…
    var bilingual: String?  // …"Dutch - English"; none for English itself
    var dictionaryIds: [String]?  // their identifiers in Dictionary.app (com.apple.dictionary.nl-en.oup), for Enable
    var script: String?  // a Unicode script only this language writes among the packs ("Greek"); words in it are its own
    var recognizer: String?  // NLLanguage code for telling the text's language, when NaturalLanguage knows it
    var ocr: [String]?  // Vision recognition languages that read it ("ru-RU" for Greek: see GreekHooks)
    var spellChecker: String?  // NSSpellChecker language, for correcting a misread word
    var verb: VerbRule?
    var verbLabels: [String]?  // the labels that open the verb part of an English entry in this X - English dictionary
    var stripHints: Bool?  // its X - English translations may start with X words as hints ("gaan walk"): drop them
    var lemmas: String?  // form ⇥ lemma, .tsv or .tsv.xz, for languages whose dictionaries do not lemmatise
    var gloss: GlossRules?
    var dir = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey {
        case code, name, flag, voice, monolingual, bilingual, dictionaryIds, script, recognizer, ocr, spellChecker, verb, verbLabels,
             stripHints, lemmas, gloss
    }

    var isEnglish: Bool { code == "en" }
    var hooks: LanguageHooks? { languageHooks[code] }
    func writes(_ word: String) -> Bool { script.map { matches(word, #"\p{"# + $0 + "}") } ?? false }
}

// What a language needs that data cannot say.
protocol LanguageHooks {
    // The words to try for a screen reading of a word in this language, when the reading alone settles that it is
    // (e.g. Cyrillic letters standing in for Greek); nil when the reading is not this language's.
    func readingCandidates(_ word: String) -> [String]?
    // More words to try when a reading found nothing, given the text's language.
    func fallbackCandidates(_ word: String, hint: String) -> [String]
    // Dictionary forms to try for an inflected word its lemma list lacks, most likely first.
    func baseForms(_ word: String) -> [String]
}

let languageHooks: [String: LanguageHooks] = ["el": GreekHooks()]

func loadPack(_ code: String) -> Pack? {
    let dir = Paths.packs.appendingPathComponent(code)
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("pack.json")) else { log("no pack \(code) in \(Paths.packs.path)"); return nil }
    do {
        var p = try JSONDecoder().decode(Pack.self, from: data)
        p.dir = dir
        return p
    } catch { log("pack \(code) unreadable: \(error)"); return nil }
}

// The packs in force, in the settings' order, English always among them (first when not listed).
let packs: [Pack] = {
    var codes = config.languages
    if !codes.contains("en") { codes.insert("en", at: 0) }
    var seen = Set<String>()
    return codes.compactMap { code in
        guard let p = loadPack(code) else { warn("languages: no pack \"\(code)\" (available: \(availablePacks.joined(separator: ", ")))"); return nil }
        return seen.insert(p.code).inserted ? p : nil  // "NL" and "nl" are one pack on a case-insensitive disk
    }
}()
var availablePacks: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: Paths.packs.path)) ?? []).filter {
        FileManager.default.fileExists(atPath: Paths.packs.appendingPathComponent("\($0)/pack.json").path)
    }.sorted()
}
let english: Pack = packs.first(where: \.isEnglish) ?? Pack(code: "en", name: "English", voice: "en-GB", monolingual: "English")
func pack(_ code: String) -> Pack? { packs.first { $0.code == code } }
var others: [Pack] { packs.filter { !$0.isEnglish } }

// Gloss rules of every pack in force, merged: a dictionary's text can carry another language's labels.
let glossLabels: Set<String> = Set(packs.flatMap { $0.gloss?.labels ?? [] })
let glossInner: Set<String> = Set(packs.flatMap { $0.gloss?.inner ?? [] })
let glossCuts: [String] = ["▸", "▶", "•"] + packs.flatMap { $0.gloss?.cuts ?? [] }
let glossNotes: [String] = packs.flatMap { $0.gloss?.grammarNotes ?? [] }
let glossVariants: [(String, String)] = packs.flatMap { $0.gloss?.variants ?? [] }.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
