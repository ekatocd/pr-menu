import AppKit
import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    var showAuthor = false
    let onRerun: () -> Void

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

                        if let ageText = pr.ageLabel {
                            Text(ageText)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(pr.ageColor.opacity(0.15))
                                .foregroundStyle(pr.ageColor)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if showAuthor, let author = pr.author {
                            Text("@\(author.login)")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
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
        .contextMenu {
            Button("Open in Browser") { openPullRequest() }
            if !pr.workflowRunIds.isEmpty {
                Button("Rerun All Checks") { onRerun() }
            }
        }
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
        HStack(spacing: 6) {
            switch pr.reviewStatus {
            case .approved:
                StatusBadge("Approved", icon: "checkmark.circle.fill", color: .green)
            case .changesRequested:
                StatusBadge("Changes requested", icon: "xmark.circle.fill", color: .red)
            case .reviewRequired:
                StatusBadge("Review pending", icon: "clock.fill", color: .orange)
            case .none:
                EmptyView()
            }

            switch pr.ciStatus {
            case .passing:
                StatusBadge("CI passing", color: .green)
            case .failing:
                StatusBadge("CI failing", color: .red)
            case .pending:
                StatusBadge("CI pending", color: .orange)
            case .unknown:
                EmptyView()
            }

            if pr.hasUnresolvedComments {
                StatusBadge("\(pr.unresolvedCommentCount) unresolved", icon: "bubble.left.fill", color: .purple)
            }
        }
    }

    private var statusColor: Color {
        switch pr.overallStatus {
        case .clear:
            return .green
        case .pending:
            return .orange
        case .unresolvedComments:
            return .purple
        case .attention, .changesRequested:
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

private struct StatusBadge: View {
    let text: String
    let icon: String?
    let color: Color

    init(_ text: String, icon: String? = nil, color: Color) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
    }
}
