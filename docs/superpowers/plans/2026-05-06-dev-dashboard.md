# Dev Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that shows your open GitHub PRs at a glance, auto-refreshing every 5 minutes, using `gh` CLI for all GitHub data.

**Architecture:** Pure Swift/SwiftUI macOS app. An `AppDelegate` manages an `NSStatusItem` (menu bar icon) and `NSPopover` (SwiftUI content). A `PRService` (ObservableObject) shells out to `gh api graphql` to fetch all open PRs authored by the current user, decodes the response, and publishes grouped PR data. The service runs on a 5-minute timer and diffs previous state to detect status changes for the icon flash animation.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSStatusItem, NSPopover), Swift Package Manager, macOS 13+ deployment target.

**Spec deviation:** The spec called for `gh search prs` + per-repo `gh pr list` (two commands). We use a single `gh api graphql` call instead — it returns all fields (including `reviewDecision` and `statusCheckRollup`) in one request. Simpler, faster, fewer process spawns.

---

## File Structure

```
DevDashboard/
├── Package.swift                              # SPM manifest, macOS 13+
├── Sources/
│   ├── DevDashboardApp.swift                  # @main, AppDelegate, NSStatusItem, NSPopover
│   ├── Models.swift                           # PullRequest, Repository, enums, GraphQL wrappers
│   ├── CommandRunner.swift                    # Protocol + ProcessCommandRunner (testable seam)
│   ├── PRService.swift                        # ObservableObject — fetch, decode, timer, diff
│   ├── PRListView.swift                       # Popover content — header, grouped list, footer
│   ├── PRRowView.swift                        # Single PR row — dot, title, metadata, time
│   └── MenuBarIcon.swift                      # Icon rendering — tint, badge count, flash
└── Tests/
    ├── ModelsTests.swift                      # JSON decoding, status computation
    ├── PRServiceTests.swift                   # Fetch + decode with mock runner, diff detection
    └── MenuBarIconTests.swift                 # Aggregate status color logic
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/DevDashboardApp.swift` (minimal placeholder)

- [ ] **Step 1: Initialize SPM package**

```bash
cd /Users/yourname/dev-dashboard
swift package init --type executable --name DevDashboard
```

This creates a default `Package.swift` and `Sources/main.swift`.

- [ ] **Step 2: Replace Package.swift with our configuration**

Replace the generated `Package.swift` with:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DevDashboard",
            path: "Sources"
        ),
        .testTarget(
            name: "DevDashboardTests",
            dependencies: ["DevDashboard"],
            path: "Tests"
        ),
    ]
)
```

- [ ] **Step 3: Replace Sources/main.swift with a minimal app entry point**

Delete `Sources/main.swift` and create `Sources/DevDashboardApp.swift`:

```swift
import SwiftUI

@main
struct DevDashboardApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 4: Create Tests directory with a placeholder test**

Create `Tests/PlaceholderTests.swift`:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 5: Verify build and test**

```bash
cd /Users/yourname/dev-dashboard
swift build 2>&1
swift test 2>&1
```

Expected: Both commands succeed with no errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/yourname/dev-dashboard
git init
echo ".build/" > .gitignore
echo ".superpowers/" >> .gitignore
echo ".swiftpm/" >> .gitignore
git add -A
git commit -m "chore: scaffold DevDashboard SPM project

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Data Models + JSON Decoding

**Files:**
- Create: `Sources/Models.swift`
- Create: `Tests/ModelsTests.swift`
- Remove: `Tests/PlaceholderTests.swift`

- [ ] **Step 1: Write failing tests for GraphQL JSON decoding**

Delete `Tests/PlaceholderTests.swift`. Create `Tests/ModelsTests.swift`:

