import SwiftUI

/// Live activity strip rendered under the composer while the planner runs.
///
/// Shows the most recent planner events — what tools the model is calling,
/// what sources it's attaching, what drafts it's proposing — so the user can
/// see real progress through the 10–30 s tool loop on the 7B model (qwen2.5)
/// instead of staring at a "Planning…" spinner.
@available(macOS 14.0, *)
struct BrainDumpActivityLog: View {
    let events: [BrainDumpPlannerEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").scaledFont(12).foregroundStyle(NDS.brand)
                Text("Activity").scaledFont(11, weight: .bold).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider().overlay(NDS.divider)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                            row(event)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .onChange(of: events.count) { _ in
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(events.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(NDS.fieldBg.opacity(0.3))
    }

    private func row(_ event: BrainDumpPlannerEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: glyph(for: event)).scaledFont(11)
                .foregroundStyle(color(for: event))
                .frame(width: 14)
            Text(event.label).font(NDS.small)
                .foregroundStyle(event.isError ? NDS.selectColor("red") : NDS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func glyph(for event: BrainDumpPlannerEvent) -> String {
        switch event {
        case .started:                       return "play.circle"
        case .toolCalled:                    return "gearshape"
        case .toolFailed, .failed:           return "exclamationmark.triangle"
        case .sourceAttached:                return "link"
        case .draftProposed(let kind, _):    return kind == "task" ? "checkmark.circle" : "calendar.badge.plus"
        case .finished:                      return "checkmark.seal"
        }
    }

    private func color(for event: BrainDumpPlannerEvent) -> Color {
        if event.isError { return NDS.selectColor("red") }
        switch event {
        case .started, .toolCalled: return NDS.brand
        case .sourceAttached:       return NDS.brand
        case .draftProposed:        return NDS.brand
        case .finished:             return NDS.brand
        default:                    return NDS.textTertiary
        }
    }
}
