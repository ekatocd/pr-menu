import AppKit
import SwiftUI

struct PRListView: View {
    @ObservedObject var service: PRService

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("My Pull Requests")
                    .font(.system(size: 14, weight: .semibold))

                Text(updatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: service.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = service.errorMessage, service.pullRequests.isEmpty {
            errorView(message: errorMessage)
        } else if service.pullRequests.isEmpty {
            emptyView
        } else {
            VStack(spacing: 0) {
                if let errorMessage = service.errorMessage {
                    warningBanner(message: errorMessage)
                }

                groupedList
            }
        }
    }

    private var groupedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(service.groupedPRs.enumerated()), id: \ .element.id) { index, group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.repo.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, 16)

                        ForEach(group.prs) { pr in
                            PRRowView(pr: pr)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                    }

                    if index < service.groupedPRs.count - 1 {
                        Divider()
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("🎉")
                .font(.system(size: 32))
            Text("No open PRs")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func warningBanner(message: String) -> some View {
        Text("⚠ \(message)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
    }

    private var footer: some View {
        HStack {
            Text(openPRCountText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var updatedText: String {
        guard let lastRefresh = service.lastRefresh else {
            return "Updated --"
        }

        let relative = lastRefresh.relativeShort
        return relative == "now" ? "Updated now" : "Updated \(relative) ago"
    }

    private var openPRCountText: String {
        let count = service.pullRequests.count
        let suffix = count == 1 ? "PR" : "PRs"
        return "\(count) open \(suffix)"
    }
}
