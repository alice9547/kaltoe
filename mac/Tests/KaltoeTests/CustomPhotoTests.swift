import XCTest
import AppKit
import ImageIO
@testable import Kaltoe

/// 사용자 지정 사진 (docs/spec.md 6-3절): 알파 판정, 경계 상자, 원형 마스크, 축소, 처리 순서, 저장, 아이콘.
final class CustomPhotoTests: XCTestCase {
    // MARK: 도우미

    private func buffer(_ w: Int, _ h: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> PixelBuffer {
        var b = PixelBuffer(width: w, height: h)
        for y in 0..<h { for x in 0..<w {
            let (r, g, bl, a) = pixel(x, y)
            let i = (y * w + x) * 4
            // 프리멀티플라이드로 저장
            b.rgba[i] = UInt8(Int(r) * Int(a) / 255); b.rgba[i + 1] = UInt8(Int(g) * Int(a) / 255)
            b.rgba[i + 2] = UInt8(Int(bl) * Int(a) / 255); b.rgba[i + 3] = a
        } }
        return b
    }

    private func opaque(_ w: Int, _ h: Int) -> PixelBuffer { buffer(w, h) { _, _ in (200, 120, 60, 255) } }

    private func cg(_ b: PixelBuffer) -> CGImage { b.makeCGImage()! }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kaltoe-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writePNG(_ image: CGImage, to url: URL, orientation: Int? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if let o = orientation { props[kCGImagePropertyOrientation] = o }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    // MARK: 알파 판정 (1% 기준)

    func testTransparency_thresholdIsOnePercentOfPixels() {
        // 100x100 = 10000 픽셀: 100개(1%) 가 투명이면 "이미 투명", 99개면 아님
        func withTransparent(_ n: Int) -> PixelBuffer {
            buffer(100, 100) { x, y in y * 100 + x < n ? (255, 255, 255, 0) : (10, 20, 30, 255) }
        }
        XCTAssertEqual(opaque(10, 10).transparentFraction, 0)
        XCTAssertFalse(opaque(10, 10).hasTransparency)
        XCTAssertTrue(withTransparent(100).hasTransparency)
        XCTAssertFalse(withTransparent(99).hasTransparency)
        XCTAssertEqual(withTransparent(2500).transparentFraction, 0.25, accuracy: 1e-9)
    }

    func testTransparency_semiTransparentCountsAsTransparent() {
        XCTAssertTrue(buffer(10, 10) { _, _ in (0, 0, 0, 254) }.hasTransparency)
    }

    // MARK: 경계 상자

    func testOpaqueBounds() {
        let b = buffer(20, 10) { x, y in (4...9).contains(x) && (2...5).contains(y) ? (1, 2, 3, 255) : (0, 0, 0, 0) }
        let r = b.opaqueBounds()!
        XCTAssertEqual([r.x, r.y, r.width, r.height], [4, 2, 6, 4])
        XCTAssertNil(buffer(5, 5) { _, _ in (0, 0, 0, 0) }.opaqueBounds())
        XCTAssertNil(buffer(5, 5) { _, _ in (9, 9, 9, 8) }.opaqueBounds(), "문턱 이하의 옅은 알파는 무시")
        let c = b.cropped(x: r.x, y: r.y, width: r.width, height: r.height)
        XCTAssertEqual(c.width, 6); XCTAssertEqual(c.height, 4)
        XCTAssertEqual(c.transparentFraction, 0)
    }

    // MARK: 원형 마스크

    func testCircleCoverage_featherOnePixelInsideTheEdge() {
        XCTAssertEqual(PixelBuffer.circleCoverage(distance: 0, radius: 50), 1)
        XCTAssertEqual(PixelBuffer.circleCoverage(distance: 48.5, radius: 50), 1)
        XCTAssertEqual(PixelBuffer.circleCoverage(distance: 49.5, radius: 50), 1, accuracy: 1e-12)
        XCTAssertEqual(PixelBuffer.circleCoverage(distance: 50, radius: 50), 0.5, accuracy: 1e-12)
        XCTAssertEqual(PixelBuffer.circleCoverage(distance: 50.5, radius: 50), 0, accuracy: 1e-12)
        XCTAssertEqual(PixelBuffer.circleCoverage(distance: 80, radius: 50), 0)
    }

    func testCircleCropped_centerSquareThenTransparentOutsideTheCircle() {
        let c = opaque(200, 100).circleCropped()
        XCTAssertEqual(c.width, 100); XCTAssertEqual(c.height, 100)
        XCTAssertEqual(c.alpha(50, 50), 255)
        XCTAssertEqual(c.alpha(0, 0), 0); XCTAssertEqual(c.alpha(99, 0), 0)
        XCTAssertEqual(c.alpha(0, 99), 0); XCTAssertEqual(c.alpha(99, 99), 0)
        XCTAssertEqual(c.alpha(50, 2), 255, "원 안쪽")
        XCTAssertGreaterThan(c.alpha(50, 0), 0, "맨 위 가운데는 거의 원 안")
        // 프리멀티플라이드이므로 색은 알파를 넘지 않는다
        for i in stride(from: 0, to: c.rgba.count, by: 4) { XCTAssertLessThanOrEqual(c.rgba[i], 255); XCTAssertLessThanOrEqual(c.rgba[i + 3], 255) }
        XCTAssertEqual(c.opaqueBounds()!.width, 100, "원의 경계 상자는 정사각형 전체")
    }

    func testCircleCropped_usesTheCenterNotTheTopLeft() {
        // 왼쪽 절반 빨강, 오른쪽 절반 파랑인 200x100 → 가운데 100x100 은 반반
        let b = buffer(200, 100) { x, _ in x < 100 ? (255, 0, 0, 255) : (0, 0, 255, 255) }
        let c = b.circleCropped()
        XCTAssertEqual(c.rgba[(50 * 100 + 30) * 4], 255, "왼쪽은 빨강")
        XCTAssertEqual(c.rgba[(50 * 100 + 70) * 4 + 2], 255, "오른쪽은 파랑")
    }

    func testApplyingMask_multipliesAlphaAndColor() {
        let b = opaque(4, 1)
        let out = b.applying(mask: [255, 128, 0, 64])
        XCTAssertEqual(out.alpha(0, 0), 255)
        XCTAssertEqual(out.alpha(1, 0), 128)
        XCTAssertEqual(out.alpha(2, 0), 0)
        XCTAssertEqual(out.alpha(3, 0), 64)
        XCTAssertEqual(out.rgba[2 * 4], 0)
        XCTAssertEqual(Int(out.rgba[1 * 4]), 200 * 128 / 255)
    }

    func testMaskErodeShrinksAndBlurSoftens() {
        // 10x10 에서 가운데 6x6 만 255
        var m = [UInt8](repeating: 0, count: 100)
        for y in 2..<8 { for x in 2..<8 { m[y * 10 + x] = 255 } }
        let e = PixelBuffer.eroded(m, width: 10, height: 10, radius: 1)
        XCTAssertEqual(e.filter { $0 == 255 }.count, 16, "6x6 → 4x4")
        XCTAssertEqual(PixelBuffer.eroded(m, width: 10, height: 10, radius: 0), m)
        let b = PixelBuffer.blurred(e, width: 10, height: 10)
        XCTAssertTrue(b.contains { $0 > 0 && $0 < 255 })
    }

    // MARK: 축소 크기

    func testFitSize_shrinksLongSideNeverEnlarges() {
        XCTAssertTrue(PixelBuffer.fitSize(width: 1024, height: 768, longSide: 512) == (512, 384))
        XCTAssertTrue(PixelBuffer.fitSize(width: 600, height: 1200, longSide: 512) == (256, 512))
        XCTAssertTrue(PixelBuffer.fitSize(width: 300, height: 200, longSide: 512) == (300, 200), "작은 사진은 키우지 않는다")
        XCTAssertTrue(PixelBuffer.fitSize(width: 512, height: 512, longSide: 512) == (512, 512))
        XCTAssertTrue(PixelBuffer.fitSize(width: 5000, height: 3, longSide: 512) == (512, 1), "최소 1px")
    }

    // MARK: 처리 순서 (읽기 → 배경 지우기 → 여백 자르기 → 512 축소)

    func testProcess_noSubject_fallsBackToCircleCropAndScalesTo512() throws {
        let out = try CustomPhotoProcessor.process(cgImage: cg(opaque(1000, 600)), maskProvider: { _ in nil })
        XCTAssertEqual(out.width, 512); XCTAssertEqual(out.height, 512)
        let b = PixelBuffer(cgImage: out)!
        XCTAssertEqual(b.alpha(0, 0), 0, "원 밖(모서리)은 투명")
        XCTAssertEqual(b.alpha(256, 256), 255)
    }

    func testProcess_tinySubjectCountsAsNotFound() throws {
        var mask = [UInt8](repeating: 0, count: 1000 * 600)
        for y in 0..<10 { for x in 0..<10 { mask[y * 1000 + x] = 255 } }     // 0.0167% — 피사체로 보기엔 너무 작다
        let out = try CustomPhotoProcessor.process(cgImage: cg(opaque(1000, 600)), maskProvider: { _ in mask })
        XCTAssertEqual(out.width, 512, "원형 자르기로 대체")
        XCTAssertEqual(out.height, 512)
    }

    func testProcess_wrongSizedMaskCountsAsNotFound() throws {
        let out = try CustomPhotoProcessor.process(cgImage: cg(opaque(1000, 600)), maskProvider: { _ in [255, 255] })
        XCTAssertEqual(out.width, 512)
    }

    func testProcess_subjectMask_keepsOnlySubjectAndTrimsTransparentMargin() throws {
        var mask = [UInt8](repeating: 0, count: 1000 * 600)
        for y in 100..<500 { for x in 300..<700 { mask[y * 1000 + x] = 255 } }   // 400x400 피사체
        let out = try CustomPhotoProcessor.process(cgImage: cg(opaque(1000, 600)), maskProvider: { _ in mask })
        XCTAssertLessThanOrEqual(out.width, 400); XCTAssertGreaterThan(out.width, 380, "가장자리를 조금 줄이지만 거의 그대로")
        XCTAssertLessThan(abs(out.width - out.height), 3)
        let b = PixelBuffer(cgImage: out)!
        XCTAssertEqual(b.alpha(out.width / 2, out.height / 2), 255)
        XCTAssertEqual(b.opaqueBounds(threshold: 8)!.width, out.width, "여백이 남지 않는다")
    }

    func testProcess_alreadyTransparentImageIsKeptAsIs_maskNotAsked() throws {
        // 바깥 25% 가 투명한 600x400 (투명 비율 ≫ 1%)
        let b = buffer(600, 400) { x, y in (150..<450).contains(x) && (100..<300).contains(y) ? (30, 60, 90, 255) : (0, 0, 0, 0) }
        var asked = false
        let out = try CustomPhotoProcessor.process(cgImage: cg(b), maskProvider: { _ in asked = true; return nil })
        XCTAssertFalse(asked, "이미 투명하면 배경 지우기를 하지 않는다")
        XCTAssertEqual(out.width, 300); XCTAssertEqual(out.height, 200, "여백만 잘라 내고 축소는 필요 없음")
        let o = PixelBuffer(cgImage: out)!
        XCTAssertEqual(o.transparentFraction, 0, accuracy: 1e-9, "남은 부분은 전부 불투명 그대로")
    }

    func testProcess_largeTransparentImageScalesLongSideTo512() throws {
        let b = buffer(2000, 1000) { x, _ in x < 1500 ? (9, 9, 9, 255) : (0, 0, 0, 0) }   // 25% 투명
        let out = try CustomPhotoProcessor.process(cgImage: cg(b), maskProvider: { _ in nil })
        XCTAssertEqual(out.width, 512)
        XCTAssertEqual(out.height, 341, "1500x1000 → 긴 변 512")
    }

    func testProcess_fullyTransparentImageFails() {
        XCTAssertThrowsError(try CustomPhotoProcessor.process(cgImage: cg(buffer(50, 50) { _, _ in (0, 0, 0, 0) }), maskProvider: { _ in nil }))
    }

    func testSubjectFraction() {
        XCTAssertEqual(CustomPhotoProcessor.subjectFraction([255, 255, 0, 0]), 0.5)
        XCTAssertEqual(CustomPhotoProcessor.subjectFraction([]), 0)
    }

    // MARK: 읽기 (EXIF 방향, 읽을 수 없는 파일)

    func testLoad_appliesExifOrientation() throws {
        let url = tempDir().appendingPathComponent("rot.png")
        try writePNG(cg(opaque(40, 20)), to: url, orientation: 6)       // 시계 방향 90° 회전해서 봐야 함
        let loaded = try CustomPhotoProcessor.load(url: url)
        XCTAssertEqual(loaded.width, 20); XCTAssertEqual(loaded.height, 40)
        let plain = tempDir().appendingPathComponent("plain.png")
        try writePNG(cg(opaque(40, 20)), to: plain)
        let p = try CustomPhotoProcessor.load(url: plain)
        XCTAssertEqual(p.width, 40); XCTAssertEqual(p.height, 20)
    }

    func testLoad_unreadableFileThrows() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let junk = dir.appendingPathComponent("junk.png")
        try Data("not an image".utf8).write(to: junk)
        XCTAssertThrowsError(try CustomPhotoProcessor.load(url: junk))
        XCTAssertThrowsError(try CustomPhotoProcessor.process(url: junk))
        XCTAssertThrowsError(try CustomPhotoProcessor.load(url: dir.appendingPathComponent("missing.jpg")))
    }

    /// 실제 Vision 으로 배경 있는 사진(shared/source/maltese-photo.jpeg)을 처리한다.
    func testProcess_realPhotoWithVision() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("shared/source/maltese-photo.jpeg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "원본 사진 없음")
        let out = try CustomPhotoProcessor.process(url: url)
        XCTAssertEqual(max(out.width, out.height), 512)
        let b = PixelBuffer(cgImage: out)!
        XCTAssertGreaterThan(b.transparentFraction, 0.10, "배경이 지워져 투명 부분이 생겼다")
        XCTAssertEqual(b.alpha(0, 0), 0, "왼쪽 위 모서리는 배경")
        XCTAssertEqual(b.alpha(b.width / 2, b.height / 2), 255, "가운데는 강아지")
        let size = (out.width, out.height)
        XCTAssertGreaterThan(size.0, 300); XCTAssertGreaterThan(size.1, 300, "전신이 남는다(너무 작게 잘리지 않음)")
        if let png = CustomPhotoProcessor.pngData(out) { try? png.write(to: URL(fileURLWithPath: "/tmp/kaltoe-shots/photo-custom-processed.png")) }
        // 피사체를 못 찾은 경우의 원형 자르기 결과도 확인용으로 남긴다
        if let circle = try? CustomPhotoProcessor.process(cgImage: CustomPhotoProcessor.load(url: url), maskProvider: { _ in nil }),
           let png = CustomPhotoProcessor.pngData(circle) { try? png.write(to: URL(fileURLWithPath: "/tmp/kaltoe-shots/photo-custom-circle-raw.png")) }
        // 확인용 산출물: 처리 결과, 그 사진으로 만든 Finder 아이콘·메뉴바 아이콘(눈으로 확인하는 용도)
        let photo = CustomPhoto(cgImage: out, token: "t")
        if let icon = CustomPhotoIcons.finderIcon(photo, size: 512), let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let png = CustomPhotoProcessor.pngData(cgIcon) { try? png.write(to: URL(fileURLWithPath: "/tmp/kaltoe-shots/photo-custom-finder-icon.png")) }
    }

    // MARK: 저장소

    func testStore_installPersistsReloadsAndRemoves() throws {
        let dir = tempDir()
        let store = CustomPhotoStore(directory: dir)
        XCTAssertNil(store.photo)
        XCTAssertEqual(store.fileURL.lastPathComponent, "custom-mascot.png")
        let image = cg(opaque(80, 40))
        try store.install(image)
        XCTAssertNotNil(store.photo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("custom-mascot.png").path))
        XCTAssertEqual(store.photo?.cgImage.width, 80)
        XCTAssertEqual(store.photo!.aspect, 2, accuracy: 1e-9)
        // 다시 열면 저장한 사진이 읽힌다 (원본 경로는 필요 없다)
        let reopened = CustomPhotoStore(directory: dir)
        XCTAssertEqual(reopened.photo?.cgImage.width, 80)
        XCTAssertEqual(reopened.photo?.token, store.photo?.token)
        store.remove()
        XCTAssertNil(store.photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertNil(CustomPhotoStore(directory: dir).photo)
        store.remove()        // 없는 파일을 또 지워도 문제없다
    }

    func testStore_brokenOrMissingFileBehavesLikeNoPhoto() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("custom-mascot.png"))
        XCTAssertNil(CustomPhotoStore(directory: dir).photo)
        XCTAssertNil(CustomPhotoStore(directory: dir.appendingPathComponent("nope")).photo)
    }

    func testStore_installFailureKeepsThePreviousPhoto() throws {
        let dir = tempDir()
        let store = CustomPhotoStore(directory: dir)
        try store.install(cg(opaque(30, 30)))
        let before = store.photo
        // 저장 위치를 파일로 막아 쓰기를 실패시킨다
        let blocked = tempDir()
        try FileManager.default.createDirectory(at: blocked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: blocked)
        let failing = CustomPhotoStore(directory: blocked)
        XCTAssertThrowsError(try failing.install(cg(opaque(10, 10))))
        XCTAssertNil(failing.photo)
        XCTAssertTrue(store.photo === before)
    }

    func testStore_transientDoesNotWriteAFile() {
        let dir = tempDir()
        let store = CustomPhotoStore(directory: dir)
        store.useTransient(cg(opaque(10, 10)))
        XCTAssertNotNil(store.photo)
        XCTAssertEqual(store.photo?.token, "transient")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testStore_newPhotoGetsANewToken() throws {
        let store = CustomPhotoStore(directory: tempDir())
        try store.install(cg(opaque(30, 30)))
        let a = store.photo?.token
        try store.install(cg(opaque(31, 29)))
        XCTAssertNotEqual(a, store.photo?.token)
    }

    // MARK: 사진 소스 (내장 / 사용자 지정, 덧그림 위치)

    func testSource_resolve() {
        let photo = CustomPhoto(cgImage: cg(opaque(60, 30)), token: "t")
        XCTAssertFalse(PhotoMascotSource.resolve(customPhoto: false, photo: photo).isCustom, "꺼져 있으면 내장")
        XCTAssertFalse(PhotoMascotSource.resolve(customPhoto: true, photo: nil).isCustom, "파일이 없으면 false 처럼")
        let s = PhotoMascotSource.resolve(customPhoto: true, photo: photo)
        XCTAssertTrue(s.isCustom)
        XCTAssertEqual(s.aspect, 2, accuracy: 1e-9)
    }

    func testSource_overlayPositions() {
        let b = PhotoMascotSource.builtin
        XCTAssertEqual(b.leftEye, PhotoMascotData.leftEye)
        XCTAssertEqual(b.rightEye, PhotoMascotData.rightEye)
        let c = PhotoMascotSource.custom(CustomPhoto(cgImage: cg(opaque(10, 10)), token: "t"))
        XCTAssertEqual(c.leftEye.x, 0.35, accuracy: 1e-12)
        XCTAssertEqual(c.rightEye.x, 0.65, accuracy: 1e-12)
        XCTAssertEqual(c.leftEye.y, 0.45, accuracy: 1e-12)
        XCTAssertEqual(c.rightEye.y, 0.45, accuracy: 1e-12)
        XCTAssertGreaterThan(c.angerCenter.x, 0.8, "오른쪽 위 모서리")
        XCTAssertLessThan(c.angerCenter.y, 0.2)
        // 눈물은 사용자 지정 눈 위치에서 시작한다
        let tears = PhotoMascotMotion.tears(seconds: 0, leftEye: c.leftEye, rightEye: c.rightEye)
        XCTAssertEqual(tears[0].x, 0.35, accuracy: 1e-12)
        XCTAssertEqual(tears[1].x, 0.65, accuracy: 1e-12)
    }

    // MARK: 아이콘

    func testMenuBarImage_customFitsWholeImageInSquare() {
        let photo = CustomPhoto(cgImage: cg(opaque(80, 40)), token: "t")
        let image = CustomPhotoIcons.menuBarImage(photo, pointSize: 18)
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(MascotImage.menuBarImage(character: .photo, customPhoto: photo).isTemplate)
        XCTAssertFalse(MascotImage.menuBarImage(character: .photo).isTemplate, "사진 없으면 내장 얼굴")
        XCTAssertTrue(MascotImage.menuBarImage(character: .orange, customPhoto: photo).isTemplate, "다른 캐릭터는 사진을 쓰지 않는다")
    }

    func testFitRect() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(CustomPhotoIcons.fitRect(aspect: 2, in: box), CGRect(x: 0, y: 25, width: 100, height: 50))
        XCTAssertEqual(CustomPhotoIcons.fitRect(aspect: 0.5, in: box), CGRect(x: 25, y: 0, width: 50, height: 100))
        XCTAssertEqual(CustomPhotoIcons.fitRect(aspect: 1, in: box), box)
    }

    func testFinderIcon_roundedTileWithPhotoInside() throws {
        let photo = CustomPhoto(cgImage: cg(buffer(100, 50) { _, _ in (255, 0, 0, 255) }), token: "t")
        let icon = try XCTUnwrap(CustomPhotoIcons.finderIcon(photo, size: 256))
        let cgIcon = try XCTUnwrap(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cgIcon.width, 256)
        let b = try XCTUnwrap(PixelBuffer(cgImage: cgIcon))
        XCTAssertEqual(b.alpha(0, 0), 0, "타일 바깥 모서리는 투명")
        XCTAssertEqual(b.alpha(30, 128), 255, "타일 안쪽(사진 바깥)은 불투명한 배경")
        XCTAssertEqual(b.rgba[(30 * 256 + 128) * 4 + 2], 0xE8, "배경은 하늘색(내장 아이콘과 같은 색)")
        XCTAssertEqual(b.rgba[(128 * 256 + 128) * 4], 255, "가운데는 사진(빨강)")
        XCTAssertEqual(b.rgba[(128 * 256 + 128) * 4 + 1], 0)
    }
}
