import SwiftUI

/// App-wide counter of in-flight *background* refreshes (off-main vault scans /
/// list reloads). Lets the UI show a subtle "updating…" hint while data
/// revalidates in place — never a blocking spinner. Increment with `begin()`
/// before kicking an async reload and `end()` when it lands; the published
/// `isRefreshing` flips false once every in-flight refresh has completed.
///
/// Single source so several concurrent refreshes (e.g. meetings + voice notes
/// prewarm at launch) collapse into one hint rather than fighting over it.
@available(macOS 14.0, *)
@MainActor
final class RefreshIndicator: ObservableObject {
    static let shared = RefreshIndicator()

    @Published private(set) var inFlight = 0

    /// True while at least one background refresh is running.
    var isRefreshing: Bool { inFlight > 0 }

    func begin() { inFlight += 1 }
    func end() { inFlight = max(0, inFlight - 1) }

    /// Convenience wrapper: brackets an async reload with begin/end so callers
    /// can't leak a count on an early return / throw.
    func track(_ body: () async -> Void) async {
        begin()
        await body()
        end()
    }
}
