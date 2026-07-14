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

Red first: `StateJsonReaderTests.swift`/`SessionsTabViewModelTests.swift` failed to
compile — `StateJsonReader.readSessionStartedAt`, `SessionRow.sessionStartedAt`,
and `SessionRowView.subtitleText` didn't exist yet. Swift TDD in this codebase
treats "doesn't compile against not-yet-built API" as red, matching P20.02's
precedent (`StateJsonReaderTests` already referenced `sessionStartedAt` on
`StateSnapshot` before that ticket's green).

Why this path: `SessionsTabViewModel.refresh()` already did a stat-and-listing
pass per slice for tiering; the smallest addition was one more lightweight
per-slice read (`StateJsonReader.readSessionStartedAt(atPath:)`, a partial
decode of just the one field) threaded into a new `SessionRow.sessionStartedAt`
field. Rendering combines the new "Started · <age>" fragment onto each tier's
*existing* status line (`Shown`/`Hidden` for Active, `Idle <age>` for Live,
`Quiet <age>` for Archived) via one extracted, testable static function
(`SessionRowView.subtitleText(for:now:)`) rather than a second subtitle row —
no information is lost (Shown/Hidden and Idle/Quiet ages still render exactly
as before when the stamp is absent) and `relativeAge` is reused unchanged for
both the existing ages and the new Started fragment, per the ticket's Refactor
note.

Alternative considered: building a full `FloatingPetWindowPool` +
`FloatingPetWindowControlling` stub in the new test file to exercise
`refresh()`'s Active-tier branch end-to-end (mirroring `MenuItemsTests
.StubWindow`) was rejected — the `session_started_at` read happens once per
candidate slice *before* the tier switch, identically for Active/Live/
Archived, so the Live/Archived `refresh()` threading tests plus exhaustive
`subtitleText` contract tests covering all three tiers (present/absent/
combine) give equivalent confidence without duplicating that ~10-method stub
class. Also considered leading with the Started fragment
(`Started · 2h ago · Idle 5m ago`) instead of trailing it
(`Idle 5m ago · Started · 2h ago`); kept the base status first since it's the
higher-signal, longer-standing fact for a returning user, with Started as
added context.

Deferred: no visual restyle of the Sessions tab row (font/color/layout
unchanged — only the subtitle string changes); no shared relative-time type
extracted beyond keeping `SessionRowView.relativeAge` as the single formatter
call site for both ages; PromptTimer's separate `compactLabel` formatter is
untouched, per the ticket's Green note.

Contract note: none — `Type: feat`, `Scope: menubar`, and `Red: required` all
matched the ticket file as authored; no deviation.
