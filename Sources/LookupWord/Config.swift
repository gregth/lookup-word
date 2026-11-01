// Settings: one JSON file, written with the defaults on first launch. Every key is optional; a missing one keeps its
// default, so a config file from an older version still loads.
import Foundation

struct StoreConfig: Codable {
    var type = "markdown"  // markdown | json | none
    var path: String?  // default: Vocabulary.md or vocabulary.json in the support folder
    var saveDate = false  // also save when each word was looked up (an Added column, an "added" field)

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = c.lenient(String.self, .type, in: "store")?.lowercased() ?? type
        if !["markdown", "json", "none"].contains(type) { warn("store.type \"\(type)\" is not markdown, json or none: using markdown"); type = "markdown" }
        path = c.lenient(String.self, .path, in: "store")
        saveDate = c.lenient(Bool.self, .saveDate, in: "store") ?? saveDate
    }
}

struct Config: Codable {
    var languages = ["en", "nl", "el"]  // pack codes; English is the pivot and is always added
    var hotkey = "option"  // the modifier to double-tap: option | control | command | shift
    var screenReading = false  // read the word under the pointer off the screen (needs Screen Recording)
    var menuBar = true  // a menu bar icon with the vocabulary, the settings and Quit
    var closeAfter = 30.0  // seconds before the card closes by itself; 0 keeps it open until a click or key
    var debug = false  // save each screen reading as capture.png in the support folder, and log its coordinates
    var store = StoreConfig()

    init() {}
    // each key on its own: a key with a wrong value keeps its default (and a warning), never the whole file
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        languages = c.lenient([String].self, .languages)?.map { $0.lowercased() } ?? languages
        hotkey = c.lenient(String.self, .hotkey)?.lowercased() ?? hotkey
        screenReading = c.lenient(Bool.self, .screenReading) ?? screenReading
        menuBar = c.lenient(Bool.self, .menuBar) ?? menuBar
        closeAfter = c.lenient(Double.self, .closeAfter) ?? closeAfter
        debug = c.lenient(Bool.self, .debug) ?? debug
        store = c.lenient(StoreConfig.self, .store) ?? store
    }
}

// What went wrong reading the settings, for the card and the log: a user who mistyped a key must not find out only
// when their words are missing.
var configWarnings: [String] = []
func warn(_ s: String) { configWarnings.append(s); log("config.json: " + s) }

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key, in parent: String? = nil) -> T? {
        guard contains(key) else { return nil }
        do { return try decodeIfPresent(type, forKey: key) } catch {
            warn("\((parent.map { $0 + "." } ?? "") + key.stringValue) has a value of the wrong kind; using the default")
            return nil
        }
    }
}

enum Paths {
    // ~/Library/Application Support/Lookup Word, or LOOKUP_SUPPORT (tests)
    static let support: URL = {
        let env = ProcessInfo.processInfo.environment["LOOKUP_SUPPORT"].map { URL(fileURLWithPath: expand($0)) }
        let dir = env ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lookup Word")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var config: URL {
        ProcessInfo.processInfo.environment["LOOKUP_CONFIG"].map { URL(fileURLWithPath: expand($0)) }
            ?? support.appendingPathComponent("config.json")
    }
    // the language packs: LOOKUP_PACKS, the app bundle's Resources/packs, or packs/ in the source tree above the
    // binary (swift build puts it a few folders down, the layout varying with the toolchain)
    static let packs: URL = {
        if let p = ProcessInfo.processInfo.environment["LOOKUP_PACKS"] { return URL(fileURLWithPath: expand(p)) }
        var tries: [URL] = []
        if let r = Bundle.main.resourceURL { tries.append(r.appendingPathComponent("packs")) }
        var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            guard let d = dir else { break }
            tries.append(d.appendingPathComponent("packs"))
            dir = d.deletingLastPathComponent()
        }
        return tries.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("en/pack.json").path) } ?? tries[0]
    }()
}

func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

// The settings in force: the file's, or the defaults (written out, so there is a file to edit). A file that is not
// JSON at all keeps the defaults and stops saving (configBroken), so words never go silently to another file.
var configBroken = false
let config: Config = {
    let url = Paths.config
    if let data = try? Data(contentsOf: url), !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
        do { return try JSONDecoder().decode(Config.self, from: data) } catch {
            configBroken = true
            warn("not valid JSON (\(error.localizedDescription)): using the defaults and saving nothing until it is fixed")
            return Config()
        }
    }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? enc.encode(Config()) { try? (data + Data("\n".utf8)).write(to: url, options: .atomic) }
    return Config()
}()

// One setting changed in config.json, every other key (and unknown ones) kept as the file has them.
func setSetting(_ key: String, _ value: Any) {
    let url = Paths.config
    var dict: [String: Any] = [:]
    if let data = try? Data(contentsOf: url), !data.isEmpty {
        guard let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { log("config.json is not valid JSON: \(key) not saved"); return }
        dict = d
    }
    dict[key] = value
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
        try? (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }
}

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
