// Finder 의 앱 아이콘을 선택한 캐릭터에 맞춘다 (docs/spec.md 6-1절, 6-2절).
// - maltese: 말티즈 이미지로 사용자 지정 아이콘을 쓴다.
// - photo: 실사 말티즈 이미지(AppIcon-photo-1024.png)로 사용자 지정 아이콘을 쓴다.
//   사용자 지정 사진이 있으면(6-3절) 그 사진을 둥근 사각 배경 위에 얹은 아이콘을 실행 중에 만들어 쓴다.
// - orange: 사용자 지정 아이콘을 지워 앱 파일에 박힌 아이콘(주황이)으로 되돌린다.
// 무엇을 할지는 순수 함수 `AppIconPolicy.action`, 실제 NSWorkspace 호출은 `AppIconSwitcher`.
import AppKit

/// 마지막으로 적용한 상태. `signature` 는 앱 실행 파일의 정체(수정 시각)라서,
/// 앱을 다시 설치하면(사용자 지정 아이콘이 사라짐) 기록이 낡은 것으로 취급돼 다시 적용된다.
struct AppliedIcon: Equatable {
    var character: MascotCharacter
    var signature: String
    /// 사용자 지정 사진의 표식(`CustomPhoto.token`). 내장 이미지면 빈 문자열.
    var variant: String

    /// 저장 형식: `character@signature` 또는 사용자 지정 사진이면 `photo+variant@signature`.
    var stored: String { "\(character.rawValue)\(variant.isEmpty ? "" : "+" + variant)@\(signature)" }

    init(character: MascotCharacter, signature: String, variant: String = "") {
        self.character = character
        self.signature = signature
        self.variant = variant
    }

    init?(stored: String?) {
        guard let stored, let at = stored.firstIndex(of: "@") else { return nil }
        let head = stored[..<at]
        let parts = head.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard let c = MascotCharacter(rawValue: String(parts[0])) else { return nil }
        self.init(character: c, signature: String(stored[stored.index(after: at)...]),
                  variant: parts.count > 1 ? String(parts[1]) : "")
    }
}

enum AppIconAction: Equatable {
    /// 이미 원하는 상태 — 다시 쓰지 않는다.
    case none
    /// 말티즈 이미지를 사용자 지정 아이콘으로 쓴다.
    case setMaltese
    /// 실사 말티즈 이미지를 사용자 지정 아이콘으로 쓴다.
    case setPhoto
    /// 사용자 지정 사진으로 만든 이미지를 사용자 지정 아이콘으로 쓴다.
    case setCustomPhoto
    /// 사용자 지정 아이콘을 지운다 (박힌 아이콘 = 주황이로 복귀).
    case clear
}

enum AppIconPolicy {
    /// 현재 캐릭터(+ 사용자 지정 사진 표식) + 마지막 적용 값 + 현재 앱 서명 → 할 일.
    /// `variant` 는 실사 캐릭터가 사용자 지정 사진을 쓸 때만 의미가 있다(다른 캐릭터에서는 무시, 내장 사진이면 빈 문자열).
    /// 기록이 없거나 서명이 다르면(재설치 등) "아직 아무것도 적용 안 된 상태"(= 박힌 주황이 아이콘)로 본다.
    static func action(character: MascotCharacter, variant: String = "", last: AppliedIcon?, signature: String) -> AppIconAction {
        let want = character == .photo ? variant : ""
        let current: (character: MascotCharacter, variant: String) =
            last?.signature == signature ? (last!.character, last!.variant) : (.orange, "")
        guard character != current.character || want != current.variant else { return .none }
        switch character {
        case .maltese: return .setMaltese
        case .photo: return want.isEmpty ? .setPhoto : .setCustomPhoto
        case .orange: return .clear          // 박힌 아이콘(주황이)으로 복귀
        }
    }
}

enum AppIconSwitcher {
    static let defaultsKey = "appIcon.applied"
    static let malteseResource = "AppIcon-maltese-1024"
    static let photoResource = "AppIcon-photo-1024"

    /// 번들의 아이콘 이미지를 사용자 지정 아이콘으로 쓴다. 성공하면 true.
    private static func setCustomIcon(resource: String, path: String) -> Bool {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return false }
        return NSWorkspace.shared.setIcon(image, forFile: path, options: [])
    }

    /// 앱 실행 파일의 수정 시각 — 재설치를 알아채는 서명.
    static func currentSignature() -> String {
        let path = Bundle.main.executablePath ?? Bundle.main.bundlePath
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        return String(Int(date?.timeIntervalSince1970 ?? 0))
    }

    /// 시작 때와 캐릭터를 바꿀 때 부른다. 번들 식별자가 없으면(swift run) 아무것도 하지 않는다.
    /// 실패(읽기 전용 위치 등)는 조용히 무시하고 기록하지 않는다 — 다음 기회에 다시 시도한다.
    /// `customPhoto` 는 실사 캐릭터가 사용자 지정 사진을 쓸 때의 그 사진(아니면 nil).
    static func apply(character: MascotCharacter, customPhoto: CustomPhoto? = nil, defaults: UserDefaults = .standard) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let signature = currentSignature()
        let last = AppliedIcon(stored: defaults.string(forKey: defaultsKey))
        let path = Bundle.main.bundlePath

        let variant = character == .photo ? (customPhoto?.token ?? "") : ""
        switch AppIconPolicy.action(character: character, variant: variant, last: last, signature: signature) {
        case .none:
            return
        case .setMaltese:
            guard setCustomIcon(resource: malteseResource, path: path) else { return }
            defaults.set(AppliedIcon(character: .maltese, signature: signature).stored, forKey: defaultsKey)
        case .setPhoto:
            guard setCustomIcon(resource: photoResource, path: path) else { return }
            defaults.set(AppliedIcon(character: .photo, signature: signature).stored, forKey: defaultsKey)
        case .setCustomPhoto:
            guard let photo = customPhoto, let image = CustomPhotoIcons.finderIcon(photo),
                  NSWorkspace.shared.setIcon(image, forFile: path, options: []) else { return }
            defaults.set(AppliedIcon(character: .photo, signature: signature, variant: photo.token).stored, forKey: defaultsKey)
        case .clear:
            guard NSWorkspace.shared.setIcon(nil, forFile: path, options: []) else { return }
            defaults.set(AppliedIcon(character: .orange, signature: signature).stored, forKey: defaultsKey)
        }
    }
}
