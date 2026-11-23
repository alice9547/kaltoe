import XCTest
import Combine
@testable import Kaltoe

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "kaltoe.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testDefaultsMatchSpec() {
        let s = WorkSettings()
        XCTAssertEqual(s.mode, .flexible)
        XCTAssertEqual(s.earliestStart, TimeOfDay(9, 0))
        XCTAssertEqual(s.workMinutes, 540)
        XCTAssertEqual(s.fixedStart, TimeOfDay(8, 30)); XCTAssertEqual(s.fixedEnd, TimeOfDay(17, 30))
        XCTAssertFalse(s.lunchEnabled)
        XCTAssertEqual(s.lunchStart, TimeOfDay(11, 30)); XCTAssertEqual(s.lunchEnd, TimeOfDay(13, 0))
        XCTAssertTrue(s.notifyLunch && s.notifyBeforeEnd && s.notifyEnd)
        XCTAssertEqual(s.fontSize, 12)
        XCTAssertEqual(s.widgetStyle, .terminal)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, s)
    }

    func testTimeOfDayParsing() {
        XCTAssertEqual(TimeOfDay(string: "08:30"), TimeOfDay(8, 30))
        XCTAssertEqual(TimeOfDay(string: "23:59"), TimeOfDay(23, 59))
        for bad in ["8:30", "24:00", "12:60", "ab:cd", "", "12-30", "12:3", "1230"] {
            XCTAssertNil(TimeOfDay(string: bad), bad)
        }
        XCTAssertEqual(TimeOfDay(7, 5).string, "07:05")
    }

    // MARK: 검증

    func testValidation_defaultsAreValid() {
        XCTAssertEqual(SettingsValidator.validate(WorkSettings()), [])
    }

    func testValidation_workMinutesRange() {
        var s = WorkSettings()
        for ok in [60, 540, 960] { s.workMinutes = ok; XCTAssertEqual(SettingsValidator.validate(s), [], "\(ok)") }
        for bad in [0, 59, 961, -1] {
            s.workMinutes = bad
            XCTAssertEqual(SettingsValidator.validate(s), [.workMinutesOutOfRange], "\(bad)")
        }
    }

    func testValidation_fixedEndMustBeAfterStart() {
        var s = WorkSettings(); s.mode = .fixed
        s.fixedStart = TimeOfDay(9, 0); s.fixedEnd = TimeOfDay(9, 0)
        XCTAssertEqual(SettingsValidator.validate(s), [.fixedEndNotAfterStart])
        s.fixedEnd = TimeOfDay(8, 59)
        XCTAssertEqual(SettingsValidator.validate(s), [.fixedEndNotAfterStart])
        s.fixedEnd = TimeOfDay(9, 1)
        XCTAssertEqual(SettingsValidator.validate(s), [])
    }

    func testValidation_unusedModeFieldsAreNotChecked() {
        var s = WorkSettings()                                // 유동 모드
        s.fixedStart = TimeOfDay(18, 0); s.fixedEnd = TimeOfDay(9, 0)
        XCTAssertEqual(SettingsValidator.validate(s), [])
        s.mode = .fixed; s.workMinutes = 5                    // 고정 모드
        s.fixedStart = TimeOfDay(8, 30); s.fixedEnd = TimeOfDay(17, 30)
        XCTAssertEqual(SettingsValidator.validate(s), [])
    }

    func testValidation_lunchEndMustBeAfterStart_onlyWhenEnabled() {
        var s = WorkSettings()
        s.lunchStart = TimeOfDay(13, 0); s.lunchEnd = TimeOfDay(12, 0)
        XCTAssertEqual(SettingsValidator.validate(s), [], "점심을 안 쓰면 검사하지 않는다")
        s.lunchEnabled = true
        XCTAssertEqual(SettingsValidator.validate(s), [.lunchEndNotAfterStart])
        s.lunchEnd = TimeOfDay(13, 0)
        XCTAssertEqual(SettingsValidator.validate(s), [.lunchEndNotAfterStart])
        s.lunchEnd = TimeOfDay(13, 1)
        XCTAssertEqual(SettingsValidator.validate(s), [])
    }

    func testValidation_fontSizeRange8to32() {
        var s = WorkSettings()
        for ok in [8, 9, 12, 20, 31, 32] { s.fontSize = ok; XCTAssertEqual(SettingsValidator.validate(s), [], "\(ok)") }
        for bad in [7, 0, -12, 33, 100] {
            s.fontSize = bad
            XCTAssertEqual(SettingsValidator.validate(s), [.fontSizeOutOfRange], "\(bad)")
        }
    }

    func testParseFontSize_numbersOnly() {
        XCTAssertEqual(try? SettingsValidator.parseFontSize("12").get(), 12)
        XCTAssertEqual(try? SettingsValidator.parseFontSize(" 20 ").get(), 20)
        XCTAssertEqual(try? SettingsValidator.parseFontSize("100").get(), 100, "범위 검사는 validate 의 몫")
        for bad in ["", "  ", "abc", "12px", "1.5", "-3", "+5", "１２", "1 2"] {
            XCTAssertEqual(SettingsValidator.parseFontSize(bad), .failure(.fontSizeNotANumber), "'\(bad)'")
        }
    }

    func testFontSizeToWidgetRatio() {
        XCTAssertEqual(WidgetView.ratio(fontSize: 12), 1, accuracy: 1e-9)
        XCTAssertEqual(WidgetView.ratio(fontSize: 24), 2, accuracy: 1e-9)
        XCTAssertEqual(WidgetView.size(fontSize: 12), CGSize(width: 320, height: 150))
        XCTAssertEqual(WidgetView.size(fontSize: 24), CGSize(width: 640, height: 300))
        XCTAssertEqual(WidgetView.size(fontSize: 8), CGSize(width: 213, height: 100))
        XCTAssertEqual(WidgetView.size(fontSize: 32), CGSize(width: 853, height: 400))
    }

    func testValidation_errorsHaveMessages() {
        for e in [SettingsError.workMinutesOutOfRange, .fixedEndNotAfterStart, .lunchEndNotAfterStart, .fontSizeOutOfRange, .fontSizeNotANumber] {
            XCTAssertFalse(e.message.isEmpty)
        }
    }

    // MARK: 저장

    func testUpdate_savesValidAndPersistsAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings
        s.mode = .fixed; s.fixedStart = TimeOfDay(10, 0); s.fixedEnd = TimeOfDay(19, 0)
        s.lunchEnabled = true; s.notifyEnd = false; s.workMinutes = 480; s.fontSize = 20
        XCTAssertEqual(store.update(s), [])
        XCTAssertEqual(store.settings, s)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, s)
        XCTAssertEqual(defaults.string(forKey: "settings.fixed.start"), "10:00")
        XCTAssertEqual(defaults.object(forKey: "settings.widget.fontSize") as? Int, 20)
    }

    func testUpdate_invalidIsNotSavedAndReturnsErrors() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings
        s.mode = .fixed; s.fixedStart = TimeOfDay(18, 0); s.fixedEnd = TimeOfDay(9, 0)
        XCTAssertEqual(store.update(s), [.fixedEndNotAfterStart])
        XCTAssertEqual(store.settings, WorkSettings())
        XCTAssertNil(defaults.string(forKey: "settings.mode"))
        s = store.settings; s.fontSize = 33
        XCTAssertEqual(store.update(s), [.fontSizeOutOfRange])
        XCTAssertEqual(store.settings.fontSize, 12)
    }

    func testUpdate_persistFalseAppliesButDoesNotSave() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings; s.fontSize = 32
        XCTAssertEqual(store.update(s, persist: false), [])
        XCTAssertEqual(store.settings.fontSize, 32)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.fontSize, 12)
    }

    func testLoad_corruptStoredValuesFallBackPerItem() {
        defaults.set("not-a-time", forKey: "settings.flexible.earliestStart")
        defaults.set(5, forKey: "settings.flexible.workMinutes")
        defaults.set(77, forKey: "settings.widget.fontSize")
        defaults.set("bogus", forKey: "settings.mode")
        let s = SettingsStore(defaults: defaults).settings
        XCTAssertEqual(s.earliestStart, TimeOfDay(9, 0))
        XCTAssertEqual(s.workMinutes, 540)
        XCTAssertEqual(s.fontSize, 12)
        XCTAssertEqual(s.mode, .flexible)
    }

    func testChangesAreObservable() {
        let store = SettingsStore(defaults: defaults)
        var seen: [Int] = []
        let c = store.$settings.dropFirst().sink { seen.append($0.fontSize) }
        var s = store.settings; s.fontSize = 16; store.update(s)
        s.fontSize = 16; store.update(s)          // 같은 값은 알리지 않는다
        s.fontSize = 8; store.update(s)
        XCTAssertEqual(seen, [16, 8])
        c.cancel()
    }

    func testWidgetStyle_savedLoadedAndFallsBack() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings; s.widgetStyle = .bubble
        XCTAssertEqual(store.update(s), [])
        XCTAssertEqual(defaults.string(forKey: "settings.widget.style"), "bubble")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.widgetStyle, .bubble)
        defaults.set("hologram", forKey: "settings.widget.style")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.widgetStyle, .terminal)
    }

    func testWindowSizeFollowsStyleAndFontSize() {
        XCTAssertEqual(WidgetController.windowSize(style: .terminal, fontSize: 12), CGSize(width: 320, height: 150))
        XCTAssertEqual(WidgetController.windowSize(style: .bubble, fontSize: 12), CGSize(width: 190, height: 120))
        XCTAssertEqual(WidgetController.windowSize(style: .bubble, fontSize: 24), CGSize(width: 380, height: 240))
    }
}
