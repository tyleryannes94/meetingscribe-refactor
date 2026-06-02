import Foundation

/// A timestamped thing worth remembering about a person (Phase C). Freeform —
/// "loves single-origin coffee", "kid started kindergarten", etc. `occurredOn`
/// is optional (some memories are dateless facts).
struct Memory: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var occurredOn: Date?
    var createdAt: Date

    init(id: String = UUID().uuidString, text: String, occurredOn: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.occurredOn = occurredOn
        self.createdAt = createdAt
    }
}

/// A long-form note attached to a person — typically a chat analysis the
/// user wanted to keep ("sentiment trends with Horst", "summary of our
/// recent conversations"). Distinct from `Memory` (short freeform facts):
/// AttachedNote carries a title, kind, and multi-paragraph body so the
/// detail view can render them as their own section with collapsible
/// content and a chip per kind.
struct AttachedNote: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var body: String
    /// Short tag describing the analysis type. Free-form so future presets
    /// can add new kinds without a schema change — common values today are
    /// "summary", "sentiment", "topics", "style", "custom".
    var kind: String
    var createdAt: Date

    init(id: String = UUID().uuidString,
         title: String,
         body: String,
         kind: String = "custom",
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.createdAt = createdAt
    }
}

// MARK: - Relationship Type

/// The category of relationship this person represents.
/// Each type carries default check-in cadence and enables type-specific
/// content (coaching prompts, frameworks, UI differentiation).
/// Stored as a String rawValue so new cases survive tolerant decoding on
/// earlier builds — unknown raw values decode to `.unset` via `decodeIfPresent`.
enum RelationshipType: String, Codable, CaseIterable, Hashable {
    case romanticPartner  = "romantic_partner"
    case familyMember     = "family_member"
    case closeFriend      = "close_friend"
    case friend           = "friend"
    case colleague        = "colleague"
    case acquaintance     = "acquaintance"
    case unset            = "unset"

    var displayName: String {
        switch self {
        case .romanticPartner:  return "Partner"
        case .familyMember:     return "Family"
        case .closeFriend:      return "Close Friend"
        case .friend:           return "Friend"
        case .colleague:        return "Colleague"
        case .acquaintance:     return "Acquaintance"
        case .unset:            return "Unset"
        }
    }

    /// Suggested days between check-ins for this relationship type.
    var defaultCheckInDays: Int {
        switch self {
        case .romanticPartner:  return 1
        case .familyMember:     return 7
        case .closeFriend:      return 14
        case .friend:           return 21
        case .colleague:        return 30
        case .acquaintance:     return 60
        case .unset:            return 14
        }
    }

    /// Types that unlock depth content (coaching frameworks, reflection prompts).
    var supportsDepthContent: Bool {
        switch self {
        case .romanticPartner, .familyMember, .closeFriend: return true
        default: return false
        }
    }

    var emoji: String {
        switch self {
        case .romanticPartner:  return "💑"
        case .familyMember:     return "👨‍👩‍👧"
        case .closeFriend:      return "🤝"
        case .friend:           return "😊"
        case .colleague:        return "💼"
        case .acquaintance:     return "👋"
        case .unset:            return "👤"
        }
    }

    /// Accent color token name for this type (referenced in NDS / SwiftUI).
    var colorName: String {
        switch self {
        case .romanticPartner:  return "RelationshipPartner"   // rose
        case .familyMember:     return "RelationshipFamily"    // amber
        case .closeFriend:      return "RelationshipCloseFriend" // teal
        case .friend:           return "RelationshipFriend"    // sky
        case .colleague:        return "RelationshipColleague" // slate
        case .acquaintance:     return "RelationshipAcquaintance" // gray
        case .unset:            return "RelationshipUnset"     // neutral
        }
    }

    /// E2-10 — best-effort classification from a freeform relationship label
    /// (e.g. "spouse", "mom", "manager"). Used as a one-time forward migration
    /// so existing users get an inferred type without re-entering data. Returns
    /// nil when no keyword matches. Symmetric romantic/family labels classify
    /// correctly regardless of edge direction; ambiguous labels stay nil.
    static func inferred(fromLabel rawLabel: String) -> RelationshipType? {
        let l = rawLabel.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { l.contains($0) } }
        // Order matters: "best friend" must hit closeFriend before "friend".
        if has(["spouse", "partner", "wife", "husband", "girlfriend",
                "boyfriend", "fiance", "fiancé", "fiancée", "significant other"]) {
            return .romanticPartner
        }
        if has(["mom", "mother", "dad", "father", "parent", "sister", "brother",
                "sibling", "son", "daughter", "kid", "child", "grandma", "grandpa",
                "grandmother", "grandfather", "aunt", "uncle", "cousin", "nephew",
                "niece", "family"]) {
            return .familyMember
        }
        if has(["best friend", "bestie", "close friend"]) { return .closeFriend }
        if has(["manager", "boss", "coworker", "co-worker", "colleague",
                "report", "teammate", "client", "vendor", "coleague"]) {
            return .colleague
        }
        if has(["friend"]) { return .friend }
        return nil
    }
}

