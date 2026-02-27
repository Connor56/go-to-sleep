import AppKit
import SwiftUI

/// Routes to the correct sub-view based on question type.
/// Reports result back via the `onResult` callback.
struct QuestionView: View {
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
  let resolved: ResolvedQuestion
  let onResult: (QuestionResult) -> Void

  var body: some View {
    let _ = print(
      "\(debugMarker) QuestionView.body routing id=\(resolved.id) type=\(resolved.question.type.rawValue)"
    )
    Group {
      switch resolved.question.type {
      case .hardMultipleChoice:
        HardMultipleChoiceView(resolved: resolved, onResult: onResult)
      case .verifiableFact:
        VerifiableFactView(resolved: resolved, onResult: onResult)
      case .calculation:
        CalculationQuestionView(resolved: resolved, onResult: onResult)
      }
    }
    .onAppear {
      print(
        "\(debugMarker) QuestionView.onAppear id=\(resolved.id) type=\(resolved.question.type.rawValue)"
      )
    }
    .onDisappear {
      print(
        "\(debugMarker) QuestionView.onDisappear id=\(resolved.id) type=\(resolved.question.type.rawValue)"
      )
    }
  }
}

// MARK: - QuestionResult

struct QuestionResult {
  let questionId: String
  let correct: Bool
  let userAnswer: String
  let attempts: Int
}

// MARK: - Hard Multiple Choice

struct HardMultipleChoiceView: View {
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
  let resolved: ResolvedQuestion
  let onResult: (QuestionResult) -> Void

  @State private var selectedIndex: Int? = nil
  @State private var timerRemaining: Int
  @State private var questionAppearedAt = Date()

  init(resolved: ResolvedQuestion, onResult: @escaping (QuestionResult) -> Void) {
    self.resolved = resolved
    self.onResult = onResult
    self._timerRemaining = State(initialValue: resolved.question.minimumSeconds ?? 30)
  }

  private var isCorrect: Bool? {
    guard let sel = selectedIndex else { return nil }
    return sel == resolved.question.answerIndex
  }

  private var choices: [ChoiceOption] { resolved.question.choices ?? [] }

  var body: some View {
    let _ = print(
      "\(debugMarker) HardMultipleChoiceView.body id=\(resolved.id) choiceCount=\(choices.count) answerIndex=\(resolved.question.answerIndex ?? -1)"
    )
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(resolved.resolvedText)
          .font(.title2)
          .fontWeight(.medium)
          .foregroundColor(.white)

        VStack(spacing: 10) {
          ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
            choiceButton(index: index, choice: choice)
          }
        }

        Spacer()

        if let selected = selectedIndex {
          let _ = print(
            "\(debugMarker) Selected index was: \(selected)"
          )
          explanationSection(selectedIndex: selected)
        }

        Spacer()

