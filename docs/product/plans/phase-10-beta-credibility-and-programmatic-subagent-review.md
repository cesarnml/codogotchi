# Phase 10: Beta Credibility and Programmatic Subagent Review

**Delivery status:** Product plan approved. Ready for decomposition.

## TL;DR

**Goal:** Make Son of Anton credible enough for beta by hardening the weakest trust boundary in the delivery loop and tightening the highest-signal public language so it matches what the product actually guarantees.

**Ships:**

- Orchestrator-owned internal subagent review for supported runners, with committed first-class support for `claude -p` and Codex Exec, configured via `orchestrator.config.json` and overridable via the same runtime run-policy model used by `/soa execute` and `/soa resume`.
- A more honest README and targeted beta-facing doc corrections that preserve SoA's product stance while stopping short of claims the current system cannot prove, especially around cross-agent parity and internal review enforcement.

**Defers:**

- Programmatic ticket implementation
- Programmatic self-review / `post-verify`
- Gemini adapter support in the first release of executor-owned subagent review
- Codex App Server integration
- Closeout-stack and multi-worktree artifact reconciliation redesign

---

Son of Anton is no longer in the "is there any real product here?" stage. The delivery engine is real: state machine, worktree orchestration, PR metadata, external AI review polling, and durable artifacts are all working. The beta blocker is not lack of machinery. The beta blocker is credibility.

Today the sharpest product claim is also the least enforced part of the system: the internal adversarial subagent review. And the README currently overstates the degree to which the orchestrator owns execution across agents. This phase is the final pre-beta release gate because it addresses both sides of that credibility gap: one technical, one narrative.

## Phase Goal

This phase should leave the product in a state where:

- For supported runners, internal subagent review is orchestrator-executed rather than execution-agent-asserted, and `open-pr` is blocked unless that review artifact exists and validates.
- A developer can rely on programmatic internal review anywhere a supported review runner is installed and authenticated in the repo environment, regardless of which host execution agent is driving the ticket.
- A developer can choose the supported internal review runner from durable config and override it for a run using the same policy model they already use for boundary mode and review policy.
- The README and beta-facing docs still make a strong product case, but no longer imply that every part of the middle of execution is equally programmatic or equally mature across all agent platforms.

## Committed Scope

### 1. Programmatic subagent review for supported runners

- Add an orchestrator-owned subagent-review execution step for ticketed delivery.
- Support two runner families in the beta-ready release:
  - Claude via `claude -p`
  - Codex via Exec
- Treat both runners as committed scope, not stretch scope.
- Persist durable review execution artifacts proving:
  - what was reviewed
  - which runner performed the review
  - what outcome was returned
  - what head SHA was reviewed
- Require valid subagent-review execution evidence before `open-pr` can proceed when subagent review is enabled by policy.
- Fail closed for supported-policy runs when the runner is unavailable, times out, or returns malformed output.

### 2. Runtime policy and config integration

- Extend `orchestrator.config.json` so the supported subagent-review runner and its settings are durable repo-level configuration.
- Make those settings participate in the same persisted `runPolicy` model already used by `/soa execute` and `/soa resume`.
- Support one-run override behavior at the command surface so a developer can switch or patch the configured review runner for a run without rewriting repo defaults.
- Keep the policy model coherent: no special-case side channel for runner selection outside the existing execute/resume override story.
- Make the product boundary runner-based rather than host-agent-based: if the supported runner is installed and authenticated, SoA can enforce internal review even when the host execution agent itself has weak or no native subagent semantics.

### 3. Honest-but-strong beta messaging

- Rewrite the README and the smallest set of directly beta-facing delivery docs where the current wording materially overclaims product guarantees.
- Preserve the core stance:
  - Son of Anton is a real delivery orchestrator, not a prompt pack
  - it works across multiple agent ecosystems
  - it provides meaningful structure and review discipline
- Narrow or clarify the weak points:
  - the internal subagent-review guarantee is strong only where the orchestrator can execute it programmatically
  - cross-agent compatibility exists, but platform maturity is not perfectly uniform
  - the orchestrator owns more of the middle than typical agent workflows, but not every step is equally compelled

## Explicit Deferrals

- **Programmatic ticket implementation** — the execution agent should remain the primary implementer; moving implementation into a headless runner is not the highest-value trust improvement.
- **Programmatic self-review** — `post-verify` remains a local discipline and state boundary, not a separate executor-owned review product in this phase.
- **Gemini support in the first programmatic subagent-review release** — viable later, but not required for the final pre-beta release gate.
- **Codex App Server integration** — promising longer-term surface, but not required to prove the concept now.
- **Multi-worktree closeout artifact reconciliation redesign** — real pain point, but secondary to the internal review credibility gap for beta readiness.
- **Broader standalone PR workflow redesign** — this phase is about ticketed delivery credibility, not reshaping the standalone path.

## Exit Condition

When this phase is complete, a skeptical beta user can truthfully be told:

Son of Anton has a real orchestrator core, and for supported internal review runners it now proves the adversarial review step instead of merely asking the execution agent to attest that it happened. The public docs describe that boundary accurately without retreating into mushy caveats. A developer can run the product, understand what is guaranteed, and not feel misled by the README after the first real phase. If Claude CLI or Codex Exec is installed and authenticated, the internal subagent-review guarantee travels with the runner rather than depending on the host agent's native subagent behavior.

## Retrospective

`required` — This phase changes the trust boundary of a core delivery step and defines the final pre-beta product story. Both the technical contract and the product narrative are likely to shape every later phase and every beta user's first impression.
