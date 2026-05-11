#!/bin/bash
set -euo pipefail

APP_NAME="PRMenu"
INSTALL_DIR="${HOME}/.local/bin"
INSTALL_PATH="${INSTALL_DIR}/pr-menu"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="${LAUNCH_AGENT_DIR}/com.corporealshift.pr-menu.plist"

# ── Helpers ──────────────────────────────────────────────────────

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mWarning:\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31mError:\033[0m %s\n' "$*"; exit 1; }

# ── Preflight checks ────────────────────────────────────────────

info "Checking prerequisites…"

# macOS check
if [[ "$(uname)" != "Darwin" ]]; then
    fail "This app only runs on macOS."
fi

# Swift toolchain
if ! command -v swift &>/dev/null; then
    fail "Swift is not installed. Install Xcode or Command Line Tools: xcode-select --install"
fi

# GitHub CLI
if ! command -v gh &>/dev/null; then
    fail "GitHub CLI (gh) is not installed. Install it with: brew install gh"
fi

# gh auth status (non-zero exit means not authenticated)
if ! gh auth status &>/dev/null; then
    fail "GitHub CLI is not authenticated. Run: gh auth login"
fi

# Detect auth method
AUTH_VIA_TOKEN=false
if [[ -n "${GITHUB_TOKEN:-}" || -n "${GH_TOKEN:-}" ]]; then
    AUTH_VIA_TOKEN=true
fi

info "All prerequisites satisfied."

# ── Build ────────────────────────────────────────────────────────

info "Building release binary…"
swift build -c release

# ── Install binary ───────────────────────────────────────────────

info "Installing binary to ${INSTALL_PATH}…"
mkdir -p "${INSTALL_DIR}"
cp ".build/release/${APP_NAME}" "${INSTALL_PATH}"
chmod +x "${INSTALL_PATH}"

# Ensure ~/.local/bin is in PATH
if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    warn "${INSTALL_DIR} is not in your PATH."
    warn "Add this to your shell profile: export PATH=\"\${HOME}/.local/bin:\${PATH}\""
fi

info "Installed pr-menu to ${INSTALL_PATH}"

# ── Configure org & team filters ─────────────────────────────────

info "Fetching your GitHub organizations…"
ORGS_JSON=$(gh api "/user/orgs" --paginate --jq '.[].login' 2>/dev/null || true)

org=""
if [[ -n "${ORGS_JSON}" ]]; then
    ORG_LIST=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] && ORG_LIST+=("${line}")
    done <<< "${ORGS_JSON}"

    echo ""
    echo "Your organizations:"
    echo "  0) (none — show PRs from all orgs)"
    for i in "${!ORG_LIST[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${ORG_LIST[$i]}"
    done

    echo ""
    read -rp "Select an org (number, or 0 for none): " org_input

    if [[ -n "${org_input}" && "${org_input}" != "0" ]]; then
        idx=$((org_input - 1))
        if [[ ${idx} -ge 0 && ${idx} -lt ${#ORG_LIST[@]} ]]; then
            org="${ORG_LIST[$idx]}"
            info "Selected org: ${org}"
        else
            warn "Invalid selection — skipping org filter."
        fi
    else
        info "No org selected — will show PRs from all orgs."
    fi
else
    warn "Could not fetch organizations. You can enter one manually."
    read -rp "Filter to a specific GitHub org? (leave blank for all): " org
fi

SELECTED_TEAMS=()
if [[ -n "${org}" ]]; then
    # ── Team selection ───────────────────────────────────────
    info "Fetching teams for ${org}…"
    TEAMS_JSON=$(gh api "/orgs/${org}/teams" --paginate --jq '.[].slug' 2>/dev/null || true)

    if [[ -n "${TEAMS_JSON}" ]]; then
        # Build indexed list (POSIX-compatible, works with macOS bash 3)
        TEAM_LIST=()
        while IFS= read -r line; do
            [[ -n "${line}" ]] && TEAM_LIST+=("${line}")
        done <<< "${TEAMS_JSON}"

        echo ""
        echo "Available teams in ${org}:"
        echo "  0) (none — show only my PRs)"
        for i in "${!TEAM_LIST[@]}"; do
            printf '  %d) %s\n' "$((i + 1))" "${TEAM_LIST[$i]}"
        done

        echo ""
        read -rp "Select teams (comma-separated numbers, or 0 for none): " team_input

        if [[ -n "${team_input}" && "${team_input}" != "0" ]]; then
            IFS=',' read -ra SELECTIONS <<< "${team_input}"
            for sel in "${SELECTIONS[@]}"; do
                sel=$(echo "${sel}" | tr -d '[:space:]')
                idx=$((sel - 1))
                if [[ ${idx} -ge 0 && ${idx} -lt ${#TEAM_LIST[@]} ]]; then
                    SELECTED_TEAMS+=("${TEAM_LIST[$idx]}")
                else
                    warn "Ignoring invalid selection: ${sel}"
                fi
            done

            if [[ ${#SELECTED_TEAMS[@]} -gt 0 ]]; then
                info "Selected teams: ${SELECTED_TEAMS[*]}"
            fi
        else
            info "No teams selected — will show only your PRs."
        fi
    else
        warn "Could not fetch teams for ${org} (you may not have permission). Skipping team selection."
    fi
fi

# Build CLI args string for display
RUN_CMD="pr-menu"
if [[ -n "${org}" ]]; then
    RUN_CMD="${RUN_CMD} --org ${org}"
fi
for team in "${SELECTED_TEAMS[@]}"; do
    RUN_CMD="${RUN_CMD} --team ${team}"
done

# ── Write config file ────────────────────────────────────────────

CONFIG_DIR="${HOME}/.config/pr-menu"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "${CONFIG_DIR}"

# Build JSON
TEAMS_JSON="[]"
if [[ ${#SELECTED_TEAMS[@]} -gt 0 ]]; then
    TEAMS_JSON="["
    for i in "${!SELECTED_TEAMS[@]}"; do
        [[ $i -gt 0 ]] && TEAMS_JSON="${TEAMS_JSON},"
        TEAMS_JSON="${TEAMS_JSON}\"${SELECTED_TEAMS[$i]}\""
    done
    TEAMS_JSON="${TEAMS_JSON}]"
fi

if [[ -n "${org}" ]]; then
    cat > "${CONFIG_FILE}" <<EOF
{"org":"${org}","teams":${TEAMS_JSON}}
EOF
else
    cat > "${CONFIG_FILE}" <<EOF
{"teams":${TEAMS_JSON}}
EOF
fi

info "Config saved to ${CONFIG_FILE}"

# ── Optional: Launch Agent ───────────────────────────────────────

read -rp "Would you like pr-menu to start automatically at login? [y/N] " auto_start
if [[ "${auto_start}" =~ ^[Yy]$ ]]; then
    # Token-based auth doesn't survive into LaunchAgents — credentials
    # must be in the macOS Keychain (which gh auth login uses).
    if $AUTH_VIA_TOKEN; then
        warn "You are authenticated via GITHUB_TOKEN/GH_TOKEN."
        warn "LaunchAgents cannot access shell env vars. Run 'gh auth login' so"
        warn "credentials are stored in the macOS Keychain (accessible to LaunchAgents)."
        read -rp "Run 'gh auth login' now? [Y/n] " do_login
        if [[ ! "${do_login}" =~ ^[Nn]$ ]]; then
            gh auth login
            if gh auth status &>/dev/null; then
                info "Keychain auth configured."
            else
                warn "gh auth login may not have completed — the LaunchAgent may fail to authenticate."
            fi
        else
            warn "Skipping — the LaunchAgent may fail to authenticate at login."
        fi
    fi

    mkdir -p "${LAUNCH_AGENT_DIR}"
    cat > "${LAUNCH_AGENT_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.corporealshift.pr-menu</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

    launchctl load "${LAUNCH_AGENT_PLIST}" 2>/dev/null || true
    info "Launch agent installed — pr-menu will start at login."
else
    info "Skipping launch agent setup."
fi

echo ""
info "Installation complete!"

read -rp "Launch pr-menu now? [Y/n] " launch_now
if [[ ! "${launch_now}" =~ ^[Nn]$ ]]; then
    "${INSTALL_PATH}"
    info "pr-menu is running."
else
    info "Run 'pr-menu' to start."
fi
