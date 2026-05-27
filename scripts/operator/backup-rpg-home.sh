#!/usr/bin/env bash
# operator-only, not user-facing
#
# backup-rpg-home.sh — copy ~/.codogotchi to ~/.codogotchi.rpg-backup-<timestamp>
#
# Use before switching to Lite mode or making destructive config changes.
# The hooks JSON files inside .codogotchi are included automatically by cp -r.
# If you manage hooks outside that directory, back them up separately.
#
# Usage:
#   bash scripts/operator/backup-rpg-home.sh

set -euo pipefail

CODOGOTCHI_HOME="${CODOGOTCHI_HOME:-${HOME}/.codogotchi}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CODOGOTCHI_HOME}.rpg-backup-${TIMESTAMP}"

if [[ ! -d "${CODOGOTCHI_HOME}" ]]; then
  echo "Nothing to back up — ${CODOGOTCHI_HOME} does not exist." >&2
  exit 1
fi

cp -r "${CODOGOTCHI_HOME}" "${BACKUP}"
echo "Backed up ${CODOGOTCHI_HOME} → ${BACKUP}"
