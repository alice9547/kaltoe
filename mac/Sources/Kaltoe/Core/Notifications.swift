// 퇴근 알림 — 계획(순수 함수)과 실제 예약(UNUserNotificationCenter)을 분리한다.
import Foundation
import UserNotifications

struct PlannedNotification: Equatable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

enum NotificationPlanner {
    static let lunchBody = "점심 시간입니다 — npm install 점심"
    static let warningBody = "퇴근 10분 전 — 지금 배포하면 안 됩니다"
    static let doneBody = "Process finished with exit code 0 — 퇴근하세요"

    /// 하루치 알림 식별자 전부 (재예약 때 먼저 취소한다). 식별자에 날짜가 들어가므로 같은 날 같은 알림은 하나뿐.
    static func identifiers(day: String) -> [String] {
        ["kaltoe.lunch.\(day)", "kaltoe.clockOut.warning.\(day)", "kaltoe.clockOut.done.\(day)"]
    }

    /// spec 4절 알림 표. 설정에서 꺼진 것·이미 지난 시각·(점심은) 유효하지 않은 점심은 제외한다.
    static func plan(times: DaySchedule.Times, settings: WorkSettings, now: Date,
                     calendar: Calendar) -> [PlannedNotification] {
        guard let clockIn = times.clockIn, let clockOut = times.clockOut else { return [] }
        let day = ClockInRules.dayKey(clockIn, calendar: calendar)
        let ids = identifiers(day: day)
        var plans: [PlannedNotification] = []

        if settings.notifyLunch,
           let lunch = SnapshotCalculator.validLunch(clockIn: clockIn, clockOut: clockOut, lunch: times.lunch) {
            plans.append(PlannedNotification(identifier: ids[0], fireDate: lunch.start,
                                             title: "칼퇴", body: lunchBody))
        }
        if settings.notifyBeforeEnd {
            plans.append(PlannedNotification(
                identifier: ids[1], fireDate: clockOut.addingTimeInterval(-WorkRules.almostDoneThreshold),
                title: "칼퇴", body: warningBody))
        }
        if settings.notifyEnd {
            plans.append(PlannedNotification(identifier: ids[2], fireDate: clockOut,
                                             title: "칼퇴", body: doneBody))
        }
        return plans.filter { $0.fireDate > now }
    }
}

/// 실제 알림 센터 래퍼.
/// `swift run` 처럼 번들 식별자가 없으면 UNUserNotificationCenter 를 건드리는 순간 크래시하므로
/// 모든 진입점에서 먼저 막는다.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// 권한 요청 (엔진 start() 에서 한 번).
    func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Kaltoe: 알림 권한 요청 실패: \(error)") }
        }
    }

    /// 그날의 예약을 모두 취소한 뒤 `plans` 를 다시 예약한다.
    func replace(day: String, with plans: [PlannedNotification], calendar: Calendar) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: NotificationPlanner.identifiers(day: day))
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            // 달력 트리거: 잠자기 중이어도 시각이 지나면 깨어나는 즉시 전달된다.
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // 같은 식별자는 덮어쓰기 — 같은 날 중복 예약이 생기지 않는다.
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            center.add(request) { error in
                if let error { NSLog("Kaltoe: 알림 예약 실패(\(plan.identifier)): \(error)") }
            }
        }
    }

    // 앱이 앞에 떠 있어도(위젯) 배너를 보여준다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
