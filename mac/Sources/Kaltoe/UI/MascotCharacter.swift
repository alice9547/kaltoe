// 마스코트 캐릭터 선택 (docs/spec.md 6-1절). 그림 데이터는 생성물(MascotData / MascotDataOrange).
enum MascotCharacter: String, CaseIterable {
    case maltese, orange

    var width: Int {
        switch self { case .maltese: return MascotData.width; case .orange: return MascotDataOrange.width }
    }
    var height: Int {
        switch self { case .maltese: return MascotData.height; case .orange: return MascotDataOrange.height }
    }
    var palette: [Character: UInt32] {
        switch self { case .maltese: return MascotData.palette; case .orange: return MascotDataOrange.palette }
    }
    var frames: [String: [String]] {
        switch self { case .maltese: return MascotData.frames; case .orange: return MascotDataOrange.frames }
    }

    /// 외곽선에서 제외하는 장식 픽셀 문자(색종이·반짝 별·화남 표시). 캐릭터 팔레트 규약.
    var decorationPixels: Set<Character> {
        switch self {
        case .maltese: return ["R", "Y", "N", "U", "S"]
        case .orange: return ["R", "Y", "N", "U"]      // 주황이의 S 는 몸 그늘색이라 외곽선 대상
        }
    }

    /// 메뉴바 템플릿 이미지로 쓸 idle 프레임의 행 범위(얼굴·몸통 부분).
    var menuBarRows: Range<Int> {
        switch self { case .maltese: return 0..<14; case .orange: return 3..<14 }
    }

    /// 메뉴바 템플릿에서 투명하게 뚫는 팔레트 문자(눈·코·입).
    var menuBarCutouts: Set<Character> {
        switch self { case .maltese: return ["K", "M", "T"]; case .orange: return ["E"] }
    }
}
