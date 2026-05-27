#!/usr/bin/env bash
set -euo pipefail

# Contract for the delivery orchestrator:
#   {
#     "agents": [{"agent":"coderabbit","state":"started|completed|findings_detected","findingsCount":1,"note":"..."}],
#     "detected": true|false,
#     "vendors": ["coderabbit", "qodo", "greptile", "sonarqube"],
#     "comments": [...]
#   }

pr_number="${1:-}"

# Early exit if prReview disabled
config_file="$(git rev-parse --show-toplevel)/orchestrator.config.json"
if [[ -f "$config_file" ]]; then
  pr_review_policy="$(jq -r '(.reviewPolicy.prReview // "")' "$config_file")"
  if [[ "$pr_review_policy" == "disabled" ]]; then
    echo '{"agents":[],"detected":false,"vendors":[],"comments":[]}'
    exit 0
  fi
fi

# Load prReviewAgents from config for dynamic login identification
pr_review_agents='[]'
if [[ -f "$config_file" ]]; then
  pr_review_agents="$(jq -c '(.prReviewAgents // [])' "$config_file" 2>/dev/null || echo '[]')"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

if [[ -z "$pr_number" ]]; then
  pr_number="$(gh pr view --json number -q .number)"
fi

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
owner="${repo%%/*}"
name="${repo##*/}"
pr_json="$(gh pr view "$pr_number" --json number,title,url,headRefName,headRefOid,baseRefName,isDraft,state,comments,reviews)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

head_sha="$(printf '%s' "$pr_json" | jq -r '.headRefOid')"

review_comments_json="$(
  gh api --paginate "repos/$repo/pulls/$pr_number/comments?per_page=100" \
    --jq '.[]'
)"

if [[ -n "$review_comments_json" ]]; then
  review_comments_json="$(printf '%s\n' "$review_comments_json" | jq -s '.')"
else
  review_comments_json='[]'
fi

