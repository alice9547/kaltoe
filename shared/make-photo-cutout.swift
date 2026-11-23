// 실사 말티즈 배경 제거 (docs/spec.md 6-2절).
//   swift shared/make-photo-cutout.swift
// shared/source/maltese-photo.jpeg → Vision 전경 인스턴스 마스크(macOS 14+)로 강아지만 남기고
// 투명 여백을 잘라 긴 변 512px 로 shared/photo-maltese.png 에 저장한다.
// 가장자리는 마스크를 안쪽으로 줄여(erode) 바닥색 테를 없애고, 알파를 살짝 부드럽게 한다.
// 앱 안에서 사용자 지정 사진을 처리하는 코드(mac/Sources/Kaltoe/Core/CustomPhotoProcessing.swift 의 ForegroundCutout·PixelBuffer)는
// 같은 Vision 요청과 erode/blur 를 쓴다. 스크립트는 앱 소스를 import 할 수 없어 복사해 가진다 — 한쪽을 고치면 다른 쪽도 확인할 것.
// (이 스크립트는 거기에 더해 이 사진 전용의 색 오염 제거·채도 낮추기를 한다.)
import AppKit
import CoreImage
import Vision

let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.path.isEmpty || scriptDir.path == "." ? URL(fileURLWithPath: fm.currentDirectoryPath) : scriptDir
let inputURL = root.appendingPathComponent("source/maltese-photo.jpeg")
let outputURL = root.appendingPathComponent("photo-maltese.png")
let longSide = 512
let erodeRadius = 2          // 마스크를 안쪽으로 줄이는 px (원본 해상도 기준)
let featherPasses = 1        // 알파 부드럽게 (박스 블러 3x3 반복 횟수)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// 1. 방향(EXIF)을 적용해 읽는다.
guard let ci = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else { fail("사진을 읽을 수 없음: \(inputURL.path)") }
let width = Int(ci.extent.width), height = Int(ci.extent.height)
let ctx = CIContext()
guard let cgImage = ctx.createCGImage(ci, from: ci.extent) else { fail("이미지 변환 실패") }

// 2. 전경 인스턴스 마스크.
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
let request = VNGenerateForegroundInstanceMaskRequest()
do { try handler.perform([request]) } catch { fail("Vision 실패: \(error)") }
guard let observation = request.results?.first else { fail("전경을 찾지 못함") }
let maskBuffer: CVPixelBuffer
do { maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) }
catch { fail("마스크 생성 실패: \(error)") }

// 3. 마스크를 width×height 의 0~255 배열로.
var alpha = [UInt8](repeating: 0, count: width * height)
do {
    CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }
    let mw = CVPixelBufferGetWidth(maskBuffer), mh = CVPixelBufferGetHeight(maskBuffer)
    guard mw == width, mh == height, let base = CVPixelBufferGetBaseAddress(maskBuffer) else { fail("마스크 크기 불일치 \(mw)x\(mh)") }
    let stride = CVPixelBufferGetBytesPerRow(maskBuffer)
    let format = CVPixelBufferGetPixelFormatType(maskBuffer)
    for y in 0..<height {
        let row = base.advanced(by: y * stride)
        for x in 0..<width {
            let v: Float
            if format == kCVPixelFormatType_OneComponent32Float { v = row.load(fromByteOffset: x * 4, as: Float.self) }
            else if format == kCVPixelFormatType_OneComponent8 { v = Float(row.load(fromByteOffset: x, as: UInt8.self)) / 255 }
            else { fail("알 수 없는 마스크 형식 \(format)") }
            alpha[y * width + x] = UInt8(max(0, min(255, (v * 255).rounded())))
        }
    }
}

// 4. 안쪽으로 줄이기(분리형 최소값 필터) + 부드럽게(3x3 박스 블러).
func erode(_ a: [UInt8], radius: Int) -> [UInt8] {
    guard radius > 0 else { return a }
    var tmp = a, out = a
    for y in 0..<height {
        for x in 0..<width {
            var m: UInt8 = 255
            for dx in -radius...radius { m = min(m, a[y * width + min(max(x + dx, 0), width - 1)]) }
            tmp[y * width + x] = m
        }
    }
    for y in 0..<height {
        for x in 0..<width {
            var m: UInt8 = 255
            for dy in -radius...radius { m = min(m, tmp[min(max(y + dy, 0), height - 1) * width + x]) }
            out[y * width + x] = m
        }
    }
    return out
}
func blur(_ a: [UInt8]) -> [UInt8] {
    var out = a
    for y in 0..<height {
        for x in 0..<width {
            var sum = 0
            for dy in -1...1 { for dx in -1...1 {
                sum += Int(a[min(max(y + dy, 0), height - 1) * width + min(max(x + dx, 0), width - 1)])
            } }
            out[y * width + x] = UInt8(sum / 9)
        }
    }
    return out
}
alpha = erode(alpha, radius: erodeRadius)
for _ in 0..<featherPasses { alpha = blur(alpha) }

