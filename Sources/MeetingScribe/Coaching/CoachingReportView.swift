import SwiftUI

/// The "Coach" tab: conversational-hygiene metrics for a single meeting —
/// talk-time balance, question count, action-item density, and a few
/// plain-language suggestions.
@available(macOS 14.0, *)
struct CoachingReportView: View {
    let report: CoachingReport

    var body: some View {
        if report.totalWords == 0 {
            placeholder
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metricsRow
                    if !report.talkTime.isEmpty {
                        talkTimeSection
                    }
                    suggestionsSection
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.mind.and.body").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No coaching insights yet").font(.headline)
            Text("Coaching runs on the transcript. Record or transcribe this meeting first.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard("Words", "\(report.totalWords)", "text.alignleft")
            metricCard("Questions", "\(report.questionCount)", "questionmark.bubble")
            metricCard("Action items", "\(report.actionItemCount)", "checklist")
            metricCard("Items / 1k words", String(format: "%.1f", report.actionItemDensity), "gauge.medium")
        }
    }

    private func metricCard(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }

    private var talkTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Talk time").font(.headline)
            ForEach(report.talkTime) { slice in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(slice.speaker).font(.callout)
                        Spacer()
                        Text("\(Int(slice.fraction * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(Color.accentColor)
                                .frame(width: max(2, geo.size.width * slice.fraction))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions").font(.headline)
            ForEach(Array(report.suggestions.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").font(.caption).foregroundStyle(.yellow)
                    Text(s).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