// MARK: - Relationship (person-to-person edge)

/// A directed relationship to another person (§4.4). Bidirectional by default —
/// when set on A→B, `PeopleStore` mirrors a reciprocal entry on B.
struct Relationship: Identifiable, Codable, Hashable {
    var id: String
    var toPersonID: String
    /// "spouse", "manager", "kid", "friend" — freeform.
    var label: String
    var createdAt: Date

    init(id: String = UUID().uuidString, toPersonID: String, label: String, createdAt: Date = Date()) {
        self.id = id
        self.toPersonID = toPersonID
        self.label = label
        self.createdAt = createdAt
    }
}

/// A first-class person in the second brain. Created manually (Phase A),
/// auto-populated from meeting transcripts (Phase B), and imported from
/// Contacts / Gmail / calendar / iMessage (Phase C).
///
/// Files live at: `<storageDir>/people/<slug>/`
///   ├── person.json   — canonical Codable record (schema-versioned envelope)
///   └── person.md      — human-readable mirror, regenerated on every write
///
/// `id` is a UUID string to match the rest of the workspace (Meeting / QuickNote
/// / MeetingTag all key on `String`), so a Person can be cross-referenced from
/// `meetingMentions` etc. in later phases without a type bridge.
struct Person: Identifiable, Codable, Hashable {
    var id: String
    /// Canonical display name. Editable.
    var displayName: String
    var company: String
    var role: String
    /// Multi-valued under the hood (Contacts import in a later phase adds more);
    /// the Phase A add/edit sheet edits the first entry.
    var emails: [String]
    var phones: [String]
    /// Freeform notes — markdown. The "notes" field in the add/edit sheet.
    var bio: String
    /// Tags this person carries — reuses the existing `MeetingTag` namespace so
    /// event tags like "Purple Party 2026" are shared with meetings.
    var tagIDs: Set<String>
    var createdAt: Date
    var updatedAt: Date
    /// Most recent encounter date (or last manual edit). Drives recency sort.
    var lastInteractionAt: Date?
    /// Backlinks (Phase B) — IDs of meetings whose transcript mentions this
    /// person, populated by the auto-extraction pipeline and by confirming a
    /// suggestion. Surfaced as "Mentioned in" in the detail view.
    var meetingMentions: Set<String>

    // MARK: - Phase C — rich profile + import provenance

    var birthday: Date?
    /// Postal addresses (multi-valued from Contacts). UI edits the first.
    var addresses: [String]
    /// "Favorite things" — coffee order, restaurants, gifts, whatever.
    var favorites: [String]
    /// Timestamped memories.
    var memories: [Memory]
    /// Relative paths (under the person's folder) to attached photos.
    var photoRelativePaths: [String]
    /// Source `CNContact.identifier`, when imported from Apple/iCloud Contacts —
    /// used to dedupe on re-import.
    var contactIdentifier: String?
    /// Where this record's data came from: "manual", "contacts", "gmail",
    /// "calendar", "vcard", "csv", "transcript". Shown as provenance.
    var importSources: Set<String>
    /// Relationships to other people (§4.4), mirrored bidirectionally.
    var relationships: [Relationship]
    /// Long-form analyses / notes attached from the chat (or future
    /// "Save to person" affordances). Distinct from `memories` — see
    /// `AttachedNote` for the shape.
    var attachedNotes: [AttachedNote]

    // MARK: - Phase D — relationship type + check-in cadence

    /// The kind of relationship (partner, family, close friend, …).
    /// Defaults to `.unset`; set in AddPersonSheet or PersonDetailView.
    var relationshipType: RelationshipType
    /// User-overridden check-in cadence in days. When nil, the type's
    /// `defaultCheckInDays` is used.
    var checkInCadenceDays: Int?

    /// Effective days between check-ins: user override if set, else type default.
    var effectiveCheckInDays: Int {
        checkInCadenceDays ?? relationshipType.defaultCheckInDays
    }

    init(id: String = UUID().uuidString,
         displayName: String,
         company: String = "",
         role: String = "",
         emails: [String] = [],
         phones: [String] = [],
         bio: String = "",
         tagIDs: Set<String> = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         lastInteractionAt: Date? = nil,
         meetingMentions: Set<String> = [],
         birthday: Date? = nil,
         addresses: [String] = [],
         favorites: [String] = [],
         memories: [Memory] = [],
         photoRelativePaths: [String] = [],
         contactIdentifier: String? = nil,
         importSources: Set<String> = [],
         relationships: [Relationship] = [],
         attachedNotes: [AttachedNote] = [],
         relationshipType: RelationshipType = .unset,
         checkInCadenceDays: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.company = company
        self.role = role
        self.emails = emails
        self.phones = phones
        self.bio = bio
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastInteractionAt = lastInteractionAt
        self.meetingMentions = meetingMentions
        self.birthday = birthday
        self.addresses = addresses
        self.favorites = favorites
        self.memories = memories
        self.photoRelativePaths = photoRelativePaths
        self.contactIdentifier = contactIdentifier
        self.importSources = importSources
        self.relationships = relationships
        self.attachedNotes = attachedNotes
        self.relationshipType = relationshipType
        self.checkInCadenceDays = checkInCadenceDays
    }

