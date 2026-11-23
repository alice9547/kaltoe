// Finder 의 앱 아이콘을 선택한 캐릭터에 맞춘다 (docs/spec.md 6-1절).
// - maltese: 말티즈 이미지로 사용자 지정 아이콘을 쓴다.
// - orange: 사용자 지정 아이콘을 지워 앱 파일에 박힌 아이콘(주황이)으로 되돌린다.
// 무엇을 할지는 순수 함수 `AppIconPolicy.action`, 실제 NSWorkspace 호출은 `AppIconSwitcher`.
import AppKit

/// 마지막으로 적용한 상태. `signature` 는 앱 실행 파일의 정체(수정 시각)라서,
/// 앱을 다시 설치하면(사용자 지정 아이콘이 사라짐) 기록이 낡은 것으로 취급돼 다시 적용된다.
struct AppliedIcon: Equatable {
    var character: MascotCharacter
    var signature: String

    var stored: String { "\(character.rawValue)@\(signature)" }

    init(character: MascotCharacter, signature: String) {
        self.character = character
        self.signature = signature
    }

    init?(stored: String?) {
        guard let stored, let at = stored.firstIndex(of: "@"),
              let c = MascotCharacter(rawValue: String(stored[..<at])) else { return nil }
        self.init(character: c, signature: String(stored[stored.index(after: at)...]))
    }
}

enum AppIconAction: Equatable {
    /// 이미 원하는 상태 — 다시 쓰지 않는다.
    case none
    /// 말티즈 이미지를 사용자 지정 아이콘으로 쓴다.
    case setMaltese
    /// 사용자 지정 아이콘을 지운다 (박힌 아이콘 = 주황이로 복귀).
    case clear
}

enum AppIconPolicy {
    /// 현재 캐릭터 + 마지막 적용 값 + 현재 앱 서명 → 할 일.
    /// 기록이 없거나 서명이 다르면(재설치 등) "아직 아무것도 적용 안 된 상태"(= 박힌 주황이 아이콘)로 본다.
    static func action(character: MascotCharacter, last: AppliedIcon?, signature: String) -> AppIconAction {
        let current: MascotCharacter = (last?.signature == signature ? last?.character : nil) ?? .orange
        switch (character, current) {
        case (.maltese, .maltese), (.orange, .orange): return .none
        case (.maltese, .orange): return .setMaltese
        case (.orange, .maltese): return .clear
        }
    }
}

enum AppIconSwitcher {
    static let defaultsKey = "appIcon.applied"
    static let malteseResource = "AppIcon-maltese-1024"

    /// 앱 실행 파일의 수정 시각 — 재설치를 알아채는 서명.
    static func currentSignature() -> String {
        let path = Bundle.main.executablePath ?? Bundle.main.bundlePath
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        return String(Int(date?.timeIntervalSince1970 ?? 0))
    }

    /// 시작 때와 캐릭터를 바꿀 때 부른다. 번들 식별자가 없으면(swift run) 아무것도 하지 않는다.
    /// 실패(읽기 전용 위치 등)는 조용히 무시하고 기록하지 않는다 — 다음 기회에 다시 시도한다.
    static func apply(character: MascotCharacter, defaults: UserDefaults = .standard) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let signature = currentSignature()
        let last = AppliedIcon(stored: defaults.string(forKey: defaultsKey))
        let path = Bundle.main.bundlePath

        switch AppIconPolicy.action(character: character, last: last, signature: signature) {
        case .none:
            return
        case .setMaltese:
            guard let url = Bundle.main.url(forResource: malteseResource, withExtension: "png"),
                  let image = NSImage(contentsOf: url),
                  NSWorkspace.shared.setIcon(image, forFile: path, options: []) else { return }
            defaults.set(AppliedIcon(character: .maltese, signature: signature).stored, forKey: defaultsKey)
        case .clear:
            guard NSWorkspace.shared.setIcon(nil, forFile: path, options: []) else { return }
            defaults.set(AppliedIcon(character: .orange, signature: signature).stored, forKey: defaultsKey)
        }
    }
}
