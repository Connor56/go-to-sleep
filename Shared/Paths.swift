import Foundation

enum Paths {
    private static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let resolvedPath = base.appendingPathComponent("GoToSleep")
        print("\(debugMarker) appSupportDir resolved: \(resolvedPath.path)")
        return resolvedPath
    }()

    static let sessionActivePath = appSupportDir.appendingPathComponent("session-active")
    static let sessionCompletedPath = appSupportDir.appendingPathComponent("session-completed")
    static let answersPath = appSupportDir.appendingPathComponent("answers.jsonl")
    static let killLogPath = appSupportDir.appendingPathComponent("kills.json")
    static let audioMutedPath = appSupportDir.appendingPathComponent("audio-muted")

    static func ensureDirectoryExists() {
        print("\(debugMarker) ensureDirectoryExists at \(appSupportDir.path)")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    static func readTimestamp(from url: URL) -> Date? {
        print("\(debugMarker) readTimestamp from \(url.path)")
        guard let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let interval = TimeInterval(string) else {
            print("\(debugMarker) readTimestamp failed for \(url.path)")
            return nil
        }
        print("\(debugMarker) readTimestamp success for \(url.path): \(interval)")
        return Date(timeIntervalSince1970: interval)
    }

    static func writeTimestamp(to url: URL, date: Date = Date()) {
        ensureDirectoryExists()
        let string = String(date.timeIntervalSince1970)
        print("\(debugMarker) writeTimestamp to \(url.path): \(string)")
        try? string.write(to: url, atomically: true, encoding: .utf8)
    }

    static func removeFile(at url: URL) {
        print("\(debugMarker) removeFile at \(url.path)")
        try? FileManager.default.removeItem(at: url)
    }

    static func fileExists(at url: URL) -> Bool {
        let exists = FileManager.default.fileExists(atPath: url.path)
        print("\(debugMarker) fileExists at \(url.path): \(exists)")
        return exists
    }
}
