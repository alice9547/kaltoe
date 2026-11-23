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
        XCTAssertEqual(s.character, .maltese)
        XCTAssertTrue(s.comprehensivePay)
        XCTAssertNil(s.rateAmount)
        XCTAssertEqual(s.rateUnit, .hour)
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
        for e in [SettingsError.workMinutesOutOfRange, .fixedEndNotAfterStart, .lunchEndNotAfterStart, .fontSizeOutOfRange, .fontSizeNotANumber, .rateAmountOutOfRange, .rateAmountNotANumber] {
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

    // MARK: 야근 (pay.*)

    func testValidation_rateAmountBounds() {
        var s = WorkSettings()
        s.rateAmount = nil
        XCTAssertEqual(SettingsValidator.validate(s), [], "비워 두기 허용")
        for ok in [1, 2, 10320, 9_999_999, 10_000_000] { s.rateAmount = ok; XCTAssertEqual(SettingsValidator.validate(s), [], "\(ok)") }
        for bad in [0, -1, 10_000_001, 99_999_999] {
            s.rateAmount = bad
            XCTAssertEqual(SettingsValidator.validate(s), [.rateAmountOutOfRange], "\(bad)")
        }
    }

    func testParseRateAmount() {
        XCTAssertEqual(try? SettingsValidator.parseRateAmount("300").get(), 300)
        XCTAssertEqual(try? SettingsValidator.parseRateAmount(" 20000 ").get(), 20000)
        XCTAssertEqual(try? SettingsValidator.parseRateAmount("10000001").get(), 10_000_001, "범위 검사는 validate 의 몫")
        XCTAssertEqual(SettingsValidator.parseRateAmount(""), .success(nil))
        XCTAssertEqual(SettingsValidator.parseRateAmount("   "), .success(nil))
        for bad in ["abc", "10,320", "1.5", "-1", "300원", "99999999999999999999"] {
            XCTAssertEqual(SettingsValidator.parseRateAmount(bad), .failure(.rateAmountNotANumber), "'\(bad)'")
        }
    }

    func testPaySettings_saveLoadAndRejectInvalid() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings; s.comprehensivePay = false; s.rateAmount = 300; s.rateUnit = .minute
        XCTAssertEqual(store.update(s), [])
        XCTAssertEqual(defaults.object(forKey: "settings.pay.comprehensive") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "settings.pay.rateAmount") as? Int, 300)
        XCTAssertEqual(defaults.string(forKey: "settings.pay.rateUnit"), "minute")
        let reloaded = SettingsStore(defaults: defaults).settings
        XCTAssertFalse(reloaded.comprehensivePay); XCTAssertEqual(reloaded.rateAmount, 300); XCTAssertEqual(reloaded.rateUnit, .minute)
        s.rateAmount = 0
        XCTAssertEqual(store.update(s), [.rateAmountOutOfRange])
        XCTAssertEqual(store.settings.rateAmount, 300)
        // 비우면 키가 지워지고 다시 읽어도 비어 있다.
        s.rateAmount = nil
        XCTAssertEqual(store.update(s), [])
        XCTAssertNil(defaults.object(forKey: "settings.pay.rateAmount"))
        XCTAssertNil(SettingsStore(defaults: defaults).settings.rateAmount)
        // 손으로 망가뜨린 저장값은 비움(최저시급)으로 되돌린다.
        defaults.set(-5, forKey: "settings.pay.rateAmount")
        XCTAssertNil(SettingsStore(defaults: defaults).settings.rateAmount)
    }

    // MARK: 캐릭터 (widget.character)

    func testCharacter_validationAcceptsEveryCase() {
        var s = WorkSettings()
        for c in MascotCharacter.allCases {
            s.character = c
            XCTAssertEqual(SettingsValidator.validate(s), [], "\(c)")
        }
    }

    func testCharacter_savedLoadedObservedAndFallsBack() {
        let store = SettingsStore(defaults: defaults)
        var seen: [MascotCharacter] = []
        let c = store.$settings.dropFirst().sink { seen.append($0.character) }
        var s = store.settings; s.character = .orange
        XCTAssertEqual(store.update(s), [])
        s.character = .maltese; store.update(s)
        s.character = .orange; store.update(s)
        s.character = .photo; store.update(s)
        XCTAssertEqual(seen, [.orange, .maltese, .orange, .photo])
        c.cancel()
        XCTAssertEqual(defaults.string(forKey: "settings.widget.character"), "photo")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.character, .photo)
        defaults.set("cat", forKey: "settings.widget.character")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.character, .maltese, "모르는 값은 기본(말티즈)")
        defaults.removeObject(forKey: "settings.widget.character")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.character, .maltese)
    }

    func testCharacter_rawValuesMatchSpec() {
        XCTAssertEqual(MascotCharacter.maltese.rawValue, "maltese")
        XCTAssertEqual(MascotCharacter.orange.rawValue, "orange")
        XCTAssertEqual(MascotCharacter.photo.rawValue, "photo")
        XCTAssertEqual(MascotCharacter.allCases.count, 3)
    }

    func testCharacter_photoSavedLoadedAndOnlyPhotoIsPhoto() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings; s.character = .photo
        XCTAssertTrue(store.update(s).isEmpty)
        XCTAssertEqual(defaults.string(forKey: "settings.widget.character"), "photo")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.character, .photo)
        XCTAssertEqual(MascotCharacter.allCases.filter(\.isPhoto), [.photo])
        defaults.set("Photo", forKey: "settings.widget.character")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.character, .maltese, "대소문자가 다른 모르는 값은 기본(말티즈)")
    }

    func testCustomPhoto_defaultFalse_savedLoadedAndNotPersistedWhenTransient() {
        XCTAssertFalse(WorkSettings().customPhoto)
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.settings.customPhoto)
        var s = store.settings; s.customPhoto = true
        XCTAssertEqual(store.update(s), [])
        XCTAssertEqual(defaults.object(forKey: "settings.widget.customPhoto") as? Bool, true)
        XCTAssertTrue(SettingsStore(defaults: defaults).settings.customPhoto)
        s.customPhoto = false; store.update(s)
        XCTAssertFalse(SettingsStore(defaults: defaults).settings.customPhoto)
        // 확인용 실행 인자(--custom-photo)처럼 저장 없이 켜면 이번 실행에만 적용된다
        s.customPhoto = true
        XCTAssertEqual(store.update(s, persist: false), [])
        XCTAssertTrue(store.settings.customPhoto)
        XCTAssertFalse(SettingsStore(defaults: defaults).settings.customPhoto)
        XCTAssertEqual(SettingsValidator.validate(s), [], "사용자 지정 사진 값은 검증에 걸리지 않는다")
    }

    func testCharacter_photoDoesNotBreakPixelGridAccessors() {
        // 사진 캐릭터는 격자가 없지만 격자 접근자는 (0 나눗셈 등 없이) 유효한 값을 돌려줘야 한다.
        let c = MascotCharacter.photo
        XCTAssertGreaterThan(c.width, 0)
        XCTAssertGreaterThan(c.height, 0)
        XCTAssertEqual(c.frames.count, 14)
        XCTAssertFalse(c.menuBarCutouts.isEmpty)
        XCTAssertFalse(c.menuBarRows.isEmpty)
    }

    func testCharacter_persistFalseDoesNotSave() {
        let store = SettingsStore(defaults: defaults)
        var s = store.settings; s.character = .orange
        store.update(s, persist: false)
        XCTAssertEqual(store.settings.character, .orange)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.character, .maltese)
    }
}
