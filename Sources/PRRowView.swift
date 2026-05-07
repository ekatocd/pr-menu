import AppKit
import SwiftUI

struct PRRowView: View {
    let pr: PullRequest

    var body: some View {
        Button(action: openPullRequest) {
            HStack(alignment: .top, spacing: 12) {
                statusDot
                    .frame(width: 10, height: 10)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        titleView
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("#\(pr.number)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    statusLabels
                }

                Spacer(minLength: 8)

                Text(pr.updatedAt.relativeShort)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(pr.isDraft ? 0.6 : 1)
    }

    @ViewBuilder
    private var titleView: some View {
        if pr.isDraft {
            Text(pr.title).italic()
        } else {
            Text(pr.title)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if pr.isDraft {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
        } else {
            Circle()
                .fill(statusColor)
        }
    }

    @ViewBuilder
    private var statusLabels: some View {
        HStack(spacing: 8) {
            switch pr.reviewStatus {
            case .approved:
                Label("Approved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .changesRequested:
                Label("Changes requested", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .reviewRequired:
                Label("Review pending", systemImage: "clock.fill")
                    .foregroundStyle(.orange)
            case .none:
                EmptyView()
            }

            switch pr.ciStatus {
            case .passing:
                Text("CI passing")
                    .foregroundStyle(.green)
            case .failing:
                Text("CI failing")
                    .foregroundStyle(.red)
            case .pending:
                Text("CI pending")
                    .foregroundStyle(.orange)
            case .unknown:
                EmptyView()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .labelStyle(.titleAndIcon)
    }

    private var statusColor: Color {
        switch pr.overallStatus {
        case .clear:
            return .green
        case .pending:
            return .orange
        case .attention:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private func openPullRequest() {
        NSWorkspace.shared.open(pr.url)
    }
}

extension Date {
    var relativeShort: String {
        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(self)))

        if elapsedSeconds < 60 {
            return "now"
        }

        let minutes = elapsedSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        return "\(hours / 24)d"
    }
}
