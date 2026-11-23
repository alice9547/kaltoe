// 오리지널 픽셀 마스코트 — 16×16 격자를 문자 2차원 배열로 정의하고 Canvas 로 찍는다.
import AppKit
import SwiftUI

enum MascotArt {
    static let size = 16
    static let spriteTop = 3

    enum Eyes { case open, closed, sparkle, happy }

    struct Pose {
        var eyes: Eyes = .open
        var leftArmUp = false
        var rightArmUp = false
        var dx = 0
        var dy = 0
        /// 몸 뒤에 깔리는 장식 픽셀 (z, 색종이).
        var extras: [(x: Int, y: Int, c: Character)] = []
    }

    /// B 몸통, S 팔·다리 그늘색, E 눈, W 눈 반짝임. (11행)
    static let baseSprite: [String] = [
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

    static let palette: [Character: UInt32] = [
        "B": 0xE07A4D, "S": 0xB85F38, "E": 0x2B1A12, "W": 0xFFF4D6,
        "z": 0xC7C7CC,
        "r": 0xFF5F57, "y": 0xFEBC2E, "g": 0x28C840, "b": 0x5AC8FA,
    ]

    static func sprite(eyes: Eyes, leftArmUp: Bool, rightArmUp: Bool) -> [[Character]] {
        var g = baseSprite.map { Array($0) }
        switch eyes {
        case .open: break
        case .closed:
            for c in [5, 10] { g[2][c] = "B" }
            for c in [4, 5, 6, 9, 10, 11] { g[3][c] = "E" }
        case .sparkle:
            for r in 2...4 { for c in [4, 5, 10, 11] { g[r][c] = "E" } }
            g[2][4] = "W"; g[2][10] = "W"
        case .happy:
            for c in [5, 10] { g[3][c] = "B" }
            for c in [4, 6, 9, 11] { g[3][c] = "E" }
        }
        if leftArmUp { g[5][1] = "."; g[6][1] = "."; g[1][1] = "S"; g[2][1] = "S" }
        if rightArmUp { g[5][14] = "."; g[6][14] = "."; g[1][14] = "S"; g[2][14] = "S" }
        return g
    }

    static func compose(_ pose: Pose) -> [[Character]] {
        var grid = Array(repeating: Array(repeating: Character("."), count: size), count: size)
        func put(_ x: Int, _ y: Int, _ ch: Character) {
            if x >= 0, x < size, y >= 0, y < size { grid[y][x] = ch }
        }
        for p in pose.extras { put(p.x, p.y, p.c) }
        let s = sprite(eyes: pose.eyes, leftArmUp: pose.leftArmUp, rightArmUp: pose.rightArmUp)
        for (r, row) in s.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                put(c + pose.dx, r + spriteTop + pose.dy, ch)
            }
        }
        return grid
    }

    // MARK: 애니메이션 (tick = 0.1초)

    private static let zShape = ["zzz", ".z.", "zzz"]
    private static let jumpTable = [-1, -2, -3, -3, -2, -1]
    private static let confetti: [(x: Int, y: Int, c: Character)] = [
        (0, 1, "r"), (15, 4, "y"), (2, 0, "g"), (13, 2, "b"), (7, 0, "r"), (10, 1, "y"),
    ]

    static func pose(phase: WorkPhase, tick: Int, jumpStart: Int?) -> Pose {
        var p = Pose()
        switch phase {
        case .waiting:
            let step = tick / 5
            p.eyes = .closed
            p.dy = step % 2
            if let top = [1, 0, 0, nil][step % 4] {
                for (r, row) in zShape.enumerated() {
                    for (c, ch) in row.enumerated() where ch == "z" {
                        p.extras.append((13 + c, top + r, "z"))
                    }
                }
            }
        case .working:
            p.dy = (tick / 5) % 2
            p.eyes = tick % 40 >= 38 ? .closed : .open
        case .almostDone:
            p.eyes = .sparkle
            p.dy = [0, -2, 0, -1][(tick / 2) % 4]
        case .done:
            let step = tick / 4
            p.eyes = .happy
            p.leftArmUp = step % 2 == 0
            p.rightArmUp = !p.leftArmUp
            p.dx = [-1, 0, 1, 0][step % 4]
            p.extras = confetti.map { ($0.x, ($0.y + step) % 8, $0.c) }
        }
        if let start = jumpStart, tick >= start, tick - start < jumpTable.count {
            p.dy += jumpTable[tick - start]
        }
        p.dy = max(p.dy, -spriteTop)
        return p
    }

    // MARK: 메뉴바 템플릿 이미지 (눈은 투명하게 뚫는다)

    static func templateImage(size pt: CGFloat = 16) -> NSImage {
        let grid = compose(Pose())
        let image = NSImage(size: NSSize(width: pt, height: pt), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(false)
            let cell = rect.width / CGFloat(size)
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    if ch == "E" || ch == "W" {
                        ctx.setBlendMode(.clear); ctx.fill(r); ctx.setBlendMode(.normal)
                    } else {
                        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(r)
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MascotView: View {
    var phase: WorkPhase
    var tick: Int
    var jumpStart: Int?
    var onTap: () -> Void

    var body: some View {
        let grid = MascotArt.compose(MascotArt.pose(phase: phase, tick: tick, jumpStart: jumpStart))
        Canvas { context, size in
            let cell = size.width / CGFloat(MascotArt.size)
            context.withCGContext { cg in
                cg.setShouldAntialias(false)
                for (y, row) in grid.enumerated() {
                    for (x, ch) in row.enumerated() {
                        guard let hex = MascotArt.palette[ch] else { continue }
                        cg.setFillColor(NSColor(hex: hex).cgColor)
                        cg.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                    }
                }
            }
        }
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
