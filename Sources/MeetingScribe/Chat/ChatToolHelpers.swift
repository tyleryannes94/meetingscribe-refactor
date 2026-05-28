import Foundation
import VaultKit

/// Shared helpers used by every domain-specific Chat tool implementation.
///
/// Lifted out of the old `ChatTools.swift` god-object as part of the Phase 0
/// refactor. Kept as an `enum` with `static` members so callers don't have to
/// allocate (or thread an instance through).
@MainActor
enum ChatToolHelpers {

    // MARK: - JSON shaping
    //
    // Every tool returns a JSON string to the model. We use sorted, fragments-
    // allowed JSON so tool output is stable and grep-friendly in transcripts.

    static func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    // MARK: - Date formatting

    /// ISO-8601 in the standard form — what the tool result schemas all advertise.
    static func iso(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }

    /// Parse a date the model handed us. Accepts full ISO-8601 (with timezone)
    /// first, falls back to bare `yyyy-MM-dd` which is what small local models
    /// emit most of the time.
    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    // MARK: - String helpers

    /// Normalize a model-supplied enum-ish string so we can match it against
    /// our own raw values without caring about case or whitespace.
    static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Meeting lookup
    //
    // Always read meetings fresh from the store (self-healing index) rather
    // than the in-memory `pastMeetings`, which can be empty/stale if the chat
    // runs before a tab populated it. This is what fixes "no meetings found".

    static func allMeetings(manager: MeetingManager) -> [Meeting] {
        let inMemory = manager.pastMeetings
        if !inMemory.isEmpty { return inMemory }
        return manager.store.listPastMeetings()
    }
}
