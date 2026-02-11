import Foundation

enum AnswerLogger {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Append a single answer entry to the answers.jsonl file.
    static func log(questionId: String, questionText: String, answer: String) {
        Paths.ensureDirectoryExists()

        let entry = SessionLog(
            timestamp: Date(),
            questionId: questionId,
            questionText: questionText,
            answer: answer
        )

        guard let data = try? encoder.encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let lineWithNewline = line + "\n"

        if FileManager.default.fileExists(atPath: Paths.answersPath.path) {
            guard let handle = try? FileHandle(forWritingTo: Paths.answersPath) else { return }
            handle.seekToEndOfFile()
            handle.write(lineWithNewline.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? lineWithNewline.write(to: Paths.answersPath, atomically: true, encoding: .utf8)
        }
    }
}
