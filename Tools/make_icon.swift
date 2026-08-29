// Writes out Mdoro's app icons from Tools/mdoro-icon.svg.
//
//   swift Tools/make_icon.swift [path to the repository]
//
// Never replace a PNG by hand. To change a colour or a shape, edit the SVG and run this.
// Rendering is left to AppKit's SVG support (_NSSVGImageRep). No external tool is needed.

import AppKit
import Foundation

let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let svg = try String(contentsOfFile: "\(repo)/Tools/mdoro-icon.svg", encoding: .utf8)

// The colour substitution tables. Light is exactly the colours written in the SVG.
// Dark changes only the ground and the `#`, because a grey that is only 1.3 against the ground
// disappears in the dark. The centre of the fruit sits on the red and reads in either mode, so it
// is left alone.
let dark = ["#F7F3ED": "#13110D", "#383A3F": "#ABA497"]
// Tinted conveys the shape by lightness alone. The system lays the user's colour over it.
let tinted = ["#F7F3ED": "#000000", "#383A3F": "#FFFFFF", "#3B3A3F": "#1C1C1C",
              "#8FA08D": "#C9C9C9", "#F2F9E7": "#FFFFFF",
              "#D8563C": "#9A9A9A", "#BC422D": "#767676"]

func recolor(_ source: String, _ map: [String: String]) -> String {
    map.reduce(source) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
}

// At 16 and 32px the fine lines only turn to mud, so they are taken out.
func withoutDetail(_ source: String) -> String {
    guard let start = source.range(of: "<g id=\"detail\""),
          let end = source.range(of: "</g>", range: start.upperBound..<source.endIndex)
    else { return source }
    return source.replacingCharacters(in: start.lowerBound..<end.upperBound, with: "")
}

func image(_ source: String) throws -> NSImage {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mdoro-icon-\(UUID().uuidString).svg")
    try source.write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp) }
    guard let img = NSImage(contentsOf: tmp) else {
        FileHandle.standardError.write(Data("cannot render the SVG\n".utf8))
        exit(1)
    }
    return img
}

