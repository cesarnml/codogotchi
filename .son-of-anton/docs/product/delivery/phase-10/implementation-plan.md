# Phase 10 — Beta Credibility and Programmatic Subagent Review

> Make the final pre-beta credibility pass by proving internal subagent review on supported runners and tightening the highest-signal product language so it matches the shipped contract.

## Epic

[docs/product/plans/phase-10-beta-credibility-and-programmatic-subagent-review.md](../../plans/phase-10-beta-credibility-and-programmatic-subagent-review.md)

## Product contract

When this phase is complete:

- For supported runners, internal subagent review is orchestrator-executed rather than execution-agent-asserted, and `open-pr` is blocked unless a valid review execution artifact exists.
- A developer can rely on programmatic internal review anywhere Claude CLI or Codex Exec is installed and authenticated in the repo environment, regardless of which host execution agent is driving the ticket.
- The review runner is configured durably in `orchestrator.config.json` and participates in the same run-policy and execute/resume override model as the other bounded delivery settings.
- The README and directly beta-facing delivery docs remain strong, but no longer imply more internal-review enforcement or cross-agent parity than the product can actually prove.

## Grill-Me decisions locked

- **Runner-native config replaces logical review-subagent identity** → the new executor model should configure the concrete runner directly instead of preserving `codex:codex-rescue` as a separate identity layer; this keeps the product simpler and makes the runtime contract less ambiguous.
- **Config and run-policy land before executor work** → the state/config contract is a core orchestrator boundary and should be reviewable on its own before runner execution semantics build on top of it.
- **Claude runner lands before Codex Exec** → `claude -p` is the lower-risk first target for proving the executor-owned subagent-review path; Codex Exec follows on the same abstraction seam.
- **README honesty pass is a separate final ticket** → beta-facing product language is a first-class deliverable, not tail cleanup folded into the last technical slice.
- **Runner guarantee is environment-based, not host-agent-based** → after this phase, internal review should work wherever a supported CLI is installed and authenticated, even if the host execution agent has weak or no native subagent semantics.

## Ticket Order

1. `P10.01 Runner-native Subagent Review Config and Run-Policy Contract`
2. `P10.02 Executor-owned Subagent Review via Claude CLI`
3. `P10.03 Codex Exec Runner Support for Programmatic Subagent Review`
4. `P10.04 Beta-surface Honesty Pass`
5. `P10.05 Phase Exit and Retrospective`

## Ticket Files

- `ticket-01-runner-native-subagent-review-config-and-run-policy-contract.md`
- `ticket-02-executor-owned-subagent-review-via-claude-cli.md`
- `ticket-03-codex-exec-runner-support-for-programmatic-subagent-review.md`
- `ticket-04-beta-surface-honesty-pass.md`
- `ticket-05-phase-exit-and-retrospective.md`

## Exit Condition

All five tickets merged to `main`. `bun run ci` is green. A code ticket at `verified` can no longer advance to `open-pr` on a merely asserted internal review outcome when a supported runner is configured. A repo with Claude CLI or Codex Exec installed and authenticated can execute the internal subagent-review step programmatically through the orchestrator. The README and directly beta-facing delivery docs describe that guarantee accurately without collapsing into weak hedging. Retrospective written.

## Delivery Status

> Delivered: 2026-05-14 — PRs #33 (P10.01), #34 (P10.02), #35 (P10.03), #36 (P10.04), #37 (P10.05) open. Awaiting developer closeout approval.

## CI Baseline

> Baseline recorded: 2026-05-14 — **pass** (`bun run ci:quiet` exit 0)

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- `P10.02` and `P10.03` both touch the same executor seam and status/gating surfaces; do not start `P10.03` until `P10.02` is merged and its artifact/state model is stable.
- `P10.04` must be reviewed against shipped behavior from `P10.01`-`P10.03`, not against pre-phase product language.

## Explicit Deferrals

- Programmatic ticket implementation
- Programmatic self-review / `post-verify`
- Gemini support in the first programmatic subagent-review release
- Codex App Server integration
- Multi-worktree closeout artifact reconciliation redesign
- Standalone PR workflow redesign beyond any incidental wording updates required by `P10.04`

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous runner semantics where a timeout, malformed result, or unavailable binary cannot be mapped cleanly to a fail-closed orchestrator state.
- Evidence that the runner-native config model creates a worse migration path than expected for existing `reviewSubagentOverride` / `runPolicy` users.
- Beta-surface wording dispute that materially changes the product promise rather than merely tightening phrasing.

## Phase Closeout

Retrospective: required
Why: This phase changes a core trust boundary in ticket execution and defines the final pre-beta public contract.
Trigger: Developer approval of final P10.05 PR merge.
Artifact: `docs/product/retrospectives/phase-10-beta-credibility-and-programmatic-subagent-review-retrospective.md`
