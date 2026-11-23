// 스텁 — 워크스트림 A 가 구현한다.
import Foundation

/// 출근 시각을 감지·저장하고 매초 store.snapshot 을 갱신한다.
final class WorkdayEngine {
    private let store: WorkdayStore

    init(store: WorkdayStore) {
        self.store = store
    }

    /// 감지와 1초 타이머를 시작한다. 메인 스레드에서 호출.
    func start() {}
}
