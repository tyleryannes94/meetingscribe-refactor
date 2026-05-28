import Foundation

/// A person in the Second Brain — someone you've met, work with, or track.
///
/// Deliberately dependency-free (`Foundation` only): no AppKit, SwiftUI, or
/// persistence-framework imports. This is the canonical model the macOS app
/// and a future iOS app can both build against. The app's richer
/// `MeetingScribe.Person` can be made to bridge to / from this over time.
public struct Person: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var emails: [String]
    public var company: String?
    public var role: String?
    public var notes: String?
    /// Free-form tags ("investor", "candidate", "teammate", …).
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        emails: [String] = [],
        company: String? = nil,
        role: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emails = emails
        self.company = company
        self.role = role
        self.notes = notes
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Best primary email, if any (first non-empty).
    public var primaryEmail: String? {
        emails.first { !$0.isEmpty }
    }
}
