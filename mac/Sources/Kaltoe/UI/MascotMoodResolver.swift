// 마스코트 기분 결정 — 단계 + 야근 분 + 포괄임금제 여부 (docs/spec.md 6절 표).
// enum 케이스 선언(MascotMood.swift)과 재생(MascotView)은 마스코트 쪽 소유이고, 여기서는 고르기만 한다.
extension MascotMood {
    /// - done 이고 야근 분 ≥ 1: 포괄 아님 → angry, 포괄 → cry
    /// - 그 외(야근 분 0 인 done 포함): 단계 기반 매핑 (done → dance)
    static func resolve(_ s: WorkdaySnapshot, settings: WorkSettings) -> MascotMood {
        if let pay = OvertimePay.display(for: s, settings: settings) {
            return pay.comprehensive ? .cry : .angry
        }
        return MascotMood(phase: s.phase)
    }
}
