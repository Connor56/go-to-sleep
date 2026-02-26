import Foundation

/// Evaluates DSL expressions for calculation questions and processes explanation templates.
///
/// DSL uses UPPERCASE function names and lowercase parameter references.
/// Example: `ROUND(HALF_LIFE_DECAY(caffeine_mg, half_life, HOURS_BETWEEN(drink_time, check_time)), 0)`
enum DSLEvaluator {

  // MARK: - Public API

  static func evaluate(expression: String, parameters: [String: DSLValue]) -> Double? {
    let tokens = tokenize(expression)
    guard let node = parse(tokens: tokens) else { return nil }
    return evaluateNode(node, parameters: parameters)
  }

  static func processExplanation(
    _ template: String, parameters: [String: DSLValue], answer: Double
  ) -> String {
    var result = template
    var allParams = parameters
    allParams["answer"] = .number(answer)

    // Replace inline DSL expressions: {ROUND(DIVIDE(answer, 95), 1)}
    while let openRange = result.range(of: "{"),
      let closeRange = findMatchingBrace(in: result, from: openRange.lowerBound)
    {
      let exprStart = result.index(after: openRange.lowerBound)
      let inner = String(result[exprStart..<closeRange.lowerBound])

      // Check if this is a DSL function call (starts with uppercase) or a simple param reference
      let trimmed = inner.trimmingCharacters(in: .whitespaces)
      let replacement: String

      if trimmed.first?.isUppercase == true {
        if let value = evaluate(expression: trimmed, parameters: allParams) {
          if value == value.rounded() && abs(value) < 1e15 {
            replacement = String(Int(value))
          } else {
            replacement = String(format: "%.1f", value)
          }
        } else {
          replacement = inner
        }
      } else if let paramValue = allParams[trimmed] {
        replacement = paramValue.displayString
      } else {
        replacement = inner
      }

      let fullRange = openRange.lowerBound..<result.index(after: closeRange.lowerBound)
      result.replaceSubrange(fullRange, with: replacement)
    }

    return result
  }

  // MARK: - Tokenizer

  private enum Token {
    case functionName(String)
    case paramRef(String)
    case number(Double)
    case openParen
    case closeParen
    case comma
    case stringLiteral(String)
  }

  private static func tokenize(_ input: String) -> [Token] {
    var tokens: [Token] = []
    let chars = Array(input)
    var i = 0

    while i < chars.count {
      let ch = chars[i]

      if ch.isWhitespace { i += 1; continue }
      if ch == "(" { tokens.append(.openParen); i += 1; continue }
      if ch == ")" { tokens.append(.closeParen); i += 1; continue }
      if ch == "," { tokens.append(.comma); i += 1; continue }

      // String literal: "..."
      if ch == "\"" {
        i += 1
        var str = ""
        while i < chars.count && chars[i] != "\"" {
          str.append(chars[i])
          i += 1
        }
        if i < chars.count { i += 1 }  // skip closing quote
        tokens.append(.stringLiteral(str))
        continue
      }

      // Number (including negative)
      if ch.isNumber || (ch == "-" && i + 1 < chars.count && chars[i + 1].isNumber) {
        var numStr = String(ch)
        i += 1
        while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
          numStr.append(chars[i])
          i += 1
        }
        if let val = Double(numStr) {
          tokens.append(.number(val))
        }
        continue
      }

      // Identifier (function name or param ref)
      if ch.isLetter || ch == "_" {
        var ident = String(ch)
        i += 1
        while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
          ident.append(chars[i])
          i += 1
        }
        if ident.first?.isUppercase == true {
          tokens.append(.functionName(ident))
        } else {
          tokens.append(.paramRef(ident))
        }
        continue
      }

