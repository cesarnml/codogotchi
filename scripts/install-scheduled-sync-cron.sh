#!/usr/bin/env bash
#
# install-scheduled-sync-cron.sh — cron installer for `codogotchi sync`.
#
# Adds a crontab entry that runs `codogotchi sync` every 15 minutes. Idempotent:
# re-running this script does not duplicate the line — it looks for a managed
# marker, strips any prior managed line, and reinstalls the current command.
#
# Logs append to ~/.codogotchi/scheduled-cron.log (separate from the engine's
# own structured ~/.codogotchi/sync.log).
#
# Usage:
#   bash scripts/install-scheduled-sync-cron.sh
#   bash scripts/install-scheduled-sync-cron.sh --uninstall

set -euo pipefail

MARKER="# managed-by:codogotchi-sync"
CRON_SCHEDULE="${CODOGOTCHI_CRON_SCHEDULE:-*/15 * * * *}"
LOG_FILE="${HOME}/.codogotchi/scheduled-cron.log"

uninstall() {
  local current
  current="$(crontab -l 2>/dev/null || true)"
  if [[ -z "${current}" ]]; then
    echo "No crontab present; nothing to uninstall."
    return 0
  fi
  echo "${current}" | grep -v "${MARKER}" | crontab -
  echo "Removed managed codogotchi cron entry."
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
mkdir -p "$(dirname "${LOG_FILE}")"

current="$(crontab -l 2>/dev/null || true)"
# Strip any prior managed line so re-runs do not duplicate.
trimmed="$(printf '%s\n' "${current}" | grep -v "${MARKER}" || true)"
new_line="${CRON_SCHEDULE} ${CODOGOTCHI_BIN} sync >> ${LOG_FILE} 2>&1 ${MARKER}"

if [[ -z "${trimmed}" ]]; then
  printf '%s\n' "${new_line}" | crontab -
else
  printf '%s\n%s\n' "${trimmed}" "${new_line}" | crontab -
fi

echo "Installed managed cron entry:"
echo "  ${new_line}"
echo "Verify with: crontab -l | grep ${MARKER}"
echo "Cron stdout / stderr: ${LOG_FILE}"
echo "Engine sync log: ~/.codogotchi/sync.log"
