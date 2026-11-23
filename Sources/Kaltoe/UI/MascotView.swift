// 픽셀 마스코트(말티즈·주황이). 그림 데이터는 MascotData.swift / MascotDataOrange.swift(생성물, 원본 shared/mascot*.json).
// 재생 규칙은 docs/spec.md 6절.
import AppKit
import SwiftUI

enum MascotPlayer {
    /// mood + tick(0.1초 단위) → 프레임 이름.
    static func frameName(mood: MascotMood, tick: Int) -> String {
        switch mood {
        case .sleep: return "sleep"
        case .idle:
            if tick % 40 >= 38 { return "blink" }            // 4초마다 0.2초 (틱 해상도 0.1초)
            return (tick / 6) % 2 == 0 ? "idle" : "breathe"   // 0.6초
        case .eat: return (tick / 4) % 2 == 0 ? "eat1" : "eat2"        // 0.4초
        case .sparkle: return (tick / 3) % 2 == 0 ? "sparkle" : "hop"  // 0.3초
        case .dance: return (tick / 4) % 2 == 0 ? "danceL" : "danceR"  // 0.4초
        case .angry: return (tick / 3) % 2 == 0 ? "angry1" : "angry2"  // 0.3초 (색종이 없음)
        case .cry: return (tick / 4) % 2 == 0 ? "cry1" : "cry2"        // 0.4초 (색종이 없음)
        }
    }

    /// 클릭 점프: 시작 이후 경과 틱 → 위로 뜬 칸 수.
    static let jumpTable = [1, 2, 3, 3, 2, 1]

    static func jumpOffset(tick: Int, jumpStart: Int?) -> Int {
        guard let s = jumpStart, tick >= s, tick - s < jumpTable.count else { return 0 }
        return jumpTable[tick - s]
    }

    /// sleep 의 떠오르는 z (3×3). 머리 오른쪽 위 빈 칸에서 한 칸씩 올라가며 옅어진다.
    static func zPixels(tick: Int, gridWidth: Int = MascotData.width) -> [(x: Int, y: Int, alpha: Double)] {
        let step = (tick / 5) % 4          // 0.5초
        guard step < 3 else { return [] }
        let top = 2 - step
        let shape = ["###", "..#", "###"].map(Array.init)
        let alpha = [1.0, 0.8, 0.55][step]
        var out: [(Int, Int, Double)] = []
        for (r, row) in shape.enumerated() {
            for (c, ch) in row.enumerated() where ch == "#" {
                out.append((gridWidth - 4 + c, top + r, alpha))
            }
        }
        return out
    }
}

struct MascotView: View {
    var mood: MascotMood
    var tick: Int
    var jumpStart: Int?
    var onTap: () -> Void
    /// true 면 실루엣 바깥에 격자 1칸 두께 외곽선(#3A3A44). 색종이·z 에는 넣지 않는다.
    var outline: Bool = false
    /// 캐릭터 (기본 말티즈). 재생 규칙·외곽선·점프는 캐릭터와 무관.
    var character: MascotCharacter = .maltese

    /// 약 56pt 영역에 맞는 정수 배율 (말티즈 기준 — 기존 호출부 호환).
    static let cell = cell(for: .maltese)
    static func cell(for character: MascotCharacter) -> Int {
        max(1, Int((56.0 / Double(character.width)).rounded()))
    }

    var body: some View {
        let cell = CGFloat(Self.cell(for: character))
        let rows = character.frames[MascotPlayer.frameName(mood: mood, tick: tick)] ?? []
        let jump = MascotPlayer.jumpOffset(tick: tick, jumpStart: jumpStart)
        let zs = mood == .sleep ? MascotPlayer.zPixels(tick: tick, gridWidth: character.width) : []
        let w = character.width, h = character.height
        // 외곽선이 격자 밖 1칸까지 나가므로 그리는 영역에 여유(1칸)를 두고, 레이아웃 크기는 그대로 둔다.
        let margin = outline ? 1 : 0
        let silhouette = outline ? Self.outlineCells(rows, character: character) : []
        Canvas { context, _ in
            context.withCGContext { cg in
                cg.setShouldAntialias(false)
                func fill(_ x: Int, _ y: Int, _ color: CGColor) {
                    cg.setFillColor(color)
                    cg.fill(CGRect(x: CGFloat(x + margin) * cell, y: CGFloat(y + margin) * cell, width: cell, height: cell))
                }
                for z in zs {
                    fill(z.x, z.y, NSColor(hex: 0xC7C7CC, alpha: CGFloat(z.alpha)).cgColor)
                }
                let edge = NSColor(hex: 0x3A3A44).cgColor
                for c in silhouette { fill(c.x, c.y, edge) }
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() {
                        guard let hex = character.palette[ch] else { continue }
                        fill(x, y, NSColor(hex: hex).cgColor)
                    }
                }
            }
        }
        .frame(width: CGFloat(w + 2 * margin) * cell, height: CGFloat(h + 2 * margin) * cell)
        .padding(-CGFloat(margin) * cell)
        .offset(y: -CGFloat(jump) * cell)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

extension MascotView {
    /// 불투명 픽셀(장식 제외)의 상하좌우 이웃인 투명 칸(격자 밖 -1…크기 포함).
    static func outlineCells(_ rows: [String], character: MascotCharacter = .maltese) -> [(x: Int, y: Int)] {
        let decoration = character.decorationPixels
        let grid = rows.map(Array.init)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            y >= 0 && y < grid.count && x >= 0 && x < grid[y].count
                && grid[y][x] != "." && !decoration.contains(grid[y][x])
        }
        var out: [(Int, Int)] = []
        for y in -1...character.height {
            for x in -1...character.width where !opaque(x, y) && !(y >= 0 && y < grid.count && x >= 0 && x < grid[y].count && grid[y][x] != ".") {
                if opaque(x - 1, y) || opaque(x + 1, y) || opaque(x, y - 1) || opaque(x, y + 1) { out.append((x, y)) }
            }
        }
        return out
    }
}

enum MascotImage {
    /// 메뉴바용 템플릿 이미지: 머리 윤곽(검정)에서 눈·코·입은 투명하게 뚫는다.
    static func menuBarTemplate(pointSize: CGFloat, character: MascotCharacter = .maltese) -> NSImage {
        let idle = character.frames["idle"] ?? []
        let range = character.menuBarRows.clamped(to: 0..<idle.count)
        let rows = Array(idle[range])
        let cells = max(character.width, rows.count)
        let k = 4                                   // 셀당 비트맵 픽셀 (부드럽게 축소됨)
        let px = cells * k
        let cutouts = character.menuBarCutouts
        let oy = (cells - rows.count) / 2
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        cg.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." && !cutouts.contains(ch) {
                // CGContext 는 좌하단 원점이라 행을 뒤집는다.
                cg.fill(CGRect(x: c * k, y: px - (r + oy + 1) * k, width: k, height: k))
            }
        }
        let image = NSImage(cgImage: cg.makeImage()!, size: NSSize(width: pointSize, height: pointSize))
        image.isTemplate = true
        return image
    }
}