    /// Convenience accessors for the Phase A single-field sheet.
    var primaryEmail: String { emails.first ?? "" }
    var primaryPhone: String { phones.first ?? "" }
    var primaryAddress: String { addresses.first ?? "" }

    /// Folder-safe slug, stable enough for a human-readable directory while a
    /// short id suffix keeps it unique across same-named people and renames.
    var slug: String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safe = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalid)
            .joined(separator: "-")
        let name = safe.isEmpty ? "person" : String(safe.prefix(40))
        return "\(name)-\(id.prefix(8))"
    }
}

extension Person {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, company, role, emails, phones, bio, tagIDs,
             createdAt, updatedAt, lastInteractionAt, meetingMentions,
             birthday, addresses, favorites, memories, photoRelativePaths,
             contactIdentifier, importSources, relationships, attachedNotes,
             relationshipType, checkInCadenceDays
    }

    /// Tolerant decoder. Like `Meeting`, every field added after the first
    /// release is optional-with-default so a `person.json` written by an
    /// earlier build (e.g. a Phase A record with no `meetingMentions`) still
    /// loads instead of silently disappearing from disk scans.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        company = (try? c.decode(String.self, forKey: .company)) ?? ""
        role = (try? c.decode(String.self, forKey: .role)) ?? ""
        emails = (try? c.decode([String].self, forKey: .emails)) ?? []
        phones = (try? c.decode([String].self, forKey: .phones)) ?? []
        bio = (try? c.decode(String.self, forKey: .bio)) ?? ""
        tagIDs = (try? c.decode(Set<String>.self, forKey: .tagIDs)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        lastInteractionAt = (try? c.decodeIfPresent(Date.self, forKey: .lastInteractionAt)) ?? nil
        meetingMentions = (try? c.decode(Set<String>.self, forKey: .meetingMentions)) ?? []
        birthday = (try? c.decodeIfPresent(Date.self, forKey: .birthday)) ?? nil
        addresses = (try? c.decode([String].self, forKey: .addresses)) ?? []
        favorites = (try? c.decode([String].self, forKey: .favorites)) ?? []
        memories = (try? c.decode([Memory].self, forKey: .memories)) ?? []
        photoRelativePaths = (try? c.decode([String].self, forKey: .photoRelativePaths)) ?? []
        contactIdentifier = (try? c.decodeIfPresent(String.self, forKey: .contactIdentifier)) ?? nil
        importSources = (try? c.decode(Set<String>.self, forKey: .importSources)) ?? []
        relationships = (try? c.decode([Relationship].self, forKey: .relationships)) ?? []
        attachedNotes = (try? c.decode([AttachedNote].self, forKey: .attachedNotes)) ?? []
        // Phase D — tolerant: unknown raw values (future types on older builds) → .unset
        relationshipType = (try? c.decodeIfPresent(RelationshipType.self, forKey: .relationshipType)) ?? .unset
        checkInCadenceDays = (try? c.decodeIfPresent(Int.self, forKey: .checkInCadenceDays)) ?? nil
    }

    /// A coarse relevance score (§12.4) used to surface high-signal people and
    /// tuck "ghost contacts" (imported once, never interacted with) behind a
    /// filter. `encounterCount` is supplied by PeopleStore (which owns
    /// encounters). Higher = more relevant.
    func relevanceScore(encounterCount: Int) -> Double {
        var score = 0.0
        if let last = lastInteractionAt {
            let days = max(0, Date().timeIntervalSince(last) / 86400)
            score += max(0, 30 - days / 12)        // recent interaction matters most
        }
        score += Double(meetingMentions.count) * 4
        score += Double(memories.count) * 3
        score += Double(attachedNotes.count) * 4
        score += Double(relationships.count) * 5
        score += Double(encounterCount) * 4
        if !photoRelativePaths.isEmpty { score += 3 }
        if !bio.isEmpty { score += 2 }
        if !tagIDs.isEmpty { score += 2 }
        // A bare contact (imported, no signal) scores ~0 → "ghost".
        return score
    }

    /// True when the person has essentially no signal beyond raw contact info —
    /// a "ghost contact" to hide behind the All-people filter.
    func isGhost(encounterCount: Int) -> Bool {
        relevanceScore(encounterCount: encounterCount) < 1
            && meetingMentions.isEmpty && memories.isEmpty
            && relationships.isEmpty && encounterCount == 0
            && tagIDs.isEmpty && lastInteractionAt == nil
    }
}
