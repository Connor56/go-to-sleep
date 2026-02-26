import Foundation

/// Levenshtein-based fuzzy string matching for verifiable_fact word answers.
enum FuzzyMatcher {

  /// Returns a similarity ratio between 0.0 (completely different) and 1.0 (identical).
  /// Both strings are lowercased and trimmed before comparison.
  static func similarity(_ s1: String, _ s2: String) -> Double {
    let a = s1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let b = s2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    if a == b { return 1.0 }
    let maxLen = max(a.count, b.count)
    if maxLen == 0 { return 1.0 }

    let distance = levenshteinDistance(a, b)
    return 1.0 - Double(distance) / Double(maxLen)
  }

  private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let a = Array(s1)
    let b = Array(s2)
    let m = a.count
    let n = b.count

    if m == 0 { return n }
    if n == 0 { return m }

    // Single-row DP
    var prev = Array(0...n)
    var curr = [Int](repeating: 0, count: n + 1)

    for i in 1...m {
      curr[0] = i
      for j in 1...n {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        curr[j] = min(
          prev[j] + 1,  // deletion
          curr[j - 1] + 1,  // insertion
          prev[j - 1] + cost  // substitution
        )
      }
      swap(&prev, &curr)
    }

    return prev[n]
  }
}
