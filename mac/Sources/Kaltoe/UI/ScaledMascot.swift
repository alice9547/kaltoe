import SwiftUI

/// 마스코트를 위젯 비율에 맞춰 키운다. 캐릭터에 따라 픽셀(MascotView) 또는 사진(PhotoMascotView)을 고른다.
/// 픽셀은 뭉개지지 않도록 격자 한 칸을 정수 pt 로 맞춘다 (docs/spec.md 5-1절).
/// MascotView 는 고치지 않고 `scaleEffect` 로만 키운다 (안티에일리어싱 없이 그리므로 정수 칸 크기에선 또렷하다).
/// 사진은 정수 배율이 필요 없어 기본 폭 60pt × 비율로 부드럽게 그린다 (docs/spec.md 6-2절).
struct ScaledMascot: View {
    var mood: MascotMood
    var tick: Int
    var jumpStart: Int?
    var outline = false
    var character: MascotCharacter = .maltese
    /// 실사(photo) 캐릭터가 그릴 사진 (내장 또는 사용자 지정). 다른 캐릭터에서는 쓰지 않는다.
    var photo: PhotoMascotSource = .builtin
    /// 기본(비율 1) 표시 크기 pt — 터미널 56, 말풍선 60.
    var baseSize: CGFloat
    /// fontSize / 12
    var ratio: CGFloat
    var onTap: () -> Void

    /// "기본 크기 × 비율"에 가장 가까운 정수 칸 크기(pt). 최소 1.
    static func cellSize(baseSize: CGFloat, ratio: CGFloat, gridWidth: Int = MascotCharacter.maltese.width) -> Int {
        max(1, Int((baseSize * ratio / CGFloat(gridWidth)).rounded()))
    }

    /// 레이아웃(화면에 차지하는) 한 변 길이 pt.
    static func displaySize(baseSize: CGFloat, ratio: CGFloat, character: MascotCharacter = .maltese) -> CGFloat {
        if character.isPhoto { return PhotoMascotView.displaySize(ratio: ratio) }
        return CGFloat(cellSize(baseSize: baseSize, ratio: ratio, gridWidth: character.width) * character.width)
    }

    var body: some View {
        if character.isPhoto {
            // 외곽선 대신 옅은 그림자 (outline 은 말풍선 모양에서만 true)
            PhotoMascotView(mood: mood, tick: tick, jumpStart: jumpStart, onTap: onTap, shadow: outline, ratio: ratio, source: photo)
        } else {
            MascotView(mood: mood, tick: tick, jumpStart: jumpStart, onTap: onTap, outline: outline, character: character)
                .scaledMascot(baseSize: baseSize, ratio: ratio, character: character)
        }
    }
}

extension View {
    /// MascotView 에 붙여 위젯 비율에 맞게 키운다 (레이아웃 크기도 함께 바뀐다).
    func scaledMascot(baseSize: CGFloat, ratio: CGFloat, character: MascotCharacter = .maltese) -> some View {
        let cell = ScaledMascot.cellSize(baseSize: baseSize, ratio: ratio, gridWidth: character.width)
        let natural = CGFloat(character.width * MascotView.cell(for: character))
        let scale = CGFloat(cell) / CGFloat(MascotView.cell(for: character))
        return self
            .frame(width: natural, height: natural, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: natural * scale, height: natural * scale, alignment: .topLeading)
    }
}
