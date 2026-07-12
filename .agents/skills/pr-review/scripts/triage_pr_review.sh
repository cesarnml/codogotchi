#!/usr/bin/env bash
set -euo pipefail

# Contract for the delivery orchestrator:
#   {
#     "outcome": "clean" | "needs_patch" | "patched",
#     "note": "concise final note",
#     "action_summary": "optional action summary",
#     "non_action_summary": "optional non-action summary",
#     "vendors": ["coderabbit", "qodo"]
#   }
#
# This default triager stays agent-environment agnostic by making only
# deterministic judgments from the structured artifact. Environments that
# support richer patching can override the hook with AI_CODE_REVIEW_TRIAGER.

artifact_json_path="${1:-}"

if [[ -z "$artifact_json_path" ]]; then
  echo "Usage: triage_pr_review.sh <artifact-json-path>" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

jq '
  def is_vendor_status:
    (.kind == "unknown")
    and (
      .authorLogin == "qodo-code-review"
      or .authorLogin == "qodo-merge"
      or .authorLogin == "coderabbitai"
      or .authorLogin == "greptile-apps"
    )
    and ((.body // "") | contains("```") | not);

  .vendors as $vendors
  | (.comments // []) as $comments
  | ($comments | map(select(is_vendor_status))) as $vendor_statuses
  | ($comments | map(select(is_vendor_status | not))) as $relevant_comments
  | ($relevant_comments | map(select((.kind == "finding") and (.is_outdated != true) and (.is_resolved != true)))) as $findings
  | ($relevant_comments | map(select((.kind == "finding") and ((.is_outdated == true) or (.is_resolved == true))))) as $stale_findings
  | ($relevant_comments | map(select(.kind == "summary"))) as $summaries
  | ($relevant_comments | map(select((.kind == "unknown") and (.is_outdated != true) and (.is_resolved != true)))) as $unknowns
  | ($relevant_comments | map(select((.kind == "unknown") and ((.is_outdated == true) or (.is_resolved == true))))) as $stale_unknowns
  | if ($findings | length) > 0 then
      {
        outcome: "needs_patch",
        note: "Actionable AI review findings were detected and still need follow-up.",
        action_summary: "Flagged \($findings | length) finding comment(s) for follow-up.",
        non_action_summary:
          (
            [
              (if ($stale_findings | length) > 0 then "Ignored \($stale_findings | length) resolved or outdated finding comment(s)." else empty end),
              (if ($stale_unknowns | length) > 0 then "Ignored \($stale_unknowns | length) resolved or outdated unclear comment(s)." else empty end),
              (if ($unknowns | length) > 0 then "Left \($unknowns | length) unclear comment(s) for manual judgment." else empty end)
            ]
            | map(select(length > 0))
            | if length > 0 then join(" ") else null end
          ),
        vendors: $vendors,
        vendor_status_count: ($vendor_statuses | length)
      }
    elif ($unknowns | length) > 0 then
      {
        outcome: "needs_patch",
        note: "AI review comments were detected, but at least one item still needs manual judgment.",
        action_summary: "Escalated \($unknowns | length) unclear comment(s) for follow-up.",
        non_action_summary:
          (
            [
              (if ($stale_findings | length) > 0 then "Ignored \($stale_findings | length) resolved or outdated finding comment(s)." else empty end),
              (if ($stale_unknowns | length) > 0 then "Ignored \($stale_unknowns | length) resolved or outdated unclear comment(s)." else empty end)
            ]
            | map(select(length > 0))
            | if length > 0 then join(" ") else null end
          ),
        vendors: $vendors,
        vendor_status_count: ($vendor_statuses | length)
      }
    else
      {
        outcome: "clean",
        note: "External AI review completed without prudent follow-up changes.",
        action_summary: null,
        non_action_summary: null,
        vendors: $vendors,
        vendor_status_count: ($vendor_statuses | length)
      }
    end
' "$artifact_json_path"
