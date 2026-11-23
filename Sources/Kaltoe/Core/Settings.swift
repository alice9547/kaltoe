// 설정 모델 — docs/spec.md 1절. 값·기본값·검증은 순수 함수, 저장은 UserDefaults.
import Foundation
import Combine

/// 하루 중 시각 (HH:mm).
struct TimeOfDay: Equatable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// "HH:mm" (24시간제, 0~23 / 0~59). 형식이 맞지 않으면 nil.
    init?(string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(h, m)
    }

    var string: String { String(format: "%02d:%02d", hour, minute) }
    var totalMinutes: Int { hour * 60 + minute }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.totalMinutes < b.totalMinutes }

    /// `day` 가 속한 날의 이 시각 (로컬 달력).
    func date(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0,
                      of: day, matchingPolicy: .nextTime) ?? calendar.startOfDay(for: day)
    }
}

enum WorkMode: String, Equatable {
    case flexible, fixed
}

/// 위젯 모양 (docs/spec.md 1절 `widget.style`).
enum WidgetStyle: String, Equatable {
    case terminal, bubble
}

struct WorkSettings: Equatable {
    var mode: WorkMode = .flexible
    var earliestStart = TimeOfDay(9, 0)
    var workMinutes = 540
    var fixedStart = TimeOfDay(8, 30)
    var fixedEnd = TimeOfDay(17, 30)
    var lunchEnabled = false
    var lunchStart = TimeOfDay(11, 30)
    var lunchEnd = TimeOfDay(13, 0)
    var notifyLunch = true
    var notifyBeforeEnd = true
    var notifyEnd = true
    /// 위젯 글자 크기(px). 위젯 전체 비율 = fontSize / 12.
    var fontSize = 12
    /// 위젯 모양: 터미널 창 / 말풍선(데스크톱 펫).
    var widgetStyle: WidgetStyle = .terminal

    static let fontSizeRange = 8...32
    static let baseFontSize = 12
    static let workMinutesRange = 60...960
    static let `default` = WorkSettings()
}

/// 저장하지 않는 잘못된 값. `message` 는 설정 화면에 빨간 글씨로 보인다.
enum SettingsError: Error, Equatable {
    case workMinutesOutOfRange
    case fixedEndNotAfterStart
    case lunchEndNotAfterStart
    case fontSizeOutOfRange
    case fontSizeNotANumber

    var message: String {
        switch self {
        case .workMinutesOutOfRange: return "근무 시간은 1시간 ~ 16시간이어야 합니다."
        case .fixedEndNotAfterStart: return "퇴근 시각은 출근 시각보다 뒤여야 합니다."
        case .lunchEndNotAfterStart: return "점심 끝은 점심 시작보다 뒤여야 합니다."
        case .fontSizeOutOfRange: return "글자 크기는 8 ~ 32 사이여야 합니다."
        case .fontSizeNotANumber: return "글자 크기는 숫자로 입력해 주세요."
        }
    }
}

enum SettingsValidator {
    /// 지금 쓰이는 값만 검사한다: 유동이면 근무 시간, 고정이면 출·퇴근 시각, 점심은 사용 중일 때만.
    /// (쓰지 않는 칸의 임시 값 때문에 오류가 뜨지 않게 한다.)
    static func validate(_ s: WorkSettings) -> [SettingsError] {
        var errors: [SettingsError] = []
        switch s.mode {
        case .flexible:
            if !WorkSettings.workMinutesRange.contains(s.workMinutes) { errors.append(.workMinutesOutOfRange) }
        case .fixed:
            if !(s.fixedStart < s.fixedEnd) { errors.append(.fixedEndNotAfterStart) }
        }
        if s.lunchEnabled, !(s.lunchStart < s.lunchEnd) { errors.append(.lunchEndNotAfterStart) }
        if !WorkSettings.fontSizeRange.contains(s.fontSize) { errors.append(.fontSizeOutOfRange) }
        return errors
    }

    /// 설정 화면의 글자 크기 입력칸 문자열 → 숫자. 숫자가 아니면 `.fontSizeNotANumber`.
    /// (범위 검사는 `validate` 가 한다.)
    static func parseFontSize(_ text: String) -> Result<Int, SettingsError> {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(t) else {
            return .failure(.fontSizeNotANumber)
        }
        return .success(v)
    }
}

/// UserDefaults 키 (`settings.` + spec 의 키 이름).
enum SettingsKey {
    static let prefix = "settings."
    static let mode = prefix + "mode"
    static let earliestStart = prefix + "flexible.earliestStart"
    static let workMinutes = prefix + "flexible.workMinutes"
    static let fixedStart = prefix + "fixed.start"
    static let fixedEnd = prefix + "fixed.end"
    static let lunchEnabled = prefix + "lunch.enabled"
    static let lunchStart = prefix + "lunch.start"
    static let lunchEnd = prefix + "lunch.end"
    static let notifyLunch = prefix + "notify.lunch"
    static let notifyBeforeEnd = prefix + "notify.beforeEnd"
    static let notifyEnd = prefix + "notify.end"
    static let fontSize = prefix + "widget.fontSize"
    static let widgetStyle = prefix + "widget.style"
}

