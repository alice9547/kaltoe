// 연장수당 계산·표기 — docs/spec.md 5-3절. 시스템 호출 없는 순수 함수 (참고용 표시, 야간·휴일 가산 없음).
import Foundation

enum OvertimePay {
    /// 야근 분 = floor(overtime / 60). 1분이 찰 때마다 오른다.
    static func overtimeMinutes(_ overtime: TimeInterval) -> Int {
        max(0, Int(overtime / 60))
    }

    /// 연장수당(원). 가산율 없이 설정한 단가 그대로 (docs/spec.md 5-3절).
    /// - 시간당: floor(야근 분 × 단가 / 60)
    /// - 분당: 야근 분 × 단가
    /// 단가가 비어 있으면(nil) 시간당 10320원. 정수 연산만 쓴다.
    static func amount(overtimeMinutes: Int, rateAmount: Int?, rateUnit: PayRateUnit) -> Int {
        guard overtimeMinutes > 0 else { return 0 }
        let (rate, unit) = rateAmount.map { ($0, rateUnit) } ?? (WorkSettings.defaultHourlyRate, .hour)
        guard rate > 0 else { return 0 }
        switch unit {
        case .hour: return overtimeMinutes * rate / 60
        case .minute: return overtimeMinutes * rate
        }
    }

    static func amount(overtimeMinutes: Int, settings: WorkSettings) -> Int {
        amount(overtimeMinutes: overtimeMinutes, rateAmount: settings.rateAmount, rateUnit: settings.rateUnit)
    }

    /// 세 자리 쉼표 + `원`. 예: `3,096원`
    static func won(_ amount: Int) -> String {
        let digits = String(abs(amount))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (amount < 0 ? "-" : "") + String(out.reversed()) + "원"
    }

    /// 화면에 보일 수당 정보. done 이고 야근 분이 1 이상일 때만 non-nil (아니면 수당 문구를 전혀 표시하지 않는다).
    struct Display: Equatable {
        var minutes: Int
        /// 원래 계산된 금액.
        var amount: Int
        var comprehensive: Bool
        /// 실제로 보여 줄 금액 (포괄이면 0).
        var shown: Int { comprehensive ? 0 : amount }
    }

    static func display(for s: WorkdaySnapshot, settings: WorkSettings) -> Display? {
        guard s.phase == .done else { return nil }
        let m = overtimeMinutes(s.overtime)
        guard m >= 1 else { return nil }
        return Display(minutes: m,
                       amount: amount(overtimeMinutes: m, settings: settings),
                       comprehensive: settings.comprehensivePay)
    }
}
