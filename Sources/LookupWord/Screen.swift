// Where the word is: the selection (accessibility), or the word under the pointer read off the screen
// (ScreenCaptureKit and macOS's text recognition), when screen reading is on.
import AppKit
import ScreenCaptureKit
import Vision

// Accessibility counts from the main screen's top-left; AppKit from its bottom-left.
func flip(_ r: CGRect) -> NSRect {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return NSRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height)
}

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func param(_ el: AXUIElement, _ name: String, _ arg: CFTypeRef) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, arg, &v) == .success ? v : nil
}

func bounds(_ el: AXUIElement, _ range: CFRange) -> NSRect? {
    var r = range
    guard let arg = AXValueCreate(.cfRange, &r), let v = param(el, kAXBoundsForRangeParameterizedAttribute, arg),
          CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(v as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
    return flip(rect)
}

// The selected text in the focused element, with where it is and the text around it.
func selection() -> (String, NSRect?, String)? {
    guard let f = attr(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
          CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
    let el = f as! AXUIElement
    guard let s = attr(el, kAXSelectedTextAttribute) as? String,
          !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    var rect: NSRect?
    if let v = attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
        var range = CFRange()
        if AXValueGetValue(v as! AXValue, .cfRange, &range) { rect = bounds(el, range) }
    }
    let around = (attr(el, kAXValueAttribute) as? String).map { String($0.prefix(1000)) } ?? s
    return (s, rect, around)
}

// The word under the pointer, read off the screen, so it works in every app (accessibility gives no word at a point
// in Chrome's web pages): a 640×90 pt capture around the pointer, macOS's text recognition (Vision), and the word
// whose box holds the pointer, with the recognised text around it for the language.
func byOCR(_ mouse: NSPoint) async -> (Reading, NSRect)? {
    // only checked: macOS is asked when the user clicks Allow, never by a lookup (one prompt at a time)
    guard CGPreflightScreenCaptureAccess() else { log("no Screen Recording"); return nil }
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
          let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
          let display = content.displays.first(where: { $0.displayID == id }) else { log("no display to capture"); return nil }
    let f = screen.frame, w: CGFloat = 640, h: CGFloat = 90
    // the region in the display's points, from its top-left, on whole points: a fractional origin, the pointer's own,
    // may be rounded by the capture and not by these coordinates (the highlight then sits 2-3 pt off the word)
    let region = CGRect(x: (mouse.x - f.minX - w / 2).rounded(), y: (f.maxY - mouse.y - h / 2).rounded(), width: w, height: h)
        .intersection(CGRect(origin: .zero, size: f.size))
    let cfg = SCStreamConfiguration()
    cfg.sourceRect = region
    cfg.width = Int(region.width * screen.backingScaleFactor)
    cfg.height = Int(region.height * screen.backingScaleFactor)
    cfg.showsCursor = false
    let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
    let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])  // not our card
    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else {
        log("capture failed"); return nil
    }
    // Two passes: text recognition places whole lines well but only estimates a word inside one, so the word's own
    // rectangle comes from text detection, and recognition then reads just that rectangle. The whole capture is read
    // too, for the language of the text around it.
    let pointer = CGPoint(x: (mouse.x - f.minX - region.minX) / region.width, y: 1 - (f.maxY - mouse.y - region.minY) / region.height)
    guard let (r, box) = wordAt(image, pointer) else { return nil }
    let onScreen = NSRect(x: f.minX + region.minX + box.minX * region.width,
                          y: f.maxY - region.minY - (1 - box.minY) * region.height,  // Vision's y runs up from the bottom
                          width: box.width * region.width, height: box.height * region.height)
    if config.debug {
        debugCapture(image, box: box, pointer: pointer)
        log("  debug: mouse \(mouse) screen \(f) scale \(screen.backingScaleFactor) region \(region) image \(image.width)×\(image.height) box \(box) on screen \(onScreen)")
    }
    return (r, onScreen)
}

// The capture as the app saw it, with the word's box (red) and the pointer (green) drawn on, to capture.png in the
// support folder: what tells a reading problem (the box off the word in the capture) from a placing one.
func debugCapture(_ image: CGImage, box: CGRect, pointer: CGPoint) {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(1)
    ctx.stroke(CGRect(x: box.minX * w, y: box.minY * h, width: box.width * w, height: box.height * h))  // CG's y is up, as Vision's
    ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: pointer.x * w - 2, y: pointer.y * h - 2, width: 4, height: 4))
    if let out = ctx.makeImage() {
        let rep = NSBitmapImageRep(cgImage: out)
        try? rep.representation(using: .png, properties: [:])?.write(to: Paths.support.appendingPathComponent("capture.png"))
    }
}

