// Puts a window screenshot on a wide, soft background, with rounded corners and a shadow, as on a desktop. GitHub
// draws every README image at the page's full width, so a window rendered on its own came out huge; on a background
// about twice its width it shows at a natural size.
//
//   swift scripts/frame-screenshot.swift docs/welcome.png docs/welcome.png [width-factor, default 2]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let shot = NSImage(contentsOfFile: args[1]), let rep = shot.representations.first else {
    print("usage: frame-screenshot.swift in.png out.png [width-factor]"); exit(1)
}
let factor = args.count > 3 ? Double(args[3]) ?? 2 : 2
let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)  // pixels: the screenshots are rendered at 2x
let pad = (h * 0.12).rounded(), W = (w * CGFloat(factor)).rounded(), H = h + 2 * pad
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
// the background: the app icon's own blues (#4677F5 to #2346B5, docs/icon.svg) as a soft diagonal tint
NSGradient(colors: [NSColor(red: 0.275, green: 0.467, blue: 0.961, alpha: 1), NSColor(red: 0.137, green: 0.275, blue: 0.710, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)
let frame = NSRect(x: ((W - w) / 2).rounded(), y: pad, width: w, height: h)
let corner = w * 0.02
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowBlurRadius = pad * 0.45; shadow.shadowOffset = NSSize(width: 0, height: -pad * 0.12)
shadow.shadowColor = NSColor(white: 0, alpha: 0.45); shadow.set()
NSColor(white: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).fill()
NSGraphicsContext.current?.restoreGraphicsState()
NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.current = nil
out.size = NSSize(width: W / 2, height: H / 2)  // keep the 2x density
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) \(Int(W))×\(Int(H)) px")
