import AppKit

/// 위젯 위치 판정·보정 (docs/spec.md 7절). 화면 의존이 없는 순수 함수.
enum WidgetPlacement {
    /// 화면(visibleFrame)에 가로·세로로 이만큼은 걸쳐 있어야 "찾을 수 있는" 위치로 본다.
    static let minOverlap: CGFloat = 48
    static let margin: CGFloat = 16

    /// 어느 작업 영역에든 가로·세로 `minOverlap` 이상 걸쳐 있는가.
    static func isReachable(_ frame: NSRect, areas: [NSRect]) -> Bool {
        let need = min(minOverlap, frame.width, frame.height)
        return areas.contains { area in
            let i = area.intersection(frame)
            return !i.isNull && i.width >= need && i.height >= need
        }
    }

    /// 닿을 수 있는 위치면 그대로, 아니면 가장 가까운 작업 영역 안으로 통째로 밀어 넣는다.
    static func corrected(_ frame: NSRect, areas: [NSRect]) -> NSRect {
        guard !areas.isEmpty, !isReachable(frame, areas: areas) else { return frame }
        let nearest = areas.min { distance(frame, $0) < distance(frame, $1) }!
        return inside(frame, area: nearest)
    }

    /// `area` 안에 완전히 들어오도록 민다 (더 크면 왼쪽 위 기준).
    static func inside(_ frame: NSRect, area: NSRect) -> NSRect {
        var f = frame
        f.origin.x = min(max(f.origin.x, area.minX), max(area.minX, area.maxX - f.width))
        f.origin.y = min(max(f.origin.y, area.minY), max(area.minY, area.maxY - f.height))
        return f
    }

    /// 주 화면 오른쪽 위, 위·오른쪽 여백 16.
    static func topRightOrigin(size: CGSize, area: NSRect) -> NSPoint {
        NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin)
    }

    /// 두 사각형 사이의 거리 (겹치면 0).
    static func distance(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let dx = max(b.minX - a.maxX, a.minX - b.maxX, 0)
        let dy = max(b.minY - a.maxY, a.minY - b.maxY, 0)
        return (dx * dx + dy * dy).squareRoot()
    }
}
