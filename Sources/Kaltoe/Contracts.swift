// 계약 파일 — Core(출근 감지)와 UI(위젯·메뉴바)가 만나는 유일한 지점.
import Foundation
import Combine

/// 하루의 진행 단계. 결정 순서는 docs/spec.md 3절 표.
enum WorkPhase: Equatable {
    /// 출근 시각이 없음 (유동: 오늘 기록 없음 / 고정: 아직 출근 시각 전).
    case waiting
    /// 점심 시작 전 (점심이 유효할 때).
    case beforeLunch
    /// 점심 시간 중.
    case lunch
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
    /// 오늘 출근 시각. 유동 모드에서 기록이 없으면 nil. (고정 모드는 출근 전에도 설정 시각이 들어 있다.)
    var clockIn: Date?
    /// 오늘 퇴근 시각. clockIn 이 없으면 nil.
    var clockOut: Date?
    /// 점심 시작·끝. 점심이 유효할 때만 (spec 3절: 사용 중 && clockIn < lunchEnd && lunchStart < clockOut).
    var lunchStart: Date?
    var lunchEnd: Date?
    /// 지금 세고 있는 목표 시각 (beforeLunch→lunchStart, lunch→lunchEnd, working·almostDone→clockOut,
    /// 고정 모드 waiting→clockIn). 없으면 nil.
    var target: Date?
    /// target 까지 남은 초. target 이 없으면 0.
    var remaining: TimeInterval
    /// 퇴근까지 남은 초 (0 이상). clockOut 이 없으면 0.
    var remainingToClockOut: TimeInterval
    /// 퇴근 시각을 넘긴 초. done 이 아니면 0.
    var overtime: TimeInterval
    /// 근무 진행률 0...1 = (now−clockIn)/(clockOut−clockIn). waiting 이면 0, done 이면 1.
    var progress: Double
    var phase: WorkPhase

    static func waiting(now: Date = Date()) -> WorkdaySnapshot {
        WorkdaySnapshot(now: now, clockIn: nil, clockOut: nil, lunchStart: nil, lunchEnd: nil,
                        target: nil, remaining: 0, remainingToClockOut: 0,
                        overtime: 0, progress: 0, phase: .waiting)
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
    /// 설정 창을 연다 (이미 열려 있으면 앞으로).
    var openSettings: () -> Void = {}
    /// "오늘 출근 다시 감지" (유동 모드).
    var redetectToday: () -> Void = {}
}

enum WorkRules {
    /// almostDone 으로 넘어가는 기준. (출근·근무 시간 등 나머지 값은 설정 — Core/Settings.swift)
    static let almostDoneThreshold: TimeInterval = 10 * 60
}
