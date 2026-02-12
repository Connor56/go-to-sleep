import Foundation

enum AnswerLogger {
    private static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Append a single answer entry to the answers.jsonl file.
    static func log(questionId: String, questionText: String, answer: String) {
        print("\(debugMarker) AnswerLogger.log called questionId=\(questionId)")
        Paths.ensureDirectoryExists()

        let entry = SessionLog(
            timestamp: Date(),
            questionId: questionId,
            questionText: questionText,
            answer: answer
        )

        guard let data = try? encoder.encode(entry),
              let line = String(data: data, encoding: .utf8) else {
            print("\(debugMarker) AnswerLogger.log failed to encode entry")
            return
        }

        let lineWithNewline = line + "\n"
        print("\(debugMarker) AnswerLogger writing to \(Paths.answersPath.path)")

        if FileManager.default.fileExists(atPath: Paths.answersPath.path) {
            guard let handle = try? FileHandle(forWritingTo: Paths.answersPath) else {
                print("\(debugMarker) AnswerLogger failed to open existing file handle")
                return
            }
            handle.seekToEndOfFile()
            handle.write(lineWithNewline.data(using: .utf8)!)
            handle.closeFile()
            print("\(debugMarker) AnswerLogger appended line")
        } else {
            try? lineWithNewline.write(to: Paths.answersPath, atomically: true, encoding: .utf8)
            print("\(debugMarker) AnswerLogger created file and wrote first line")
        }
    }
}
