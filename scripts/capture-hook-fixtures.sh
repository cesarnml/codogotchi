#!/usr/bin/env bash
#
# capture-hook-fixtures.sh — recipe for capturing fresh Claude Code and Codex
# hook event JSON against the *current* upstream schemas. The fixtures live in
# packages/engine/test/fixtures/hooks/{claude,codex}/ and are committed.
#
# This script is documentation as code: it does not auto-capture — Claude Code
# and Codex hook lifecycles are driven by the upstream agent runtime, not by
# this repo. Instead, it (1) wires a temporary capturing hook into the agent's
# settings file, (2) prints the steps to drive each lifecycle, and (3)
# restores the prior settings when run with --restore.
#
# Usage:
#   bash scripts/capture-hook-fixtures.sh --install
#   # …drive Claude Code / Codex through the lifecycles below…
#   bash scripts/capture-hook-fixtures.sh --restore
#
# After --install, every hook invocation tees its stdin to
#   $TMPDIR/codogotchi-fixtures/<agent>/<event-name>.<timestamp>.json
# Pick the cleanest exemplar per lifecycle and move it into
#   packages/engine/test/fixtures/hooks/<agent>/<event-name>.json
#
# Tested against:
#   - Claude Code 2.x hook schema (PreToolUse, PostToolUse, Stop)
#   - Codex 0.4x hook schema (pre_tool_use, post_tool_use, session_end)
#
# Re-run this capture if upstream schemas drift — keep the committed fixtures
# representative of what the codogotchi-hook binary actually receives.

set -euo pipefail

TARGET_DIR="${TMPDIR:-/tmp}/codogotchi-fixtures"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CLAUDE_SETTINGS_BAK="${HOME}/.claude/settings.json.codogotchi-capture.bak"
CODEX_HOOKS="${HOME}/.codex/hooks/codogotchi.toml"
CODEX_HOOKS_BAK="${HOME}/.codex/hooks/codogotchi.toml.codogotchi-capture.bak"

install_capture() {
  mkdir -p "${TARGET_DIR}/claude" "${TARGET_DIR}/codex"
  cat <<EOF
Capture target directory: ${TARGET_DIR}

To capture Claude Code fixtures:
  1. Back up your current ~/.claude/settings.json (this script does it once).
  2. Replace the codogotchi hook command with:
       /bin/sh -c 'cat | tee ${TARGET_DIR}/claude/\$CLAUDE_HOOK_EVENT_NAME.\$(date +%s).json | codogotchi-hook'
  3. Drive lifecycles in a real Claude Code session:
       - Edit a file (Edit / Write / MultiEdit) → PreToolUse, PostToolUse
       - Read several files in a row             → consecutive Read events
       - Run \`bun test\` from the agent          → Bash + PostToolUse
       - End the session                         → Stop
  4. Inspect ${TARGET_DIR}/claude/ for the per-event JSON dumps.

To capture Codex fixtures:
  1. Back up ~/.codex/hooks/codogotchi.toml (this script does it once).
  2. Replace the command line with:
       command = "/bin/sh -c 'cat | tee ${TARGET_DIR}/codex/\$CODEX_HOOK_EVENT_NAME.\$(date +%s).json | codogotchi-hook'"
  3. Drive a Codex session with similar lifecycle coverage.
  4. Inspect ${TARGET_DIR}/codex/.

After capture, copy the cleanest exemplar per lifecycle into
  packages/engine/test/fixtures/hooks/claude/<event>.json
  packages/engine/test/fixtures/hooks/codex/<event>.json
Strip any host-specific paths from the JSON before committing.
EOF
  if [[ -f "${CLAUDE_SETTINGS}" && ! -f "${CLAUDE_SETTINGS_BAK}" ]]; then
    cp "${CLAUDE_SETTINGS}" "${CLAUDE_SETTINGS_BAK}"
    echo "Backed up ${CLAUDE_SETTINGS} -> ${CLAUDE_SETTINGS_BAK}"
  fi
  if [[ -f "${CODEX_HOOKS}" && ! -f "${CODEX_HOOKS_BAK}" ]]; then
    cp "${CODEX_HOOKS}" "${CODEX_HOOKS_BAK}"
    echo "Backed up ${CODEX_HOOKS} -> ${CODEX_HOOKS_BAK}"
  fi
}

restore_capture() {
  if [[ -f "${CLAUDE_SETTINGS_BAK}" ]]; then
    mv "${CLAUDE_SETTINGS_BAK}" "${CLAUDE_SETTINGS}"
    echo "Restored ${CLAUDE_SETTINGS}."
  fi
  if [[ -f "${CODEX_HOOKS_BAK}" ]]; then
    mv "${CODEX_HOOKS_BAK}" "${CODEX_HOOKS}"
    echo "Restored ${CODEX_HOOKS}."
  fi
  echo "Capture artifacts remain in ${TARGET_DIR}; move chosen exemplars into packages/engine/test/fixtures/hooks/."
}

case "${1:---install}" in
  --install) install_capture ;;
  --restore) restore_capture ;;
  *) echo "Usage: $0 [--install|--restore]" >&2 ; exit 2 ;;
esac
