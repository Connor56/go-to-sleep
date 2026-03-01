import SwiftUI

/// Full-screen bedtime overlay with score-to-exit question system.
/// The user must correctly answer N questions (from AppSettings.questionsPerSession)
/// before the overlay dismisses. Questions are drawn from an infinite pool.
struct OverlayView: View {
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
  let questionStore: QuestionStore
  let onComplete: () -> Void

  @State private var currentResolved: ResolvedQuestion?
  @State private var score = 0
  @State private var seenQuestionIds = Set<String>()
  @State private var questionsAttempted = 0

  private var targetScore: Int { AppSettings.shared.questionsPerSession }

  @State private var lastQuestionAppearance: Int = Int(Date().timeIntervalSince1970)
  @State private var timeToDismiss: Int = 100  // Default, gets updated later

  init(questionStore: QuestionStore, onComplete: @escaping () -> Void) {
    self.questionStore = questionStore
    self.onComplete = onComplete
  }

  var body: some View {
    let _ = print(
      "\(debugMarker) OverlayView.body score=\(score)/\(targetScore) questionsAttempted=\(questionsAttempted) currentResolved=\(currentResolved?.id ?? "nil") seenCount=\(seenQuestionIds.count)"
    )
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.05, green: 0.05, blue: 0.15),
          Color(red: 0.1, green: 0.08, blue: 0.2),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      // Debug dismiss button
      VStack {
        HStack {
          Spacer()
          Button("Dismiss in \(timeToDismiss)") {
            let now = Int(Date().timeIntervalSince1970)
            timeToDismiss = lastQuestionAppearance + 300 - now

            guard timeToDismiss < 0 else { return }

            print("\(debugMarker) Debug dismiss button pressed")

            onComplete()
          }
          .buttonStyle(.plain)
          .font(.caption)
          .foregroundColor(.white.opacity(0.4))
          .padding(8)
          .background(Color.white.opacity(0.1))
          .cornerRadius(6)
          .padding(16)
        }
        Spacer()
      }

      VStack(spacing: 40) {
        Spacer()

        scoreIndicator

        if let resolved = currentResolved {
          let _ = print(
            "\(debugMarker) OverlayView rendering QuestionView id=\(resolved.id) type=\(resolved.question.type.rawValue) renderId=\(resolved.id)-\(questionsAttempted)"
          )
          QuestionView(resolved: resolved) { result in
            print(
              "\(debugMarker) OverlayView received result questionId=\(result.questionId) correct=\(result.correct) attempts=\(result.attempts) userAnswer='\(result.userAnswer)'"
            )
            handleResult(result)
          }
          .frame(maxWidth: 500)
          .id(resolved.id + "-\(questionsAttempted)")  // force re-render
          .onAppear {
            let now = Int(Date().timeIntervalSince1970)

            print("\(debugMarker) Setting timer for debug button: \(now)")

            lastQuestionAppearance = now
          }
        } else {
          let _ = print("\(debugMarker) OverlayView has nil currentResolved, QuestionView hidden")
        }

        Spacer()
      }
      .padding(40)
    }
    .onAppear {
      print("\(debugMarker) OverlayView appeared, targetScore=\(targetScore)")
      drawNextQuestion()
    }
    .onDisappear {
      print("\(debugMarker) OverlayView disappeared")
    }
    .onChange(of: currentResolved?.id) { value in
      print("\(debugMarker) OverlayView.currentResolved changed id=\(value ?? "nil")")
    }
    .onChange(of: score) { value in
      print("\(debugMarker) OverlayView.score changed value=\(value)")
    }
    .onChange(of: questionsAttempted) { value in
      print("\(debugMarker) OverlayView.questionsAttempted changed value=\(value)")
    }
    .onChange(of: seenQuestionIds) { value in
      print(
        "\(debugMarker) OverlayView.seenQuestionIds changed count=\(value.count) ids=\(value.sorted())"
      )
    }
  }

  private var scoreIndicator: some View {
    Text("\(score) / \(targetScore) correct")
      .font(.caption)
      .foregroundColor(.white.opacity(0.5))
      .tracking(2)
      .textCase(.uppercase)
  }

  private func drawNextQuestion() {
    let previousResolvedId = currentResolved?.id ?? "nil"
    print(
      "\(debugMarker) drawNextQuestion called from=\(previousResolvedId) seenCount=\(seenQuestionIds.count) score=\(score)/\(targetScore)"
    )
    if let next = questionStore.nextQuestion(excluding: seenQuestionIds) {
      seenQuestionIds.insert(next.id)
      currentResolved = next
      print(
        "\(debugMarker) drawNextQuestion selected id=\(next.id) type=\(next.question.type.rawValue) previous=\(previousResolvedId) resolvedText=\(next.resolvedText.prefix(80))..."
      )
    } else {
      // All seen — reset and try again
      print("\(debugMarker) All questions seen, resetting pool")
      seenQuestionIds.removeAll()
      if let next = questionStore.nextQuestion(excluding: seenQuestionIds) {
        seenQuestionIds.insert(next.id)
        currentResolved = next
        print(
          "\(debugMarker) drawNextQuestion selected after reset id=\(next.id) type=\(next.question.type.rawValue) previous=\(previousResolvedId)"
        )
      } else {
        currentResolved = nil
        print("\(debugMarker) drawNextQuestion no question after reset, currentResolved=nil")
      }
    }
  }

  private func handleResult(_ result: QuestionResult) {
    print(
      "\(debugMarker) handleResult start questionId=\(result.questionId) correct=\(result.correct) attempts=\(result.attempts) currentResolved=\(currentResolved?.id ?? "nil")"
    )
    questionsAttempted += 1

    AnswerLogger.log(
      questionId: result.questionId,
      questionText: currentResolved?.resolvedText ?? "",
      answer: result.userAnswer
    )

    if result.correct {
      score += 1
      print(
        "\(debugMarker) Correct! score=\(score)/\(targetScore) attempts=\(result.attempts)")
    } else {
      print(
        "\(debugMarker) Incorrect. score=\(score)/\(targetScore) attempts=\(result.attempts)")
    }

    if score >= targetScore {
      print("\(debugMarker) Target score reached, completing session")
      onComplete()
    } else {
      print("\(debugMarker) handleResult drawing next question")
      drawNextQuestion()
    }

    print(
      "\(debugMarker) handleResult end score=\(score)/\(targetScore) questionsAttempted=\(questionsAttempted) currentResolved=\(currentResolved?.id ?? "nil")"
    )
  }
}
