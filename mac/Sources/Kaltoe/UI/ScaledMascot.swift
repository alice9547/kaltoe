import SwiftUI

/// 마스코트를 위젯 비율에 맞춰 키운다. 픽셀이 뭉개지지 않도록 격자 한 칸을 정수 pt 로 맞춘다 (docs/spec.md 5-1절).
/// MascotView 는 고치지 않고 `scaleEffect` 로만 키운다 (안티에일리어싱 없이 그리므로 정수 칸 크기에선 또렷하다).
struct ScaledMascot: View {
    var mood: MascotMood
    var tick: Int
    var jumpStart: Int?
    var outline = false
    var character: MascotCharacter = .maltese
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
        CGFloat(cellSize(baseSize: baseSize, ratio: ratio, gridWidth: character.width) * character.width)
    }

    var body: some View {
        MascotView(mood: mood, tick: tick, jumpStart: jumpStart, onTap: onTap, outline: outline, character: character)
            .scaledMascot(baseSize: baseSize, ratio: ratio, character: character)
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
