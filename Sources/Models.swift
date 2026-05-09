import Foundation
import SwiftUI

struct GraphQLResponse: Codable, Sendable {
    let data: SearchData
}

struct SearchData: Codable, Sendable {
    let search: SearchResult
}

struct SearchResult: Codable, Sendable {
    let nodes: [PullRequest]
}

struct TeamGraphQLResponse: Decodable, Sendable {
    let data: TeamSearchData
}

struct TeamSearchData: Decodable, Sendable {
    let results: [SearchResult]

    var allPullRequests: [PullRequest] {
        results.flatMap(\.nodes)
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        results = try container.allKeys.map { try container.decode(SearchResult.self, forKey: $0) }
    }
}

struct Author: Codable, Sendable {
    let login: String
}

struct PullRequest: Codable, Identifiable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let reviewDecision: String?
    let author: Author?
    let repository: Repository
    let reviewThreads: ReviewThreadConnection?
    let commits: CommitConnection

    var id: String { "\(repository.nameWithOwner)#\(number)" }

    var workflowRunIds: [Int] {
        commits.nodes.first?.commit.checkSuites?.nodes
            .compactMap { $0.workflowRun?.databaseId } ?? []
    }

    var unresolvedCommentCount: Int {
        reviewThreads?.nodes.filter { !$0.isResolved }.count ?? 0
    }

    var hasUnresolvedComments: Bool {
        unresolvedCommentCount > 0
    }

    var ciStatus: CIStatus {
        guard let state = commits.nodes.first?.commit.statusCheckRollup?.state.uppercased() else {
            return .unknown
        }

        switch state {
        case "SUCCESS":
            return .passing
        case "FAILURE", "ERROR":
            return .failing
        case "PENDING", "EXPECTED":
            return .pending
        default:
            return .unknown
        }
    }

    var reviewStatus: ReviewStatus {
        guard let reviewDecision = reviewDecision?.uppercased() else {
            return .none
        }

        switch reviewDecision {
        case "APPROVED":
            return .approved
        case "CHANGES_REQUESTED":
            return .changesRequested
        case "REVIEW_REQUIRED":
            return .reviewRequired
        default:
            return .none
        }
    }

    var overallStatus: PRStatus {
        if reviewStatus == .changesRequested {
            return .changesRequested
        }
        if ciStatus == .failing {
            return .attention
        }
        if hasUnresolvedComments {
            return .unresolvedComments
        }
        if ciStatus == .pending {
            return .pending
        }
        if ciStatus == .passing {
            return .clear
        }
        return .unknown
    }

    // MARK: - Staleness & Attention

    var ageDays: Int {
        Int(Date().timeIntervalSince(createdAt) / 86400)
    }

    var staleDays: Int {
        Int(Date().timeIntervalSince(updatedAt) / 86400)
    }

    var needsAttention: Bool {
        if isDraft { return false }
        return reviewStatus == .changesRequested
            || ciStatus == .failing
            || staleDays >= 3
            || (reviewStatus == .reviewRequired && ageDays >= 2)
    }

    var attentionScore: Int {
        var score = 0
        if reviewStatus == .changesRequested { score += 40 }
        if ciStatus == .failing { score += 30 }
        if hasUnresolvedComments { score += 10 }
        score += min(staleDays * 3, 30)  // up to 30 for staleness
        score += min(ageDays, 20)        // up to 20 for age
        return score
    }

    var ageLabel: String? {
        let days = ageDays
        if days < 3 { return nil }
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        return "\(weeks)w"
    }

    var ageColor: Color {
        let days = ageDays
        if days < 3 { return .green }
        if days < 7 { return .orange }
        return .red
    }
}

struct Repository: Codable, Hashable, Sendable {
    let nameWithOwner: String
}

struct ReviewThreadConnection: Codable, Sendable {
    let nodes: [ReviewThread]
}

struct ReviewThread: Codable, Sendable {
    let isResolved: Bool
}

struct CommitConnection: Codable, Sendable {
    let nodes: [CommitNode]
}

struct CommitNode: Codable, Sendable {
    let commit: CommitInfo
}

struct CommitInfo: Codable, Sendable {
    let statusCheckRollup: StatusCheckRollup?
    let checkSuites: CheckSuiteConnection?
}

struct StatusCheckRollup: Codable, Sendable {
    let state: String
}

struct CheckSuiteConnection: Codable, Sendable {
    let nodes: [CheckSuiteNode]
}

struct CheckSuiteNode: Codable, Sendable {
    let workflowRun: WorkflowRunRef?
}

struct WorkflowRunRef: Codable, Sendable {
    let databaseId: Int
}

enum CIStatus: Equatable, Sendable {
    case passing
    case failing
    case pending
    case unknown
}

enum ReviewStatus: Equatable, Sendable {
    case approved
    case changesRequested
    case reviewRequired
    case none
}

enum PRStatus: Comparable, Equatable, Sendable {
    case clear
    case unknown
    case pending
    case unresolvedComments
    case attention
    case changesRequested

    private var severity: Int {
        switch self {
        case .clear:
            return 0
        case .unknown:
            return 1
        case .pending:
            return 2
        case .unresolvedComments:
            return 3
        case .attention:
            return 4
        case .changesRequested:
            return 5
        }
    }

    static func < (lhs: PRStatus, rhs: PRStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}

struct PRGroup: Identifiable, Sendable {
    let repo: String
    let prs: [PullRequest]

    var id: String { repo }
}

enum PRFilter: String, CaseIterable, Identifiable, Sendable {
    case mine = "Mine"
    case priority = "Priority"
    case all  = "All"

    var id: String { rawValue }
}

extension PullRequest {
    static func grouped(_ prs: [PullRequest]) -> [PRGroup] {
        Dictionary(grouping: prs, by: { $0.repository.nameWithOwner })
            .map { repo, pullRequests in
                PRGroup(
                    repo: repo,
                    prs: pullRequests.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted { $0.repo.localizedStandardCompare($1.repo) == .orderedAscending }
    }
}
