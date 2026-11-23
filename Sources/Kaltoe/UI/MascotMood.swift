// 마스코트의 기분. 재생 규칙은 docs/spec.md 6절.
enum MascotMood: Equatable {
    case sleep, idle, eat, sparkle, dance
}

extension MascotMood {
    /// 단계 → 기분. 새 단계가 추가되면 여기에 명시한다 (docs/spec.md 6절).
    init(phase: WorkPhase) {
        switch phase {
        case .waiting: self = .sleep
        case .almostDone: self = .sparkle
        case .done: self = .dance
        default: self = .idle
        }
    }
}
