// 사용법: swift Scripts/make-icon.swift  → Resources/AppIcon.icns 생성
import AppKit

let sprite: [String] = [
    "...BBBBBBBBBB...",
    "..BBBBBBBBBBBB..",
    "..BBBEBBBBEBBB..",
    "..BBBEBBBBEBBB..",
    "..BBBBBBBBBBBB..",
    ".SBBBBBBBBBBBBS.",
    ".SBBBBBBBBBBBBS.",
    "..BBBBBBBBBBBB..",
    "...BBBBBBBBBB...",
    "....S.S..S.S....",
    "....S.S..S.S....",
]
let palette: [Character: UInt32] = ["B": 0xE07A4D, "S": 0xB85F38, "E": 0x2B1A12]

func color(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px)
    // macOS 아이콘 여백: 824/1024 비율의 둥근 사각형
    let inset = s * 100 / 1024
    let bg = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    color(0x1B1B1F).setFill()
    NSBezierPath(roundedRect: bg, xRadius: bg.width * 0.225, yRadius: bg.width * 0.225).fill()
    cg.setShouldAntialias(false)
    let cell = (bg.width * 0.62 / 16).rounded(.down).nonZero(1)
    let w = cell * 16, h = cell * CGFloat(sprite.count)
    let ox = ((s - w) / 2).rounded(), oy = ((s - h) / 2).rounded()
    for (r, row) in sprite.enumerated() {
        for (c, ch) in row.enumerated() {
            guard let hex = palette[ch] else { continue }
            color(hex).setFill()
            // 위에서 아래로 그리므로 y 반전
            CGRect(x: ox + CGFloat(c) * cell, y: oy + h - CGFloat(r + 1) * cell,
                   width: cell, height: cell).fill()
        }
    }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

extension CGFloat { func nonZero(_ f: CGFloat) -> CGFloat { self == 0 ? f : self } }

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

try render(1024).write(to: resources.appendingPathComponent("AppIcon-1024.png"))
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "OK: Resources/AppIcon.icns" : "iconutil failed")
exit(p.terminationStatus)
