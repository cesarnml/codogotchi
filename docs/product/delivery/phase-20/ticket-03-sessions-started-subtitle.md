# P20.03 Settings > Sessions Started subtitle

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- Settings > Sessions rows in **Active**, **Live**, and **Archived** show a relative Started fragment when `session_started_at` is present (e.g. `Started · 2h ago`).
- When Idle age is already shown on the row, Started and Idle combine into **one** subtitle line.
- When `session_started_at` is missing (pre-v10 / unstamped slices), the Started fragment is omitted — never fabricated from `updated_at`.
- View-model / formatting tests cover present, absent, and combine-with-idle cases.

## Red

- Failing tests prove Started is absent today for stamped fixtures and specify the relative/combined copy contract.
- Commit with suffix `[red]` before implementation.

## Green

- Thread `session_started_at` from session scan/read path into `SessionsTabViewModel` (or equivalent) and render the subtitle in `SessionsTabView`.
- Smallest UI change — no PromptTimer edits unless a shared relative-time helper is the smaller path.

## Refactor

- Share relative-time formatting with existing Idle age helpers if that shrinks duplication; do not restyle the Sessions tab.

## Review Focus

- All three lifecycle buckets (Active / Live / Archived) get the same Started rule.
- Omit-on-missing is mandatory.
- No new floating-window session-age chip; Settings only.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
