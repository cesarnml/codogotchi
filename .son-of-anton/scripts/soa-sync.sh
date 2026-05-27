#!/usr/bin/env bash
# Syncs son-of-anton skills into the consumer repo and runs structural migrations.
#
# Works in two modes:
#   source repo  — run from the son-of-anton repo itself (.agents/skills/ exists at root)
#   consumer repo — run from a repo that has done `git subtree add` (.son-of-anton/ exists)
#
# Source-repo mode: skips migration logic; only relinks skills.
# Consumer-repo mode: runs apply_migrations() before symlinking.
#
# Naming convention:
#   The skill named "soa" is linked as "soa" (not "soa-soa") — it is the entry point.
#   All other skills are linked with the "soa-" prefix.
#
# Idempotent: removes stale soa-* symlinks before relinking so reruns don't leave ghosts.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILLS_DEST="$REPO_ROOT/.claude/skills"
SOA_TARGET_VERSION=1

if [ -d "$REPO_ROOT/.agents/skills" ] && [ ! -d "$REPO_ROOT/.son-of-anton" ]; then
  # Source repo: skills live at .agents/skills/ directly
  SKILLS_SRC="$REPO_ROOT/.agents/skills"
  LINK_TARGET_PREFIX="../../.agents/skills"
  IS_SOURCE_REPO=true
else
  # Consumer repo: skills live under .son-of-anton/
  SKILLS_SRC="$REPO_ROOT/.son-of-anton/.agents/skills"
  LINK_TARGET_PREFIX="../../.son-of-anton/.agents/skills"
  IS_SOURCE_REPO=false
fi

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

read_soa_version() {
  local version_file="$REPO_ROOT/.soa-sync-version"
  if [ -f "$version_file" ]; then
    local raw
    raw="$(cat "$version_file")"
    if ! [[ "$raw" =~ ^[0-9]+$ ]]; then
      echo "soa-sync: .soa-sync-version contains non-integer value '$raw'; aborting" >&2
      exit 1
    fi
    echo "$raw"
  else
    echo "0"
  fi
}

write_soa_version() {
  echo "$1" > "$REPO_ROOT/.soa-sync-version"
}

ensure_gitignore_pattern() {
  local pattern="$1"
  local gitignore="$REPO_ROOT/.gitignore"

  if [ -f "$gitignore" ] && grep -qxF "$pattern" "$gitignore"; then
    return
  fi

  if [ -f "$gitignore" ] && [ -s "$gitignore" ] && [ "$(tail -c 1 "$gitignore")" != "" ]; then
    printf '\n' >> "$gitignore"
  fi
  printf '%s\n' "$pattern" >> "$gitignore"
  echo "  updated: .gitignore ($pattern)"
}

# ---------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------

