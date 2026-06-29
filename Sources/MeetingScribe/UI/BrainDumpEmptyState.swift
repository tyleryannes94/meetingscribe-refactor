import SwiftUI

/// Landing UI shown when there are no Brain Dump sessions yet. Sells the page
/// (composer + URL/search + AI → tasks + calendar) and offers one-click start.
@available(macOS 14.0, *)
struct BrainDumpEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "brain.head.profile.fill")
                .scaledFont(56).foregroundStyle(NDS.brand.opacity(0.85))
            VStack(spacing: 6) {
                Text("Capture everything on your mind")
                    .scaledFont(22, weight: .bold, kind: .display)
                Text("Type, paste URLs, pull a daily brief — then let the planner turn it into tasks and time-blocked focus.")
                    .font(NDS.body).foregroundStyle(NDS.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            Button {
                onCreate()
            } label: {
                Label("Start a brain dump", systemImage: "plus.circle.fill")
            }
            .buttonStyle(MSPrimaryButtonStyle())
            VStack(alignment: .leading, spacing: 6) {
                exampleRow("brain.head.profile", "\"Need to finish the Q3 deck by Friday, follow up with Sam about the contract…\"")
                exampleRow("link", "Paste a URL — the planner reads it and folds the key points into your plan.")
                exampleRow("magnifyingglass", "Type a search query — the planner runs the web for you (Tavily).")
                exampleRow("calendar.badge.clock", "Suggested tasks and 25-min focus blocks land in your calendar.")
            }
            .padding(16)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius)
                .strokeBorder(NDS.hairline, lineWidth: 0.5))
            .frame(maxWidth: 520)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func exampleRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).scaledFont(14).foregroundStyle(NDS.brand)
                .frame(width: 18)
            Text(text).font(NDS.small).foregroundStyle(NDS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
