import AppKit
import Foundation

/// Loads questions from JSON, filters by enabled skill tags, and provides
/// random question selection with parameter resolution for calculation questions.
class QuestionStore {
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
  private let allQuestions: [Question]

  init() {
    print("\(debugMarker) QuestionStore init started")
    guard let url = Bundle.main.url(forResource: "questions", withExtension: "json") else {
      print("\(debugMarker) QuestionStore FATAL: questions.json not found in bundle")
      allQuestions = []
      return
    }
    print("\(debugMarker) QuestionStore found questions.json at \(url.path)")

    let data: Data
    do {
      data = try Data(contentsOf: url)
      print("\(debugMarker) QuestionStore read \(data.count) bytes")
    } catch {
      print("\(debugMarker) QuestionStore FATAL: failed to read file: \(error)")
      allQuestions = []
      return
    }

    do {
      let decoded = try JSONDecoder().decode([Question].self, from: data)
      print("\(debugMarker) QuestionStore loaded questions count=\(decoded.count)")
      for q in decoded {
        print(
          "\(debugMarker)   question id=\(q.id) type=\(q.type.rawValue) answerType=\(q.answerType ?? "nil") exactAnswer=\(q.exactAnswer.map { "\($0)" } ?? "nil")"
        )
      }
      allQuestions = decoded
    } catch {
      print("\(debugMarker) QuestionStore FATAL: JSON decode error: \(error)")
      allQuestions = []
    }
  }

  /// All unique skill tags found across all calculation questions.
  var allAvailableTags: Set<String> {
    var tags = Set<String>()
    for q in allQuestions {
      if let qTags = q.tags {
        tags.formUnion(qTags)
      }
    }
    return tags
  }

  /// Returns the next question not in the `excluding` set, filtered by enabled tags.
  /// Returns nil if all questions have been seen (caller should reset the seen set).
  func nextQuestion(excluding seen: Set<String>) -> ResolvedQuestion? {
    let enabledTags = AppSettings.shared.getEnabledTags()
    print(
      "\(debugMarker) nextQuestion called: allQuestions=\(allQuestions.count) seen=\(seen.count) enabledTags=\(enabledTags)"
    )
    let eligible = allQuestions.filter { q in
      if seen.contains(q.id) {
        print("\(debugMarker)   skip \(q.id): already seen")
        return false
      }
      if let qTags = q.tags, !qTags.isEmpty {
        let pass = qTags.allSatisfy { enabledTags.contains($0) }
        if !pass { print("\(debugMarker)   skip \(q.id): tags \(qTags) not all enabled") }
        return pass
      }
      return true
    }
    print("\(debugMarker) nextQuestion: eligible=\(eligible.count) ids=\(eligible.map { $0.id })")

    // for question in eligible {
    //   print("eligible-question: \(question)\n")
    // }
    // TODO: put this back in after debugging problems
    guard let question = eligible.randomElement() else {
      print("\(debugMarker) nextQuestion: no eligible questions")
      return nil
    }

    // let question = eligible[6]

    print("\(debugMarker) nextQuestion: selected id=\(question.id) type=\(question.type.rawValue)")
    return resolve(question)
  }

  /// Total number of eligible questions for the current tag settings.
  func eligibleCount() -> Int {
    let enabledTags = AppSettings.shared.getEnabledTags()
    return allQuestions.filter { q in
      if let qTags = q.tags, !qTags.isEmpty {
        return qTags.allSatisfy { enabledTags.contains($0) }
      }
      return true
    }.count
  }
}

// MARK: - Parameter Resolution

extension QuestionStore {

  private func resolve(_ question: Question) -> ResolvedQuestion {
    guard question.type == .calculation,
      let paramDefs = question.parameters,
      let calculateExpr = question.calculate
    else {
      print(
        "\(debugMarker) resolve: non-calculation question id=\(question.id) type=\(question.type.rawValue) — returning as-is"
      )
      print("\(debugMarker) resolve:   text=\(question.text.prefix(80))...")
      print(
        "\(debugMarker) resolve:   answerType=\(question.answerType ?? "nil") exactAnswer=\(question.exactAnswer.map { "\($0)" } ?? "nil")"
      )
      return ResolvedQuestion(
        question: question, resolvedText: question.text, resolvedParameters: [:],
        computedAnswer: nil)
    }

    var resolvedParams: [String: DSLValue] = [:]
    for (name, def) in paramDefs {
      resolvedParams[name] = resolveParameter(def)
    }

    // Substitute {param_name} in the question text
    var resolvedText = question.text
    for (name, value) in resolvedParams {
      resolvedText = resolvedText.replacingOccurrences(of: "{\(name)}", with: value.displayString)
    }

    // Evaluate the calculate expression
    let answer = DSLEvaluator.evaluate(expression: calculateExpr, parameters: resolvedParams)

    print(
      "\(debugMarker) resolve calculation id=\(question.id) params=\(resolvedParams.mapValues { $0.displayString }) answer=\(answer ?? -1)"
    )

    return ResolvedQuestion(
      question: question, resolvedText: resolvedText, resolvedParameters: resolvedParams,
      computedAnswer: answer)
  }

  private func resolveParameter(_ def: ParameterDefinition) -> DSLValue {
    switch def.type {
    case "int":
      let min = Int(def.min ?? 0)
      let max = Int(def.max ?? 100)
      let step = Int(def.step ?? 1)
      let steps = (max - min) / step
      let randomStep = Int.random(in: 0...Swift.max(steps, 0))
      let value = min + randomStep * step
      return .number(Double(value))

    case "float":
      let min = def.min ?? 0
      let max = def.max ?? 100
      let step = def.step ?? 0.1
      let steps = Int((max - min) / step)
      let randomStep = Int.random(in: 0...Swift.max(steps, 0))
      var value = min + Double(randomStep) * step
      if let dp = def.decimalPlaces {
        let mult = pow(10.0, Double(dp))
        value = (value * mult).rounded() / mult
      }
      return .number(value)

    case "enum":
      let values = def.values ?? []
      let picked = values.randomElement() ?? ""
      return .string(picked)

    default:
      return .number(0)
    }
  }
}

// MARK: - ResolvedQuestion

/// A question with its parameters resolved to concrete values (for calculation type)
/// or simply wrapping the original question (for other types).
struct ResolvedQuestion {
  let question: Question
  let resolvedText: String
  let resolvedParameters: [String: DSLValue]
  let computedAnswer: Double?

  var id: String { question.id }

  /// Process the correctExplanation template with resolved values.
  func processedExplanation() -> String? {
    guard let template = question.correctExplanation else { return nil }
    guard question.type == .calculation, let answer = computedAnswer else { return template }
    return DSLEvaluator.processExplanation(template, parameters: resolvedParameters, answer: answer)
  }
}
