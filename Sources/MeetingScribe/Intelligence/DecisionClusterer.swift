import Foundation

/// Groups decisions by topic using their embeddings (4-D). Greedy
/// cosine-threshold clustering — cheap, deterministic, and runs in-memory over
/// the (typically tens to low-hundreds of) decisions. Cluster labels are derived
/// from the most frequent significant word in each cluster's decision texts, so
/// no extra Ollama round-trip is needed to render the grouped ledger.
enum DecisionClusterer {

    /// Returns `(label, decisions)` groups, largest first. Decisions without an
    /// embedding fall into a trailing "Other" group so nothing is dropped.
    static func cluster(_ decisions: [Decision],
                        embeddings: [String: [Float]],
                        threshold: Float = 0.55) -> [(key: String, items: [Decision])] {
        var clusters: [[Decision]] = []
        var assigned = Set<String>()

        for d in decisions {
            guard let v = embeddings[d.id], !assigned.contains(d.id) else { continue }
            var group = [d]
            assigned.insert(d.id)
            for other in decisions where !assigned.contains(other.id) {
                guard let ov = embeddings[other.id] else { continue }
                if EmbeddingService.cosine(v, ov) >= threshold {
                    group.append(other)
                    assigned.insert(other.id)
                }
            }
            clusters.append(group)
        }

        var result = clusters.map { group in
            (key: label(for: group), items: group.sorted { $0.date > $1.date })
        }
        let unembedded = decisions.filter { !assigned.contains($0.id) }
        if !unembedded.isEmpty {
            result.append((key: "Other (\(unembedded.count))",
                           items: unembedded.sorted { $0.date > $1.date }))
        }
        // Largest topics first; the "Other" bucket naturally sinks if small.
        return result.sorted { $0.items.count > $1.items.count }
    }

    private static let stopwords: Set<String> = [
        "the","that","this","with","from","into","about","will","would","should",
        "have","has","our","your","their","them","they","what","when","which",
        "make","made","need","want","keep","move","plan","also","than","then",
        "decision","decided","decide"
    ]

    private static func label(for group: [Decision]) -> String {
        var counts: [String: Int] = [:]
        for d in group {
            let words = d.text.lowercased().split { !$0.isLetter }
            for w in words where w.count > 3 && !stopwords.contains(String(w)) {
                counts[String(w), default: 0] += 1
            }
        }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else {
            return "Decisions (\(group.count))"
        }
        let titled = top.prefix(1).uppercased() + top.dropFirst()
        return "\(titled) (\(group.count))"
    }
}
