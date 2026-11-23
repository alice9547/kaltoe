import XCTest
import AppKit
@testable import Kaltoe

/// 실사 캐릭터 (docs/spec.md 6-2절): 움직임·덧그림 계산(순수 함수), 내장 이미지, 크기, 메뉴바 아이콘.
final class PhotoMascotTests: XCTestCase {
    private typealias M = PhotoMascotMotion
    private func tf(_ mood: MascotMood, _ t: Double) -> PhotoTransform { M.transform(mood: mood, seconds: t) }
    private func assertEqual(_ a: Double, _ b: Double, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 1e-9, msg, file: file, line: line)
    }

    // MARK: 움직임 (표의 범위와 주기)

    func testSleep_breathesSlowlyAtHalfOpacity() {
        assertEqual(tf(.sleep, 0).scaleY, 1.00)
        assertEqual(tf(.sleep, 1.0).scaleY, 1.03, "2초 주기의 절반에서 최대")
        assertEqual(tf(.sleep, 2.0).scaleY, 1.00)
        assertEqual(tf(.sleep, 0.37).opacity, 0.85)
        assertEqual(tf(.sleep, 0.37).offsetY, 0)
    }

    func testIdle_breathes() {
        assertEqual(tf(.idle, 0).scaleY, 1.00)
        assertEqual(tf(.idle, 0.6).scaleY, 1.02, "1.2초 주기의 절반에서 최대")
        assertEqual(tf(.idle, 1.2).scaleY, 1.00)
        XCTAssertEqual(tf(.idle, 0.2).opacity, 1)
    }

    func testEat_nodsDownTwoPixels() {
        assertEqual(tf(.eat, 0).offsetY, 0)
        assertEqual(tf(.eat, 0.2).offsetY, 2, "0.4초 주기의 절반에서 아래로 2px")
        assertEqual(tf(.eat, 0.4).offsetY, 0)
    }

    func testSparkle_hopsUpFourPixels() {
        assertEqual(tf(.sparkle, 0).offsetY, 0)
        assertEqual(tf(.sparkle, 0.15).offsetY, -4, "0.3초 주기의 절반에서 위로 4px")
        assertEqual(tf(.sparkle, 0.3).offsetY, 0)
    }

    func testDance_tiltsMinusEightToPlusEight() {
        assertEqual(tf(.dance, 0).rotation, -8)
        assertEqual(tf(.dance, 0.2).rotation, 8)
        assertEqual(tf(.dance, 0.4).rotation, -8)
        for i in 0...40 {
            let r = tf(.dance, Double(i) * 0.01).rotation
            XCTAssertTrue((-8.000001...8.000001).contains(r), "\(r)")
        }
    }

    func testAngry_shakesPlusMinusOnePointFivePerEightyMilliseconds() {
        assertEqual(tf(.angry, 0.00).offsetX, -1.5)
        assertEqual(tf(.angry, 0.07).offsetX, -1.5)
        assertEqual(tf(.angry, 0.08).offsetX, 1.5)
        assertEqual(tf(.angry, 0.159).offsetX, 1.5)
        assertEqual(tf(.angry, 0.16).offsetX, -1.5)
        assertEqual(tf(.angry, 0.5).offsetY, 0)
    }

    func testCry_droopsOnePixel() {
        for t in [0.0, 0.13, 0.4, 3.3] { assertEqual(tf(.cry, t).offsetY, 1) }
        assertEqual(tf(.cry, 0.2).scaleY, 1)
    }

    func testTickIsTenthOfSecond() {
        XCTAssertEqual(M.seconds(tick: 12), 1.2, accuracy: 1e-12)
        XCTAssertEqual(M.transform(mood: .eat, tick: 2), M.transform(mood: .eat, seconds: 0.2))
    }

    // MARK: 클릭 점프

    func testJump_followsPixelJumpCurveThreePixelsPerStep() {
        XCTAssertEqual(M.jumpLift(tick: 5, jumpStart: nil), 0)
        XCTAssertEqual((0..<8).map { M.jumpLift(tick: 100 + $0, jumpStart: 100) }, [3, 6, 9, 9, 6, 3, 0, 0])
        XCTAssertEqual(M.jumpLift(tick: 99, jumpStart: 100), 0)
    }

    // MARK: 덧그림

    func testZ_risesAndFadesThenRests() {
        let zs = (0..<20).map { M.zFloat(tick: $0) }
        XCTAssertEqual(zs[0]?.alpha, 1.0)
        XCTAssertEqual(zs[5]?.alpha, 0.8)
        XCTAssertEqual(zs[10]?.alpha, 0.55)
        XCTAssertNil(zs[15], "4번째 칸은 쉰다")
        XCTAssertGreaterThan(zs[0]!.y, zs[5]!.y, "위로 올라간다(y 감소)")
        XCTAssertGreaterThan(zs[5]!.y, zs[10]!.y)
        XCTAssertEqual(M.zFloat(tick: 20)?.alpha, 1.0, "2초 주기")
    }

    func testTears_fallFromEachEyeEveryFourTenthsOfASecond() {
        let l = CGPoint(x: 0.376, y: 0.395), r = CGPoint(x: 0.64, y: 0.386)
        let a = M.tears(seconds: 0, leftEye: l, rightEye: r)
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[0].x, 0.376, accuracy: 1e-12)
        XCTAssertEqual(a[1].x, 0.64, accuracy: 1e-12)
        XCTAssertGreaterThan(a[0].y, 0.395, "눈 아래에서 시작")
        let b = M.tears(seconds: 0.2, leftEye: l, rightEye: r)
        XCTAssertGreaterThan(b[0].y, a[0].y, "시간이 지나면 떨어진다")
        XCTAssertLessThan(b[0].alpha, a[0].alpha, "옅어진다")
        let c = M.tears(seconds: 0.4, leftEye: l, rightEye: r)
        XCTAssertEqual(c[0].y, a[0].y, accuracy: 1e-9, "0.4초 주기")
        XCTAssertEqual(c[0].alpha, a[0].alpha, accuracy: 1e-9)
    }

    func testSparks_twoPairsAlternateEveryThirtyHundredths() {
        let a = M.sparks(seconds: 0), b = M.sparks(seconds: 0.3)
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.map(\.x), b.map(\.x), "자리는 그대로")
        XCTAssertNotEqual(a.map(\.size), b.map(\.size), "커지는 쌍이 번갈아 바뀐다")
        XCTAssertEqual(a.map(\.size), M.sparks(seconds: 0.6).map(\.size))
        XCTAssertTrue(a.contains { $0.x < 0.2 } && a.contains { $0.x > 0.8 }, "양옆")
    }

    func testConfetti_aroundTheBodyWithKnownColors() {
        let pieces = M.confetti(seconds: 0.4)
        XCTAssertEqual(pieces.count, M.confettiSlots.count)
        XCTAssertTrue(pieces.allSatisfy { M.confettiColors.contains($0.color) })
        XCTAssertGreaterThan(Set(pieces.map(\.color)).count, 3)
        XCTAssertTrue(pieces.allSatisfy { (0..<360).contains($0.rotation) })
    }

    func testAnger_pulsesAroundTheBaseSize() {
        assertEqual(M.angerPulse(seconds: 0), 1.0)
        assertEqual(M.angerPulse(seconds: 0.15), 1.15)
        XCTAssertGreaterThan(M.angerCenter.x, 0.7, "머리 오른쪽")
        XCTAssertLessThan(M.angerCenter.y, 0.3, "머리 위")
    }

    // MARK: 내장 이미지

    func testEmbeddedImage_decodesWithExpectedAspect() {
        let image = PhotoMascotImage.image
        XCTAssertEqual(max(image.size.width, image.size.height), 192, "긴 변 192px")
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertEqual(PhotoMascotImage.aspect, image.size.width / image.size.height, accuracy: 1e-9)
        XCTAssertGreaterThan(PhotoMascotImage.aspect, 1, "가로가 더 긴 이미지(긴 변 = 폭)")
    }

    func testEyeCoordinatesAreRatiosInsideTheImageAndLeftOfRight() {
        let l = PhotoMascotData.leftEye, r = PhotoMascotData.rightEye
        for p in [l, r] { XCTAssertTrue((0.0...1.0).contains(p.x) && (0.0...1.0).contains(p.y), "\(p)") }
        XCTAssertLessThan(l.x, r.x)
        XCTAssertLessThan(abs(l.y - r.y), 0.05, "두 눈은 거의 같은 높이")
    }

    // MARK: 크기·메뉴바

    func testDisplaySize_isSixtyTimesRatioForEveryFontSize() {
        XCTAssertEqual(PhotoMascotView.displaySize(ratio: 1), 60)
        XCTAssertEqual(ScaledMascot.displaySize(baseSize: 56, ratio: 1, character: .photo), 60, "터미널 56 이 아니라 60")
        XCTAssertEqual(ScaledMascot.displaySize(baseSize: 60, ratio: 2, character: .photo), 120)
        XCTAssertEqual(ScaledMascot.displaySize(baseSize: 60, ratio: 8.0 / 12, character: .photo), 40, accuracy: 1e-9)
        XCTAssertEqual(ScaledMascot.displaySize(baseSize: 60, ratio: 1, character: .maltese), 60, "픽셀 캐릭터는 그대로")
    }

    func testMenuBarImage_photoIsColorNotTemplateAndPixelsAreTemplates() {
        let photo = MascotImage.menuBarImage(character: .photo)
        XCTAssertFalse(photo.isTemplate)
        XCTAssertEqual(photo.size, NSSize(width: 18, height: 18))
        let rep = photo.representations.first
        XCTAssertEqual(rep?.pixelsWide, rep?.pixelsHigh, "정사각형")
        XCTAssertGreaterThanOrEqual(rep?.pixelsWide ?? 0, 36, "레티나(18pt × 2) 이상")
        XCTAssertNotNil(photo.cgImage(forProposedRect: nil, context: nil, hints: nil), "얼굴 이미지 디코딩 성공")
        for c in [MascotCharacter.maltese, .orange] {
            XCTAssertTrue(MascotImage.menuBarImage(character: c).isTemplate)
        }
    }
}
