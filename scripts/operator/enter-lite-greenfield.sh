#!/usr/bin/env bash
# operator-only, not user-facing
#
# enter-lite-greenfield.sh — back up and remove ~/.codogotchi to start Lite fresh.
#
# Does NOT uninstall hooks. If you want to remove hooks before switching,
# run: codogotchi hooks uninstall
#
# After entering Lite greenfield, run: codogotchi setup
# To restore RPG data later, run: bash scripts/operator/restore-rpg-home.sh
#
# Usage:
#   bash scripts/operator/enter-lite-greenfield.sh

set -euo pipefail

CODOGOTCHI_HOME="${CODOGOTCHI_HOME:-${HOME}/.codogotchi}"

if [[ ! -d "${CODOGOTCHI_HOME}" ]]; then
  echo "Nothing to remove — ${CODOGOTCHI_HOME} does not exist. Already greenfield." >&2
  exit 0
fi

echo "This will:"
echo "  1. Back up ${CODOGOTCHI_HOME} to ${CODOGOTCHI_HOME}.rpg-backup-<timestamp>"
echo "  2. Delete ${CODOGOTCHI_HOME}"
echo ""
echo "Hooks are NOT removed. Run 'codogotchi hooks uninstall' first if desired."
echo ""
read -r -p "Proceed? (yes/no) " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted." >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CODOGOTCHI_HOME}.rpg-backup-${TIMESTAMP}"
cp -r "${CODOGOTCHI_HOME}" "${BACKUP}"
echo "Backup created: ${BACKUP}"

rm -rf "${CODOGOTCHI_HOME}"
echo "Removed ${CODOGOTCHI_HOME}."
echo ""
echo "Ready for Lite greenfield. Run: codogotchi setup"
