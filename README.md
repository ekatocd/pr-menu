# PR Menu

A lightweight macOS menu bar app that shows your open GitHub pull requests at a glance.

## Features

- **Menu bar icon** with color-coded status (green/orange/red/purple)
- **Auto-refresh** every 5 minutes
- **Grouped by repo** for easy scanning
- **Status badges** — CI status, review state, unresolved comment count
- **Age badges** — colored pills showing PR staleness (e.g. "3d", "1w")
- **Priority tab** — surfaces PRs needing attention, scored by staleness, failing CI, changes requested, and unresolved comments
- **Team PRs** — view PRs authored by team members and PRs where the team is a requested reviewer, with sectioned grouping
- **Click to open** any PR in your browser
- **Right-click → Rerun All Checks** via `gh run rerun`
- **Flash animation** when PR status changes
- **Org filtering** to scope to a specific GitHub org

### Icon colors

| State | Color |
|---|---|
| Changes requested | 🔴 Red |
| CI failing | 🔴 Red |
| Unresolved comments | 🟣 Purple |
| CI pending | 🟠 Orange |
| All clear | 🟢 Green |

## Prerequisites

- macOS 13+
- Swift 6.0+ (via Xcode or Command Line Tools)
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated

```sh
brew install gh
gh auth login
```

## Build

```sh
swift build -c release
sudo cp .build/release/PRMenu /usr/local/bin/pr-menu
```

## Run

```sh
# Show your PRs from all orgs
pr-menu

# Filter to a specific org
pr-menu --org your-org

# Include team PRs (requires --org)
pr-menu --org your-org --team mobile-team --team backend-team

# Run in foreground (useful for debugging)
pr-menu --foreground
```

The app runs as a menu bar icon — click it to open the PR list popover. Running `pr-menu` again will replace the previous instance.

## Configuration

Create `~/.config/pr-menu/config.json` to set defaults:

```json
{
  "org": "your-org",
  "teams": ["mobile-team", "backend-team"]
}
```

CLI flags (`--org`, `--team`) override config file values.
