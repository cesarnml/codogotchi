#!/usr/bin/env bash
#
# install-scheduled-sync.sh — macOS launchd installer for `codogotchi sync`.
#
# Generates and loads a LaunchAgent at
# ~/Library/LaunchAgents/com.codogotchi.sync.plist that runs `codogotchi sync`
# every 15 minutes. Idempotent: re-running unloads the existing agent before
# reloading so plist edits take effect cleanly.
#
# Requires `codogotchi` on PATH. Logs to ~/Library/Logs/codogotchi/sync.{out,err}.log
# (separate from the engine's own ~/.codogotchi/sync.log which is the
# canonical structured log).
#
# Usage:
#   bash scripts/install-scheduled-sync.sh
#   bash scripts/install-scheduled-sync.sh --uninstall

set -euo pipefail

LABEL="com.codogotchi.sync"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/codogotchi"
INTERVAL_SECONDS="${CODOGOTCHI_SYNC_INTERVAL_SECONDS:-900}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer targets macOS (launchd). On Linux, run install-scheduled-sync-cron.sh." >&2
  exit 1
fi

uninstall() {
  if launchctl list 2>/dev/null | grep -q "${LABEL}"; then
    launchctl unload "${PLIST}" 2>/dev/null || true
  fi
  rm -f "${PLIST}"
  echo "Removed ${PLIST}."
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
fi

if ! command -v codogotchi >/dev/null 2>&1; then
  echo "codogotchi CLI not found on PATH. Install it before scheduling." >&2
  exit 1
fi

CODOGOTCHI_BIN="$(command -v codogotchi)"

mkdir -p "${LOG_DIR}"
mkdir -p "${HOME}/Library/LaunchAgents"

# Unload any prior version so the new plist is honored on reload.
if launchctl list 2>/dev/null | grep -q "${LABEL}"; then
  launchctl unload "${PLIST}" 2>/dev/null || true
fi

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${CODOGOTCHI_BIN}</string>
    <string>sync</string>
  </array>
  <key>StartInterval</key>
  <integer>${INTERVAL_SECONDS}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/sync.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/sync.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${PATH}</string>
  </dict>
</dict>
</plist>
PLIST

launchctl load "${PLIST}"

echo "Installed and loaded ${PLIST}."
echo "Verify with: launchctl list | grep ${LABEL}"
echo "Engine sync log: ~/.codogotchi/sync.log"
echo "Stdout / stderr: ${LOG_DIR}/sync.{out,err}.log"