// 5. 원본 RGB 와 합쳐 비프리멀티 RGBA 로.
var rgba = [UInt8](repeating: 0, count: width * height * 4)
do {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let c = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("컨텍스트 실패") }
    c.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
}
// 5-1. 가장자리 색 오염 제거: 반투명한 털 가장자리에는 바닥색이 섞여 베이지 테가 생긴다.
// 안쪽(깊이 `coreDepth` px 이상)의 색을 바깥으로 번지게 해서, 가장자리 띠의 색을 안쪽 털 색으로 바꾼다.
let coreDepth = 10
let core = erode(alpha, radius: coreDepth)
var filled = [Bool](repeating: false, count: width * height)
var field = [Float](repeating: 0, count: width * height * 3)
for i in 0..<(width * height) where core[i] >= 250 {
    filled[i] = true
    for k in 0..<3 { field[i * 3 + k] = Float(rgba[i * 4 + k]) }
}
for _ in 0..<(coreDepth + 8) {
    var newly: [(Int, [Float])] = []
    for y in 0..<height {
        for x in 0..<width where !filled[y * width + x] && alpha[y * width + x] > 0 {
            var sum: [Float] = [0, 0, 0], n: Float = 0
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height, filled[ny * width + nx] else { continue }
                for k in 0..<3 { sum[k] += field[(ny * width + nx) * 3 + k] }
                n += 1
            }
            if n > 0 { newly.append((y * width + x, sum.map { $0 / n })) }
        }
    }
    if newly.isEmpty { break }
    for (i, c) in newly { filled[i] = true; for k in 0..<3 { field[i * 3 + k] = c[k] } }
}
for i in 0..<(width * height) where core[i] < 250 && filled[i] && alpha[i] > 0 {
    for k in 0..<3 {
        rgba[i * 4 + k] = UInt8(max(0, min(255, (Float(rgba[i * 4 + k]) * 0.15 + field[i * 3 + k] * 0.85).rounded())))
    }
}

// 5-2. 귀처럼 얇고 반투명한 털은 전체가 바닥색으로 물든다. 가장자리에서 안쪽으로 갈수록 옅어지는 가중치로
// 채도를 낮추고 살짝 밝힌다 (가중치를 크게 번지게 해서 띠 경계가 보이지 않게 한다).
func boxBlur(_ a: [Float], radius: Int) -> [Float] {
    var tmp = a, out = a
    let n = Float(2 * radius + 1)
    for y in 0..<height {
        var sum: Float = 0
        for dx in -radius...radius { sum += a[y * width + min(max(dx, 0), width - 1)] }
        for x in 0..<width {
            tmp[y * width + x] = sum / n
            sum += a[y * width + min(x + radius + 1, width - 1)] - a[y * width + max(x - radius, 0)]
        }
    }
    for x in 0..<width {
        var sum: Float = 0
        for dy in -radius...radius { sum += tmp[min(max(dy, 0), height - 1) * width + x] }
        for y in 0..<height {
            out[y * width + x] = sum / n
            sum += tmp[min(y + radius + 1, height - 1) * width + x] - tmp[max(y - radius, 0) * width + x]
        }
    }
    return out
}
let warmDepth = 30
var weight = erode(alpha, radius: warmDepth).map { 1 - Float($0) / 255 }
for _ in 0..<3 { weight = boxBlur(weight, radius: 14) }
for i in 0..<(width * height) where alpha[i] > 0 {
    let w = weight[i] * 0.9
    if w < 0.01 { continue }
    let r = Float(rgba[i * 4]), g = Float(rgba[i * 4 + 1]), b = Float(rgba[i * 4 + 2])
    let lum = 0.299 * r + 0.587 * g + 0.114 * b
    for (k, v) in [r, g, b].enumerated() {
        var c = lum + (v - lum) * 0.4             // 채도 60% 감소
        c += (255 - c) * 0.2                      // 밝게
        rgba[i * 4 + k] = UInt8(max(0, min(255, (v + (c - v) * w).rounded())))
    }
}

// premultiplied 원본(알파 255) × 마스크 알파 → 프리멀티 값으로 곱한다.
for i in 0..<(width * height) {
    let a = Int(alpha[i])
    rgba[i * 4] = UInt8(Int(rgba[i * 4]) * a / 255)
    rgba[i * 4 + 1] = UInt8(Int(rgba[i * 4 + 1]) * a / 255)
    rgba[i * 4 + 2] = UInt8(Int(rgba[i * 4 + 2]) * a / 255)
    rgba[i * 4 + 3] = UInt8(a)
}

// 6. 투명 여백 자르기 (알파 > 8 기준 경계 상자).
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height { for x in 0..<width where alpha[y * width + x] > 8 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
guard maxX >= 0 else { fail("남은 픽셀이 없음") }
let cropW = maxX - minX + 1, cropH = maxY - minY + 1
print("bbox(원본 좌표, 방향 적용 후): x \(minX)…\(maxX), y \(minY)…\(maxY) → \(cropW)x\(cropH)")

var cropped = [UInt8](repeating: 0, count: cropW * cropH * 4)
for y in 0..<cropH {
    let s = ((y + minY) * width + minX) * 4
    cropped.replaceSubrange((y * cropW * 4)..<((y + 1) * cropW * 4), with: rgba[s..<(s + cropW * 4)])
}

// 7. 긴 변 512px 로 축소 (고품질 보간, 프리멀티 상태로).
let scale = Double(longSide) / Double(max(cropW, cropH))
let outW = max(1, Int((Double(cropW) * scale).rounded())), outH = max(1, Int((Double(cropH) * scale).rounded()))
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let srcCtx = CGContext(data: &cropped, width: cropW, height: cropH, bitsPerComponent: 8, bytesPerRow: cropW * 4,
                             space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let srcImage = srcCtx.makeImage(),
      let dstCtx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                             space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("축소 컨텍스트 실패") }
dstCtx.interpolationQuality = .high
dstCtx.draw(srcImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
guard let outImage = dstCtx.makeImage() else { fail("출력 이미지 실패") }

let rep = NSBitmapImageRep(cgImage: outImage)
guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG 인코딩 실패") }
do { try data.write(to: outputURL) } catch { fail("저장 실패: \(error)") }
print("저장: \(outputURL.path) (\(outW)x\(outH))")
