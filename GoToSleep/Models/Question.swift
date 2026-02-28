import Foundation

enum QuestionType: String, Codable {
  case hardMultipleChoice = "hard_multiple_choice"
  case verifiableFact = "verifiable_fact"
  case calculation = "calculation"
}

struct ChoiceOption: Codable {
  let text: String
  let hint: String?
}

struct ParameterDefinition: Codable {
  let type: String  // "int", "float", "enum"
  let min: Double?
  let max: Double?
  let step: Double?
  let unit: String?
  let values: [String]?  // for enum type
  let decimalPlaces: Int?
}

struct VerifiableFactHints: Codable {
  let tooLowClose: String   // within 25% below the answer
  let tooHighClose: String  // within 25% above the answer
  let tooLowFar: String     // more than 25% below the answer
  let tooHighFar: String    // more than 25% above the answer
}

struct Question: Codable, Identifiable {
  let id: String
  let type: QuestionType
  let chapter: Int?
  let text: String
  let reference: String?
  let tags: [String]?
  let minimumSeconds: Int?
  let maxAttempts: Int?

  // hard_multiple_choice
  let choices: [ChoiceOption]?
  let answerIndex: Int?

  // verifiable_fact
  let answerType: String?  // "percentage", "number", "word"
  let exactAnswer: AnyCodableValue?
  let tolerance: Double?
  let unit: String?
  let hints: VerifiableFactHints?  // directional hints for numeric answers

  // calculation
  let parameters: [String: ParameterDefinition]?
  let calculate: String?

  // shared
  let correctExplanation: String?
}

// MARK: - AnyCodableValue

/// A JSON value that can be either a number or a string.
enum AnyCodableValue: Codable, Equatable {
  case double(Double)
  case string(String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let intVal = try? container.decode(Int.self) {
      self = .double(Double(intVal))
    } else if let doubleVal = try? container.decode(Double.self) {
      self = .double(doubleVal)
    } else if let stringVal = try? container.decode(String.self) {
      self = .string(stringVal)
    } else {
      throw DecodingError.typeMismatch(
        AnyCodableValue.self,
        .init(codingPath: decoder.codingPath, debugDescription: "Expected number or string"))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .double(let v): try container.encode(v)
    case .string(let v): try container.encode(v)
    }
  }

  var doubleValue: Double? {
    switch self {
    case .double(let v): return v
    case .string(_): return nil
    }
  }

  var stringValue: String {
    switch self {
    case .double(let v):
      if v == v.rounded() && v < 1e15 {
        return String(Int(v))
      }
      return String(v)
    case .string(let v): return v
    }
  }
}
