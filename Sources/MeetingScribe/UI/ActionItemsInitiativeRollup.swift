import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Initiative roll-up (3-2)

    /// The initiative pane: a compact header over its projects shown as a board
    /// (or list). All the real layout lives in `InitiativeDetailView`; routing in
    /// `detailContent` still calls this so callers are untouched.
    @ViewBuilder
    func initiativeRollup(_ id: String) -> some View {
        InitiativeDetailView(parent: self, store: store, initiativeID: id)
    }
}