run_migration_1() {
  # When .agents is a symlink, review files are never git-tracked — nothing to move.
  if [ -L "$REPO_ROOT/.agents" ]; then
    return
  fi

  local old_base="$REPO_ROOT/.agents/delivery"
  local new_base="$REPO_ROOT/docs/product/delivery"

  for reviews_dir in "$old_base"/*/reviews; do
    if [ -d "$reviews_dir" ]; then
      local phase
      phase="$(basename "$(dirname "$reviews_dir")")"
      mkdir -p "$new_base/$phase"
      git -C "$REPO_ROOT" mv ".agents/delivery/$phase/reviews" "docs/product/delivery/$phase/reviews"
    fi
  done
}

apply_migrations() {
  local current_version
  current_version="$(read_soa_version)"

  if [ "$current_version" -ge "$SOA_TARGET_VERSION" ]; then
    return
  fi

  local v="$current_version"
  while [ "$v" -lt "$SOA_TARGET_VERSION" ]; do
    v=$((v + 1))
    "run_migration_$v"
  done

  write_soa_version "$SOA_TARGET_VERSION"
}

# ---------------------------------------------------------------------------
# Agent-rule injection
# ---------------------------------------------------------------------------

# inject_soa_block <source-path-relative-to-REPO_ROOT> <target-path-relative-to-REPO_ROOT>
# Replaces or inserts a <!-- soa:start --> ... <!-- soa:end --> block in target.
# Creates target if absent. No-op when content is already current.
inject_soa_block() {
  local source_rel="$1"
  local target_rel="$2"
  local source_path="$REPO_ROOT/$source_rel"
  local target_path="$REPO_ROOT/$target_rel"

  [ -f "$source_path" ] || return 0

  # Resolve symlink so we write through to the referent, not replace the link.
  if [ -L "$target_path" ]; then
    target_path="$(readlink -f "$target_path")"
  fi

  local tmp
  tmp="$(mktemp)"

  # Use replacement mode only when BOTH markers are present; a file with only
  # the start marker (corrupted) falls through to append so content is not lost.
  if [ -f "$target_path" ] \
      && grep -qF '<!-- soa:start -->' "$target_path" \
      && grep -qF '<!-- soa:end -->' "$target_path"; then
    # Replace existing block while preserving content outside the markers
    awk -v src="$source_path" '
      /<!-- soa:start -->/ {
        print "<!-- soa:start -->"
        while ((getline line < src) > 0) print line
        print "<!-- soa:end -->"
        skip=1; next
      }
      skip && /<!-- soa:end -->/ { skip=0; next }
      !skip { print }
    ' "$target_path" > "$tmp"
  elif [ -f "$target_path" ]; then
    # Append block to existing file (no markers present)
    { cat "$target_path"; printf '\n<!-- soa:start -->\n'; cat "$source_path"; printf '<!-- soa:end -->\n'; } > "$tmp"
  else
    # Create new file containing only the block
    { printf '<!-- soa:start -->\n'; cat "$source_path"; printf '<!-- soa:end -->\n'; } > "$tmp"
  fi

  if [ -f "$target_path" ] && diff -q "$target_path" "$tmp" > /dev/null 2>&1; then
    rm "$tmp"
  else
    mv "$tmp" "$target_path"
  fi
}

# ---------------------------------------------------------------------------
# Run migrations (consumer mode only)
# ---------------------------------------------------------------------------

if [ "$IS_SOURCE_REPO" = false ]; then
  apply_migrations
fi

# ---------------------------------------------------------------------------
# Skill symlinking (both modes)
# ---------------------------------------------------------------------------

mkdir -p "$SKILLS_DEST"

# Remove stale soa-* symlinks/directories and the bare "soa" entry before relinking.
for stale in "$SKILLS_DEST"/soa-* "$SKILLS_DEST/soa"; do
  if [ -L "$stale" ]; then
    rm "$stale"
  elif [ -d "$stale" ]; then
    rm -rf "$stale"
  fi
done

for skill_dir in "$SKILLS_SRC"/*/; do
  name="$(basename "$skill_dir")"
  target="$LINK_TARGET_PREFIX/$name"

  # "soa" is the entry point — link as "soa", not "soa-soa"
  if [ "$name" = "soa" ]; then
    link="$SKILLS_DEST/soa"
  else
    link="$SKILLS_DEST/soa-$name"
  fi

  ln -sf "$target" "$link"
  echo "  linked: .claude/skills/$(basename "$link")"
done

# Ensure repo-root symlinks required by the delivery orchestrator exist (consumer only).
if [ "$IS_SOURCE_REPO" = false ]; then
  for pair in ".agents:.son-of-anton/.agents" "tools:.son-of-anton/tools"; do
    link_name="${pair%%:*}"
    target="${pair##*:}"
    link="$REPO_ROOT/$link_name"
    if [ ! -e "$link" ] && [ ! -L "$link" ]; then
      ln -s "$target" "$link"
      echo "  linked: $link_name -> $target"
    elif [ "$link_name" = ".agents" ]; then
      echo "  kept: .agents already exists; Son-of-Anton skills remain under .son-of-anton/.agents"
    fi
  done

  # Inject agent-rule blocks into AGENTS.md and CLAUDE.md
  inject_soa_block ".son-of-anton/AGENTS.soa.md" "AGENTS.md"
  inject_soa_block ".son-of-anton/CLAUDE.soa.md" "CLAUDE.md"

  # Scaffold orchestrator.config.json if absent.
  # Detects packageManager from lock files; defaults to bun if none found.
  SOA_CONFIG="$REPO_ROOT/orchestrator.config.json"
  if [ ! -f "$SOA_CONFIG" ]; then
    if [ -f "$REPO_ROOT/pnpm-lock.yaml" ]; then
      _pm="pnpm"; _rt="node"
    elif [ -f "$REPO_ROOT/yarn.lock" ]; then
      _pm="yarn"; _rt="node"
    elif [ -f "$REPO_ROOT/package-lock.json" ]; then
      _pm="npm"; _rt="node"
    else
      _pm="bun"; _rt="bun"
    fi
    cat > "$SOA_CONFIG" <<EOF_CONFIG
{
  "defaultBranch": "main",
  "planRoot": "docs",
  "runtime": "$_rt",
  "packageManager": "$_pm",
  "ticketBoundaryMode": "cook",
  "reviewPolicy": {
    "subagentReview": "skip_doc_only",
    "prReview": "disabled"
  },
  "prReviewAgents": [
    { "login": "coderabbitai", "name": "coderabbit", "resolveThreads": true }
  ],
  "primaryAgent": "unknown"
}
EOF_CONFIG
    echo "  created: orchestrator.config.json (review defaultBranch, runtime, packageManager)"
  fi

  # Refresh the global Claude Code entrypoint skill if previously installed.
  # The global skill is a manual one-time install that otherwise drifts silently.
  SOURCE_SOA_SKILL="$REPO_ROOT/.son-of-anton/.agents/skills/soa/SKILL.md"
  GLOBAL_SOA_SKILL="$HOME/.claude/skills/soa/SKILL.md"
  if [ -f "$SOURCE_SOA_SKILL" ] && [ -f "$GLOBAL_SOA_SKILL" ]; then
    cp "$SOURCE_SOA_SKILL" "$GLOBAL_SOA_SKILL"
    echo "  refreshed: ~/.claude/skills/soa/SKILL.md"
  fi

  ensure_gitignore_pattern "*-subagent-review.trace.log"

  echo ""
  echo "soa-sync: setup complete."
  echo ""
  echo "  Prerequisites:"
  echo "    bun    (global) — required for all delivery commands: https://bun.sh"
  echo "    gh     (global) — required for PR creation and review polling: https://cli.github.com"
  echo "    claude (global) — optional, enables programmatic subagent review via --subagent claude-cli"
  echo "    codex  (global) — optional, enables programmatic subagent review via --subagent codex-cli"
  echo "    agent  (global) — optional, Cursor Agent CLI; enables programmatic subagent review via --subagent cursor-cli"
  echo ""
  echo "  Add .son-of-anton/ to your lint/format ignore config (e.g. .prettierignore, .eslintignore)"
  echo "  Review orchestrator.config.json, then run: bun run deliver --plan <plan-path> start"
fi

echo "soa-sync: done"
