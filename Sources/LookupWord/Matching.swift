// Matching a screen reading against the app's own text, so a misread word (or a Greek one read as look-alike Latin
// or Cyrillic letters) is looked up as the word it really is.
import Foundation

// A word's shape in plain Latin letters, so a reading in look-alike letters compares with the real word: Greek and
// Cyrillic letters as the Latin ones they resemble, accents and case dropped (ιθαγενές and "IBaYEVÉS" both near
// "ioayeves").
let shapes: [Character: Character] = [
    "α": "a", "β": "b", "γ": "y", "δ": "d", "ε": "e", "ζ": "z", "η": "n", "θ": "o", "ι": "i", "κ": "k", "λ": "a",
    "μ": "u", "ν": "v", "ξ": "e", "ο": "o", "π": "n", "ρ": "p", "σ": "o", "ς": "s", "τ": "t", "υ": "u", "φ": "o",
    "χ": "x", "ψ": "y", "ω": "w", "а": "a", "б": "b", "в": "b", "г": "r", "д": "d", "е": "e", "и": "u", "к": "k",
    "л": "n", "м": "m", "н": "h", "о": "o", "п": "n", "р": "p", "с": "c", "т": "t", "у": "y", "ф": "o", "х": "x",
    "ш": "w",
]
// capitals look unlike their small letters (Η is H, η is n), and digits stand in for letters (Η read as "H", του as
// "n01", σε as "30", ότι as "110", Ψ as Cyrillic Ч), so those map before case is dropped
let capitals: [Character: Character] = [
    "Α": "a", "Β": "b", "Γ": "r", "Δ": "a", "Ε": "e", "Ζ": "z", "Η": "h", "Θ": "o", "Ι": "i", "Κ": "k", "Λ": "a", "Μ": "m",
    "Ν": "n", "Ξ": "e", "Ο": "o", "Π": "n", "Ρ": "p", "Σ": "e", "Τ": "t", "Υ": "y", "Φ": "o", "Χ": "x", "Ψ": "y", "Ω": "o",
    "А": "a", "В": "b", "Г": "r", "Д": "a", "Е": "e", "И": "n", "К": "k", "Л": "a", "М": "m", "Н": "h", "О": "o", "П": "n",
    "Р": "p", "С": "c", "Т": "t", "У": "y", "Ф": "o", "Х": "x", "Ч": "y", "Ш": "w", "Э": "e",
    "0": "o", "1": "i", "3": "e", "l": "i", "ı": "i", "ї": "i",
]
func shape(_ s: String) -> [Character] {
    s.folding(options: [.diacriticInsensitive], locale: nil).map { capitals[$0] ?? Character(String($0).lowercased()) }
        .map { shapes[$0] ?? $0 }
}

func distance(_ a: [Character], _ b: [Character]) -> Int {
    var row = Array(0...b.count)
    for (i, x) in a.enumerated() {
        var prev = row[0]; row[0] = i + 1
        for (j, y) in b.enumerated() {
            let cur = row[j + 1]
            row[j + 1] = min(row[j + 1] + 1, row[j] + 1, prev + (x == y ? 0 : 1))
            prev = cur
        }
    }
    return row[b.count]
}

// the likeness of a reading to a word, 0…1; a reading spelled backwards counts too (recognition sometimes returns a
// Greek word's letters in reverse, περιοχής as "SỤX01031", αρχή as "uXdo")
func similarity(_ a: String, _ b: String) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    let x = shape(a), y = shape(b), n = Double(max(x.count, y.count, 1))
    return max(1 - Double(distance(x, y)) / n, 1 - Double(distance(Array(x.reversed()), y)) / n)
}

func words(_ text: String) -> [String] {  // a hyphenated compound is two
    text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }).map(String.init)
}

// The word of the real text at the place that best fits the reading: each word of the text scores by its own
// likeness to what was read, weighed by the reading's length, and by its neighbours' likeness to the words read
// beside it (four a side, the nearer counting more), so "aitia n01 Aavátou" finds "αίτια του θανάτου" even though
// "n01" alone resembles nothing. The weighted average must reach 0.33.
func closest(_ r: Reading, in text: String) -> String? {
    let ws = words(text), near: [Double] = [1, 0.75, 0.5, 0.35]
    var best: (String, Double)?
    for j in ws.indices {
        // the word's own reading weighs by its length: nothing when unread (it is placed by its neighbours), up to 4
        // for a long one (a long near-right reading must not be outvoted)
        let own = min(4, Double(r.word.count) / 2 + (r.word.isEmpty ? 0 : 1))
        var score = own * similarity(r.word, ws[j]), weight = own
        for (k, w) in r.before.reversed().prefix(4).enumerated() where j - 1 - k >= 0 {
            score += near[k] * similarity(w, ws[j - 1 - k]); weight += near[k]
        }
        for (k, w) in r.after.prefix(4).enumerated() where j + 1 + k < ws.count {
            score += near[k] * similarity(w, ws[j + 1 + k]); weight += near[k]
        }
        if weight > 0, score / weight > (best?.1 ?? 0.33) { best = (ws[j], score / weight) }
    }
    return best?.0
}

// The word of the real text closest in shape to one word read alone; nil when none is close enough to be it.
func closest(_ read: String, in text: String) -> String? {
    let r = shape(read)
    var best: (String, Double)?
    for w in text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" }).map(String.init) {
        let s = shape(w), score = 1 - Double(distance(r, s)) / Double(max(r.count, s.count, 1))
        if score > (best?.1 ?? 0.45) { best = (w, score) }
    }
    return best?.0
}
