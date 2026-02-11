import Foundation

enum QuestionType: String, Codable {
    case freeText = "free_text"
    case multipleChoice = "multiple_choice"
}

struct Question: Codable, Identifiable {
    let id: String
    let text: String
    let type: QuestionType
    let choices: [String]?
}
