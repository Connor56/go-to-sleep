import Foundation

struct SessionLog: Codable {
    let timestamp: Date
    let questionId: String
    let questionText: String
    let answer: String
}
