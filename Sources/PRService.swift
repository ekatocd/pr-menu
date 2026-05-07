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

    private static let graphQLQuery = """
    {
      search(query: "is:pr is:open author:@me", type: ISSUE, first: 100) {
        nodes {
          ... on PullRequest {
            number title url state createdAt updatedAt isDraft reviewDecision
            repository { nameWithOwner }
            commits(last: 1) {
              nodes { commit { statusCheckRollup { state } } }
            }
          }
        }
      }
    }
    """

    init(commandRunner: any CommandRunner = ProcessCommandRunner()) {
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
                arguments: ["api", "graphql", "-f", "query=\(Self.graphQLQuery)"]
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
