// 마스코트 캐릭터 선택 (docs/spec.md 6-1절, 6-2절).
// 픽셀 그림 데이터는 생성물(MascotData / MascotDataOrange), 실사(photo)는 PhotoMascotData + PhotoMascotView.
enum MascotCharacter: String, CaseIterable {
    case maltese, orange, photo

    /// 사진 한 장으로 그리는 캐릭터인가. 픽셀 격자(width/height/palette/frames)가 없다.
    var isPhoto: Bool { self == .photo }

    /// 픽셀 격자 접근자가 읽는 캐릭터. 사진 캐릭터에는 격자가 없어서 말티즈 격자로 대신한다
    /// (격자 값을 쓰는 곳이 깨지지 않게 하는 안전값일 뿐 — 그리는 쪽은 `isPhoto` 로 먼저 분기해야 한다).
    private var pixelSource: MascotCharacter { self == .photo ? .maltese : self }

    var width: Int {
        switch pixelSource { case .orange: return MascotDataOrange.width; default: return MascotData.width }
    }
    var height: Int {
        switch pixelSource { case .orange: return MascotDataOrange.height; default: return MascotData.height }
    }
    var palette: [Character: UInt32] {
        switch pixelSource { case .orange: return MascotDataOrange.palette; default: return MascotData.palette }
    }
    var frames: [String: [String]] {
        switch pixelSource { case .orange: return MascotDataOrange.frames; default: return MascotData.frames }
    }

    /// 외곽선에서 제외하는 장식 픽셀 문자(색종이·반짝 별·화남 표시). 캐릭터 팔레트 규약.
    var decorationPixels: Set<Character> {
        switch pixelSource {
        case .orange: return ["R", "Y", "N", "U"]      // 주황이의 S 는 몸 그늘색이라 외곽선 대상
        default: return ["R", "Y", "N", "U", "S"]
        }
    }

    /// 메뉴바 템플릿 이미지로 쓸 idle 프레임의 행 범위(얼굴·몸통 부분).
    var menuBarRows: Range<Int> {
        switch pixelSource { case .orange: return 3..<14; default: return 0..<14 }
    }

    /// 메뉴바 템플릿에서 투명하게 뚫는 팔레트 문자(눈·코·입).
    var menuBarCutouts: Set<Character> {
        switch pixelSource { case .orange: return ["E"]; default: return ["K", "M", "T"] }
    }
}
