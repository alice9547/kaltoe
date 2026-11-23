// TODO(conductor): [마스코트↔맥] 메뉴바 아이콘을 MascotData 기반으로 교체 — MenuBarController 가 아직 MascotArt.templateImage 를 부른다(아래 호환 shim 이 MascotImage 로 연결). 호출부를 MascotImage.menuBarTemplate 로 바꾸면 shim 삭제 가능.
//
// 하얀 말티즈 픽셀 마스코트. 그림 데이터는 MascotData.swift(생성물, 원본 shared/mascot.json).
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
        }
    }

    /// 클릭 점프: 시작 이후 경과 틱 → 위로 뜬 칸 수.
    static let jumpTable = [1, 2, 3, 3, 2, 1]

    static func jumpOffset(tick: Int, jumpStart: Int?) -> Int {
        guard let s = jumpStart, tick >= s, tick - s < jumpTable.count else { return 0 }
        return jumpTable[tick - s]
    }

    /// sleep 의 떠오르는 z (3×3). 머리 오른쪽 위 빈 칸에서 한 칸씩 올라가며 옅어진다.
    static func zPixels(tick: Int) -> [(x: Int, y: Int, alpha: Double)] {
        let step = (tick / 5) % 4          // 0.5초
        guard step < 3 else { return [] }
        let top = 2 - step
        let shape = ["###", "..#", "###"].map(Array.init)
        let alpha = [1.0, 0.8, 0.55][step]
        var out: [(Int, Int, Double)] = []
        for (r, row) in shape.enumerated() {
            for (c, ch) in row.enumerated() where ch == "#" {
                out.append((MascotData.width - 4 + c, top + r, alpha))
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

    /// 약 56pt 영역에 맞는 정수 배율.
    static let cell = max(1, Int((56.0 / Double(MascotData.width)).rounded()))

    var body: some View {
        let cell = CGFloat(Self.cell)
        let rows = MascotData.frames[MascotPlayer.frameName(mood: mood, tick: tick)] ?? []
        let jump = MascotPlayer.jumpOffset(tick: tick, jumpStart: jumpStart)
        let zs = mood == .sleep ? MascotPlayer.zPixels(tick: tick) : []
        let w = MascotData.width, h = MascotData.height
        // 외곽선이 격자 밖 1칸까지 나가므로 그리는 영역에 여유(1칸)를 두고, 레이아웃 크기는 그대로 둔다.
        let margin = outline ? 1 : 0
        let silhouette = outline ? Self.outlineCells(rows) : []
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
                        guard let hex = MascotData.palette[ch] else { continue }
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
    /// 외곽선에서 제외하는 장식 픽셀(색종이 R·Y·N·U, 반짝 별 S). mascot.json 팔레트 규약.
    private static let decoration: Set<Character> = ["R", "Y", "N", "U", "S"]

    /// 불투명 픽셀(장식 제외)의 상하좌우 이웃인 투명 칸(격자 밖 -1…크기 포함).
    static func outlineCells(_ rows: [String]) -> [(x: Int, y: Int)] {
        let grid = rows.map(Array.init)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            y >= 0 && y < grid.count && x >= 0 && x < grid[y].count
                && grid[y][x] != "." && !decoration.contains(grid[y][x])
        }
        var out: [(Int, Int)] = []
        for y in -1...MascotData.height {
            for x in -1...MascotData.width where !opaque(x, y) && !(y >= 0 && y < grid.count && x >= 0 && x < grid[y].count && grid[y][x] != ".") {
                if opaque(x - 1, y) || opaque(x + 1, y) || opaque(x, y - 1) || opaque(x, y + 1) { out.append((x, y)) }
            }
        }
        return out
    }
}

enum MascotImage {
    /// 메뉴바용 템플릿 이미지: 머리 윤곽(검정)에서 눈·코·입은 투명하게 뚫는다.
    static func menuBarTemplate(pointSize: CGFloat) -> NSImage {
        let rows = Array((MascotData.frames["idle"] ?? []).prefix(14))
        let cells = max(MascotData.width, rows.count)
        let k = 4                                   // 셀당 비트맵 픽셀 (부드럽게 축소됨)
        let px = cells * k
        let cutouts: Set<Character> = ["K", "M", "T"]
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

/// 호환 shim — MenuBarController(맥 작업자 소유)가 아직 이 이름을 부른다.
enum MascotArt {
    static func templateImage(size: CGFloat = 16) -> NSImage { MascotImage.menuBarTemplate(pointSize: size) }
}
