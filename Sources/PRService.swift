import Combine
import Foundation

@MainActor
final class PRService: ObservableObject {
    @Published private(set) var myPRs: [PullRequest] = []
    @Published private(set) var teamPRs: [PullRequest] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusChanged = false
    @Published private(set) var isLoading = false
    @Published var activeFilter: PRFilter = .mine
    @Published var selectedTeam: String?

    /// Maps team slug → set of member logins
    private(set) var teamMembership: [String: Set<String>] = [:]

    var pullRequests: [PullRequest] {
        switch activeFilter {
        case .mine: return myPRs
        case .team: return filteredTeamPRs
        case .all:
            let teamOnly = filteredTeamPRs.filter { pr in !myPRs.contains(where: { $0.id == pr.id }) }
            return myPRs + teamOnly
        }
    }

    private var filteredTeamPRs: [PullRequest] {
        guard let selected = selectedTeam,
              let members = teamMembership[selected] else {
            return teamPRs
        }
        return teamPRs.filter { pr in
            guard let login = pr.author?.login else { return false }
            return members.contains(login)
        }
    }

    var groupedPRs: [PRGroup] {
        PullRequest.grouped(pullRequests)
    }

    var aggregateStatus: PRStatus {
        myPRs.map(\.overallStatus).max() ?? .unknown
    }

    var availableFilters: [PRFilter] {
        isTeamMode ? PRFilter.allCases : [.mine]
    }

    private let commandRunner: any CommandRunner
    private var refreshTimer: AnyCancellable?
    private var previousStatusSnapshot: [String: PRStatus] = [:]

    private let orgFilter: String?
    let teamFilters: [String]

    var isTeamMode: Bool { !teamFilters.isEmpty }

    private var graphQLQuery: String {
        let orgClause = orgFilter.map { " org:\($0)" } ?? ""
        return """
        {
          search(query: "is:pr is:open author:@me\(orgClause)", type: ISSUE, first: 100) {
            nodes {
              ... on PullRequest {
                number title url state createdAt updatedAt isDraft reviewDecision
                author { login }
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

    init(orgFilter: String? = nil, teamFilters: [String] = [], commandRunner: any CommandRunner = ProcessCommandRunner()) {
        self.orgFilter = orgFilter
        self.teamFilters = teamFilters
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
        if !teamFilters.isEmpty && orgFilter == nil {
            errorMessage = "--team requires --org"
            return
        }

        let wasFirstLoad = lastRefresh == nil
        if wasFirstLoad { isLoading = true }
        defer { if wasFirstLoad { isLoading = false } }

        do {
            let gh = try findGh()

            // Always fetch the user's own PRs
            let myData = try await commandRunner.run(
                executable: gh,
                arguments: ["api", "graphql", "-f", "query=\(graphQLQuery)"]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let myResponse = try decoder.decode(GraphQLResponse.self, from: myData)
            let newMyPRs = myResponse.data.search.nodes

            // Fetch team PRs when in team mode
            var newTeamPRs: [PullRequest] = []
            if !teamFilters.isEmpty, let orgFilter {
                let membership = try await fetchTeamMembership(gh: gh, org: orgFilter, teams: teamFilters)
                teamMembership = membership
                let allMembers = Array(Set(membership.values.flatMap { $0 }))
                if !allMembers.isEmpty {
                    // Batch into chunks of 5 to avoid GitHub GraphQL complexity limits
                    let chunkSize = 5
                    for chunkStart in stride(from: 0, to: allMembers.count, by: chunkSize) {
                        let chunk = Array(allMembers[chunkStart..<min(chunkStart + chunkSize, allMembers.count)])
                        let query = teamGraphQLQuery(members: chunk)
                        let teamData = try await commandRunner.run(
                            executable: gh,
                            arguments: ["api", "graphql", "-f", "query=\(query)"]
                        )
                        let teamDecoder = JSONDecoder()
                        teamDecoder.dateDecodingStrategy = .iso8601
                        let teamResponse = try teamDecoder.decode(TeamGraphQLResponse.self, from: teamData)
                        newTeamPRs.append(contentsOf: teamResponse.data.allPullRequests)
                    }
                }
            }

            let allNew = newMyPRs + newTeamPRs.filter { pr in !newMyPRs.contains(where: { $0.id == pr.id }) }
            statusChanged = detectStatusChange(allNew)
            myPRs = newMyPRs
            teamPRs = newTeamPRs
            errorMessage = nil
            lastRefresh = Date()
        } catch CommandError.notFound {
            errorMessage = "Install GitHub CLI: brew install gh"
        } catch let CommandError.nonZeroExit(_, stderr) {
            if stderr.contains("auth") || stderr.contains("token") {
                errorMessage = "gh auth failed — run `gh auth login`"
            } else {
                errorMessage = stderr.isEmpty ? "gh command failed" : String(stderr.prefix(200))
            }
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

    private func teamGraphQLQuery(members: [String]) -> String {
        let orgClause = orgFilter.map { " org:\($0)" } ?? ""
        let fields = """
            nodes {
              ... on PullRequest {
                number title url state createdAt updatedAt isDraft reviewDecision
                author { login }
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
        """
        let searches = members.enumerated().map { index, login in
            "user\(index): search(query: \"is:pr is:open author:\(login)\(orgClause)\", type: ISSUE, first: 100) { \(fields) }"
        }.joined(separator: "\n    ")
        return "{\n    \(searches)\n}"
    }

    private func fetchTeamMembership(gh: String, org: String, teams: [String]) async throws -> [String: Set<String>] {
        struct Member: Decodable { let login: String }
        var membership: [String: Set<String>] = [:]
        for team in teams {
            let data = try await commandRunner.run(
                executable: gh,
                arguments: ["api", "/orgs/\(org)/teams/\(team)/members", "--paginate"]
            )
            let members = try JSONDecoder().decode([Member].self, from: data)
            membership[team] = Set(members.map(\.login))
        }
        return membership
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
