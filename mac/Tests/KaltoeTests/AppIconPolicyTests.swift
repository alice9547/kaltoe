import XCTest
@testable import Kaltoe

/// Finder 앱 아이콘 정책 (docs/spec.md 6-1절, 6-2절): 현재 캐릭터 + 마지막 적용 값 → 아무것도 안 함 / 말티즈로 설정 / 실사로 설정 / 지우기.
final class AppIconPolicyTests: XCTestCase {
    private let sig = "1790000000"
    private func last(_ c: MascotCharacter, _ s: String? = nil) -> AppliedIcon { AppliedIcon(character: c, signature: s ?? sig) }
    private func action(_ c: MascotCharacter, _ l: AppliedIcon?, variant: String = "") -> AppIconAction {
        AppIconPolicy.action(character: c, variant: variant, last: l, signature: sig)
    }
    private func lastCustom(_ variant: String, _ s: String? = nil) -> AppliedIcon {
        AppliedIcon(character: .photo, signature: s ?? sig, variant: variant)
    }

    func testMaltese_setsWhenNotAppliedYet() {
        XCTAssertEqual(action(.maltese, nil), .setMaltese)
        XCTAssertEqual(action(.maltese, last(.orange)), .setMaltese)
        XCTAssertEqual(action(.maltese, last(.photo)), .setMaltese, "실사 → 말티즈: 다른 이미지로 덮어쓴다")
    }

    func testPhoto_setsWhenNotAppliedYet() {
        XCTAssertEqual(action(.photo, nil), .setPhoto)
        XCTAssertEqual(action(.photo, last(.orange)), .setPhoto)
        XCTAssertEqual(action(.photo, last(.maltese)), .setPhoto, "말티즈 → 실사: 다른 이미지로 덮어쓴다")
    }

    func testPhoto_doesNothingWhenAlreadyApplied() {
        XCTAssertEqual(action(.photo, last(.photo)), .none)
    }

    func testMaltese_doesNothingWhenAlreadyApplied() {
        XCTAssertEqual(action(.maltese, last(.maltese)), .none)
    }

    func testOrange_clearsOnlyAfterMalteseWasApplied() {
        XCTAssertEqual(action(.orange, last(.maltese)), .clear)
        XCTAssertEqual(action(.orange, last(.photo)), .clear)
    }

    func testOrange_doesNothingWhenEmbeddedIconAlreadyShown() {
        XCTAssertEqual(action(.orange, nil), .none, "처음 실행 + 주황이: 박힌 아이콘 그대로")
        XCTAssertEqual(action(.orange, last(.orange)), .none)
    }

    func testStaleSignature_afterReinstallIsTreatedAsNotApplied() {
        // 재설치하면 사용자 지정 아이콘이 사라진다 — 기록은 낡은 것으로 보고 다시 적용한다.
        XCTAssertEqual(action(.maltese, last(.maltese, "old")), .setMaltese)
        XCTAssertEqual(action(.orange, last(.maltese, "old")), .none, "이미 박힌 주황이 상태")
        XCTAssertEqual(action(.photo, last(.photo, "old")), .setPhoto)
        XCTAssertEqual(action(.orange, last(.photo, "old")), .none)
    }

    func testSwitchingBackAndForth() {
        var state: AppliedIcon? = nil
        func run(_ c: MascotCharacter) -> AppIconAction {
            let a = action(c, state)
            switch a {
            case .setMaltese: state = last(.maltese)
            case .setPhoto: state = last(.photo)
            case .setCustomPhoto: state = lastCustom("v1")
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
        XCTAssertEqual(run(.photo), .setPhoto)
        XCTAssertEqual(run(.photo), .none)
        XCTAssertEqual(run(.maltese), .setMaltese)
        XCTAssertEqual(run(.photo), .setPhoto)
        XCTAssertEqual(run(.orange), .clear)
        XCTAssertEqual(run(.orange), .none)
    }

    // MARK: 사용자 지정 사진 (docs/spec.md 6-3절)

    func testCustomPhoto_setsWhenSelectedAndWhenPhotoChanges() {
        XCTAssertEqual(action(.photo, nil, variant: "a"), .setCustomPhoto)
        XCTAssertEqual(action(.photo, last(.orange), variant: "a"), .setCustomPhoto)
        XCTAssertEqual(action(.photo, last(.maltese), variant: "a"), .setCustomPhoto)
        XCTAssertEqual(action(.photo, last(.photo), variant: "a"), .setCustomPhoto, "내장 사진 아이콘 → 사용자 지정 사진")
        XCTAssertEqual(action(.photo, lastCustom("a"), variant: "b"), .setCustomPhoto, "다른 사진을 고르면 다시 만든다")
    }

    func testCustomPhoto_doesNothingWhenSamePhotoAlreadyApplied() {
        XCTAssertEqual(action(.photo, lastCustom("a"), variant: "a"), .none)
    }

    func testCustomPhoto_backToBuiltinPhotoOrOtherCharacters() {
        XCTAssertEqual(action(.photo, lastCustom("a"), variant: ""), .setPhoto, "기본 사진으로 돌아가면 내장 아이콘")
        XCTAssertEqual(action(.maltese, lastCustom("a"), variant: "a"), .setMaltese)
        XCTAssertEqual(action(.orange, lastCustom("a")), .clear)
        XCTAssertEqual(action(.orange, nil, variant: "a"), .none, "주황이는 사진 표식을 무시")
        XCTAssertEqual(action(.maltese, last(.maltese), variant: "zzz"), .none, "말티즈는 사진 표식을 무시")
    }

    func testCustomPhoto_staleSignatureAfterReinstall() {
        XCTAssertEqual(action(.photo, lastCustom("a", "old"), variant: "a"), .setCustomPhoto)
    }

    func testStoredRoundTrip_customVariant() {
        let a = lastCustom("1795-2048")
        XCTAssertEqual(a.stored, "photo+1795-2048@1790000000")
        XCTAssertEqual(AppliedIcon(stored: a.stored), a)
        XCTAssertEqual(AppliedIcon(stored: "photo@5"), AppliedIcon(character: .photo, signature: "5"))
        XCTAssertEqual(AppliedIcon(stored: "photo@5")?.variant, "")
    }

    func testStoredRoundTrip() {
        let a = last(.maltese)
        XCTAssertEqual(a.stored, "maltese@1790000000")
        XCTAssertEqual(AppliedIcon(stored: a.stored), a)
        let p = last(.photo)
        XCTAssertEqual(p.stored, "photo@1790000000")
        XCTAssertEqual(AppliedIcon(stored: p.stored), p)
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
