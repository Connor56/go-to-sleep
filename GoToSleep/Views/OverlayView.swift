import SwiftUI

struct OverlayView: View {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    let questions: [Question]
    let onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var answers: [String]

    init(questions: [Question], onComplete: @escaping () -> Void) {
        self.questions = questions
        self.onComplete = onComplete
        self._answers = State(initialValue: Array(repeating: "", count: questions.count))
    }

    private var currentAnswer: Binding<String> {
        $answers[currentIndex]
    }

    private var isCurrentAnswered: Bool {
        !answers[currentIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    var body: some View {
        ZStack {
            // Dark calming background
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                         Color(red: 0.1, green: 0.08, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Progress indicator
                Text("\(currentIndex + 1) of \(questions.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(2)
                    .textCase(.uppercase)

                // Question
                QuestionView(question: questions[currentIndex], answer: currentAnswer)
                    .frame(maxWidth: 500)
                    .id(currentIndex) // force re-render on index change

                // Navigation button
                Button(action: advance) {
                    Text(isLastQuestion ? "Finish" : "Next")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 160, height: 44)
                        .background(isCurrentAnswered ? Color.blue : Color.gray.opacity(0.3))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!isCurrentAnswered)
                .keyboardShortcut(.return, modifiers: [])

                Spacer()
            }
            .padding(40)
        }
        .onAppear {
            print("\(debugMarker) OverlayView appeared with questionCount=\(questions.count)")
        }
        .onChange(of: currentIndex) { newValue in
            print("\(debugMarker) OverlayView currentIndex changed -> \(newValue)")
        }
    }

    private func advance() {
        print("\(debugMarker) OverlayView.advance called index=\(currentIndex)")
        guard isCurrentAnswered else { return }

        // Log this answer
        let q = questions[currentIndex]
        print("\(debugMarker) Logging answer for questionId=\(q.id)")
        AnswerLogger.log(
            questionId: q.id,
            questionText: q.text,
            answer: answers[currentIndex]
        )

        if isLastQuestion {
            print("\(debugMarker) Last question answered, calling onComplete")
            onComplete()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentIndex += 1
            }
            print("\(debugMarker) Moving to next question index=\(currentIndex)")
        }
    }
}
