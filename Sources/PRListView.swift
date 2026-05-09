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
        .frame(width: 400)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if service.availableFilters.count > 1 {
                    Picker("", selection: $service.activeFilter) {
                        ForEach(service.availableFilters) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                } else {
                    Text("My Pull Requests")
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 6) {
                    if service.activeFilter != .mine && !service.teamFilters.isEmpty {
                        teamPicker
                    }

                    Text(updatedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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

    private var teamPicker: some View {
        Picker("", selection: $service.selectedTeam) {
            Text("All teams").tag(nil as String?)
            ForEach(service.teamFilters, id: \.self) { team in
                Text(team).tag(team as String?)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(.system(size: 11))
        .frame(maxWidth: 120)
    }

    @ViewBuilder
    private var content: some View {
        if service.isLoading {
            loadingView
        } else if let errorMessage = service.errorMessage, service.pullRequests.isEmpty {
            errorView(message: errorMessage)
        } else if service.pullRequests.isEmpty {
            emptyView
        } else {
            VStack(spacing: 0) {
                if let errorMessage = service.errorMessage {
                    warningBanner(message: errorMessage)
                }

                if service.activeFilter == .priority {
                    flatList
                } else {
                    groupedList
                }
            }
        }
    }

    private var flatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(service.pullRequests) { pr in
                    PRRowView(pr: pr, showAuthor: true) {
                        Task { await service.rerunChecks(for: pr) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 12)
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
                            PRRowView(pr: pr, showAuthor: service.activeFilter != .mine) {
                                Task { await service.rerunChecks(for: pr) }
                            }
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

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Fetching pull requests…")
                .font(.system(size: 13))
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
        let mine = service.myPRs.count
        let team = service.teamPRs.count
        if team > 0 {
            return "\(mine) mine · \(team) team"
        }
        let suffix = mine == 1 ? "PR" : "PRs"
        return "\(mine) open \(suffix)"
    }
}
