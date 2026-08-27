// Mdoro のアプリアイコンを Tools/mdoro-icon.svg から書き出す。
//
//   swift Tools/make_icon.swift [リポジトリのパス]
//
// PNG を手で置き換えないこと。色や形を変えるときは SVG を直して、これを回す。
// 描画は AppKit の SVG 対応（_NSSVGImageRep）に任せてある。外部ツールは要らない。

import AppKit
import Foundation

let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let svg = try String(contentsOfFile: "\(repo)/Tools/mdoro-icon.svg", encoding: .utf8)

// 色の差し替え表。ライトが SVG に書いてある色そのもの。
// ダークで変えるのは地と `#` だけ。地に対して 1.3 しかない灰は暗所で消えるため。
// 実の中心は赤の上にあり、どちらのモードでも読めるので触らない。
let dark = ["#F7F3ED": "#13110D", "#383A3F": "#ABA497"]
// ティントは明度だけで形を伝える。システムが利用者の色を乗せる。
let tinted = ["#F7F3ED": "#000000", "#383A3F": "#FFFFFF", "#3B3A3F": "#1C1C1C",
              "#8FA08D": "#C9C9C9", "#F2F9E7": "#FFFFFF",
              "#D8563C": "#9A9A9A", "#BC422D": "#767676"]

func recolor(_ source: String, _ map: [String: String]) -> String {
    map.reduce(source) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
}

// 16・32px では細部の線が濁るだけなので外す。
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

// iOS は全面を塗る。角丸は OS が被せる。
func fullBleed(_ img: NSImage, _ n: Int) -> Data {
    canvas(n) { img.draw(in: NSRect(x: 0, y: 0, width: n, height: n)) }
}

// macOS は 1024 のうち中央 824 に収め、角丸 185.4 で抜く。外側は透明。
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

// MARK: - macOS

let mac = "\(repo)/PomodoroMac/PomodoroMac/Assets.xcassets/AppIcon.appiconset"
print("macOS")
var entries: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let name = "icon-mac-\(pt)@\(scale)x.png"
        // 細部を残すか外すかは**出力する画素数**で決める。pt ではない。
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
