// 새 버전으로 갈아타기 (docs/spec.md 8절).
// 새 버전이 뜨면 ① 다른 곳에서 켜져 있는 칼퇴(같거나 옛 버전)를 끄고 ② 다른 위치에 남은 옛 버전 Kaltoe.app 을 휴지통으로 옮긴다.
// /Applications 에 덮어쓴 경우는 경로가 같아 지울 것이 없고, 켜져 있던 옛 프로세스만 끈다.
import AppKit

enum Handoff {
    static let bundleID = "dev.kaltoe.app"

    /// "1.2.3" 비교용. 숫자가 아닌 조각은 0.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// 번들의 Info.plist 를 직접 읽는다(Bundle 캐시를 피함). 칼퇴 번들이 아니면 nil.
    static func version(ofBundleAt url: URL) -> String? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              info["CFBundleIdentifier"] as? String == bundleID else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    /// 실행 중인 다른 칼퇴 처리. 나보다 새 버전이 이미 떠 있으면 false (나를 끈다).
    static func run() -> Bool {
        guard Bundle.main.bundleIdentifier == bundleID,
              let mine = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return true }
        let myURL = Bundle.main.bundleURL.standardizedFileURL
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        var oldBundles: [URL] = []
        for app in others {
            guard let url = app.bundleURL?.standardizedFileURL else { continue }
            if url != myURL, let v = version(ofBundleAt: url), compare(v, mine) == .orderedDescending {
                NSLog("Kaltoe: 더 새 버전(\(v))이 실행 중이라 종료")
                app.activate()
                return false
            }
            if url != myURL, let v = version(ofBundleAt: url), compare(v, mine) == .orderedAscending {
                oldBundles.append(url)
            }
            app.terminate()
        }

        // 다른 위치의 옛 번들은 프로세스가 끝나길 기다렸다가 휴지통으로 (실수해도 되살릴 수 있게 영구 삭제는 안 함).
        guard !others.isEmpty else { return true }
        DispatchQueue.global(qos: .utility).async {
            for app in others {
                for _ in 0..<30 where !app.isTerminated { Thread.sleep(forTimeInterval: 0.1) }
                if !app.isTerminated { app.forceTerminate() }
            }
            for url in oldBundles where url.lastPathComponent == "Kaltoe.app" {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    NSLog("Kaltoe: 옛 버전을 휴지통으로 옮김 \(url.path)")
                } catch {
                    NSLog("Kaltoe: 옛 버전 정리 실패 \(url.path): \(error)")
                }
            }
        }
        return true
    }
}