/// 설정 저장소. 바뀌면 `settings` 를 구독하는 쪽(엔진·화면)이 즉시 반영한다. 메인 스레드에서 쓴다.
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: WorkSettings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    /// 유효하면 저장하고 반영한 뒤 빈 배열, 아니면 저장하지 않고 오류를 돌려준다.
    /// `persist: false` 는 저장 없이 이번 실행에만 반영한다 (확인용 실행 인자).
    @discardableResult
    func update(_ new: WorkSettings, persist: Bool = true) -> [SettingsError] {
        let errors = SettingsValidator.validate(new)
        guard errors.isEmpty else { return errors }
        guard new != settings else { return [] }
        if persist { Self.save(new, to: defaults) }
        settings = new
        return []
    }

    // MARK: 저장·불러오기

    static func load(from d: UserDefaults) -> WorkSettings {
        var s = WorkSettings()
        func time(_ key: String, _ fallback: TimeOfDay) -> TimeOfDay {
            d.string(forKey: key).flatMap(TimeOfDay.init(string:)) ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) as? Bool ?? fallback
        }
        s.mode = d.string(forKey: SettingsKey.mode).flatMap(WorkMode.init(rawValue:)) ?? s.mode
        s.earliestStart = time(SettingsKey.earliestStart, s.earliestStart)
        if let m = d.object(forKey: SettingsKey.workMinutes) as? Int { s.workMinutes = m }
        s.fixedStart = time(SettingsKey.fixedStart, s.fixedStart)
        s.fixedEnd = time(SettingsKey.fixedEnd, s.fixedEnd)
        s.lunchEnabled = flag(SettingsKey.lunchEnabled, s.lunchEnabled)
        s.lunchStart = time(SettingsKey.lunchStart, s.lunchStart)
        s.lunchEnd = time(SettingsKey.lunchEnd, s.lunchEnd)
        s.notifyLunch = flag(SettingsKey.notifyLunch, s.notifyLunch)
        s.notifyBeforeEnd = flag(SettingsKey.notifyBeforeEnd, s.notifyBeforeEnd)
        s.notifyEnd = flag(SettingsKey.notifyEnd, s.notifyEnd)
        if let v = d.object(forKey: SettingsKey.fontSize) as? Int { s.fontSize = v }
        s.widgetStyle = d.string(forKey: SettingsKey.widgetStyle).flatMap(WidgetStyle.init(rawValue:)) ?? s.widgetStyle

        // 손으로 고친 값 등으로 저장값이 잘못됐으면 해당 항목만 기본값으로 되돌린다.
        for error in SettingsValidator.validate(s) {
            switch error {
            case .workMinutesOutOfRange: s.workMinutes = WorkSettings.default.workMinutes
            case .fixedEndNotAfterStart:
                s.fixedStart = WorkSettings.default.fixedStart
                s.fixedEnd = WorkSettings.default.fixedEnd
            case .lunchEndNotAfterStart:
                s.lunchStart = WorkSettings.default.lunchStart
                s.lunchEnd = WorkSettings.default.lunchEnd
            case .fontSizeOutOfRange: s.fontSize = WorkSettings.default.fontSize
            case .fontSizeNotANumber: break
            }
        }
        return s
    }

    static func save(_ s: WorkSettings, to d: UserDefaults) {
        d.set(s.mode.rawValue, forKey: SettingsKey.mode)
        d.set(s.earliestStart.string, forKey: SettingsKey.earliestStart)
        d.set(s.workMinutes, forKey: SettingsKey.workMinutes)
        d.set(s.fixedStart.string, forKey: SettingsKey.fixedStart)
        d.set(s.fixedEnd.string, forKey: SettingsKey.fixedEnd)
        d.set(s.lunchEnabled, forKey: SettingsKey.lunchEnabled)
        d.set(s.lunchStart.string, forKey: SettingsKey.lunchStart)
        d.set(s.lunchEnd.string, forKey: SettingsKey.lunchEnd)
        d.set(s.notifyLunch, forKey: SettingsKey.notifyLunch)
        d.set(s.notifyBeforeEnd, forKey: SettingsKey.notifyBeforeEnd)
        d.set(s.notifyEnd, forKey: SettingsKey.notifyEnd)
        d.set(s.fontSize, forKey: SettingsKey.fontSize)
        d.set(s.widgetStyle.rawValue, forKey: SettingsKey.widgetStyle)
    }
}
