import Foundation

class QuestionStore {
    private let questions: [Question]

    init() {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Question].self, from: data) else {
            questions = []
            return
        }
        questions = decoded
    }

    /// Returns a random selection of questions for a session.
    func selectQuestions(count: Int) -> [Question] {
        Array(questions.shuffled().prefix(count))
    }
}