```swift
import XCTest
@testable import DevDashboard

final class ModelsTests: XCTestCase {

    let sampleGraphQLJSON = """
    {
      "data": {
        "search": {
          "nodes": [
            {
              "number": 1247,
              "title": "Fix auth token refresh logic",
              "url": "https://github.com/acme/backend-api/pull/1247",
              "state": "OPEN",
              "createdAt": "2026-05-03T10:00:00Z",
              "updatedAt": "2026-05-05T12:00:00Z",
              "isDraft": false,
              "reviewDecision": "APPROVED",
              "repository": { "nameWithOwner": "acme/backend-api" },
              "commits": {
                "nodes": [
                  {
                    "commit": {
                      "statusCheckRollup": { "state": "SUCCESS" }
                    }
                  }
                ]
              }
            },
            {
              "number": 892,
              "title": "Migrate dashboard to React 19",
              "url": "https://github.com/acme/web-frontend/pull/892",
              "state": "OPEN",
              "createdAt": "2026-05-01T08:00:00Z",
              "updatedAt": "2026-05-02T14:00:00Z",
              "isDraft": false,
              "reviewDecision": "CHANGES_REQUESTED",
              "repository": { "nameWithOwner": "acme/web-frontend" },
              "commits": {
                "nodes": [
                  {
                    "commit": {
                      "statusCheckRollup": { "state": "FAILURE" }
                    }
                  }
                ]
              }
            },
            {
              "number": 901,
              "title": "WIP: Redesign settings page",
              "url": "https://github.com/acme/web-frontend/pull/901",
              "state": "OPEN",
              "createdAt": "2026-04-30T09:00:00Z",
              "updatedAt": "2026-04-30T11:00:00Z",
              "isDraft": true,
              "reviewDecision": null,
              "repository": { "nameWithOwner": "acme/web-frontend" },
              "commits": {
                "nodes": [
                  {
                    "commit": {
                      "statusCheckRollup": null
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    func testDecodesGraphQLResponse() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GraphQLResponse.self, from: sampleGraphQLJSON)

        XCTAssertEqual(response.data.search.nodes.count, 3)

        let first = response.data.search.nodes[0]
        XCTAssertEqual(first.number, 1247)
        XCTAssertEqual(first.title, "Fix auth token refresh logic")
        XCTAssertEqual(first.repository.nameWithOwner, "acme/backend-api")
        XCTAssertFalse(first.isDraft)
        XCTAssertEqual(first.reviewDecision, "APPROVED")
    }

    func testCIStatusComputation() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GraphQLResponse.self, from: sampleGraphQLJSON)
        let prs = response.data.search.nodes

        XCTAssertEqual(prs[0].ciStatus, .passing)   // SUCCESS
        XCTAssertEqual(prs[1].ciStatus, .failing)    // FAILURE
        XCTAssertEqual(prs[2].ciStatus, .unknown)    // null statusCheckRollup
    }

    func testReviewStatusComputation() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GraphQLResponse.self, from: sampleGraphQLJSON)
        let prs = response.data.search.nodes

        XCTAssertEqual(prs[0].reviewStatus, .approved)
        XCTAssertEqual(prs[1].reviewStatus, .changesRequested)
        XCTAssertEqual(prs[2].reviewStatus, .none)
    }

    func testOverallPRStatus() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GraphQLResponse.self, from: sampleGraphQLJSON)
        let prs = response.data.search.nodes

        XCTAssertEqual(prs[0].overallStatus, .clear)     // approved + passing
        XCTAssertEqual(prs[1].overallStatus, .attention)  // changes requested + failing
        XCTAssertEqual(prs[2].overallStatus, .unknown)    // draft, no checks
    }

    func testGroupsByRepository() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GraphQLResponse.self, from: sampleGraphQLJSON)
        let grouped = PullRequest.grouped(response.data.search.nodes)

        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].repo, "acme/backend-api")
        XCTAssertEqual(grouped[0].prs.count, 1)
        XCTAssertEqual(grouped[1].repo, "acme/web-frontend")
        XCTAssertEqual(grouped[1].prs.count, 2)
        // Within group, sorted by updatedAt descending
        XCTAssertEqual(grouped[1].prs[0].number, 892)
        XCTAssertEqual(grouped[1].prs[1].number, 901)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/yourname/dev-dashboard
swift test 2>&1
```

