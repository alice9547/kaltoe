// 사용자 지정 사진의 저장·보관 (docs/spec.md 6-3절).
// 저장 위치: ~/Library/Application Support/Kaltoe/custom-mascot.png. 원본 파일 경로는 저장하지 않는다.
import AppKit
import Combine

/// 처리가 끝난 사용자 지정 사진 한 장.
final class CustomPhoto {
    let cgImage: CGImage
    let nsImage: NSImage
    /// 사진이 바뀌었는지 알아보는 표식 (Finder 아이콘을 다시 만들지 판단하는 데 쓴다).
    let token: String

    init(cgImage: CGImage, token: String) {
        self.cgImage = cgImage
        self.nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        self.token = token
    }

    var aspect: CGFloat { CGFloat(cgImage.width) / CGFloat(max(1, cgImage.height)) }
}

final class CustomPhotoStore: ObservableObject {
    static let shared = CustomPhotoStore()
    static let fileName = "custom-mascot.png"

    @Published private(set) var photo: CustomPhoto?
    private let directory: URL

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kaltoe", isDirectory: true)
    }

    init(directory: URL = CustomPhotoStore.defaultDirectory) {
        self.directory = directory
        self.photo = Self.read(fileURL: directory.appendingPathComponent(Self.fileName))
    }

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// 저장한 파일을 읽는다. 없거나 깨졌으면 nil (그러면 내장 사진처럼 동작한다).
    static func read(fileURL: URL) -> CustomPhoto? {
        guard let data = try? Data(contentsOf: fileURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let stamp = Int(((attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970)
        return CustomPhoto(cgImage: image, token: "\(stamp)-\(data.count)")
    }

    /// 처리된 사진을 저장하고 즉시 반영한다. 저장에 실패하면 던지고 이전 사진을 유지한다.
    func install(_ image: CGImage) throws {
        guard let png = CustomPhotoProcessor.pngData(image) else { throw CustomPhotoError.processingFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: fileURL, options: .atomic)
        photo = Self.read(fileURL: fileURL) ?? CustomPhoto(cgImage: image, token: "\(png.count)")
    }

    /// 이번 실행에만 쓴다 — 파일을 쓰지 않는다 (확인용 `--custom-photo`).
    func useTransient(_ image: CGImage) {
        photo = CustomPhoto(cgImage: image, token: "transient")
    }

    /// 저장한 파일을 지우고 내장 사진으로 돌아간다.
    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        photo = nil
    }
}

/// 위젯이 그릴 사진 한 장과 덧그림 위치 (docs/spec.md 6-2절, 6-3절).
struct PhotoMascotSource {
    var image: NSImage
    /// 이미지 폭 / 높이
    var aspect: CGFloat
    /// 이미지 기준 비율 좌표 (눈물이 떨어지는 곳, 화남 표시의 중심)
    var leftEye: CGPoint
    var rightEye: CGPoint
    var angerCenter: CGPoint
    var isCustom: Bool

    /// 내장 강아지 사진: 눈 좌표는 측정한 값(PhotoMascotData).
    static let builtin = PhotoMascotSource(
        image: PhotoMascotImage.image, aspect: PhotoMascotImage.aspect,
        leftEye: PhotoMascotData.leftEye, rightEye: PhotoMascotData.rightEye,
        angerCenter: CGPoint(x: PhotoMascotMotion.angerCenter.x, y: PhotoMascotMotion.angerCenter.y), isCustom: false)

    /// 사용자 지정 사진: 눈 위치를 모르므로 눈물은 폭의 35%·65%, 높이의 45% 에서 떨어지고 화남 표시는 오른쪽 위 모서리 (spec 6-3절).
    static func custom(_ photo: CustomPhoto) -> PhotoMascotSource {
        PhotoMascotSource(
            image: photo.nsImage, aspect: photo.aspect,
            leftEye: PhotoMascotMotion.customLeftEye, rightEye: PhotoMascotMotion.customRightEye,
            angerCenter: CGPoint(x: PhotoMascotMotion.customAngerCenter.x, y: PhotoMascotMotion.customAngerCenter.y), isCustom: true)
    }

    /// 설정의 `customPhoto` 가 켜져 있고 사진이 있으면 사용자 지정, 아니면 내장 사진.
    static func resolve(customPhoto enabled: Bool, photo: CustomPhoto?) -> PhotoMascotSource {
        if enabled, let photo { return .custom(photo) }
        return .builtin
    }
}

/// 사용자 지정 사진으로 만드는 아이콘들.
enum CustomPhotoIcons {
    /// 메뉴바용: 전체 이미지를 정사각(pt) 안에 맞춰 넣은 컬러 이미지(템플릿 아님).
    static func menuBarImage(_ photo: CustomPhoto, pointSize: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let fit = fitRect(aspect: photo.aspect, in: rect)
            NSGraphicsContext.current?.imageInterpolation = .high
            photo.nsImage.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// `rect` 안에 비율을 유지하며 가운데 놓는 사각형.
    static func fitRect(aspect: CGFloat, in rect: CGRect) -> CGRect {
        let w = aspect >= 1 ? rect.width : rect.height * aspect
        let h = aspect >= 1 ? rect.width / aspect : rect.height
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Finder 아이콘: 둥근 사각 배경(AppIcon-photo-1024.png 와 같은 색·모양) 위에 사진을 맞춰 놓는다. 크기는 1024px.
    static func finderIcon(_ photo: CustomPhoto, size: Int = 1024) -> NSImage? {
        let s = CGFloat(size)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let margin = (s * 100 / 1024).rounded()
        let tile = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.setFillColor(CGColor(colorSpace: sRGB, components: [0x8E / 255.0, 0xC5 / 255.0, 0xE8 / 255.0, 1])!)   // 하늘색 (내장 아이콘과 같음)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil))
        ctx.fillPath()
        let box = CGRect(x: 0, y: 0, width: s * 0.70, height: s * 0.70)
        var fit = fitRect(aspect: photo.aspect, in: box)
        fit = fit.offsetBy(dx: s / 2 - box.midX, dy: s / 2 - box.midY)
        ctx.interpolationQuality = .high
        ctx.draw(photo.cgImage, in: fit)
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: size, height: size))
    }
}
