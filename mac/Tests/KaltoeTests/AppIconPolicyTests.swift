import XCTest
@testable import Kaltoe

/// Finder 앱 아이콘 정책 (docs/spec.md 6-1절): 현재 캐릭터 + 마지막 적용 값 → 아무것도 안 함 / 말티즈로 설정 / 지우기.
final class AppIconPolicyTests: XCTestCase {
    private let sig = "1790000000"
    private func last(_ c: MascotCharacter, _ s: String? = nil) -> AppliedIcon { AppliedIcon(character: c, signature: s ?? sig) }
    private func action(_ c: MascotCharacter, _ l: AppliedIcon?) -> AppIconAction {
        AppIconPolicy.action(character: c, last: l, signature: sig)
    }

    func testMaltese_setsWhenNotAppliedYet() {
        XCTAssertEqual(action(.maltese, nil), .setMaltese)
        XCTAssertEqual(action(.maltese, last(.orange)), .setMaltese)
    }

    func testMaltese_doesNothingWhenAlreadyApplied() {
        XCTAssertEqual(action(.maltese, last(.maltese)), .none)
    }

    func testOrange_clearsOnlyAfterMalteseWasApplied() {
        XCTAssertEqual(action(.orange, last(.maltese)), .clear)
    }

    func testOrange_doesNothingWhenEmbeddedIconAlreadyShown() {
        XCTAssertEqual(action(.orange, nil), .none, "처음 실행 + 주황이: 박힌 아이콘 그대로")
        XCTAssertEqual(action(.orange, last(.orange)), .none)
    }

    func testStaleSignature_afterReinstallIsTreatedAsNotApplied() {
        // 재설치하면 사용자 지정 아이콘이 사라진다 — 기록은 낡은 것으로 보고 다시 적용한다.
        XCTAssertEqual(action(.maltese, last(.maltese, "old")), .setMaltese)
        XCTAssertEqual(action(.orange, last(.maltese, "old")), .none, "이미 박힌 주황이 상태")
    }

    func testSwitchingBackAndForth() {
        var state: AppliedIcon? = nil
        func run(_ c: MascotCharacter) -> AppIconAction {
            let a = action(c, state)
            switch a {
            case .setMaltese: state = last(.maltese)
            case .clear: state = last(.orange)
            case .none: break
            }
            return a
        }
        XCTAssertEqual(run(.maltese), .setMaltese)
        XCTAssertEqual(run(.maltese), .none)
        XCTAssertEqual(run(.orange), .clear)
        XCTAssertEqual(run(.orange), .none)
        XCTAssertEqual(run(.maltese), .setMaltese)
    }

    func testStoredRoundTrip() {
        let a = last(.maltese)
        XCTAssertEqual(a.stored, "maltese@1790000000")
        XCTAssertEqual(AppliedIcon(stored: a.stored), a)
        XCTAssertNil(AppliedIcon(stored: nil))
        XCTAssertNil(AppliedIcon(stored: "garbage"))
        XCTAssertNil(AppliedIcon(stored: "cat@123"))
    }

    func testNoBundleIdentifier_applyDoesNothing() {
        // swift test 의 번들은 식별자가 있을 수 있어 직접 확인하지 못하므로, 호출이 크래시 없이 끝나는지만 본다.
        let suite = "kaltoe.icon.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        if Bundle.main.bundleIdentifier == nil {
            AppIconSwitcher.apply(character: .maltese, defaults: d)
            XCTAssertNil(d.string(forKey: AppIconSwitcher.defaultsKey))
        }
    }
}
