# Dev Dashboard — Design Spec

**Date:** 2026-05-05
**Status:** Draft

## Problem

I want a glanceable, always-available view of my open GitHub PRs across all repos. Today I have to open GitHub, navigate to my PRs, and visually parse the page. A lightweight Mac-native menu bar app that auto-refreshes and shows status at a glance solves this.

## Approach

Pure Swift/SwiftUI macOS menu bar app. Shells out to the `gh` CLI for all GitHub data — no direct API calls, no token management, no networking code. The app is view-only in v1; context menu actions (rerun checks, merge, etc.) are a natural v2 follow-up.

## Architecture

```
┌─────────────────────────────┐
│  SwiftUI Views              │  NSStatusItem + popover panel
│  PRListView, PRRowView      │  PR list grouped by repo
├─────────────────────────────┤
│  PRService                  │  ObservableObject
│  (Process → gh CLI)         │  Spawns gh, decodes JSON,
│  Timer for auto-refresh     │  publishes [PullRequest]
│  Diff detection for flash   │  Detects status changes
├─────────────────────────────┤
│  StatusIcon                 │  Menu bar icon rendering
│  Tint color + badge count   │  Flash animation on changes
├─────────────────────────────┤
│  gh CLI (external)          │  gh search prs --author=@me
│                             │  JSON output, handles auth
└─────────────────────────────┘
```

- **No networking code** — `gh` handles auth and GitHub API calls
- **No persistence** — everything is ephemeral, re-fetched on each tick
- **No config files** (v1) — sensible defaults only
- **Single-target macOS app** — no iOS, no Catalyst

## Data Model

### CLI Command

```bash
gh search prs --author=@me --state=open \
  --json number,title,url,state,createdAt,updatedAt,repository,isDraft,reviewDecision
```

Returns a flat JSON array of PR objects.

> **Note:** `gh search prs` does not support `statusCheckRollup` in its `--json` fields. To get CI status, we make a secondary call per-repo batch: `gh pr list --repo owner/repo --author=@me --state=open --json number,statusCheckRollup`. The service merges these results by PR number. This secondary fetch only runs for repos that appeared in the search results, keeping the call count minimal.

### Swift Structs

```swift
struct PullRequest: Codable, Identifiable {
    let number: Int
    let title: String
    let url: URL
    let state: String
    let createdAt: Date
    let updatedAt: Date
    let repository: Repository
    let isDraft: Bool
    let reviewDecision: String?       // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or nil
    let statusCheckRollup: [CheckRun]

    var id: String { "\(repository.nameWithOwner)#\(number)" }
}

struct Repository: Codable {
    let nameWithOwner: String  // "owner/repo"
}

struct CheckRun: Codable {
    let state: String  // SUCCESS, FAILURE, PENDING
}
```

### Grouping & Sorting

- Group by `repository.nameWithOwner` using `Dictionary(grouping:)`
- Repos sorted alphabetically
- PRs within each group sorted by `updatedAt` descending (most recent first)

## Refresh Strategy

- **Auto-refresh:** `Timer.publish(every: 300)` (5 minutes) triggers a re-fetch
- **On-open refresh:** Refresh when the popover opens
- **Manual refresh:** Button in the popover header
- **Diff detection:** On each fetch, compare previous PR states to current. If any PR's `reviewDecision` or check status changed, trigger a menu bar icon flash animation (2–3 second pulse). Previous state held in memory only.

## Menu Bar Icon

- **Icon:** Custom template image (a simple pull request branch icon rendered as an `NSImage` template so macOS handles light/dark automatically). SF Symbols doesn't include a PR-specific glyph, so we'll create a small template asset.
- **Badge:** Small count of open PRs
- **Tint color:** Reflects the "worst" status across all PRs:
  - **Red** — any PR has failing CI or changes requested
  - **Orange** — any PR has pending review (no failures)
  - **Green** — all PRs approved and CI passing
  - **Gray** — no open PRs (neutral, no badge)
- **Flash:** Brief 2–3 second pulse animation when any PR changes status between refreshes

### Status Priority (highest to lowest)

1. `CHANGES_REQUESTED` or any CI `FAILURE` → red
2. `REVIEW_REQUIRED` or any CI `PENDING` → orange
3. `APPROVED` and all CI `SUCCESS` → green

## UI Layout

### Popover Panel (~320px wide)

```
┌──────────────────────────────────┐
│ My Pull Requests    Updated 12s ⟳│  ← Header
├──────────────────────────────────┤
│ ACME/BACKEND-API                 │  ← Repo group header
│ ● Fix auth token refresh   #1247│  ← PR row
│   ✓ Approved · CI passing    2h │
│ ● Add rate limiting         #1239│
│   ⟳ Review pending · CI pass  1d│
├──────────────────────────────────┤
│ ACME/WEB-FRONTEND                │
│ ● Migrate to React 19      #892 │
│   ✗ Changes req · CI failing  3d│
│ ◌ WIP: Redesign settings   #901 │  ← Draft (dimmed)
│   Draft · CI pending          5d│
├──────────────────────────────────┤
│ 4 open PRs                  Quit │  ← Footer
└──────────────────────────────────┘
```

### PR Row Elements

- **Status dot** — colored circle indicating overall PR health
  - Green: approved + CI passing
  - Orange: review pending
  - Red: changes requested or CI failing
  - Gray hollow: draft
- **Title** — truncated with ellipsis if too long
- **PR number** — e.g. `#1247`
- **Review status** — text label (Approved, Review pending, Changes requested)
- **CI status** — text label with color (CI passing, CI failing, CI pending)
- **Relative time** — right-aligned, time since last update ("2h", "1d", "3d")
- **Draft treatment** — reduced opacity, italic title, hollow dot

### Interactions

- **Click PR row** → opens PR URL in default browser
- **Click refresh button** → triggers immediate re-fetch
- **Click Quit** → terminates the app

### Visual Style

- Native macOS appearance — follows system light/dark mode
- System fonts (SF Pro)
- Standard macOS popover with vibrancy where appropriate
- System colors for tinting

## File Structure

```
DevDashboard/
├── DevDashboardApp.swift      # @main, NSStatusItem setup, popover binding
├── PRService.swift            # ObservableObject — spawns gh, decodes, timer, diff
├── Models.swift               # PullRequest, Repository, CheckRun structs
├── PRListView.swift           # Main popover view — header, grouped list, footer
├── PRRowView.swift            # Single PR row — dot, title, metadata
└── StatusIcon.swift           # Menu bar icon — tint, badge, flash animation
```

## Error Handling

| Condition | Behavior |
|-----------|----------|
| No open PRs | "No open PRs 🎉" message in popover |
| `gh` not installed | "Install GitHub CLI: `brew install gh`" |
| `gh` not authenticated | "Run `gh auth login` to get started" |
| Network error / timeout | Show stale data with "Last updated X ago" warning, retry next tick |
| Rate limiting | Back off timer temporarily, show note in header |
| 0 PRs | Icon shows neutral gray, no badge |

## Out of Scope (v1)

- Context menu actions (merge, rerun checks, mark ready, copy URL)
- Configuration UI (refresh interval, repo filters)
- Notifications (macOS native notifications on status change)
- Multiple GitHub accounts
- GitHub Enterprise support
- Launch at login toggle (can be done via macOS System Settings manually)

## Future (v2+)

- Right-click context menu on PR rows for quick actions
- Configurable refresh interval
- Launch at login preference
- macOS notifications for status changes
- Keyboard navigation within popover
