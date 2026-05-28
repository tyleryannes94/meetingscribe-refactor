import Foundation

/// Jaro-Winkler string similarity, used to decide whether a name extracted
/// from a transcript ("Jane", "Jane S.") refers to an existing `Person`
/// ("Jane Smith"). Returns a score in 0...1; the Winkler prefix boost makes
/// "Sara" → "Sara Smith" score high enough to auto-link (audit §5.2).
enum NameSimilarity {

    /// Case- and whitespace-insensitive Jaro-Winkler over two names. Compares
    /// the full strings and also each token of `b` against `a`, taking the
    /// best — so "Jane" matches "Smith, Jane" as well as "Jane Smith".
    static func score(_ a: String, _ b: String) -> Double {
        let na = normalize(a)
        let nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return 0 }
        if na == nb { return 1 }
        var best = jaroWinkler(na, nb)
        // First-name / token matches: a transcript often uses just a first
        // name. Compare the shorter string against each token of the longer.
        let (shorter, longer) = na.count <= nb.count ? (na, nb) : (nb, na)
        for token in longer.split(separator: " ") where token.count >= 2 {
            best = max(best, jaroWinkler(shorter, String(token)))
        }
        return best
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Classic Jaro-Winkler with the standard prefix scaling factor (0.1) and
    /// a 4-character prefix cap.
    static func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        let j = jaro(s1, s2)
        guard j > 0.7 else { return j }
        let a = Array(s1), b = Array(s2)
        var prefix = 0
        for i in 0..<min(4, min(a.count, b.count)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }
        return j + Double(prefix) * 0.1 * (1 - j)
    }

    private static func jaro(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1), b = Array(s2)
        if a.isEmpty || b.isEmpty { return 0 }
        let matchDistance = max(a.count, b.count) / 2 - 1
        var aMatches = [Bool](repeating: false, count: a.count)
        var bMatches = [Bool](repeating: false, count: b.count)
        var matches = 0
        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, b.count)
            guard start < end else { continue }
            for k in start..<end where !bMatches[k] && a[i] == b[k] {
                aMatches[i] = true
                bMatches[k] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        // Count transpositions.
        var transpositions = 0
        var k = 0
        for i in 0..<a.count where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let t = Double(transpositions) / 2
        return (m / Double(a.count) + m / Double(b.count) + (m - t) / m) / 3
    }
}