      i += 1  // skip unknown chars
    }

    return tokens
  }

  // MARK: - AST

  private indirect enum ASTNode {
    case literal(Double)
    case paramRef(String)
    case functionCall(String, [ASTNode])
  }

  // MARK: - Parser

  private static func parse(tokens: [Token]) -> ASTNode? {
    var pos = 0
    return parseExpr(tokens: tokens, pos: &pos)
  }

  private static func parseExpr(tokens: [Token], pos: inout Int) -> ASTNode? {
    guard pos < tokens.count else { return nil }

    switch tokens[pos] {
    case .number(let v):
      pos += 1
      return .literal(v)

    case .stringLiteral(let s):
      pos += 1
      // String literals are kept as param refs so HOURS_BETWEEN can resolve them
      return .paramRef("__literal__\(s)")

    case .paramRef(let name):
      pos += 1
      return .paramRef(name)

    case .functionName(let name):
      pos += 1  // skip function name
      guard pos < tokens.count, case .openParen = tokens[pos] else { return nil }
      pos += 1  // skip (

      var args: [ASTNode] = []
      while pos < tokens.count {
        if case .closeParen = tokens[pos] { pos += 1; break }
        if case .comma = tokens[pos] { pos += 1; continue }
        if let arg = parseExpr(tokens: tokens, pos: &pos) {
          args.append(arg)
        }
      }
      return .functionCall(name, args)

    default:
      return nil
    }
  }

  // MARK: - Evaluator

  private static func evaluateNode(_ node: ASTNode, parameters: [String: DSLValue]) -> Double? {
    switch node {
    case .literal(let v):
      return v

    case .paramRef(let name):
      if name.hasPrefix("__literal__") {
        // This is a string literal used inside HOURS_BETWEEN — return nil
        // The function itself handles string resolution
        return nil
      }
      guard let value = parameters[name] else { return nil }
      return value.numericValue

    case .functionCall(let name, let args):
      return evaluateFunction(name, args: args, parameters: parameters)
    }
  }

  private static func evaluateFunction(
    _ name: String, args: [ASTNode], parameters: [String: DSLValue]
  ) -> Double? {
    // Resolve arguments, handling special cases for string args in HOURS_BETWEEN
    func resolveNumeric(_ index: Int) -> Double? {
      guard index < args.count else { return nil }
      return evaluateNode(args[index], parameters: parameters)
    }

    func resolveString(_ index: Int) -> String? {
      guard index < args.count else { return nil }
      if case .paramRef(let ref) = args[index] {
        if ref.hasPrefix("__literal__") {
          return String(ref.dropFirst("__literal__".count))
        }
        return parameters[ref]?.stringValue
      }
      return nil
    }

    switch name {
    case "ADD":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1) else { return nil }
      return a + b

    case "SUBTRACT":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1) else { return nil }
      return a - b

    case "MULTIPLY":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1) else { return nil }
      return a * b

    case "DIVIDE":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1), b != 0 else { return nil }
      return a / b

    case "ROUND":
      guard let value = resolveNumeric(0), let places = resolveNumeric(1) else { return nil }
      let multiplier = pow(10.0, places)
      return (value * multiplier).rounded() / multiplier

    case "PERCENT":
      guard let value = resolveNumeric(0) else { return nil }
      return value * 100

    case "HALF_LIFE_DECAY":
      guard let initial = resolveNumeric(0), let halfLife = resolveNumeric(1),
        let elapsed = resolveNumeric(2)
      else { return nil }
      return initial * pow(0.5, elapsed / halfLife)

    case "HOURS_BETWEEN":
      guard let time1 = resolveString(0), let time2 = resolveString(1) else { return nil }
      guard let hours = hoursBetween(time1, time2) else { return nil }
      return hours

    case "MIN":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1) else { return nil }
      return Swift.min(a, b)

    case "MAX":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1) else { return nil }
      return Swift.max(a, b)

    case "CLAMP":
      guard let value = resolveNumeric(0), let low = resolveNumeric(1),
        let high = resolveNumeric(2)
      else { return nil }
      return Swift.min(Swift.max(value, low), high)

    case "IF_GREATER":
      guard let a = resolveNumeric(0), let b = resolveNumeric(1),
        let then = resolveNumeric(2), let elseVal = resolveNumeric(3)
      else { return nil }
      return a > b ? then : elseVal

    case "PERCENTAGE_OF":
      guard let part = resolveNumeric(0), let whole = resolveNumeric(1), whole != 0 else {
        return nil
      }
      return (part / whole) * 100

    default:
      return nil
    }
  }

  // MARK: - Time Helpers

  private static func hoursBetween(_ t1: String, _ t2: String) -> Double? {
    guard let h1 = parseTimeToHour(t1), let h2 = parseTimeToHour(t2) else { return nil }
    var diff = h2 - h1
    if diff < 0 { diff += 24 }  // wraps past midnight
    return diff
  }

  private static func parseTimeToHour(_ time: String) -> Double? {
    let trimmed = time.trimmingCharacters(in: .whitespaces).uppercased()

    let isPM = trimmed.contains("PM")
    let isAM = trimmed.contains("AM")
    let numericPart =
      trimmed
      .replacingOccurrences(of: "AM", with: "")
      .replacingOccurrences(of: "PM", with: "")
      .trimmingCharacters(in: .whitespaces)

    let parts = numericPart.split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty else { return nil }

    var hour = parts[0]
    let minutes = parts.count > 1 ? parts[1] : 0

    if isPM && hour != 12 { hour += 12 }
    if isAM && hour == 12 { hour = 0 }

    return hour + minutes / 60.0
  }

  // MARK: - Brace Matching

  private static func findMatchingBrace(in str: String, from start: String.Index) -> Range<
    String.Index
  >? {
    var depth = 0
    var i = str.index(after: start)
    while i < str.endIndex {
      let ch = str[i]
      if ch == "{" {
        depth += 1
      } else if ch == "}" {
        if depth == 0 {
          return i..<str.index(after: i)
        }
        depth -= 1
      }
      i = str.index(after: i)
    }
    return nil
  }
}

// MARK: - DSLValue

/// A resolved parameter value — either numeric or string.
enum DSLValue {
  case number(Double)
  case string(String)

  var numericValue: Double? {
    switch self {
    case .number(let v): return v
    case .string(_): return nil
    }
  }

  var stringValue: String? {
    switch self {
    case .number(_): return nil
    case .string(let v): return v
    }
  }

  var displayString: String {
    switch self {
    case .number(let v):
      if v == v.rounded() && abs(v) < 1e15 {
        return String(Int(v))
      }
      return String(format: "%.1f", v)
    case .string(let v): return v
    }
  }
}