Expected: Compilation errors — `GraphQLResponse`, `PullRequest`, etc. not defined.

- [ ] **Step 3: Implement Models.swift**

Create `Sources/Models.swift`:

```swift
import Foundation

// MARK: - GraphQL Response Wrappers

struct GraphQLResponse: Codable {
    let data: SearchData
}

struct SearchData: Codable {
    let search: SearchResult
}

struct SearchResult: Codable {
    let nodes: [PullRequest]
}

// MARK: - Core Models

struct PullRequest: Codable, Identifiable {
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
        guard let state = commits.nodes.first?.commit.statusCheckRollup?.state else {
            return .unknown
        }
        switch state {
        case "SUCCESS": return .passing
        case "FAILURE", "ERROR": return .failing
        case "PENDING", "EXPECTED": return .pending
        default: return .unknown
        }
    }

    var reviewStatus: ReviewStatus {
        ReviewStatus(from: reviewDecision)
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

struct Repository: Codable, Hashable {
    let nameWithOwner: String
}

struct CommitConnection: Codable {
    let nodes: [CommitNode]
}

struct CommitNode: Codable {
    let commit: CommitInfo
}

struct CommitInfo: Codable {
    let statusCheckRollup: StatusCheckRollup?
}

struct StatusCheckRollup: Codable {
    let state: String
}

// MARK: - Status Enums

enum CIStatus: Equatable {
    case passing, failing, pending, unknown
}

enum ReviewStatus: Equatable {
    case approved, changesRequested, reviewRequired, none

    init(from decision: String?) {
        switch decision {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "REVIEW_REQUIRED": self = .reviewRequired
        default: self = .none
        }
    }
}

enum PRStatus: Comparable, Equatable {
    case clear, unknown, pending, attention
}

// MARK: - Grouping

struct PRGroup: Identifiable {
    let repo: String
    let prs: [PullRequest]
    var id: String { repo }
}

extension PullRequest {
    static func grouped(_ prs: [PullRequest]) -> [PRGroup] {
        let byRepo = Dictionary(grouping: prs) { $0.repository.nameWithOwner }
        return byRepo.keys.sorted().map { repo in
            let sorted = byRepo[repo]!.sorted { $0.updatedAt > $1.updatedAt }
            return PRGroup(repo: repo, prs: sorted)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/yourname/dev-dashboard
swift test --filter ModelsTests 2>&1
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: add data models with JSON decoding and status computation

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: CommandRunner Protocol

**Files:**
- Create: `Sources/CommandRunner.swift`

The `CommandRunner` protocol provides a testable seam — PRService depends on the protocol, and tests inject a mock.

- [ ] **Step 1: Create CommandRunner.swift**

```swift
import Foundation

protocol CommandRunner: Sendable {
    func run(executable: String, arguments: [String]) async throws -> Data
}

struct ProcessCommandRunner: CommandRunner {
    func run(executable: String, arguments: [String]) async throws -> Data {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError.nonZeroExit(process.terminationStatus)
        }
        return data
    }
}