fetch_review_threads_page() {
  local after_cursor="${1:-}"

  if [[ -n "$after_cursor" ]]; then
    gh api graphql \
      -F owner="$owner" \
      -F name="$name" \
      -F number="$pr_number" \
      -F after="$after_cursor" \
      -f query='
        query($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100, after: $after) {
                nodes {
                  id
                  isResolved
                  isOutdated
                  viewerCanResolve
                  comments(first: 100) {
                    nodes {
                      databaseId
                      url
                    }
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
                  }
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
        }
      '
  else
    gh api graphql \
      -F owner="$owner" \
      -F name="$name" \
      -F number="$pr_number" \
      -f query='
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100) {
                nodes {
                  id
                  isResolved
                  isOutdated
                  viewerCanResolve
                  comments(first: 100) {
                    nodes {
                      databaseId
                      url
                    }
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
                  }
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
        }
      '
  fi
}

fetch_thread_comments_page() {
  local thread_id="$1"
  local after_cursor="${2:-}"

  if [[ -n "$after_cursor" ]]; then
    gh api graphql \
      -F threadId="$thread_id" \
      -F after="$after_cursor" \
      -f query='
        query($threadId: ID!, $after: String) {
          node(id: $threadId) {
            ... on PullRequestReviewThread {
              comments(first: 100, after: $after) {
                nodes {
                  databaseId
                  url
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
        }
      '
  else
    gh api graphql \
      -F threadId="$thread_id" \
      -f query='
        query($threadId: ID!) {
          node(id: $threadId) {
            ... on PullRequestReviewThread {
              comments(first: 100) {
                nodes {
                  databaseId
                  url
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
        }
      '
  fi
}

thread_pages_file="$temp_dir/review-thread-pages.jsonl"
: >"$thread_pages_file"
thread_cursor=""

while :; do
  thread_page_json="$(fetch_review_threads_page "$thread_cursor")"
  thread_nodes_json="$(printf '%s' "$thread_page_json" | jq '.data.repository.pullRequest.reviewThreads.nodes')"

  if [[ "$thread_nodes_json" != "[]" ]]; then
    printf '%s\n' "$thread_nodes_json" >>"$thread_pages_file"
  fi

  thread_has_next="$(printf '%s' "$thread_page_json" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false')"
  if [[ "$thread_has_next" != "true" ]]; then
    break
  fi

  thread_cursor="$(printf '%s' "$thread_page_json" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // ""')"
done

if [[ -s "$thread_pages_file" ]]; then
  review_threads_json="$(jq -s 'add // []' "$thread_pages_file")"
else
  review_threads_json='[]'
fi

expanded_threads_file="$temp_dir/expanded-review-threads.jsonl"
: >"$expanded_threads_file"
while IFS= read -r thread_json; do
  [[ -z "$thread_json" ]] && continue

  thread_id="$(printf '%s' "$thread_json" | jq -r '.id')"
  comment_pages_file="$(mktemp "$temp_dir/thread-comments.XXXXXX.jsonl")"
  comment_nodes_json="$(printf '%s' "$thread_json" | jq '.comments.nodes // []')"
  printf '%s\n' "$comment_nodes_json" >"$comment_pages_file"
  comment_has_next="$(printf '%s' "$thread_json" | jq -r '.comments.pageInfo.hasNextPage // false')"
  comment_cursor="$(printf '%s' "$thread_json" | jq -r '.comments.pageInfo.endCursor // ""')"

  while [[ "$comment_has_next" == "true" ]]; do
    comment_page_json="$(fetch_thread_comments_page "$thread_id" "$comment_cursor")"
    page_nodes_json="$(printf '%s' "$comment_page_json" | jq '.data.node.comments.nodes // []')"
    printf '%s\n' "$page_nodes_json" >>"$comment_pages_file"
    comment_has_next="$(printf '%s' "$comment_page_json" | jq -r '.data.node.comments.pageInfo.hasNextPage // false')"
    comment_cursor="$(printf '%s' "$comment_page_json" | jq -r '.data.node.comments.pageInfo.endCursor // ""')"
  done

  comment_nodes_json="$(jq -s 'add // []' "$comment_pages_file")"
  rm -f "$comment_pages_file"
  expanded_thread_json="$(
    printf '%s' "$thread_json" | jq --argjson nodes "$comment_nodes_json" '.comments = { nodes: $nodes }'
  )"
  printf '%s\n' "$expanded_thread_json" >>"$expanded_threads_file"
done < <(printf '%s' "$review_threads_json" | jq -c '.[]')

if [[ -s "$expanded_threads_file" ]]; then
  review_threads_json="$(jq -s '.' "$expanded_threads_file")"
else
  review_threads_json='[]'
fi

if check_run_rows="$(
  gh api --paginate "repos/$repo/commits/$head_sha/check-runs?per_page=100" \
    --jq '.check_runs[]?' 2>/dev/null
)"; then
  if [[ -n "$check_run_rows" ]]; then
    check_runs_json="$(printf '%s\n' "$check_run_rows" | jq -s '{check_runs: .}')"
  else
    check_runs_json='{"check_runs":[]}'
  fi
else
  printf '%s\n' "warning: unable to fetch check runs; skipping SonarQube annotations" >&2
  check_runs_json='{"check_runs":[]}'
fi

sonarqube_check_runs_json="$(
  printf '%s' "$check_runs_json" | jq '
    (.check_runs // [])
    | map(
        select(
          ((.app.slug // "" | ascii_downcase) == "sonarqubecloud")
          or ((.name // "" | ascii_downcase) == "sonarcloud code analysis")
        )
      )
  '
)"

sonarqube_annotations_file="$temp_dir/sonarqube-annotations.jsonl"
: >"$sonarqube_annotations_file"

while IFS= read -r check_run_id; do
  [[ -z "$check_run_id" ]] && continue
  annotation_rows="$(
    gh api --paginate "repos/$repo/check-runs/$check_run_id/annotations?per_page=100" \
      --jq '.[]'
  )"
  if [[ -n "$annotation_rows" ]]; then
    printf '%s\n' "$annotation_rows" >>"$sonarqube_annotations_file"
  fi
done < <(printf '%s' "$sonarqube_check_runs_json" | jq -r '.[].id')

if [[ -s "$sonarqube_annotations_file" ]]; then
  sonarqube_annotations_json="$(jq -s '.' "$sonarqube_annotations_file")"
else
  sonarqube_annotations_json='[]'
fi

jq -n \
  --argjson pr "$pr_json" \
  --argjson review_comments "$review_comments_json" \
  --argjson review_threads "$review_threads_json" \
  --argjson sonarqube_annotations "$sonarqube_annotations_json" \
  --argjson pr_review_agents "$pr_review_agents" '
    def normalize_text:
      tostring
      | gsub("\r"; "")
      | gsub("\\s+"; " ")
      | gsub("^ +| +$"; "")
      | ascii_downcase;

    def author_login:
      (.author.login // .user.login // "unknown");

    def author_type:
      (.author.type // .user.type // "unknown");

    def body_text:
      (.body // "");

    def current_head_sha:
      ($pr.headRefOid // "" | ascii_downcase);

    def looks_like_supported_ai_identity:
      (author_login | ascii_downcase) as $login
      | ($pr_review_agents | map(.login | ascii_downcase) | any(. == $login));

    def looks_like_supported_ai_text:
      (body_text | normalize_text) as $body
      | ($body | test("coderabbit|code rabbit|qodo|greptile|sonarqube|sonarcloud"));

    def looks_like_started_text:
      (body_text | normalize_text) as $body
      | ($body | test("review started|review in progress|currently reviewing|i am reviewing|i'\''m reviewing|analyzing this pr|analysis in progress|starting review|check back in a few minutes|processing new changes in this pr"));

    def looks_like_summary_noise_text:
      (body_text | normalize_text) as $body
      | ($body | test("review summary by|code review by|walkthroughs|file changes|looking for bugs\\?|finishing touches|summary of changes|rule violations|bugs \\("));

    def vendor_name:
      (author_login | ascii_downcase) as $login
      | (body_text | normalize_text) as $body
      | ($pr_review_agents | map({login: (.login | ascii_downcase), name: .name}) | map(select(.login == $login)) | .[0].name) as $by_login
      | if $by_login != null then $by_login
        elif ($body | test("coderabbit|code rabbit")) then "coderabbit"
        elif ($body | test("qodo")) then "qodo"
        elif ($body | test("greptile")) then "greptile"
        elif ($body | test("sonarqube|sonarcloud")) then "sonarqube"
        else null
        end;

    def greptile_reviewed_sha:
      (try (body_text | capture("commit/(?<sha>[0-9a-fA-F]{7,40})").sha) catch "" | ascii_downcase);

    def looks_like_current_greptile_started_text:
      (body_text | normalize_text) as $body
      | (vendor_name) as $vendor
      | if $vendor != "greptile" then
          false
        elif ($body | test("last reviewed commit|re-trigger greptile|retrigger greptile|reviews \\(")) | not then
          false
        else
          (greptile_reviewed_sha) as $reviewed
          | (current_head_sha) as $current
          | ($reviewed | length) > 0
            and ($current | length) > 0
            and ($current | startswith($reviewed))
        end;

    def enrich_threads:
      $review_threads
      | map(
          . as $thread
          | (.comments.nodes // [])
          | map(
              . + {
                __thread_is_outdated: ($thread.isOutdated // false),
                __thread_is_resolved: ($thread.isResolved // false),
                __thread_id: ($thread.id // null),
                __thread_viewer_can_resolve: ($thread.viewerCanResolve // null)
              }
            )
        )
      | add // [];

    def thread_lookup:
      (enrich_threads)
      | map({
          thread_id: (.__thread_id // null),
          key_db: (if .databaseId then (.databaseId | tostring) else null end),
          key_url: (.url // null),
          is_outdated: .__thread_is_outdated,
          is_resolved: .__thread_is_resolved,
          viewer_can_resolve: (.__thread_viewer_can_resolve // null)
        })
      | map(select(.key_db != null or .key_url != null));

    def comment_thread_state:
      . as $comment
      | (thread_lookup) as $lookup
      | ($lookup
          | map(
              select(
                (.key_db != null and .key_db == (($comment.databaseId // null) | tostring))
                or (.key_url != null and .key_url == ($comment.html_url // $comment.url // ""))
              )
            )
          | .[0]) as $match
      | {
          thread_id: ($match.thread_id // null),
          is_outdated: ($match.is_outdated // false),
          is_resolved: ($match.is_resolved // false),
          viewer_can_resolve: ($match.viewer_can_resolve // null)
        };

    def comment_kind($channel):
      (body_text | normalize_text) as $body
      | (vendor_name) as $vendor
      | if $channel == "inline_review" then
          if (comment_thread_state.is_outdated or comment_thread_state.is_resolved) then "unknown" else "finding" end
        elif $vendor == "qodo" and $channel == "issue_comment" and ($body | test("review summary by qodo")) then
          "summary"
        elif $vendor == "qodo" and $channel == "issue_comment" and ($body | test("code review by qodo")) then
          if (
            ($body | test("bugs \\(0\\)"))
            and ($body | test("rule violations \\(0\\)"))
            and ($body | test("requirement gaps \\(0\\)"))
            and ($body | test("ux issues \\(0\\)"))
          ) then
            "summary"
          elif (comment_thread_state.is_outdated or comment_thread_state.is_resolved) then
            "unknown"
          else
            "finding"
          end
        elif $vendor == "coderabbit" and ($channel == "issue_comment" or $channel == "review_summary") then
          "summary"
        elif $vendor == "greptile" and $channel == "issue_comment" then
          "summary"
        elif $vendor == "sonarqube" and $channel == "issue_comment" then
          "summary"
        elif $vendor == "sonarqube" and $channel == "inline_review" then
          "unknown"
        elif $channel == "review_summary" and ($body | length) == 0 then
          "summary"
        elif looks_like_started_text or looks_like_current_greptile_started_text or looks_like_summary_noise_text then
          "summary"
        elif ($body | test("summary|overall|overview|high level|high-level|general feedback|looks good|no major issues|quick recap")) then
          "summary"
        elif ($body | test("should|could|must|consider|missing|bug|issue|incorrect|guard|handle|return|null|undefined|race|rename|suggestion:|nit:|nitpick")) then
          "finding"
        else
          "unknown"
        end;

    def derived_agent_state($channel):
      if $channel == "inline_review" then
        if (comment_thread_state.is_outdated or comment_thread_state.is_resolved) then "completed" else "findings_detected" end
      elif looks_like_started_text or looks_like_current_greptile_started_text then "started"
      elif comment_kind($channel) == "finding" then "findings_detected"
      else "completed"
      end;

    def review_entry($channel; $path; $line):
      (vendor_name) as $vendor
      | (comment_thread_state) as $thread_state
      | if $vendor == null then
          empty
        elif $channel == "review_summary" and ((body_text | normalize_text) | length) == 0 then
          empty
        else
          {
            vendor: $vendor,
            channel: $channel,
            author_login: author_login,
            author_type: author_type,
            body: body_text,
            path: $path,
            line: $line,
            thread_id: ($thread_state.thread_id // null),
            thread_viewer_can_resolve: ($thread_state.viewer_can_resolve // null),
            url: (.html_url // .url // ""),
            updated_at: (.updated_at // .submittedAt // .updatedAt // .createdAt // ""),
            is_outdated: ($thread_state.is_outdated // false),
            is_resolved: ($thread_state.is_resolved // false),
            kind: comment_kind($channel),
            derived_state: derived_agent_state($channel),
            database_id: (.databaseId // .id // null)
          }
        end;

    def annotation_url:
      try (
        .message
        | capture("(?<url>https://sonarcloud\\.io[^[:space:])]+)").url
      ) catch "";

    def annotation_body:
      ((.title // "SonarQube annotation") | tostring) as $title
      | ((.message // "") | tostring | gsub("^\n+"; "") | gsub("\r"; "")) as $message
      | if ($message | length) > 0 then "\($title)\n\n\($message)" else $title end;

    def sonarqube_annotation_entry:
      {
        vendor: "sonarqube",
        channel: "inline_review",
        author_login: "sonarqubecloud",
        author_type: "Bot",
        body: annotation_body,
        path: (.path // null),
        line: (.start_line // .end_line // null),
        thread_id: null,
        thread_viewer_can_resolve: null,
        url: annotation_url,
        updated_at: "",
        is_outdated: false,
        is_resolved: false,
        kind: "unknown",
        derived_state: "findings_detected",
        database_id: null
      };

    ($pr.comments // [])
    | map(review_entry("issue_comment"; null; null)) as $issue_comments
    | ($pr.reviews // [])
    | map(review_entry("review_summary"; null; null)) as $review_summaries
    | $review_comments
    | map(review_entry("inline_review"; (.path // null); (.line // .original_line // null))) as $inline_comments
    | ($sonarqube_annotations
        | map(
            select((.annotation_level // "") == "failure")
            | sonarqube_annotation_entry
          )) as $sonarqube_inline_comments
    | (
        (($inline_comments + $sonarqube_inline_comments)
          | sort_by((.is_outdated // false), (.is_resolved // false), .vendor, .path, .line))
        + ($issue_comments | sort_by(.vendor, .updated_at))
        + ($review_summaries | sort_by(.vendor, .updated_at))
      ) as $matches
    | ($matches | map(.vendor) | unique | sort) as $vendors
    | (
        $matches
        | sort_by(.vendor)
        | group_by(.vendor)
        | map({
            agent: .[0].vendor,
            state:
              (if any(.derived_state == "findings_detected") then "findings_detected"
               elif any(.derived_state == "started") then "started"
               else "completed"
               end),
            findingsCount: (map(select(.derived_state == "findings_detected")) | length),
            note:
              (if any(.derived_state == "findings_detected") then
                 "actionable findings captured"
               elif any(.derived_state == "started") then
                 "review still in progress"
               else
                 "review completed without actionable findings"
               end)
          })
      ) as $agents
    | {
        agents: $agents,
        detected: ($matches | length > 0),
        reviewed_head_sha: ($pr.headRefOid // null),
        vendors: $vendors,
        comments: $matches
      }
  '
