// 사용자 지정 사진 처리 (docs/spec.md 6-3절): 읽기(EXIF 방향) → 배경 지우기 → 투명 여백 자르기 → 긴 변 512px 로 축소.
// 픽셀 계산은 `PixelBuffer` 의 순수 함수(알파 판정·경계 상자·원형 마스크·마스크 적용·축소 크기)로 분리해 테스트한다.
// Vision 으로 피사체만 남기는 부분(`ForegroundCutout`)은 shared/make-photo-cutout.swift 의 처리와 같은 방식이다
// (스크립트는 이 앱 소스를 import 할 수 없어서 따로 복사해 가진다 — 한쪽을 고치면 다른 쪽도 확인할 것).
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// 프리멀티플라이드 RGBA(8비트) 픽셀 버퍼. CoreGraphics 의 premultipliedLast 와 같은 배치.
struct PixelBuffer: Equatable {
    var width: Int
    var height: Int
    var rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4)
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    init(width: Int, height: Int) {
        self.init(width: width, height: height, rgba: [UInt8](repeating: 0, count: width * height * 4))
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { rgba[(y * width + x) * 4 + 3] }

    // MARK: 알파 판정·경계 상자 (순수)

    /// 알파가 255 보다 작은 픽셀의 비율 (0~1).
    var transparentFraction: Double {
        guard width * height > 0 else { return 0 }
        var n = 0
        var i = 3
        while i < rgba.count { if rgba[i] < 255 { n += 1 }; i += 4 }
        return Double(n) / Double(width * height)
    }

    /// 이미 투명 부분이 있는 이미지인가: 알파 < 255 인 픽셀이 1% 이상 (spec 6-3절).
    var hasTransparency: Bool { transparentFraction >= 0.01 }

    /// 알파가 `threshold` 보다 큰 픽셀을 모두 담는 최소 사각형. 하나도 없으면 nil.
    func opaqueBounds(threshold: UInt8 = 8) -> (x: Int, y: Int, width: Int, height: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) > threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    // MARK: 자르기·마스크 (순수)

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> PixelBuffer {
        var out = PixelBuffer(width: w, height: h)
        for row in 0..<h {
            let src = ((y + row) * width + x) * 4
            out.rgba.replaceSubrange((row * w * 4)..<((row + 1) * w * 4), with: rgba[src..<(src + w * 4)])
        }
        return out
    }

    /// 가운데 기준 정사각형으로 자른 뒤 원 밖을 투명하게 한다. 가장자리 1px 는 부드럽게 (spec 6-3절 원형 자르기).
    func circleCropped() -> PixelBuffer {
        let side = min(width, height)
        var out = cropped(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        let c = Double(side) / 2
        for y in 0..<side {
            for x in 0..<side {
                let d = (((Double(x) + 0.5 - c) * (Double(x) + 0.5 - c)) + ((Double(y) + 0.5 - c) * (Double(y) + 0.5 - c))).squareRoot()
                out.scaleAlpha(x, y, by: PixelBuffer.circleCoverage(distance: d, radius: c))
            }
        }
        return out
    }

    /// 중심에서 `distance` 만큼 떨어진 픽셀의 원 안쪽 비율(0~1). 반지름 안쪽 1px 에 걸쳐 부드럽게 줄어든다.
    static func circleCoverage(distance: Double, radius: Double) -> Double {
        min(1, max(0, radius - distance + 0.5))
    }

    /// 마스크(0~255, 크기가 같아야 함)를 알파에 곱한다.
    func applying(mask: [UInt8]) -> PixelBuffer {
        precondition(mask.count == width * height)
        var out = self
        for i in 0..<(width * height) {
            let m = Int(mask[i])
            if m == 255 { continue }
            for k in 0..<4 { out.rgba[i * 4 + k] = UInt8(Int(out.rgba[i * 4 + k]) * m / 255) }
        }
        return out
    }

    private mutating func scaleAlpha(_ x: Int, _ y: Int, by f: Double) {
        guard f < 1 else { return }
        let i = (y * width + x) * 4
        for k in 0..<4 { rgba[i + k] = UInt8((Double(rgba[i + k]) * f).rounded()) }
    }

    /// 긴 변이 `longSide` 를 넘으면 그 크기에 맞춘 (너비, 높이). 작으면 그대로(키우지 않는다).
    static func fitSize(width: Int, height: Int, longSide: Int) -> (width: Int, height: Int) {
        let long = max(width, height)
        guard long > longSide else { return (width, height) }
        let k = Double(longSide) / Double(long)
        return (max(1, Int((Double(width) * k).rounded())), max(1, Int((Double(height) * k).rounded())))
    }

    // MARK: 마스크 다듬기 (순수)

    /// 마스크를 안쪽으로 줄인다(최소값 필터, 분리형).
    static func eroded(_ a: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return a }
        var tmp = a, out = a
        for y in 0..<height { for x in 0..<width {
            var m: UInt8 = 255
            for dx in -radius...radius { m = min(m, a[y * width + min(max(x + dx, 0), width - 1)]) }
            tmp[y * width + x] = m
        } }
        for y in 0..<height { for x in 0..<width {
            var m: UInt8 = 255
            for dy in -radius...radius { m = min(m, tmp[min(max(y + dy, 0), height - 1) * width + x]) }
            out[y * width + x] = m
        } }
        return out
    }

    /// 3x3 박스 블러.
    static func blurred(_ a: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = a
        for y in 0..<height { for x in 0..<width {
            var sum = 0
            for dy in -1...1 { for dx in -1...1 {
                sum += Int(a[min(max(y + dy, 0), height - 1) * width + min(max(x + dx, 0), width - 1)])
            } }
            out[y * width + x] = UInt8(sum / 9)
        } }
        return out
    }

    // MARK: CGImage 변환

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: PixelBuffer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, rgba: data)
    }

    func makeCGImage() -> CGImage? {
        var data = rgba
        return data.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: PixelBuffer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }
}

