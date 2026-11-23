// 계약 파일 — Core(출근 감지)와 UI(위젯·메뉴바)가 만나는 유일한 지점.
// 이 파일은 머리(conductor) 소유. 손은 수정하지 말고, 바꿔야 하면 질문할 것.
import Foundation
import Combine

/// 하루의 진행 단계.
enum WorkPhase: Equatable {
    /// 오늘 출근 기록이 아직 없음 (9시 전이거나, 9시 이후 아직 잠금 해제 전).
    case waiting
    /// 근무 중. 퇴근까지 10분 넘게 남음.
    case working
    /// 퇴근까지 10분 이하 남음.
    case almostDone
    /// 퇴근 시각이 지남.
    case done
}

/// 매초 갱신되는 화면용 상태. UI 는 이것만 읽는다.
struct WorkdaySnapshot: Equatable {
    /// 현재 시각.
    var now: Date
    /// 오늘 출근 시각. waiting 이면 nil.
    var clockIn: Date?
    /// 오늘 퇴근 시각 (clockIn + 9시간). waiting 이면 nil.
    var clockOut: Date?
    /// 퇴근까지 남은 초. waiting·done 이면 0.
    var remaining: TimeInterval
    /// 퇴근 시각을 넘긴 초. done 이 아니면 0.
    var overtime: TimeInterval
    /// 근무 진행률 0...1. waiting 이면 0, done 이면 1.
    var progress: Double
    var phase: WorkPhase

    static func waiting(now: Date = Date()) -> WorkdaySnapshot {
        WorkdaySnapshot(now: now, clockIn: nil, clockOut: nil,
                        remaining: 0, overtime: 0, progress: 0, phase: .waiting)
    }
}

/// Core 가 쓰고 UI 가 읽는 저장소. 메인 스레드에서만 변경한다.
final class WorkdayStore: ObservableObject {
    @Published var snapshot: WorkdaySnapshot = .waiting()
}

/// UI 가 호출하는, UI 바깥의 동작. 실제 구현은 App.swift 에서 꽂는다.
struct AppActions {
    var isLaunchAtLoginEnabled: () -> Bool = { false }
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var quit: () -> Void = {}
}

enum WorkRules {
    /// 출근으로 인정하는 가장 이른 시각 (시).
    static let earliestClockInHour = 9
    /// 근무 시간 (점심 포함).
    static let workDuration: TimeInterval = 9 * 60 * 60
    /// almostDone 으로 넘어가는 기준.
    static let almostDoneThreshold: TimeInterval = 10 * 60
}
