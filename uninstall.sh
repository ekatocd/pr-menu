#!/bin/bash
set -euo pipefail

INSTALL_PATH="/usr/local/bin/pr-menu"
LAUNCH_AGENT_PLIST="${HOME}/Library/LaunchAgents/com.corporealshift.pr-menu.plist"

# ── Helpers ──────────────────────────────────────────────────────

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mWarning:\033[0m %s\n' "$*"; }

# ── Stop running instance ───────────────────────────────────────

if pgrep -x PRMenu &>/dev/null; then
    info "Stopping running pr-menu process…"
    pkill -x PRMenu || true
fi

# ── Remove launch agent ─────────────────────────────────────────

if [[ -f "${LAUNCH_AGENT_PLIST}" ]]; then
    info "Unloading launch agent…"
    launchctl unload "${LAUNCH_AGENT_PLIST}" 2>/dev/null || true
    rm -f "${LAUNCH_AGENT_PLIST}"
    info "Launch agent removed."
else
    info "No launch agent found — skipping."
fi

# ── Remove binary ───────────────────────────────────────────────

if [[ -f "${INSTALL_PATH}" ]]; then
    info "Removing ${INSTALL_PATH}…"
    sudo rm -f "${INSTALL_PATH}"
    info "Binary removed."
else
    warn "Binary not found at ${INSTALL_PATH} — skipping."
fi

echo ""
info "Uninstall complete."
