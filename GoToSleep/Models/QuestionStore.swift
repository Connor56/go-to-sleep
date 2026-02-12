import Foundation

class QuestionStore {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private let questions: [Question]

    init() {
        print("\(debugMarker) QuestionStore init started")
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Question].self, from: data) else {
            print("\(debugMarker) QuestionStore failed to load questions.json")
            questions = []
            return
        }
        print("\(debugMarker) QuestionStore loaded questions count=\(decoded.count)")
        questions = decoded
    }

    /// Returns a random selection of questions for a session.
    func selectQuestions(count: Int) -> [Question] {
        let selectedQuestions = Array(questions.shuffled().prefix(count))
        print("\(debugMarker) selectQuestions requested=\(count), returned=\(selectedQuestions.count)")
        print("\(debugMarker) selected question ids=\(selectedQuestions.map { $0.id })")
        return selectedQuestions
    }
}