// What the screen reading saw at the pointer: the word, up to four words read before and after it on its line (for
// matching it against the app's own text), and all the text read (for the language).
struct Reading { var word: String; var before: [String]; var after: [String]; var around: String }

// The word at a point of an image (0…1, from its bottom-left), its box in the same units, and all the text read.
func wordAt(_ image: CGImage, _ pt: CGPoint) -> (Reading, CGRect)? {
    let detect = VNDetectTextRectanglesRequest(), read = recognizer()
    detect.reportCharacterBoxes = true
    // each request on its own handler: run together, the recognition came back empty
    guard (try? VNImageRequestHandler(cgImage: image).perform([detect])) != nil else { return nil }
    do { try VNImageRequestHandler(cgImage: image).perform([read]) } catch { log("reading failed: \(error)") }
    let around = (read.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    // the line under the pointer (detection boxes lines), then its word: from the character under the pointer out to
    // the gaps wide enough to be spaces
    let lines = (detect.results ?? []).filter { $0.boundingBox.insetBy(dx: -0.004, dy: -0.03).contains(pt) }
    if let line = lines.min(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
       let chars = line.characterBoxes?.map(\.boundingBox).sorted(by: { $0.minX < $1.minX }), !chars.isEmpty {
        let i = chars.firstIndex { $0.maxX >= pt.x } ?? chars.count - 1
        // a gap wider than any between letters of one word, in x's units: Vision's 0…1 run separately along the width
        // and the height, so the line's height is first scaled by the image's aspect (a 640×90 capture: ×0.14)
        let space = line.boundingBox.height * CGFloat(image.height) / CGFloat(image.width) * 0.22
        // the line's words: runs of letter boxes split at gaps wide enough to be spaces; the pointer's is a…b
        var runs: [ClosedRange<Int>] = [], s0 = 0
        for j in 1...chars.count where j == chars.count || chars[j].minX - chars[j - 1].maxX >= space { runs.append(s0...(j - 1)); s0 = j }
        let k = runs.firstIndex { $0.contains(i) } ?? 0
        let (a, b) = (runs[k].lowerBound, runs[k].upperBound)
        let box = chars[a...b].reduce(chars[a]) { $0.union($1) }.union(CGRect(x: chars[a].minX, y: line.boundingBox.minY,
                                                                                 width: 0, height: line.boundingBox.height))
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // the word itself, read from a crop of just its letters, three ways, the surest kept: each pointer position
        // frames the word a little differently, and a framing that fails one way often reads another: the usual
        // margin, a wider one, and the usual one enlarged twice
        var word = "", x0 = box.minX, x1 = box.maxX, sure: Float = -1
        for (dx, dy, zoom) in [(6.0, 4.0, 1.0), (14.0, 8.0, 1.0), (6.0, 4.0, 2.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let cr = CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h)
                .insetBy(dx: -dx, dy: -dy).intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard var cut = image.cropping(to: cr) else { continue }
            if zoom > 1, let ctx = CGContext(data: nil, width: Int(CGFloat(cut.width) * zoom), height: Int(CGFloat(cut.height) * zoom),
                                             bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(cut, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
                if let big = ctx.makeImage() { cut = big }
            }
            let one = recognizer()
            guard (try? VNImageRequestHandler(cgImage: cut).perform([one])) != nil,
                  let c = one.results?.first?.topCandidates(1).first, c.confidence > sure else { continue }
            // the crop may catch a neighbour's edge or punctuation: its word nearest the pointer, not its longest
            // (Greek να read as the αναμένεται beside it), and that word's own bounds (crop units, so the zoom does
            // not matter) for the highlight
            let at = (pt.x * w - cr.minX) / cr.width
            var best: Range<String.Index>?, gap = CGFloat.infinity
            c.string.enumerateSubstrings(in: c.string.startIndex..., options: .byWords) { _, r, _, _ in
                let bb = (try? c.boundingBox(for: r))?.boundingBox
                let d = bb.map { $0.minX <= at && at <= $0.maxX ? 0 : min(abs($0.minX - at), abs($0.maxX - at)) } ?? 1
                if d < gap { gap = d; best = r }
            }
            guard let range = best else { continue }
            word = String(c.string[range]); sure = c.confidence
            let rb = (try? c.boundingBox(for: range))?.boundingBox ?? one.results!.first!.boundingBox
            x0 = (cr.minX + rb.minX * cr.width) / w; x1 = (cr.minX + rb.maxX * cr.width) / w
        }
        // its neighbours, up to four a side, each read from a crop of its own run of letters: recognition can give
        // up on a whole long line and return nothing, while single words read
        func readRun(_ r: ClosedRange<Int>) -> String {
            let bx = chars[r].reduce(chars[r.lowerBound]) { $0.union($1) }
            let rp = CGRect(x: bx.minX * w, y: (1 - line.boundingBox.maxY) * h, width: bx.width * w, height: line.boundingBox.height * h)
                .insetBy(dx: -6, dy: -4).intersection(CGRect(x: 0, y: 0, width: w, height: h))
            let q = recognizer()
            guard let cut = image.cropping(to: rp), (try? VNImageRequestHandler(cgImage: cut).perform([q])) != nil,
                  let s = q.results?.first?.topCandidates(1).first?.string else { return "" }
            return words(s).max(by: { $0.count < $1.count }) ?? ""
        }
        let before = runs[max(0, k - 4)..<k].map(readRun)
        let after = runs[(k + 1)..<min(runs.count, k + 5)].map(readRun)
        // a word its own crop cannot read (one- and two-letter words such as Ο, η, τα, is): an empty reading, which
        // the match against the app's text places by its neighbours alone
        if word.isEmpty && before.allSatisfy(\.isEmpty) && after.allSatisfy(\.isEmpty) { log("no word read at the pointer"); return nil }
        // the letters' own boxes inside the word's bounds: as tight as the letters, without a colon or space
        let inside = chars[a...b].filter { $0.midX >= x0 && $0.midX <= x1 }
        let xs = inside.isEmpty ? (box.minX, box.maxX) : (inside.map { $0.minX }.min()!, inside.map { $0.maxX }.max()!)
        let tight = inked(image, CGRect(x: xs.0, y: line.boundingBox.minY, width: xs.1 - xs.0, height: line.boundingBox.height))
        log("read \(before.joined(separator: " ")) [\(word)] \(after.joined(separator: " ")) off the screen")
        return (Reading(word: word, before: before, after: after, around: around), tight)
    }
    log("no word read at the pointer (\(lines.count) lines)")
    return nil
}

// Vision's recognition languages: each pack's, in the settings' order.
let ocrLanguages: [String] = {
    var seen = Set<String>()
    return packs.flatMap { $0.ocr ?? [] }.filter { seen.insert($0).inserted }
}()

// A box trimmed to its ink: on screen, Vision's letter boxes can take in the space beside a word, so the columns at
// each edge that hold only the background colour (the box's own corners) are cut off. Units are Vision's: 0…1 from
// the image's bottom-left.
func inked(_ image: CGImage, _ box: CGRect) -> CGRect {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    let px = CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h).integral
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard px.width > 2, px.height > 2, let cut = image.cropping(to: px) else { return box }
    let cw = cut.width, ch = cut.height
    var data = [UInt8](repeating: 0, count: cw * ch * 4)
    guard let ctx = CGContext(data: &data, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return box }
    ctx.draw(cut, in: CGRect(x: 0, y: 0, width: cw, height: ch))
    let pixel = { (x: Int, y: Int) -> (Int, Int, Int) in let i = (y * cw + x) * 4; return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2])) }
    // the background: the most common of the four corners' colours (a corner can touch a letter)
    let corners = [pixel(0, 0), pixel(cw - 1, 0), pixel(0, ch - 1), pixel(cw - 1, ch - 1)]
    let bg = corners.max { a, b in corners.filter { $0 == a }.count < corners.filter { $0 == b }.count }!
    let inked = { (x: Int) -> Bool in
        (0..<ch).contains { y in let c = pixel(x, y); return abs(c.0 - bg.0) + abs(c.1 - bg.1) + abs(c.2 - bg.2) > 90 }
    }
    guard let first = (0..<cw).first(where: inked), let last = (0..<cw).last(where: inked), last >= first else { return box }
    return CGRect(x: (px.minX + CGFloat(first)) / w, y: box.minY, width: CGFloat(last - first + 1) / w, height: box.height)
}

func recognizer() -> VNRecognizeTextRequest {
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate
    // fixed left-to-right languages, not detection: detection sometimes took Greek for a right-to-left script and
    // read it backwards (αρχή as "uXdo"); Russian reads Greek as look-alike Cyrillic
    if let langs = ProcessInfo.processInfo.environment["LOOKUP_LANGS"] {  // a test can try other sets
        if langs == "auto" { r.automaticallyDetectsLanguage = true } else { r.recognitionLanguages = langs.split(separator: ",").map(String.init) }
    } else {
        r.recognitionLanguages = ocrLanguages
    }
    r.usesLanguageCorrection = false
    return r
}

// The true text under the pointer: apps that give no word at a point (Chrome, Electron) still give the text of the
// element there, a web page's paragraph. The screen reading says where the word is and roughly what; this says what
// it really is (Greek ιθαγενές read as "IBaYEVÉS", which no letter mapping undoes).
func textUnderPointer(_ mouse: NSPoint) -> String? {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(mouse.x), Float(top - mouse.y), &hit) == .success,
          let el = hit else { return nil }
    for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let s = attr(el, key) as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
    }
    return nil
}
