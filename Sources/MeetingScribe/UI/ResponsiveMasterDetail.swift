import SwiftUI

/// A two-column master-detail layout that stays a draggable `HSplitView` on
/// roomy panes but **collapses to a single column** below `threshold` — showing
/// the detail (with a back bar) when something is selected, otherwise the
/// sidebar. This is the app-wide fix for tabs whose `HSplitView` minimums
/// (sidebar + detail) exceeded the window once it could shrink past ~620pt, so
/// People / Recordings / Voice Notes never clip or break at narrow widths.
@available(macOS 14.0, *)
struct ResponsiveMasterDetail<Sidebar: View, Detail: View>: View {
    /// Pane width below which the split collapses to one column.
    var threshold: CGFloat = 640
    /// True when a detail item is selected (drives which column shows when narrow).
    let showingDetail: Bool
    /// Clears the selection (the narrow-mode back action).
    let onBack: () -> Void
    /// Label for the back button (e.g. "Voice Notes").
    let backLabel: String
    var sidebarMin: CGFloat = 240
    var sidebarIdeal: CGFloat = 320
    var sidebarMax: CGFloat = 360
    var detailMin: CGFloat = 380
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        GeometryReader { geo in
            if geo.size.width < threshold {
                Group {
                    if showingDetail {
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Button(action: onBack) {
                                    Label(backLabel, systemImage: "chevron.left")
                                        .font(NDS.small).lineLimit(1)
                                }
                                .buttonStyle(.plain).foregroundStyle(NDS.accent)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            Divider().overlay(NDS.divider)
                            detail()
                        }
                    } else {
                        sidebar()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                HSplitView {
                    sidebar().frame(minWidth: sidebarMin, idealWidth: sidebarIdeal, maxWidth: sidebarMax)
                    detail().frame(minWidth: detailMin)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}
