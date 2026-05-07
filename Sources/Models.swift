import Foundation

struct GraphQLResponse: Codable, Sendable {
    let data: SearchData
}

struct SearchData: Codable, Sendable {
    let search: SearchResult
}

struct SearchResult: Codable, Sendable {
    let nodes: [PullRequest]
}

struct PullRequest: Codable, Identifiable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let state: String
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let reviewDecision: String?
    let repository: Repository
    let commits: CommitConnection

    var id: String { "\(repository.nameWithOwner)#\(number)" }

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
        if reviewStatus == .changesRequested || ciStatus == .failing {
            return .attention
        }

        if reviewStatus == .reviewRequired || ciStatus == .pending {
            return .pending
        }

        if reviewStatus == .approved && ciStatus == .passing {
            return .clear
        }

        return .unknown
    }
}

struct Repository: Codable, Hashable, Sendable {
    let nameWithOwner: String
}

struct CommitConnection: Codable, Sendable {
    let nodes: [CommitNode]
}

struct CommitNode: Codable, Sendable {
    let commit: CommitInfo
}

struct CommitInfo: Codable, Sendable {
    let statusCheckRollup: StatusCheckRollup?
}

struct StatusCheckRollup: Codable, Sendable {
    let state: String
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
    case attention

    private var severity: Int {
        switch self {
        case .clear:
            return 0
        case .unknown:
            return 1
        case .pending:
            return 2
        case .attention:
            return 3
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
