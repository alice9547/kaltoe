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
        XCTAssertEqual(plain(late).last, "# 야근 중 +0h 12m")
        XCTAssertEqual(plain(snap(now: d(18, 17), clockIn: d(9, 16), clockOut: d(18, 16))).count, 4, "정확히 60초면 표시")
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

    private func bubble(_ s: WorkdaySnapshot) -> String { WidgetText.bubbleText(for: s) }

    func testBubble_allPhases() {
        let lunch = (d(11, 30), d(13, 0))
        XCTAssertEqual(bubble(snap(now: d(8, 0), clockIn: nil, clockOut: nil)), "출근 전…")                       // waiting 유동
        XCTAssertEqual(bubble(snap(now: d(8, 18), clockIn: d(8, 30), clockOut: d(17, 30))), "출근 12분 전")         // waiting 고정
        XCTAssertEqual(bubble(snap(now: d(10, 47, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 43분 전")  // 42m08s → 올림 43
        XCTAssertEqual(bubble(snap(now: d(12, 41, 52), clockIn: d(8, 30), clockOut: d(17, 30), lunch: lunch)), "점심 끝 19분 전")
        XCTAssertEqual(bubble(snap(now: d(15, 14, 59), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근 182분 전")       // 3h01m01s = 181분 01초 → 올림 182
        XCTAssertEqual(bubble(snap(now: d(18, 6, 55), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근 10분 전!")      // 9m05s → 10분
        XCTAssertEqual(bubble(snap(now: d(18, 16), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근하세요!")
        XCTAssertEqual(bubble(snap(now: d(18, 28, 59), clockIn: d(9, 16), clockOut: d(18, 16))), "퇴근하세요! +12분")   // 내림
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
        func done(_ over: TimeInterval) -> String { bubble(snap(now: out.addingTimeInterval(over), clockIn: d(9, 16), clockOut: out)) }
        XCTAssertEqual(done(0), "퇴근하세요!")
        XCTAssertEqual(done(59), "퇴근하세요!")
        XCTAssertEqual(done(60), "퇴근하세요! +1분")
        XCTAssertEqual(done(119), "퇴근하세요! +1분")
        XCTAssertEqual(done(120), "퇴근하세요! +2분")
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
}
