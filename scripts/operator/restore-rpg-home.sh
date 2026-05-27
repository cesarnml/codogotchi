#!/usr/bin/env bash
# operator-only, not user-facing
#
# restore-rpg-home.sh — restore ~/.codogotchi from a backup directory.
#
# Lists available backups and prompts for a choice. The current ~/.codogotchi
# (if present) is itself backed up before being replaced.
#
# After restoring RPG data, run `codogotchi sync` to refresh the server cache.
#
# Usage:
#   bash scripts/operator/restore-rpg-home.sh

set -euo pipefail

CODOGOTCHI_HOME="${CODOGOTCHI_HOME:-${HOME}/.codogotchi}"
PARENT="$(dirname "${CODOGOTCHI_HOME}")"
PREFIX="$(basename "${CODOGOTCHI_HOME}").rpg-backup-"

mapfile -t BACKUPS < <(find "${PARENT}" -maxdepth 1 -type d -name "${PREFIX}*" | sort -r)

if [[ ${#BACKUPS[@]} -eq 0 ]]; then
  echo "No backups found matching ${PARENT}/${PREFIX}*" >&2
  exit 1
fi

echo "Available backups (newest first):"
for i in "${!BACKUPS[@]}"; do
  echo "  $((i + 1))) ${BACKUPS[$i]}"
done
echo ""
read -r -p "Choose a backup to restore (1-${#BACKUPS[@]}): " CHOICE

if ! [[ "${CHOICE}" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#BACKUPS[@]} )); then
  echo "Invalid choice." >&2
  exit 1
fi

SELECTED="${BACKUPS[$((CHOICE - 1))]}"

if [[ -d "${CODOGOTCHI_HOME}" ]]; then
  SAFETY_BACKUP="${CODOGOTCHI_HOME}.pre-restore-$(date +%Y%m%d-%H%M%S)"
  cp -r "${CODOGOTCHI_HOME}" "${SAFETY_BACKUP}"
  echo "Saved current ${CODOGOTCHI_HOME} → ${SAFETY_BACKUP}"
  rm -rf "${CODOGOTCHI_HOME}"
fi

cp -r "${SELECTED}" "${CODOGOTCHI_HOME}"
echo "Restored ${SELECTED} → ${CODOGOTCHI_HOME}"
echo ""
echo "RPG mode: run 'codogotchi sync' to refresh the server cache."
