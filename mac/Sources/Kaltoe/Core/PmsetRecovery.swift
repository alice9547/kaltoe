// 사후 복구 — `pmset -g log` 에서 "사용자가 깨운" 첫 시각을 찾는다.
import Foundation

enum PmsetLogParser {
    /// 로그에서 전체 깨어남(FullWake) 시각을 모두 뽑는다 (로그 순서대로).
    ///
    /// 이 맥의 실제 형식 (구분: 시각 / 카테고리 / 설명, 카테고리 뒤는 공백·탭):
    ///   `2026-11-23 13:27:17 +0900 Wake   \tDarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity ...`
    ///   `2026-11-23 12:38:36 +0900 Wake   \tWake from Deep Idle [CDNVA] : due to ... HID Activity ...`
    /// 카테고리가 정확히 `Wake` 인 줄만 채택한다. 제외되는 줄:
    ///   - `DarkWake` 카테고리 (화면이 켜지지 않는 백그라운드 깨어남)
    ///   - `Wake Requests`, `WakeDetails`, `WakeTime` 등 이름만 비슷한 다른 카테고리
    static func fullWakeTimes(in log: String) -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var result: [Date] = []
        log.enumerateLines { line, _ in
            // 시각 부분 "2026-11-23 13:27:17 +0900" 은 25자, 뒤에 공백 1칸.
            guard line.utf8.count > 30, line.hasPrefix("20") else { return }
            let timestamp = line.prefix(25)
            let rest = line.dropFirst(26)
            guard rest.hasPrefix("Wake") else { return }
            let afterCategory = rest.dropFirst(4)
            // 카테고리가 "Wake" 로 정확히 끝나야 한다 (WakeTime, WakeDetails 제외).
            guard let sep = afterCategory.first, sep == " " || sep == "\t" else { return }
            let description = afterCategory.drop(while: { $0 == " " || $0 == "\t" })
            // "Wake Requests" 는 카테고리 이름 자체가 두 단어라 설명이 "Requests" 로 시작한다.
            guard description.hasPrefix("DarkWake to FullWake")
                    || description.hasPrefix("Wake from")
                    || description.hasPrefix("FullWake") else { return }
            if let date = formatter.date(from: String(timestamp)) {
                result.append(date)
            }
        }
        return result
    }
}

enum PmsetRecovery {
    /// 복구 시각 결정 (순수 함수).
    /// 후보 = 오늘 9시 ~ 지금 사이의 FullWake 와 부팅 시각. 가장 이른 것, 없으면 오늘 9시.
    static func clockIn(fromLog log: String, boot: Date?, nineAM: Date, now: Date) -> Date {
        var candidates = PmsetLogParser.fullWakeTimes(in: log).filter { $0 >= nineAM && $0 <= now }
        if let boot, boot >= nineAM, boot <= now { candidates.append(boot) }
        return candidates.min() ?? nineAM
    }

    static let timeout: TimeInterval = 10

    /// 실제 실행: 백그라운드 큐에서 `pmset -g log` 를 한 번 돌리고 메인 스레드로 결과를 돌려준다.
    /// 실행 실패·타임아웃(10초)이면 nil.
    static func runLive(nineAM: Date, now: Date, completion: @escaping (Date?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let log = readPmsetLog(timeout: timeout)
            let result = log.map {
                clockIn(fromLog: $0, boot: SystemInfo.bootTime(), nineAM: nineAM, now: now)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func readPmsetLog(timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            NSLog("Kaltoe: pmset 실행 실패: \(error)")
            return nil
        }

        let lock = NSLock()
        var timedOut = false
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            lock.lock(); defer { lock.unlock() }
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }
        // 파이프가 가득 차 pmset 이 멈추지 않도록 끝까지 읽는다 (terminate 되면 EOF).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        lock.lock(); defer { lock.unlock() }
        if timedOut {
            NSLog("Kaltoe: pmset -g log 타임아웃(\(Int(timeout))초)")
            return nil
        }
        guard process.terminationStatus == 0 else {
            NSLog("Kaltoe: pmset 종료 코드 \(process.terminationStatus)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
