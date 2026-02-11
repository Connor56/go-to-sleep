import Foundation

enum Paths {
    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("GoToSleep")
    }()

    static let sessionActivePath = appSupportDir.appendingPathComponent("session-active")
    static let sessionCompletedPath = appSupportDir.appendingPathComponent("session-completed")
    static let answersPath = appSupportDir.appendingPathComponent("answers.jsonl")
    static let killLogPath = appSupportDir.appendingPathComponent("kills.json")

    static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    static func readTimestamp(from url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let interval = TimeInterval(string) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    static func writeTimestamp(to url: URL, date: Date = Date()) {
        ensureDirectoryExists()
        let string = String(date.timeIntervalSince1970)
        try? string.write(to: url, atomically: true, encoding: .utf8)
    }

    static func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