        nextButton
      }
    }
    .onAppear { questionAppearedAt = Date() }
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      updateTimer()
    }
  }

  private func choiceButton(index: Int, choice: ChoiceOption) -> some View {
    Button {
      // guard selectedIndex == nil else { return }
      selectedIndex = index
    } label: {
      HStack {
        Text(choice.text)
          .foregroundColor(.white)
          .multilineTextAlignment(.leading)
        Spacer()
        if selectedIndex == index {
          Image(systemName: isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(isCorrect == true ? .green : .red)
        }
      }
      .padding(12)
      .background(choiceBackground(for: index))
      .cornerRadius(8)
    }
    .buttonStyle(.plain)
    .disabled(selectedIndex != nil)
  }

  private func choiceBackground(for index: Int) -> Color {
    guard let sel = selectedIndex else { return Color.white.opacity(0.1) }
    if index == sel {
      return isCorrect == true ? Color.green.opacity(0.3) : Color.red.opacity(0.3)
    }
    return Color.white.opacity(0.05)
  }

  @ViewBuilder
  private func explanationSection(selectedIndex: Int) -> some View {
    // Show hint for wrong answer
    let _ = print(
      "\(debugMarker) isCorrect: \(isCorrect), selected index: \(selectedIndex)"
    )
    if isCorrect == false, let hint = choices[selectedIndex].hint {
      Text(hint)
        .font(.callout)
        .foregroundColor(.orange)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    }

    // Show explanation
    if isCorrect == true, let explanation = resolved.processedExplanation() {
      let _ = print(
        "\(debugMarker) the explanation is: \(explanation)"
      )
      Text(explanation)
        .font(.body)
        .foregroundColor(.white.opacity(0.85))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)
        .transition(.opacity)
    }

    let _ = print(
      "\(debugMarker) made it here."
    )
  }

  private var nextButton: some View {
    Group {
      if selectedIndex != nil {
        let _ = print("I'm at the next button")
        Button(action: reportResult) {
          Text(timerRemaining > 0 ? "Next (\(timerRemaining)s)" : "Next")
            .font(.headline)
            .foregroundColor(.white)
            .frame(width: 160, height: 44)
            .background(timerRemaining > 0 ? Color.gray.opacity(0.3) : Color.blue)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(timerRemaining > 0)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func updateTimer() {
    // guard selectedIndex != nil else { return }
    let elapsed = Int(Date().timeIntervalSince(questionAppearedAt))
    let minimum = 5  //resolved.question.minimumSeconds ?? 30
    timerRemaining = max(0, minimum - elapsed)
  }

  private func reportResult() {
    let correct = isCorrect == true
    let answer = selectedIndex.map { choices[$0].text } ?? ""
    print(
      "\(debugMarker) HardMultipleChoiceView.reportResult id=\(resolved.id) correct=\(correct) answer='\(answer)' timerRemaining=\(timerRemaining)"
    )
    onResult(
      QuestionResult(
        questionId: resolved.id, correct: correct, userAnswer: answer, attempts: 1))
  }
}

// MARK: - Verifiable Fact

struct VerifiableFactView: View {
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
  let resolved: ResolvedQuestion
  let onResult: (QuestionResult) -> Void

  @State private var userInput = ""
  @State private var currentAttempt = 0
  @State private var isCorrect = false
  @State private var isFailed = false
  @State private var feedbackMessage = ""
  @State private var timerRemaining: Int
  @State private var questionAppearedAt = Date()
  @State private var showShake = false

  init(resolved: ResolvedQuestion, onResult: @escaping (QuestionResult) -> Void) {
    self.resolved = resolved
    self.onResult = onResult
    self._timerRemaining = State(initialValue: resolved.question.minimumSeconds ?? 30)

    print("The resolved stuff is: \(self.resolved), \(self.onResult)")
  }

  private var maxAttempts: Int { resolved.question.maxAttempts ?? 5 }
  private var isWordType: Bool { resolved.question.answerType == "word" }
  private var isFinished: Bool { isCorrect || isFailed }

  var body: some View {
    let _ = print(
      "\(debugMarker) VerifiableFactView.body id=\(resolved.id) isWordType=\(isWordType) isFinished=\(isFinished) answerType=\(resolved.question.answerType ?? "nil") exactAnswer=\(resolved.question.exactAnswer.map { "\($0)" } ?? "nil") unit=\(resolved.question.unit ?? "nil")"
    )
    VStack(alignment: .leading, spacing: 20) {
      Text(resolved.resolvedText)
        .font(.title2)
        .fontWeight(.medium)
        .foregroundColor(.white)

      if !isFinished {
        let _ = print("\(debugMarker) VerifiableFactView showing inputSection")
        inputSection
      }

      if !feedbackMessage.isEmpty {
        let _ = print(
          "\(debugMarker) VerifiableFactView showing feedback message='\(feedbackMessage)' isCorrect=\(isCorrect) isFailed=\(isFailed)"
        )
        Text(feedbackMessage)
          .font(.callout)
          .foregroundColor(isCorrect ? .green : (isFailed ? .red : .orange))
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      if isCorrect, let explanation = resolved.processedExplanation() {
        let _ = print(
          "\(debugMarker) VerifiableFactView showing explanation length=\(explanation.count)")
        Text(explanation)
          .font(.body)
          .foregroundColor(.white.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      if isFinished {
        let _ = print(
          "\(debugMarker) VerifiableFactView showing nextButton timerRemaining=\(timerRemaining)")
        nextButton
      }
    }
  }

  private var inputSection: some View {
    HStack(spacing: 12) {
      TextField(isWordType ? "Type your answer..." : "Enter a number...", text: $userInput)
        .textFieldStyle(PlainTextFieldStyle())
        .font(.system(size: 16))
        .foregroundColor(.white)
        .padding(8)
        .frame(height: 40)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .offset(x: showShake ? -5 : 0)

      if let unit = resolved.question.unit, !unit.isEmpty {
        Text(unit)
          .font(.title3)
          .foregroundColor(.white.opacity(0.6))
      }

      Button("Submit") { submitAnswer() }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
          userInput.trimmingCharacters(in: .whitespaces).isEmpty
            ? Color.gray.opacity(0.3) : Color.blue
        )
        .cornerRadius(8)
        .disabled(userInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }

  private var nextButton: some View {
    Button(action: reportResult) {
      Text(timerRemaining > 0 ? "Next (\(timerRemaining)s)" : "Next")
        .font(.headline)
        .foregroundColor(.white)
        .frame(width: 160, height: 44)
        .background(timerRemaining > 0 ? Color.gray.opacity(0.3) : Color.blue)
        .cornerRadius(10)
    }
    .buttonStyle(.plain)
    .disabled(timerRemaining > 0)
  }

  private func submitAnswer() {
    let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    print(
      "\(debugMarker) VerifiableFactView.submitAnswer: input='\(trimmed)' isWordType=\(isWordType) attempt=\(currentAttempt + 1)"
    )
    guard !trimmed.isEmpty else {
      print("\(debugMarker) VerifiableFactView.submitAnswer: empty input, ignoring")
      return
    }
    currentAttempt += 1

    if isWordType {
      submitWordAnswer(trimmed)
    } else {
      submitNumericAnswer(trimmed)
    }
  }

  private func submitWordAnswer(_ input: String) {
    guard let exact = resolved.question.exactAnswer?.stringValue else {
      print(
        "\(debugMarker) VerifiableFactView.submitWordAnswer: exactAnswer has no stringValue! exactAnswer=\(resolved.question.exactAnswer.map { "\($0)" } ?? "nil")"
      )
      fail(message: "Incorrect.")
      return
    }

    let sim = FuzzyMatcher.similarity(input, exact)
    print(
      "\(debugMarker) VerifiableFactView.submitWordAnswer: input='\(input)' exact='\(exact)' similarity=\(sim)"
    )

    if sim >= 0.98 {
      succeed(
        message: sim < 1.0
          ? "Not quite perfect \u{2014} the exact answer is: \(exact)"
          : "Correct!")
    } else if sim >= 0.9 {
      // Close — doesn't count as fail, allow retry
      currentAttempt -= 1  // don't count this attempt
      feedbackMessage = "Almost! Try again."
      userInput = ""
      shakeInput()
    } else {
      if currentAttempt >= maxAttempts {
        fail(message: "Incorrect.")
      } else {
        feedbackMessage = "Incorrect. Attempt \(currentAttempt) of \(maxAttempts)."
        userInput = ""
        shakeInput()
      }
    }
  }

  private func submitNumericAnswer(_ input: String) {
    print("\(debugMarker) VerifiableFactView.submitNumericAnswer: input='\(input)'")
    guard let userValue = Double(input) else {
      print(
        "\(debugMarker) VerifiableFactView.submitNumericAnswer: failed to parse '\(input)' as Double"
      )
      feedbackMessage = "Please enter a valid number."
      return
    }
    guard let exactAnswer = resolved.question.exactAnswer?.doubleValue else {
      print(
        "\(debugMarker) VerifiableFactView.submitNumericAnswer: exactAnswer has no doubleValue! exactAnswer=\(resolved.question.exactAnswer.map { "\($0)" } ?? "nil")"
      )
      feedbackMessage = "Please enter a valid number."
      return
    }

    let tolerance = resolved.question.tolerance ?? 0
    let diff = abs(userValue - exactAnswer)
    print(
      "\(debugMarker) VerifiableFactView.submitNumericAnswer: userValue=\(userValue) exactAnswer=\(exactAnswer) tolerance=\(tolerance) diff=\(diff) pass=\(diff <= tolerance)"
    )
    if diff <= tolerance {
      succeed(message: "Correct!")
    } else {
      fail(message: "Incorrect.")
    }
  }

  private func succeed(message: String) {
    print(
      "\(debugMarker) VerifiableFactView.succeed id=\(resolved.id) message='\(message)' currentAttempt=\(currentAttempt)"
    )
    isCorrect = true
    feedbackMessage = message
    startCountdown()
  }

  private func fail(message: String) {
    print(
      "\(debugMarker) VerifiableFactView.fail id=\(resolved.id) message='\(message)' currentAttempt=\(currentAttempt)"
    )
    isFailed = true
    feedbackMessage = message
    startCountdown()
  }

  private func shakeInput() {
    withAnimation(.default) { showShake = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      withAnimation { showShake = false }
    }
  }

  private func startCountdown() {
    let elapsed = Int(Date().timeIntervalSince(questionAppearedAt))
    let minimum = resolved.question.minimumSeconds ?? 30
    timerRemaining = max(0, minimum - elapsed)
    print(
      "\(debugMarker) VerifiableFactView.startCountdown id=\(resolved.id) elapsed=\(elapsed) minimum=\(minimum) timerRemaining=\(timerRemaining)"
    )
  }

  private func updateTimer() {
    guard isFinished else { return }
    let elapsed = Int(Date().timeIntervalSince(questionAppearedAt))
    let minimum = resolved.question.minimumSeconds ?? 30
    timerRemaining = max(0, minimum - elapsed)
  }

  private func reportResult() {
    print(
      "\(debugMarker) VerifiableFactView.reportResult id=\(resolved.id) correct=\(isCorrect) isFailed=\(isFailed) attempts=\(currentAttempt) userAnswer='\(userInput)' timerRemaining=\(timerRemaining)"
    )
    onResult(
      QuestionResult(
        questionId: resolved.id, correct: isCorrect, userAnswer: userInput,
        attempts: currentAttempt))
  }
}

// MARK: - Calculation

struct CalculationQuestionView: View {
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
  let resolved: ResolvedQuestion
  let onResult: (QuestionResult) -> Void

  @State private var userInput = ""
  @State private var currentAttempt = 0
  @State private var isCorrect = false
  @State private var isFailed = false
  @State private var feedbackMessage = ""
  @State private var timerRemaining: Int
  @State private var questionAppearedAt = Date()
  @State private var showShake = false

  init(resolved: ResolvedQuestion, onResult: @escaping (QuestionResult) -> Void) {
    self.resolved = resolved
    self.onResult = onResult
    self._timerRemaining = State(initialValue: resolved.question.minimumSeconds ?? 30)
  }

  private var maxAttempts: Int { resolved.question.maxAttempts ?? 5 }
  private var isFinished: Bool { isCorrect || isFailed }

  var body: some View {
    let _ = print(
      "\(debugMarker) CalculationQuestionView.body id=\(resolved.id) computedAnswer=\(resolved.computedAnswer ?? -999) paramCount=\(resolved.resolvedParameters.count)"
    )
    VStack(alignment: .leading, spacing: 20) {
      Text(resolved.resolvedText)
        .font(.title2)
        .fontWeight(.medium)
        .foregroundColor(.white)

      givenPanel

      if !isFinished {
        inputSection
      }

      if !feedbackMessage.isEmpty {
        Text(feedbackMessage)
          .font(.callout)
          .foregroundColor(isCorrect ? .green : (isFailed ? .red : .orange))
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      if isFinished, let explanation = resolved.processedExplanation() {
        Text(explanation)
          .font(.body)
          .foregroundColor(.white.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      if isFinished {
        nextButton
      }
    }
    .onAppear { questionAppearedAt = Date() }
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      updateTimer()
    }
  }

  private var givenPanel: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Given:")
        .font(.caption)
        .foregroundColor(.white.opacity(0.5))
        .textCase(.uppercase)

      ForEach(
        resolved.resolvedParameters.sorted(by: { $0.key < $1.key }), id: \.key
      ) { key, value in
        let def = resolved.question.parameters?[key]
        let unitStr = def?.unit.map { " \($0)" } ?? ""
        Text("\(friendlyParamName(key)) = \(value.displayString)\(unitStr)")
          .font(.system(.body, design: .monospaced))
          .foregroundColor(.white.opacity(0.7))
      }
    }
    .padding(12)
    .background(Color.white.opacity(0.05))
    .cornerRadius(8)
  }

  private var inputSection: some View {
    HStack(spacing: 12) {
      TextField("Enter your answer...", text: $userInput)
        .textFieldStyle(PlainTextFieldStyle())
        .font(.system(size: 16))
        .foregroundColor(.white)
        .padding(8)
        .frame(height: 40)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .offset(x: showShake ? -5 : 0)

      if let unit = resolved.question.unit, !unit.isEmpty {
        Text(unit)
          .font(.title3)
          .foregroundColor(.white.opacity(0.6))
      }

      Button("Submit") { submitAnswer() }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
          userInput.trimmingCharacters(in: .whitespaces).isEmpty
            ? Color.gray.opacity(0.3) : Color.blue
        )
        .cornerRadius(8)
        .disabled(userInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }

  private var nextButton: some View {
    Button(action: reportResult) {
      Text(timerRemaining > 0 ? "Next (\(timerRemaining)s)" : "Next")
        .font(.headline)
        .foregroundColor(.white)
        .frame(width: 160, height: 44)
        .background(timerRemaining > 0 ? Color.gray.opacity(0.3) : Color.blue)
        .cornerRadius(10)
    }
    .buttonStyle(.plain)
    .disabled(timerRemaining > 0)
  }

  private func submitAnswer() {
    let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let userValue = Double(trimmed) else {
      feedbackMessage = "Please enter a valid number."
      return
    }
    currentAttempt += 1

    guard let expected = resolved.computedAnswer else {
      fail()
      return
    }

    let tolerance = resolved.question.tolerance ?? 5
    if abs(userValue - expected) <= tolerance {
      isCorrect = true
      feedbackMessage = "Correct!"
      startCountdown()
    } else if currentAttempt >= maxAttempts {
      fail()
    } else {
      feedbackMessage = "Not quite, try again. Attempt \(currentAttempt) of \(maxAttempts)."
      userInput = ""
      shakeInput()
    }
  }

  private func fail() {
    isFailed = true
    if let answer = resolved.computedAnswer {
      let answerStr: String
      if answer == answer.rounded() && abs(answer) < 1e15 {
        answerStr = String(Int(answer))
      } else {
        answerStr = String(format: "%.1f", answer)
      }
      feedbackMessage = "The answer was \(answerStr)."
    } else {
      feedbackMessage = "Incorrect."
    }
    startCountdown()
  }

  private func shakeInput() {
    withAnimation(.default) { showShake = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      withAnimation { showShake = false }
    }
  }

  private func startCountdown() {
    let elapsed = Int(Date().timeIntervalSince(questionAppearedAt))
    let minimum = resolved.question.minimumSeconds ?? 30
    timerRemaining = max(0, minimum - elapsed)
  }

  private func updateTimer() {
    guard isFinished else { return }
    let elapsed = Int(Date().timeIntervalSince(questionAppearedAt))
    let minimum = resolved.question.minimumSeconds ?? 30
    timerRemaining = max(0, minimum - elapsed)
  }

  private func reportResult() {
    onResult(
      QuestionResult(
        questionId: resolved.id, correct: isCorrect, userAnswer: userInput,
        attempts: currentAttempt))
  }

  private func friendlyParamName(_ key: String) -> String {
    key.replacingOccurrences(of: "_", with: " ")
  }
}

// MARK: - TransparentTextEditor

struct TransparentTextEditor: NSViewRepresentable {
  @Binding var text: String

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false

    let textView = NSTextView(frame: scrollView.bounds)
    textView.isRichText = false
    textView.drawsBackground = false
    textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    textView.textColor = .white
    textView.insertionPointColor = .white
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.delegate = context.coordinator
    textView.textContainerInset = NSSize(width: 8, height: 8)

    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if textView.string != text {
      textView.string = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    init(text: Binding<String>) { self.text = text }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }
}
