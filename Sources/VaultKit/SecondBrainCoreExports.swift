// SecondBrainCore
//
// The dependency-free heart of the Second Brain: `Person`, `Encounter`, and
// the `SecondBrainStore` protocol (with an `InMemorySecondBrainStore`
// reference implementation). No AppKit / SwiftUI / CloudKit — import this from
// either the macOS app or a future iOS app.
//
// This file exists as the module's documentation anchor and a single place to
// add `@_exported import` re-exports if the module later splits into files
// that callers shouldn't have to import individually.

import Foundation

public enum SecondBrainCore {
    /// Bump when the on-disk / on-wire model shape changes incompatibly.
    public static let schemaVersion = 1
}
