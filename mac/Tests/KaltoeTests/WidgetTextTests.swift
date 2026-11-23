import XCTest
@testable import Kaltoe

/// docs/spec.md 4절 문구.
final class WidgetTextTests: XCTestCase {
    // 문구는 시스템 시간대로 시각을 찍는다. 테스트 날짜는 서울 기준이므로
    // 다른 시간대의 컴퓨터(빌드 서버 등)에서도 같은 결과가 나오게 고정한다.
    private var savedTimeZone: TimeZone!

    override func setUp() {
        super.setUp()
        savedTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Asia/Seoul")!
    }

    override func tearDown() {
        NSTimeZone.default = savedTimeZone
        super.tearDown()
    }

    private func d(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { TestCalendar.date(h, m, s) }

    /// 포괄임금제 끔(연장수당 표시) / 켬(기본값).
    private var normalPay: WorkSettings { var s = WorkSettings(); s.comprehensivePay = false; return s }
    private var comprehensive: WorkSettings { var s = WorkSettings(); s.comprehensivePay = true; return s }

    private func snap(now: Date, clockIn: Date?, clockOut: Date?, lunch: (Date, Date)? = nil) -> WorkdaySnapshot {
        SnapshotCalculator.make(now: now, clockIn: clockIn, clockOut: clockOut, lunchStart: lunch?.0, lunchEnd: lunch?.1)
    }

    private func plain(_ s: WorkdaySnapshot, _ settings: WorkSettings = WorkSettings()) -> [String] {
        WidgetText.lines(for: s, settings: settings).map(\.plain)
    }

    // MARK: 포맷

    func testFormats() {
        XCTAssertEqual(WidgetText.remainingLong(3 * 3600 + 12 * 60 + 8), "3h 12m 08s")
        XCTAssertEqual(WidgetText.remainingLong(12 * 60 + 8), "12m 08s")
        XCTAssertEqual(WidgetText.remainingShort(3 * 3600 + 12 * 60 + 8), "3h 12m")
        XCTAssertEqual(WidgetText.remainingShort(12 * 60 + 8), "12m")
        XCTAssertEqual(WidgetText.remainingShort(42), "42s")
        XCTAssertEqual(WidgetText.progressBar(0.27), "[#####...............] 27%")
        XCTAssertEqual(WidgetText.progressBar(0.41), "[########............] 41%")
        XCTAssertEqual(WidgetText.overtime(12 * 60 + 5), "+0h 12m")
    }

    // MARK: 위젯 줄

    func testWaiting_flexible() {
        let s = snap(now: d(8, 0), clockIn: nil, clockOut: nil)
        XCTAssertEqual(plain(s), ["$ whoami", "아직 출근 전인 사람", "# waiting for first unlock after 09:00..."])
        var custom = WorkSettings(); custom.earliestStart = TimeOfDay(8, 15)
        XCTAssertEqual(plain(s, custom).last, "# waiting for first unlock after 08:15...")
    }

    func testWaiting_fixed() {
        let s = snap(now: d(8, 18), clockIn: d(8, 30), clockOut: d(17, 30))
        XCTAssertEqual(plain(s), ["$ whoami", "아직 출근 전인 사람", "# 출근 08:30 까지 12m"])
        let near = snap(now: d(8, 29, 18), clockIn: d(8, 30), clockOut: d(17, 30))
        XCTAssertEqual(plain(near).last, "# 출근 08:30 까지 42s")
    }

    func testBeforeLunch() {
        // 출근 08:30, 점심 11:30, 지금 10:47:52 → 점심까지 42m 08s
        let s = snap(now: d(10, 47, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: (d(11, 30), d(13, 0)))
        XCTAssertEqual(s.phase, .beforeLunch)
        XCTAssertEqual(plain(s), [
            "$ npm install 점심",
            "installing... 42m 08s left",
            "[#####...............] 25%",
            "in 08:30 → out 17:30",
            "# 점심 11:30 · 퇴근까지 6h 42m",
        ])
    }

    func testLunch() {
        let s = snap(now: d(12, 41, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: (d(11, 30), d(13, 0)))
        XCTAssertEqual(s.phase, .lunch)
        XCTAssertEqual(plain(s), [
            "$ sleep 점심",
            "점심 끝까지 18m 08s",
            "[#########...........] 46%",
            "in 08:30 → out 17:30",
            "# 지금은 밥이 P0 입니다",
        ])
    }

    func testWorking_commentsByProgress() {
        func comment(_ h: Int, _ m: Int) -> String {
            plain(snap(now: d(h, m), clockIn: d(9, 16), clockOut: d(18, 16))).last!
        }
        XCTAssertEqual(comment(10, 0), "# 아직 컴파일 중...")                       // 8%
        XCTAssertEqual(comment(13, 30), "# it works on my machine")                 // 47%
        XCTAssertEqual(comment(15, 0), "# 반 넘었다. 나머지는 미래의 내가")            // 64%
        XCTAssertEqual(comment(17, 0), "# 거의 다 왔다. 금요일 배포만 하지 말자")        // 86%
        let first = plain(snap(now: d(15, 4, 8), clockIn: d(9, 16), clockOut: d(18, 16)))
        XCTAssertEqual(Array(first.prefix(4)), [
            "$ sudo 퇴근 --force", "Permission denied: 3h 11m 52s left", "[############........] 64%", "in 09:16 → out 18:16"])
    }

    func testWorking_noonCommentOnlyWhenLunchUnused() {
        let s = snap(now: d(12, 30), clockIn: d(9, 16), clockOut: d(18, 16))   // 점심 미사용, 12시대
        XCTAssertEqual(plain(s).last, "# 점심: 일단 밥부터 먹고 생각하자")
        XCTAssertEqual(plain(snap(now: d(11, 59, 59), clockIn: d(9, 16), clockOut: d(18, 16))).last, "# it works on my machine")
        XCTAssertEqual(plain(snap(now: d(13, 0), clockIn: d(9, 16), clockOut: d(18, 16))).last, "# it works on my machine")
        // 점심 사용 중이면 12시대(점심 끝난 뒤)에도 일반 주석
        var lunchOn = WorkSettings(); lunchOn.lunchEnabled = true
        lunchOn.lunchStart = TimeOfDay(11, 0); lunchOn.lunchEnd = TimeOfDay(12, 10)
        let after = snap(now: d(12, 30), clockIn: d(9, 16), clockOut: d(18, 16), lunch: (d(11, 0), d(12, 10)))
        XCTAssertEqual(after.phase, .working)
        XCTAssertEqual(plain(after, lunchOn).last, "# it works on my machine")
    }

    func testAlmostDone() {
        let s = snap(now: d(18, 6, 55), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertEqual(plain(s), [
            "$ git commit -m \"퇴근 준비\"", "9m 05s left", "[###################.] 98%",
            "in 09:16 → out 18:16", "# 지금 배포하면 안 됩니다",
        ])
    }

    func testDone_withAndWithoutOvertime() {
        let early = snap(now: d(18, 16, 59), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertEqual(plain(early), ["$ exit", "Process finished with exit code 0", "퇴근하세요! out 18:16"])
        let late = snap(now: d(18, 28, 30), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertEqual(plain(late, normalPay), ["$ exit", "Process finished with exit code 0", "퇴근하세요! out 18:16",
                                                "# 야근 중 +0h 12m", "# 연장수당 +2,064원"])
        XCTAssertEqual(plain(snap(now: d(18, 17), clockIn: d(9, 16), clockOut: d(18, 16))).count, 5, "정확히 60초면 야근 줄과 수당 줄 표시")
    }

    func testLineStyles_forNewPhases() {
        let before = WidgetText.lines(for: snap(now: d(10, 47, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: (d(11, 30), d(13, 0))))
        XCTAssertEqual(before[1].spans.map(\.style), [.output, .accent, .output])
        XCTAssertEqual(before[4].spans.map(\.style), [.comment])
        let lunch = WidgetText.lines(for: snap(now: d(12, 0), clockIn: d(8, 30), clockOut: d(17, 30), lunch: (d(11, 30), d(13, 0))))
        XCTAssertEqual(lunch[1].spans.map(\.style), [.output, .accent])
    }

    // MARK: 메뉴바 한 줄

    func testMenuBarTitles() {
        let lunch = (d(11, 30), d(13, 0))
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(8, 0), clockIn: nil, clockOut: nil)), "출근 전")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(8, 18), clockIn: d(8, 30), clockOut: d(17, 30))), "출근 전")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(10, 47, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심까지 42m")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(12, 41, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 끝까지 18m")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(15, 4, 8), clockIn: d(9, 16), clockOut: d(18, 16))), "18:16까지 3h 11m")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(18, 6, 55), clockIn: d(9, 16), clockOut: d(18, 16))), "18:16까지 9m")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(18, 16, 30), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근!")
        XCTAssertEqual(WidgetText.menuBarTitle(for: snap(now: d(18, 28, 30), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근! +12m")
    }

    // MARK: 메뉴 항목

    func testMenuItemTitles() {
        let working = snap(now: d(12, 0), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertEqual(WidgetText.clockInMenuTitle(for: working), "출근 09:16")
        XCTAssertEqual(WidgetText.clockOutMenuTitle(for: working), "퇴근 18:16")
        let none = snap(now: d(8, 0), clockIn: nil, clockOut: nil)
        XCTAssertEqual(WidgetText.clockInMenuTitle(for: none), "출근 기록 없음")
        XCTAssertNil(WidgetText.clockOutMenuTitle(for: none))
        let fixedWaiting = snap(now: d(8, 0), clockIn: d(8, 30), clockOut: d(17, 30))   // 고정 모드 출근 전에도 설정 시각 표시
        XCTAssertEqual(WidgetText.clockInMenuTitle(for: fixedWaiting), "출근 08:30")
        XCTAssertEqual(WidgetText.clockOutMenuTitle(for: fixedWaiting), "퇴근 17:30")
    }

    func testLunchMenuTitle_onlyWhenEnabled() {
        var s = WorkSettings()
        XCTAssertNil(WidgetText.lunchMenuTitle(for: s))
        s.lunchEnabled = true
        XCTAssertEqual(WidgetText.lunchMenuTitle(for: s), "점심 11:30–13:00")
    }

    // MARK: 설정 미리보기

    func testPreviewLine() {
        let cal = TestCalendar.seoul
        var s = WorkSettings(); s.mode = .fixed; s.lunchEnabled = true
        XCTAssertEqual(WidgetText.previewLine(settings: s, detectedClockIn: nil, now: d(10, 0), calendar: cal),
                       "출근 08:30 · 점심 11:30–13:00 · 퇴근 17:30")
        s.lunchEnabled = false
        XCTAssertEqual(WidgetText.previewLine(settings: s, detectedClockIn: nil, now: d(10, 0), calendar: cal),
                       "출근 08:30 · 퇴근 17:30")
        s.mode = .flexible
        XCTAssertEqual(WidgetText.previewLine(settings: s, detectedClockIn: nil, now: d(10, 0), calendar: cal),
                       "출근 — · 퇴근 —")
        XCTAssertEqual(WidgetText.previewLine(settings: s, detectedClockIn: d(9, 16), now: d(10, 0), calendar: cal),
                       "출근 09:16 · 퇴근 18:16")
    }

    // MARK: 마스코트 기분 매핑

    func testMascotMoodMapping() {
        XCTAssertEqual(MascotMood(phase: .waiting), .sleep)
        XCTAssertEqual(MascotMood(phase: .beforeLunch), .idle)
        XCTAssertEqual(MascotMood(phase: .lunch), .eat)
        XCTAssertEqual(MascotMood(phase: .working), .idle)
        XCTAssertEqual(MascotMood(phase: .almostDone), .sparkle)
        XCTAssertEqual(MascotMood(phase: .done), .dance)
    }

    // MARK: 말풍선 (spec 5-2절)

    private func bubble(_ s: WorkdaySnapshot, _ settings: WorkSettings = WorkSettings()) -> String { WidgetText.bubbleText(for: s, settings: settings) }

    func testBubble_allPhases() {
        let lunch = (d(11, 30), d(13, 0))
        XCTAssertEqual(bubble(snap(now: d(8, 0), clockIn: nil, clockOut: nil)), "출근 전…")                       // waiting 유동
        XCTAssertEqual(bubble(snap(now: d(8, 18), clockIn: d(8, 30), clockOut: d(17, 30))), "출근 12분 전")         // waiting 고정
        XCTAssertEqual(bubble(snap(now: d(10, 47, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 43분 전")  // 42m08s → 올림 43
        XCTAssertEqual(bubble(snap(now: d(12, 41, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 끝 19분 전")
        XCTAssertEqual(bubble(snap(now: d(15, 14, 59), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근 182분 전")       // 3h01m01s = 181분 01초 → 올림 182
        XCTAssertEqual(bubble(snap(now: d(18, 6, 55), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근 10분 전!")      // 9m05s → 10분
        XCTAssertEqual(bubble(snap(now: d(18, 16), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근하세요!")
        XCTAssertEqual(bubble(snap(now: d(18, 28, 59), clockIn: d(9, 16), clockOut: d(18, 16)), normalPay), "야근 12분 · +2,064원")   // 내림 + 연장수당
    }

    func testBubble_spec_examples() {
        // 표의 예시 값: 176분 01초 → 177분, 42분 → 42분 전, 18분 → 18분 전, 9분 → 9분 전
        XCTAssertEqual(bubble(snap(now: d(18, 16).addingTimeInterval(-(176 * 60 + 1)), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근 177분 전")
        let lunch = (d(11, 30), d(13, 0))
        XCTAssertEqual(bubble(snap(now: d(11, 30).addingTimeInterval(-42 * 60), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 42분 전")
        XCTAssertEqual(bubble(snap(now: d(13, 0).addingTimeInterval(-18 * 60), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 끝 18분 전")
        XCTAssertEqual(bubble(snap(now: d(18, 16).addingTimeInterval(-9 * 60), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근 9분 전!")
    }

    func testBubble_ceilBoundaries() {
        XCTAssertEqual(WidgetText.ceilMinutes(0.5), 1)
        XCTAssertEqual(WidgetText.ceilMinutes(1), 1)
        XCTAssertEqual(WidgetText.ceilMinutes(30), 1)
        XCTAssertEqual(WidgetText.ceilMinutes(60), 1)          // 60초 → 1분
        XCTAssertEqual(WidgetText.ceilMinutes(61), 2)          // 61초 → 2분
        XCTAssertEqual(WidgetText.ceilMinutes(120), 2)
        XCTAssertEqual(WidgetText.ceilMinutes(121), 3)
        XCTAssertEqual(WidgetText.ceilMinutes(176 * 60 + 1), 177)
        XCTAssertEqual(WidgetText.ceilMinutes(0), 1, "0 은 문구에 나오지 않지만 0분이 되지는 않는다")
        // 문구에서도: 퇴근 직전 마지막 1초, 60초, 61초
        let out = d(18, 16)
        func working(_ left: TimeInterval) -> String {
            bubble(snap(now: out.addingTimeInterval(-left), clockIn: d(9, 16), clockOut: out))
        }
        XCTAssertEqual(working(1), "퇴근 1분 전!")
        XCTAssertEqual(working(60), "퇴근 1분 전!")
        XCTAssertEqual(working(61), "퇴근 2분 전!")
        XCTAssertEqual(working(600), "퇴근 10분 전!")
        XCTAssertEqual(working(601), "퇴근 11분 전")           // almostDone 경계(10분)를 넘으면 working → ! 없음
    }

    func testBubble_overtimeFloorsAndNeedsOneMinute() {
        let out = d(18, 16)
        func done(_ over: TimeInterval) -> String { bubble(snap(now: out.addingTimeInterval(over), clockIn: d(9, 16), clockOut: out), normalPay) }
        XCTAssertEqual(done(0), "퇴근하세요!")
        XCTAssertEqual(done(59), "퇴근하세요!")
        XCTAssertEqual(done(60), "야근 1분 · +172원")
        XCTAssertEqual(done(119), "야근 1분 · +172원")
        XCTAssertEqual(done(120), "야근 2분 · +344원")
    }

    func testBubble_fixedWaitingRoundsUp() {
        XCTAssertEqual(bubble(snap(now: d(8, 29, 30), clockIn: d(8, 30), clockOut: d(17, 30))), "출근 1분 전")
        XCTAssertEqual(bubble(snap(now: d(8, 28, 59), clockIn: d(8, 30), clockOut: d(17, 30))), "출근 2분 전")
    }

    // MARK: 마스코트 크기 (정수 칸)

    func testMascotCellSize_nearestInteger() {
        // 격자 20칸 기준: 터미널 56 → 3칸(60pt), 말풍선 60 → 3칸
        XCTAssertEqual(ScaledMascot.cellSize(baseSize: 56, ratio: 1, gridWidth: 20), 3)
        XCTAssertEqual(ScaledMascot.cellSize(baseSize: 60, ratio: 1, gridWidth: 20), 3)
        XCTAssertEqual(ScaledMascot.cellSize(baseSize: 60, ratio: 8.0 / 12, gridWidth: 20), 2)    // 40pt
        XCTAssertEqual(ScaledMascot.cellSize(baseSize: 60, ratio: 2, gridWidth: 20), 6)
        XCTAssertEqual(ScaledMascot.cellSize(baseSize: 60, ratio: 32.0 / 12, gridWidth: 20), 8)   // 160pt
        XCTAssertEqual(ScaledMascot.cellSize(baseSize: 1, ratio: 0.1, gridWidth: 20), 1, "최소 1칸")
    }

    // MARK: 연장수당 (spec 5-3절, 기본 = 시간당 10,320원)

    private func doneSnap(overMinutes: Double, extraSeconds: Double = 0) -> WorkdaySnapshot {
        let out = d(18, 16)
        return snap(now: out.addingTimeInterval(overMinutes * 60 + extraSeconds), clockIn: d(9, 16), clockOut: out)
    }

    func testPay_defaultIsComprehensive() {
        XCTAssertTrue(WorkSettings().comprehensivePay)
        XCTAssertEqual(plain(doneSnap(overMinutes: 12)).last, "# 포괄이라 0원 (원래 +2,064원)")
    }

    func testPay_terminalLastLine() {
        let s = doneSnap(overMinutes: 12)
        XCTAssertEqual(plain(s, normalPay), ["$ exit", "Process finished with exit code 0", "퇴근하세요! out 18:16",
                                             "# 야근 중 +0h 12m", "# 연장수당 +2,064원"])
        XCTAssertEqual(plain(s, comprehensive), ["$ exit", "Process finished with exit code 0", "퇴근하세요! out 18:16",
                                                 "# 야근 중 +0h 12m", "# 포괄이라 0원 (원래 +2,064원)"])
        XCTAssertEqual(plain(s, normalPay).count, 5, "working 단계와 같은 5줄")
    }

    func testPay_terminalAccentSpans() {
        let normal = WidgetText.lines(for: doneSnap(overMinutes: 12), settings: normalPay).last!
        XCTAssertEqual(normal.spans.filter { $0.style == .accent }.map(\.text), ["+2,064원"])
        let flat = WidgetText.lines(for: doneSnap(overMinutes: 12), settings: comprehensive).last!
        XCTAssertEqual(flat.spans.filter { $0.style == .accent }.map(\.text), ["0원"])
    }

    func testPay_noPayTextBelowOneMinute() {
        for s in [doneSnap(overMinutes: 0), doneSnap(overMinutes: 0, extraSeconds: 59)] {
            for settings in [normalPay, comprehensive] {
                XCTAssertEqual(plain(s, settings), ["$ exit", "Process finished with exit code 0", "퇴근하세요! out 18:16"])
                XCTAssertEqual(WidgetText.bubbleText(for: s, settings: settings), "퇴근하세요!")
                XCTAssertNil(WidgetText.overtimePayMenuTitle(for: s, settings: settings))
            }
        }
    }

    func testPay_bubble() {
        let s = doneSnap(overMinutes: 12)
        XCTAssertEqual(WidgetText.bubbleText(for: s, settings: normalPay), "야근 12분 · +2,064원")
        XCTAssertEqual(WidgetText.bubbleText(for: s, settings: comprehensive), "야근 12분 · 0원 (포괄)")
    }

    func testPay_menuItem() {
        let s = doneSnap(overMinutes: 12)
        XCTAssertEqual(WidgetText.overtimePayMenuTitle(for: s, settings: normalPay), "연장수당 +2,064원")
        XCTAssertEqual(WidgetText.overtimePayMenuTitle(for: s, settings: comprehensive), "연장수당 0원 (포괄)")
    }

    func testPay_notShownBeforeDone() {
        let working = snap(now: d(15, 0), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertNil(WidgetText.overtimePayMenuTitle(for: working, settings: normalPay))
        XCTAssertNil(OvertimePay.display(for: working, settings: normalPay))
    }

    func testPay_menuBarLineUnchanged() {
        XCTAssertEqual(WidgetText.menuBarTitle(for: doneSnap(overMinutes: 12)), "퇴근! +12m")
    }

    func testPay_customRates() {
        var perMinute = normalPay; perMinute.rateAmount = 300; perMinute.rateUnit = .minute
        XCTAssertEqual(WidgetText.bubbleText(for: doneSnap(overMinutes: 12), settings: perMinute), "야근 12분 · +3,600원")
        var perHour = normalPay; perHour.rateAmount = 20000; perHour.rateUnit = .hour
        XCTAssertEqual(WidgetText.bubbleText(for: doneSnap(overMinutes: 12), settings: perHour), "야근 12분 · +4,000원")
        perHour.comprehensivePay = true
        XCTAssertEqual(plain(doneSnap(overMinutes: 12), perHour).last, "# 포괄이라 0원 (원래 +4,000원)")
    }

    // MARK: 마스코트 기분 (spec 6절)

    func testMood_overtimeDecidesAngryOrCry() {
        let overtime = doneSnap(overMinutes: 12)
        XCTAssertEqual(MascotMood.resolve(overtime, settings: normalPay), .angry)
        XCTAssertEqual(MascotMood.resolve(overtime, settings: comprehensive), .cry)
        XCTAssertEqual(MascotMood.resolve(doneSnap(overMinutes: 1), settings: normalPay), .angry)
        XCTAssertEqual(MascotMood.resolve(doneSnap(overMinutes: 1), settings: comprehensive), .cry)
    }

    func testMood_doneWithoutOvertimeStillDances() {
        for s in [doneSnap(overMinutes: 0), doneSnap(overMinutes: 0, extraSeconds: 59)] {
            XCTAssertEqual(MascotMood.resolve(s, settings: normalPay), .dance)
            XCTAssertEqual(MascotMood.resolve(s, settings: comprehensive), .dance)
        }
    }

    func testMood_otherPhasesFollowPhase() {
        let working = snap(now: d(15, 0), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertEqual(MascotMood.resolve(working, settings: comprehensive), .idle)
        let almost = snap(now: d(18, 10), clockIn: d(9, 16), clockOut: d(18, 16))
        XCTAssertEqual(MascotMood.resolve(almost, settings: normalPay), .sparkle)
        let waiting = snap(now: d(8, 0), clockIn: nil, clockOut: nil)
        XCTAssertEqual(MascotMood.resolve(waiting, settings: normalPay), .sleep)
    }
}

/// 연장수당 계산·표기 순수 함수.
final class OvertimePayTests: XCTestCase {
    private func pay(_ minutes: Int, _ amount: Int? = nil, _ unit: PayRateUnit = .hour) -> Int {
        OvertimePay.amount(overtimeMinutes: minutes, rateAmount: amount, rateUnit: unit)
    }

    func testAmount_defaultIsMinimumHourlyWage() {
        XCTAssertEqual(pay(0), 0)
        XCTAssertEqual(pay(1), 172)          // 10320 / 60
        XCTAssertEqual(pay(12), 2064)
        XCTAssertEqual(pay(60), 10320)
        XCTAssertEqual(pay(80), 13760)
        XCTAssertEqual(pay(1, nil, .minute), 172, "단가가 비면 단위 설정은 무시")
    }

    func testAmount_perMinute() {
        XCTAssertEqual(pay(12, 300, .minute), 3600)
        XCTAssertEqual(pay(1, 1, .minute), 1)
        XCTAssertEqual(pay(0, 300, .minute), 0)
    }

    func testAmount_perHour_floors() {
        XCTAssertEqual(pay(12, 20000, .hour), 4000)
        XCTAssertEqual(pay(1, 59, .hour), 0)           // 59/60 → 0
        XCTAssertEqual(pay(1, 60, .hour), 1)
        XCTAssertEqual(pay(7, 10001, .hour), 1166)     // 70007/60 = 1166.78
        XCTAssertEqual(pay(60, 10_000_000, .hour), 10_000_000)
    }

    func testAmount_noMultiplier() {
        XCTAssertEqual(pay(60, 10320, .hour), 10320, "가산율 1.5 를 곱하지 않는다")
    }

    func testOvertimeMinutes_floor() {
        XCTAssertEqual(OvertimePay.overtimeMinutes(0), 0)
        XCTAssertEqual(OvertimePay.overtimeMinutes(59.9), 0)
        XCTAssertEqual(OvertimePay.overtimeMinutes(60), 1)
        XCTAssertEqual(OvertimePay.overtimeMinutes(119.9), 1)
        XCTAssertEqual(OvertimePay.overtimeMinutes(-5), 0)
    }

    func testWon_commas() {
        XCTAssertEqual(OvertimePay.won(0), "0원")
        XCTAssertEqual(OvertimePay.won(172), "172원")
        XCTAssertEqual(OvertimePay.won(999), "999원")
        XCTAssertEqual(OvertimePay.won(1000), "1,000원")
        XCTAssertEqual(OvertimePay.won(2064), "2,064원")
        XCTAssertEqual(OvertimePay.won(10320), "10,320원")
        XCTAssertEqual(OvertimePay.won(1_500_000), "1,500,000원")
    }
}
