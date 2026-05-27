#!/usr/bin/env bash
# Update the son-of-anton subtree in a consumer repo, sync skills, and verify content.
#
# Consumer repos only — the source repo uses plain git pull on main.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SOA_PREFIX="$REPO_ROOT/.son-of-anton"
UPSTREAM_URL="https://github.com/cesarnml/son-of-anton.git"
UPSTREAM_BRANCH="main"
# Production-repo path; consumer copy lives under .son-of-anton/
VERIFY_REL="docs/template/delivery/adversarial-review-template.md"

if [ ! -d "$SOA_PREFIX" ]; then
  echo "soa-update: .son-of-anton not found — run /soa install first" >&2
  exit 1
fi

cd "$REPO_ROOT"

git fetch "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
UPSTREAM_SHA="$(git rev-parse FETCH_HEAD)"

git subtree merge --prefix .son-of-anton "$UPSTREAM_SHA" --squash

bash "$SOA_PREFIX/scripts/soa-sync.sh"

upstream_hash="$(git show "$UPSTREAM_SHA:$VERIFY_REL" | git hash-object --stdin)"
local_hash="$(git hash-object "$SOA_PREFIX/$VERIFY_REL")"

if [ "$upstream_hash" != "$local_hash" ]; then
  echo "soa-update: verification failed — subtree content does not match upstream $UPSTREAM_SHA" >&2
  echo "  upstream: $upstream_hash ($VERIFY_REL)" >&2
  echo "  local:    $local_hash (.son-of-anton/$VERIFY_REL)" >&2
  exit 1
fi

echo "soa-update: OK (upstream $UPSTREAM_SHA)"