enum CommandError: Error, Equatable {
    case nonZeroExit(Int32)
    case notFound
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/yourname/dev-dashboard
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: add CommandRunner protocol for testable process execution

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: PRService + Tests

**Files:**
- Create: `Sources/PRService.swift`
- Create: `Tests/PRServiceTests.swift`

- [ ] **Step 1: Write failing tests for PRService**

Create `Tests/PRServiceTests.swift`:

```swift
import XCTest
@testable import DevDashboard

final class MockCommandRunner: CommandRunner {
    var resultData: Data = Data()
    var shouldThrow: Error?
    var lastArguments: [String]?

    func run(executable: String, arguments: [String]) async throws -> Data {
        lastArguments = arguments
        if let error = shouldThrow {
            throw error
        }
        return resultData
    }
}

final class PRServiceTests: XCTestCase {

    let sampleJSON = """
    {
      "data": {
        "search": {
          "nodes": [
            {
              "number": 42,
              "title": "Test PR",
              "url": "https://github.com/test/repo/pull/42",
              "state": "OPEN",
              "createdAt": "2026-05-01T10:00:00Z",
              "updatedAt": "2026-05-05T12:00:00Z",
              "isDraft": false,
              "reviewDecision": "APPROVED",
              "repository": { "nameWithOwner": "test/repo" },
              "commits": {
                "nodes": [
                  { "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }
                ]
              }
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let emptyJSON = """
    { "data": { "search": { "nodes": [] } } }
    """.data(using: .utf8)!

    func testFetchesPRsSuccessfully() async {
        let runner = MockCommandRunner()
        runner.resultData = sampleJSON
        let service = PRService(commandRunner: runner)

        await service.refresh()

        XCTAssertEqual(service.pullRequests.count, 1)
        XCTAssertEqual(service.pullRequests[0].number, 42)
        XCTAssertNil(service.errorMessage)
    }

    func testHandlesEmptyResults() async {
        let runner = MockCommandRunner()
        runner.resultData = emptyJSON
        let service = PRService(commandRunner: runner)

        await service.refresh()

        XCTAssertTrue(service.pullRequests.isEmpty)
        XCTAssertNil(service.errorMessage)
    }

    func testHandlesGhNotInstalled() async {
        let runner = MockCommandRunner()
        runner.shouldThrow = CommandError.notFound
        let service = PRService(commandRunner: runner)

        await service.refresh()

        XCTAssertTrue(service.pullRequests.isEmpty)
        XCTAssertNotNil(service.errorMessage)
    }

    func testHandlesNonZeroExit() async {
        let runner = MockCommandRunner()
        runner.shouldThrow = CommandError.nonZeroExit(1)
        let service = PRService(commandRunner: runner)

        await service.refresh()

        XCTAssertTrue(service.pullRequests.isEmpty)
        XCTAssertNotNil(service.errorMessage)
    }

    func testDetectsStatusChange() async {
        let runner = MockCommandRunner()
        runner.resultData = sampleJSON
        let service = PRService(commandRunner: runner)

        // First fetch — no previous state, no change detected
        await service.refresh()
        XCTAssertFalse(service.statusChanged)

        // Second fetch with same data — no change
        await service.refresh()
        XCTAssertFalse(service.statusChanged)

        // Third fetch with different status
        let changedJSON = """
        {
          "data": {
            "search": {
              "nodes": [
                {
                  "number": 42,
                  "title": "Test PR",
                  "url": "https://github.com/test/repo/pull/42",
                  "state": "OPEN",
                  "createdAt": "2026-05-01T10:00:00Z",
                  "updatedAt": "2026-05-05T14:00:00Z",
                  "isDraft": false,
                  "reviewDecision": "CHANGES_REQUESTED",
                  "repository": { "nameWithOwner": "test/repo" },
                  "commits": {
                    "nodes": [
                      { "commit": { "statusCheckRollup": { "state": "FAILURE" } } }
                    ]
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        runner.resultData = changedJSON
        await service.refresh()
        XCTAssertTrue(service.statusChanged)
    }

    func testGroupedPRsProperty() async {
        let twoRepoJSON = """
        {
          "data": {
            "search": {
              "nodes": [
                {
                  "number": 1, "title": "PR1",
                  "url": "https://github.com/a/one/pull/1",
                  "state": "OPEN", "createdAt": "2026-05-01T10:00:00Z",
                  "updatedAt": "2026-05-05T12:00:00Z", "isDraft": false,
                  "reviewDecision": null,
                  "repository": { "nameWithOwner": "a/one" },
                  "commits": { "nodes": [{ "commit": { "statusCheckRollup": null } }] }
                },
                {
                  "number": 2, "title": "PR2",
                  "url": "https://github.com/b/two/pull/2",
                  "state": "OPEN", "createdAt": "2026-05-01T10:00:00Z",
                  "updatedAt": "2026-05-05T12:00:00Z", "isDraft": false,
                  "reviewDecision": null,
                  "repository": { "nameWithOwner": "b/two" },
                  "commits": { "nodes": [{ "commit": { "statusCheckRollup": null } }] }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let runner = MockCommandRunner()
        runner.resultData = twoRepoJSON
        let service = PRService(commandRunner: runner)

        await service.refresh()

        XCTAssertEqual(service.groupedPRs.count, 2)
        XCTAssertEqual(service.groupedPRs[0].repo, "a/one")
        XCTAssertEqual(service.groupedPRs[1].repo, "b/two")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/yourname/dev-dashboard
swift test --filter PRServiceTests 2>&1
```

Expected: Compilation errors — `PRService` not defined.

- [ ] **Step 3: Implement PRService.swift**

Create `Sources/PRService.swift`:

```swift
import Foundation
import Combine

@MainActor
final class PRService: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusChanged: Bool = false

    var groupedPRs: [PRGroup] {
        PullRequest.grouped(pullRequests)
    }

    var aggregateStatus: PRStatus {
        guard !pullRequests.isEmpty else { return .unknown }
        return pullRequests.map(\.overallStatus).max() ?? .unknown
    }

    private let commandRunner: CommandRunner
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

    init(commandRunner: CommandRunner = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func startAutoRefresh() {
        refresh()
        refreshTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    func refresh() {
        Task { await fetchPRs() }
    }

    private func fetchPRs() async {
        do {
            let ghPath = try findGh()
            let data = try await commandRunner.run(
                executable: ghPath,
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
        } catch is DecodingError {
            errorMessage = "Failed to parse PR data"
        } catch CommandError.notFound {
            errorMessage = "Install GitHub CLI: brew install gh"
        } catch CommandError.nonZeroExit {
            if pullRequests.isEmpty {
                errorMessage = "Run `gh auth login` to get started"
            }
            // If we have stale data, keep showing it
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
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw CommandError.notFound
    }

    private func detectStatusChange(_ newPRs: [PullRequest]) -> Bool {
        let newSnapshot = Dictionary(
            uniqueKeysWithValues: newPRs.map { ($0.id, $0.overallStatus) }
        )
        defer { previousStatusSnapshot = newSnapshot }

        guard !previousStatusSnapshot.isEmpty else { return false }

        for (id, newStatus) in newSnapshot {
            if let oldStatus = previousStatusSnapshot[id], oldStatus != newStatus {
                return true
            }
        }
        // Also flag if a PR appeared or disappeared
        return Set(newSnapshot.keys) != Set(previousStatusSnapshot.keys)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/yourname/dev-dashboard
swift test --filter PRServiceTests 2>&1
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: add PRService with gh GraphQL integration and diff detection

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Menu Bar Icon Logic + Tests

**Files:**
- Create: `Sources/MenuBarIcon.swift`
- Create: `Tests/MenuBarIconTests.swift`

- [ ] **Step 1: Write failing tests for aggregate status and icon color**

Create `Tests/MenuBarIconTests.swift`:

```swift
import XCTest
@testable import DevDashboard

final class MenuBarIconTests: XCTestCase {

