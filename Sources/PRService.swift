import Combine
import Foundation

@MainActor
final class PRService: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusChanged = false

    var groupedPRs: [PRGroup] {
        PullRequest.grouped(pullRequests)
    }

    var aggregateStatus: PRStatus {
        pullRequests.map(\.overallStatus).max() ?? .unknown
    }

    private let commandRunner: any CommandRunner
    private var refreshTimer: AnyCancellable?
    private var previousStatusSnapshot: [String: PRStatus] = [:]

    private let orgFilter: String?

    private var graphQLQuery: String {
        let orgClause = orgFilter.map { " org:\($0)" } ?? ""
        return """
        {
          search(query: "is:pr is:open author:@me\(orgClause)", type: ISSUE, first: 100) {
            nodes {
              ... on PullRequest {
                number title url state createdAt updatedAt isDraft reviewDecision
                repository { nameWithOwner }
                reviewThreads(first: 100) { nodes { isResolved } }
                commits(last: 1) {
                  nodes { commit {
                    statusCheckRollup { state }
                    checkSuites(first: 20) {
                      nodes { workflowRun { databaseId } }
                    }
                  } }
                }
              }
            }
          }
        }
        """
    }

    init(orgFilter: String? = nil, commandRunner: any CommandRunner = ProcessCommandRunner()) {
        self.orgFilter = orgFilter
        self.commandRunner = commandRunner
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else { return }

        refresh()
        refreshTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    func refresh() {
        Task { [weak self] in
            await self?.fetchPRs()
        }
    }

    private func fetchPRs() async {
        do {
            let gh = try findGh()
            let data = try await commandRunner.run(
                executable: gh,
                arguments: ["api", "graphql", "-f", "query=\(graphQLQuery)"]
            )

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let response = try decoder.decode(GraphQLResponse.self, from: data)
            let newPRs = response.data.search.nodes

            statusChanged = detectStatusChange(newPRs)
            pullRequests = newPRs
            errorMessage = nil
            lastRefresh = Date()
        } catch CommandError.notFound {
            errorMessage = "Install GitHub CLI: brew install gh"
        } catch CommandError.nonZeroExit {
            errorMessage = "Run `gh auth login` to get started"
        } catch is DecodingError {
            errorMessage = "Failed to parse PR data"
        } catch {
            if pullRequests.isEmpty {
                errorMessage = "Failed to fetch PRs"
            }
        }
    }

    func rerunChecks(for pr: PullRequest) async {
        guard !pr.workflowRunIds.isEmpty else { return }
        do {
            let gh = try findGh()
            for runId in pr.workflowRunIds {
                _ = try? await commandRunner.run(
                    executable: gh,
                    arguments: ["run", "rerun", "\(runId)", "-R", pr.repository.nameWithOwner]
                )
            }
            // Refresh after a short delay to pick up new status
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await fetchPRs()
        } catch {
            // gh not found — already shown elsewhere
        }
    }

    private func findGh() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        throw CommandError.notFound
    }

    private func detectStatusChange(_ newPRs: [PullRequest]) -> Bool {
        let newSnapshot = Dictionary(uniqueKeysWithValues: newPRs.map { ($0.id, $0.overallStatus) })
        defer { previousStatusSnapshot = newSnapshot }

        guard !previousStatusSnapshot.isEmpty else {
            return false
        }

        return previousStatusSnapshot != newSnapshot
    }
}