func canvas(_ n: Int, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iOS paints the whole face. The OS lays the rounded corners over it.
func fullBleed(_ img: NSImage, _ n: Int) -> Data {
    canvas(n) { img.draw(in: NSRect(x: 0, y: 0, width: n, height: n)) }
}

// macOS fits it into the central 824 of 1024 and cuts it with a corner radius of 185.4.
// Everything outside is transparent.
func macTile(_ img: NSImage, _ n: Int) -> Data {
    let side = CGFloat(n) * 824.0 / 1024.0
    let radius = CGFloat(n) * 185.4 / 1024.0
    let offset = (CGFloat(n) - side) / 2
    return canvas(n) {
        NSBezierPath(roundedRect: NSRect(x: offset, y: offset, width: side, height: side),
                     xRadius: radius, yRadius: radius).setClip()
        img.draw(in: NSRect(x: offset, y: offset, width: side, height: side))
    }
}

func write(_ data: Data, _ path: String) throws {
    try data.write(to: URL(fileURLWithPath: path))
    print("  \((path as NSString).lastPathComponent)")
}

// MARK: - iOS

let ios = "\(repo)/PomodoroMac/PomodoroiOS/Assets.xcassets/AppIcon.appiconset"
print("iOS")
try write(fullBleed(image(svg), 1024), "\(ios)/icon-light-1024.png")
try write(fullBleed(image(recolor(svg, dark)), 1024), "\(ios)/icon-dark-1024.png")
try write(fullBleed(image(recolor(svg, tinted)), 1024), "\(ios)/icon-tinted-1024.png")
try write(Data("""
{
  "images" : [
    {
      "filename" : "icon-light-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "icon-dark-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "icon-tinted-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".utf8), "\(ios)/Contents.json")

// MARK: - Menu bar

// Registered as template images. The OS decides the colour to match the brightness of the ground
// (REQ-COL-022).
// **The state is shown by shape alone.** Only three images are used. The fruit stands in for a
// vessel: idle is a full fruit, running is a water level, paused is an empty vessel
// (REQ-UIX-030 / 035 / Decision 0031).
//
// The source of truth is the author's SVGs under `docs/images/icons/`. This only reads them, and
// never writes back.
let menuBarStates = [
    ("MenuBarIdle", "mdoro-menubar-idle"),
    ("MenuBarRunning", "mdoro-menubar-running-60"),
    ("MenuBarPaused", "mdoro-menubar-paused"),
]

// The menu bar is 24pt high (`docs/PLATFORM.md`). By convention the mark is kept to 16–18pt.
let menuBarPointSize = 18
// The share of the canvas the ink takes. The SVG's margins are thrown away here.
let menuBarInkFill = 0.98

// The range actually drawn inside the SVG (the viewBox's 100 coordinate system, y from the top).
func inkBounds(_ img: NSImage, samples n: Int = 400) -> (x: Double, y: Double, w: Double, h: Double) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
    NSGraphicsContext.restoreGraphicsState()

    var minX = n, minY = n, maxX = -1, maxY = -1
    for y in 0..<n {
        for x in 0..<n {
            guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.02 else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    let unit = Double(n) / 100
    return (Double(minX) / unit, Double(minY) / unit,
            Double(maxX - minX + 1) / unit, Double(maxY - minY + 1) / unit)
}

// Throws the margins away and fits the ink to the canvas.
//
// **The same transform has to be applied to all three.** Trimming them one at a time gives every
// picture a different ink width, so the scale drifts and **the mark jumps in size** as it changes
// between idle, running and paused.
// The bounding rectangle is therefore the **union** of the three.
func menuBarTile(_ img: NSImage, _ n: Int, ink: (x: Double, y: Double, w: Double, h: Double)) -> Data {
    let k = Double(n) * menuBarInkFill / max(ink.w, ink.h)
    let side = 100.0 * k
    // `colorAt` has its origin at the top left, drawing at the bottom left. Flip y and centre it.
    let originX = Double(n) / 2 - (ink.x + ink.w / 2) * k
    let originY = Double(n) / 2 - (side - (ink.y + ink.h / 2) * k)
    return canvas(n) {
        img.draw(in: NSRect(x: originX, y: originY, width: side, height: side))
    }
}

print("menu bar")
let menuBarImages = try menuBarStates.map { try image(String(
    contentsOfFile: "\(repo)/docs/images/icons/\($0.1).svg", encoding: .utf8)) }

var ink = inkBounds(menuBarImages[0])
for img in menuBarImages.dropFirst() {
    let b = inkBounds(img)
    let right = max(ink.x + ink.w, b.x + b.w), bottom = max(ink.y + ink.h, b.y + b.h)
    ink.x = min(ink.x, b.x); ink.y = min(ink.y, b.y)
    ink.w = right - ink.x; ink.h = bottom - ink.y
}
print(String(format: "  ink x=%.1f y=%.1f w=%.1f h=%.1f (union of 3)", ink.x, ink.y, ink.w, ink.h))

for (index, state) in menuBarStates.enumerated() {
    let dir = "\(repo)/PomodoroMac/PomodoroMac/Assets.xcassets/\(state.0).imageset"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for scale in [1, 2, 3] {
        try write(menuBarTile(menuBarImages[index], menuBarPointSize * scale, ink: ink),
                  "\(dir)/menu-bar-\(scale)x.png")
    }
    try write(Data("""
    {
      "images" : [
        { "filename" : "menu-bar-1x.png", "idiom" : "universal", "scale" : "1x" },
        { "filename" : "menu-bar-2x.png", "idiom" : "universal", "scale" : "2x" },
        { "filename" : "menu-bar-3x.png", "idiom" : "universal", "scale" : "3x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "template" }
    }

    """.utf8), "\(dir)/Contents.json")
}

// MARK: - macOS

let mac = "\(repo)/PomodoroMac/PomodoroMac/Assets.xcassets/AppIcon.appiconset"
print("macOS")
var entries: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let name = "icon-mac-\(pt)@\(scale)x.png"
        // Whether the detail stays or goes is decided by **the pixel count written out**, not by pt.
        try write(macTile(image(px <= 32 ? withoutDetail(svg) : svg), px), "\(mac)/\(name)")
        entries.append("""
            {
              "filename" : "\(name)",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(pt)x\(pt)"
            }
        """)
    }
}
try write(Data("""
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".utf8), "\(mac)/Contents.json")
