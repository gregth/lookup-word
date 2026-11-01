// Greek's hooks. macOS's text recognition has no Greek: it answers with Cyrillic or Latin letters of the same shape
// (φυτό as "фuTó"), so a reading is mapped back to the Greek letters it looks like; the dictionaries ignore accents
// and case, so the shape is enough. And the Greek dictionaries list μεταφέρω, not μεταφέρθηκε, while macOS has no
// Greek lemmatizer, so a form the lemma list lacks is tried as the base forms its regular ending points to.
import Foundation

let lookalike: [Character: Character] = [
    "А": "Α", "а": "α", "В": "Β", "в": "β", "Г": "Γ", "г": "γ", "Д": "Δ", "д": "δ", "Е": "Ε", "е": "ε", "З": "Ζ",
    "И": "Η", "и": "υ", "К": "Κ", "к": "κ", "Л": "Λ", "л": "λ", "М": "Μ", "м": "μ", "Н": "Η", "н": "η", "О": "Ο",
    "о": "ο", "П": "Π", "п": "π", "Р": "Ρ", "р": "ρ", "С": "Σ", "с": "σ", "Т": "Τ", "т": "τ", "У": "Υ", "у": "υ",
    "Ф": "Φ", "ф": "φ", "Х": "Χ", "х": "χ", "ш": "ω", "A": "Α", "a": "α", "B": "Β", "E": "Ε", "e": "ε", "H": "Η",
    "I": "Ι", "i": "ι", "K": "Κ", "k": "κ", "M": "Μ", "N": "Ν", "n": "η", "O": "Ο", "o": "ο", "P": "Ρ", "p": "ρ",
    "T": "Τ", "t": "τ", "u": "υ", "v": "ν", "w": "ω", "X": "Χ", "x": "χ", "Y": "Υ", "y": "γ", "Z": "Ζ", "c": "σ",
    "á": "ά", "é": "έ", "í": "ί", "ó": "ό", "ú": "ύ", "ý": "ύ", "ń": "ή", "à": "ά", "è": "έ", "ò": "ό",
    "є": "ε", "Є": "Ε", "і": "ι", "ї": "ϊ", "Ї": "Ϊ", "ł": "λ",
]

func greekified(_ w: String) -> String {
    var g = String(w.map { lookalike[$0] ?? $0 })
    if g.hasSuffix("σ") { g = String(g.dropLast()) + "ς" }
    return g
}

// Regular endings and the dictionary forms they point to, accents left out (the dictionaries ignore them).
// Stem-changing pasts (έγραψε → γράφω) mostly stay unfound; the lemma list covers many of those.
let greekEndings: [(String, [String])] = [
    // verbs: passive past, then present passive, then active past and present
    ("ιστηκ", ["ιζω"]), ("αστηκ", ["αζω"]), ("ευτηκ", ["ευω"]), ("ωθηκ", ["ωνω"]), ("ηθηκ", ["ω", "ουμαι", "αω"]),
    ("θηκ", ["ω", "ομαι"]),
    ("ιεται", ["ιω", "ω"]), ("ιουνται", ["ιω", "ω"]), ("ουνται", ["ουμαι", "ω"]), ("ειται", ["ουμαι", "ω"]),
    ("εται", ["ω", "ομαι"]), ("ονται", ["ω", "ομαι"]), ("εσαι", ["ω", "ομαι"]), ("ομαστε", ["ω", "ομαι"]), ("ομαι", ["ω", "ομαι"]),
    ("ευσ", ["ευω"]), ("ωσ", ["ωνω"]), ("ισ", ["ιζω"]), ("ασ", ["αζω"]), ("ησ", ["ω", "αω", "ηζω"]), ("ουσ", ["ω"]),
    ("ξ", ["ζω", "σσω", "γω", "χω", "κω"]), ("ψ", ["φω", "βω", "πω", "πτω"]), ("σ", ["ζω", "νω", "ω"]),
    ("ουμε", ["ω"]), ("ουνε", ["ω"]), ("ουν", ["ω"]), ("ετε", ["ω"]), ("εις", ["ω", "η", "ης"]), ("ει", ["ω"]),
    // nouns and adjectives
    ("ματος", ["μα"]), ("ματα", ["μα"]), ("ματων", ["μα"]), ("ιου", ["ι"]), ("ιων", ["ι", "ια"]), ("ια", ["ι", "ια"]),
    ("ους", ["ος"]), ("ου", ["ος", "ο", "ης", "ι"]), ("ων", ["ος", "ο", "α", "η", "ας", "ης"]), ("οι", ["ος"]),
    ("ες", ["α", "η", "ος", "ης"]), ("ας", ["α"]), ("ης", ["η", "ος"]), ("α", ["ο", "ος", "ας"]), ("η", ["ος", "ης"]),
    ("ο", ["ος"]), ("ε", ["ος", "ω"]), ("ι", ["ος"]),
]
// the past's endings after the stem's last consonant: -θηκε/-θηκαν, -ησε/-ησαν, -ξε, -ψαμε…
let pastTails = ["ε", "α", "ες", "αμε", "ατε", "αν", "ανε", "αμε", "ατε"]
let pastMarkers: Set = ["θηκ", "ιστηκ", "αστηκ", "ευτηκ", "ωθηκ", "ηθηκ", "ευσ", "ωσ", "ισ", "ασ", "ησ", "ουσ", "ξ", "ψ", "σ"]

struct GreekHooks: LanguageHooks {
    // a reading with any Cyrillic in it is Greek read as look-alikes, unless a pack in force writes Cyrillic; θ reads
    // as an oval "о" (Μεταφέρθηκε as "Метафéроnкє"), so θ is also tried for each ο
    func readingCandidates(_ w: String) -> [String]? {
        guard matches(w, #"\p{Cyrillic}"#), !packs.contains(where: { $0.script == "Cyrillic" }) else { return nil }
        let g = greekified(w)
        return [g] + g.indices.filter { "οό".contains(g[$0]) }.map { var v = g; v.replaceSubrange($0...$0, with: "θ"); return v }
    }

    // a Latin reading of a Greek text that no dictionary had: the Greek letters it looks like
    func fallbackCandidates(_ w: String, hint: String) -> [String] {
        matches(w, #"^[\p{Latin}]+$"#) && hint == "el" ? [greekified(w)] : []
    }

    func baseForms(_ word: String) -> [String] {
        let w = fold(word)
        var out: [String] = []
        for (e, n) in greekEndings {
            let end = fold(e), news = n.map(fold)
            // a past's ending is its stem marker plus a person ending (θηκ+ε); others match as they are
            let tails = pastMarkers.contains(e) ? pastTails.map(fold) : [""]
            for tail in tails where w.hasSuffix(end + tail) && w.count > end.count + tail.count + 1 {
                let stem = String(w.dropLast(end.count + tail.count))
                out += news.map { stem + $0 }
                if tail != "", stem.hasPrefix("ε") { out += news.map { stem.dropFirst() + $0 } }  // the past's augment: έγραψε
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }.map(spelled)
    }
}
