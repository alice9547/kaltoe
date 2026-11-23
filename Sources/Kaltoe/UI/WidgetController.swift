// 스텁 — 워크스트림 B 가 구현한다.
import AppKit

/// 항상 최상단에 뜨는 플로팅 위젯 창.
final class WidgetController {
    init(store: WorkdayStore) {}

    var isVisible: Bool { false }
    func show() {}
    func hide() {}
}