    func testAggregateStatusAllClear() {
        let statuses: [PRStatus] = [.clear, .clear, .clear]
        XCTAssertEqual(MenuBarIcon.aggregateColor(for: statuses), .clear)
    }

    func testAggregateStatusOneAttention() {
        let statuses: [PRStatus] = [.clear, .attention, .clear]
        XCTAssertEqual(MenuBarIcon.aggregateColor(for: statuses), .attention)
    }

    func testAggregateStatusOnePending() {
        let statuses: [PRStatus] = [.clear, .pending]
        XCTAssertEqual(MenuBarIcon.aggregateColor(for: statuses), .pending)
    }

    func testAggregateStatusMixed() {
        let statuses: [PRStatus] = [.clear, .pending, .attention]
        XCTAssertEqual(MenuBarIcon.aggregateColor(for: statuses), .attention)
    }

    func testAggregateStatusEmpty() {
        let statuses: [PRStatus] = []
        XCTAssertEqual(MenuBarIcon.aggregateColor(for: statuses), .unknown)
    }

    func testBadgeTextForCount() {
        XCTAssertNil(MenuBarIcon.badgeText(for: 0))
        XCTAssertEqual(MenuBarIcon.badgeText(for: 3), "3")
        XCTAssertEqual(MenuBarIcon.badgeText(for: 99), "99")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/yourname/dev-dashboard
swift test --filter MenuBarIconTests 2>&1
```

Expected: Compilation errors — `MenuBarIcon` not defined.

- [ ] **Step 3: Implement MenuBarIcon.swift**

Create `Sources/MenuBarIcon.swift`:

```swift
import AppKit
import SwiftUI

enum MenuBarIcon {

    static func aggregateColor(for statuses: [PRStatus]) -> PRStatus {
        guard !statuses.isEmpty else { return .unknown }
        return statuses.max() ?? .unknown
    }

    static func badgeText(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }

    static func nsColor(for status: PRStatus) -> NSColor {
        switch status {
        case .clear: return .systemGreen
        case .pending: return .systemOrange
        case .attention: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }

    static func createIcon(status: PRStatus, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let color = nsColor(for: status)
            color.setFill()

            // Draw a simple branch/PR icon shape
            let path = NSBezierPath()
            let midX = rect.midX
            let midY = rect.midY

            // Main vertical line (source branch)
            path.move(to: NSPoint(x: midX - 3, y: rect.minY + 2))
            path.line(to: NSPoint(x: midX - 3, y: rect.maxY - 2))

            // Branch line curving to merge point
            path.move(to: NSPoint(x: midX + 3, y: rect.minY + 5))
            path.curve(
                to: NSPoint(x: midX - 3, y: rect.maxY - 5),
                controlPoint1: NSPoint(x: midX + 3, y: midY),
                controlPoint2: NSPoint(x: midX - 3, y: midY)
            )

            path.lineWidth = 1.5
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()

            // Dots at endpoints
            let dotSize: CGFloat = 3
            let dots = [
                NSPoint(x: midX - 3, y: rect.minY + 2),
                NSPoint(x: midX - 3, y: rect.maxY - 2),
                NSPoint(x: midX + 3, y: rect.minY + 5),
            ]
            for dot in dots {
                let dotRect = NSRect(
                    x: dot.x - dotSize / 2,
                    y: dot.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/yourname/dev-dashboard
swift test --filter MenuBarIconTests 2>&1
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: add menu bar icon with status-based tinting

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: PR Row View

**Files:**
- Create: `Sources/PRRowView.swift`

- [ ] **Step 1: Implement PRRowView.swift**

```swift
import SwiftUI

struct PRRowView: View {
    let pr: PullRequest

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .italic(pr.isDraft)
                HStack(spacing: 8) {
                    Text("#\(pr.number)")
                        .foregroundStyle(.secondary)
                    reviewLabel
                    ciLabel
                }
                .font(.system(size: 11))
            }
            Spacer()
            Text(pr.updatedAt.relativeShort)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .opacity(pr.isDraft ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(pr.url) }
    }

    @ViewBuilder
    private var statusDot: some View {
        if pr.isDraft {
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))
                .frame(width: 14, height: 14)
                .padding(.top, 2)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
                .padding(.horizontal, 3)
        }
    }

    private var statusColor: Color {
        switch pr.overallStatus {
        case .clear: return .green
        case .pending: return .orange
        case .attention: return .red
        case .unknown: return .secondary
        }
    }

    @ViewBuilder
    private var reviewLabel: some View {
        switch pr.reviewStatus {
        case .approved:
            Label("Approved", systemImage: "checkmark")
                .foregroundStyle(.green)
        case .changesRequested:
            Label("Changes requested", systemImage: "xmark")
                .foregroundStyle(.red)
        case .reviewRequired:
            Label("Review pending", systemImage: "clock")
                .foregroundStyle(.orange)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var ciLabel: some View {
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
}

// MARK: - Relative Date Formatting

extension Date {
    var relativeShort: String {
        let interval = Date().timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if hours < 24 { return "\(hours)h" }
        return "\(days)d"
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/yourname/dev-dashboard
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: add PRRowView with status indicators

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: PR List View

**Files:**
- Create: `Sources/PRListView.swift`

- [ ] **Step 1: Implement PRListView.swift**

```swift
import SwiftUI

struct PRListView: View {
    @ObservedObject var service: PRService

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("My Pull Requests")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if let lastRefresh = service.lastRefresh {
                Text("Updated \(lastRefresh.relativeShort) ago")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button(action: { service.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = service.errorMessage {
            errorView(error)
        } else if service.pullRequests.isEmpty {
            emptyView
        } else {
            prList
        }
    }

    private var prList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(service.groupedPRs) { group in
                    repoHeader(group.repo)
                    ForEach(group.prs) { pr in
                        PRRowView(pr: pr)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func repoHeader(_ repo: String) -> some View {
        Text(repo)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Empty / Error States

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("🎉")
                .font(.system(size: 32))
            Text("No open PRs")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(service.pullRequests.count) open PR\(service.pullRequests.count == 1 ? "" : "s")")
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
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/yourname/dev-dashboard
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: add PRListView with grouped layout and error states

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: App Entry Point + NSStatusItem + Popover

**Files:**
- Modify: `Sources/DevDashboardApp.swift`

- [ ] **Step 1: Implement the full app entry point with AppDelegate**

Replace `Sources/DevDashboardApp.swift`:

```swift
import SwiftUI
import Combine

@main
struct DevDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let prService = PRService()
    private var cancellables = Set<AnyCancellable>()
    private var flashTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PRListView(service: prService)
        )

        if let button = statusItem.button {
            button.image = MenuBarIcon.createIcon(status: .unknown)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Observe PR changes to update icon
        prService.$pullRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prs in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        // Observe status changes for flash
        prService.$statusChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changed in
                if changed { self?.flashIcon() }
            }
            .store(in: &cancellables)

        prService.startAutoRefresh()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            prService.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateIcon() {
        let status = prService.aggregateStatus
        statusItem.button?.image = MenuBarIcon.createIcon(status: status)
        statusItem.button?.title = MenuBarIcon.badgeText(for: prService.pullRequests.count) ?? ""
    }

    private func flashIcon() {
        var flashCount = 0
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            flashCount += 1
            if flashCount >= 8 { // 4 flashes (on/off cycles)
                timer.invalidate()
                self.updateIcon()
                return
            }
            self.statusItem.button?.image = flashCount.isMultiple(of: 2)
                ? MenuBarIcon.createIcon(status: self.prService.aggregateStatus)
                : nil
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/yourname/dev-dashboard
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Run all tests**

```bash
cd /Users/yourname/dev-dashboard
swift test 2>&1
```

Expected: All tests pass (Models, PRService, MenuBarIcon).

- [ ] **Step 4: Commit**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "feat: wire up app with NSStatusItem, popover, and flash animation

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Manual Integration Test

- [ ] **Step 1: Build and launch the app**

```bash
cd /Users/yourname/dev-dashboard
swift build 2>&1
.build/debug/DevDashboard &
```

- [ ] **Step 2: Verify the following manually**

1. Menu bar icon appears (should show gray icon initially)
2. Click icon → popover opens with PR list (or error message if `gh` not authed)
3. Click a PR row → opens in browser
4. Click refresh button → "Updated" text resets
5. Click outside popover → popover closes
6. Click Quit → app terminates

- [ ] **Step 3: Verify icon updates**

Wait for auto-refresh or click refresh. The icon should:
- Show count next to icon
- Tint green/orange/red based on PR statuses

- [ ] **Step 4: Commit any fixes from testing**

```bash
cd /Users/yourname/dev-dashboard
git add -A
git commit -m "fix: integration test fixes

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
