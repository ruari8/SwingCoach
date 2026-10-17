//
//  GroundedCoachingView.swift
//  SwingCoach
//
//  Source-backed coaching focus, evidence and sources for a saved analysis.
//

import SwiftUI

struct GroundedCoachingView: View {
    let coaching: SavedCoachingDetail

    private func timestamp(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private var statusLabel: String {
        switch coaching.status {
        case "recommend": "One focus to test"
        case "preserve": "Keep what works"
        case "need_evidence": "More evidence needed"
        default: "Measurements ready · Coach unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityIdentifier("coaching-status")
            Text(coaching.focus).font(.headline).accessibilityIdentifier("coaching-focus")
            Text(coaching.rationale).font(.subheadline)
            if let cue = coaching.cue {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your cue").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(cue).font(.headline)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Check the change").font(.subheadline.weight(.semibold))
                Text(coaching.reassess).font(.subheadline)
            }
            ForEach(coaching.questions, id: \.self) { question in
                Label(question, systemImage: "questionmark.bubble").font(.subheadline)
            }
            if !coaching.evidence.isEmpty {
                DisclosureGroup("Evidence from this swing") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(coaching.evidence) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.description).font(.caption)
                                Text("\(item.kind == "measured_2d" ? "2D measurement" : item.kind == "golfer_report" ? "Your report" : "Visual interpretation") · \(Int(item.confidence * 100))% confidence")
                                    .font(.caption2).foregroundStyle(.secondary)
                                if !item.timestamps.isEmpty {
                                    Text(item.timestamps.map(timestamp).joined(separator: " · "))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(.top, 8)
                }
            }
            if !coaching.sources.isEmpty {
                DisclosureGroup("Coaching source and moments") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(coaching.sources.enumerated()), id: \.offset) { _, source in
                            if let url = URL(string: source.url), ["https", "http"].contains(url.scheme ?? "") {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.title).font(.caption.weight(.semibold))
                                        Text("\(source.publisher) · \(timestamp(source.startSeconds))–\(timestamp(source.endSeconds))")
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        Text("Source checked; independent coach validation pending. The source opens at its default position; use the time shown.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            }
            if !coaching.limitations.isEmpty {
                DisclosureGroup("What this analysis cannot establish") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(coaching.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.top, 8)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