/// Vision 의 전경 인스턴스 마스크(macOS 14+)로 피사체만 남기는 마스크(0~255)를 만든다. 못 찾으면 nil.
enum ForegroundCutout {
    static func mask(for image: CGImage) -> [UInt8]? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first, !observation.allInstances.isEmpty,
              let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w == image.width, h == image.height, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * stride)
            for x in 0..<w {
                let v: Float
                if format == kCVPixelFormatType_OneComponent32Float { v = row.load(fromByteOffset: x * 4, as: Float.self) }
                else if format == kCVPixelFormatType_OneComponent8 { v = Float(row.load(fromByteOffset: x, as: UInt8.self)) / 255 }
                else { return nil }
                out[y * w + x] = UInt8(max(0, min(255, (v * 255).rounded())))
            }
        }
        return out
    }
}

enum CustomPhotoError: Error { case unreadable, processingFailed }

enum CustomPhotoProcessor {
    /// 저장하는 사진의 긴 변 (spec 6-3절).
    static let longSide = 512
    /// 읽을 때 줄여 두는 상한(처리 속도·메모리). 512 로 줄이기 전의 작업 해상도.
    static let workingLongSide = 1600
    /// 피사체로 인정하는 최소 면적 비율. 이보다 작으면 "못 찾음" 으로 보고 원형 자르기로 대체한다.
    static let minSubjectFraction = 0.02

    /// 피사체 마스크를 만드는 함수 (테스트에서 바꿔 끼운다). 못 찾으면 nil.
    typealias MaskProvider = (CGImage) -> [UInt8]?

    /// 파일 → 처리된 이미지. EXIF 방향을 적용해 읽는다 (PNG, JPEG, HEIC, BMP, GIF 첫 프레임).
    static func process(url: URL, maskProvider: MaskProvider = ForegroundCutout.mask(for:)) throws -> CGImage {
        try process(cgImage: try load(url: url), maskProvider: maskProvider)
    }

    /// (1) 읽기, EXIF 방향 적용 — 방향까지 반영된 CGImage 를 돌려준다. 작업 해상도(긴 변 1600)로 줄인다.
    static func load(url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw CustomPhotoError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // EXIF 방향 적용
            kCGImageSourceThumbnailMaxPixelSize: workingLongSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {   // 0번째 프레임
            throw CustomPhotoError.unreadable
        }
        return image
    }

    /// (2) 배경 지우기 → (3) 투명 여백 자르기 → (4) 긴 변 512px 로 축소.
    static func process(cgImage: CGImage, maskProvider: MaskProvider = ForegroundCutout.mask(for:)) throws -> CGImage {
        guard var buffer = PixelBuffer(cgImage: cgImage) else { throw CustomPhotoError.unreadable }

        if !buffer.hasTransparency {                    // 이미 투명 부분이 있으면 그대로 쓴다
            if let mask = maskProvider(cgImage), mask.count == buffer.width * buffer.height, subjectFraction(mask) >= minSubjectFraction {
                let radius = max(1, Int((Double(max(buffer.width, buffer.height)) / 600).rounded()))
                var m = PixelBuffer.eroded(mask, width: buffer.width, height: buffer.height, radius: radius)   // 가장자리 배경색 테 제거
                m = PixelBuffer.blurred(m, width: buffer.width, height: buffer.height)
                buffer = buffer.applying(mask: m)
            } else {
                buffer = buffer.circleCropped()         // 피사체를 못 찾으면 가운데 원형
            }
        }

        guard let b = buffer.opaqueBounds() else { throw CustomPhotoError.processingFailed }
        let trimmed = buffer.cropped(x: b.x, y: b.y, width: b.width, height: b.height)
        guard let cg = trimmed.makeCGImage() else { throw CustomPhotoError.processingFailed }
        return try scaledDown(cg, longSide: longSide)
    }

    /// 마스크에서 피사체(값 > 127)가 차지하는 비율.
    static func subjectFraction(_ mask: [UInt8]) -> Double {
        guard !mask.isEmpty else { return 0 }
        return Double(mask.filter { $0 > 127 }.count) / Double(mask.count)
    }

    static func scaledDown(_ image: CGImage, longSide: Int) throws -> CGImage {
        let size = PixelBuffer.fitSize(width: image.width, height: image.height, longSide: longSide)
        if size.width == image.width && size.height == image.height { return image }
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CustomPhotoError.processingFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let out = ctx.makeImage() else { throw CustomPhotoError.processingFailed }
        return out
    }

    /// (5) PNG 데이터.
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
