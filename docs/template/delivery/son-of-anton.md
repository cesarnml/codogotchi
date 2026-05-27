# Son-of-Anton

Son-of-Anton is the dev-facing doctrine behind this repo's AI-assisted workflow.

It is not a claim that AI should be tightly micromanaged.
It is not a claim that stacked PRs are sacred.
It is not a generic "move fast with agents" slogan.

It is a practical answer to a specific solo-developer problem:

- you want AI to run long enough to do meaningful end-to-end work
- you do not want to surrender authorship, reviewability, or control of how the software evolves

Son-of-Anton exists to hold those two truths together.

## The Problem It Solves

AI-assisted development creates a recurring tension:

- long-running AI sessions preserve context and unlock real momentum
- large AI-generated diffs quickly exceed what a human can review with confidence

Most workflows collapse toward one of two bad extremes:

- constant interruption and short-session vibe coding that never quite lands a coherent slice
- monolithic AI output that the developer is expected to trust or rubber-stamp

Son-of-Anton rejects both.

The point is to let the AI cook inside a bounded delivery model that keeps the human genuinely in control.

## Core Stance

Son-of-Anton is a slice-based, gate-enforced, AI-assisted delivery workflow for a solo developer.

The core idea is:

- let AI run for long enough to produce real progress
- force that progress to surface as reviewable slices
- preserve durable context between slices and sessions
- require explicit human control points before the workflow advances

That is the product.

Stacked PRs are one sensible delivery mechanism for this on GitHub because they keep slices reviewable and ordered. They are useful, but they are not the essence. The essence is:

- slice
- review gate
- explicit advance

## The Three Developer Control Points

Son-of-Anton assumes the developer stays directly engaged at three moments:

1. Ideation into concrete product goals

The developer is responsible for deciding where the product should go next, based on current state, pain points, missing functionality, and value to the end user.

2. Approval of the decomposed delivery slices

The developer reviews the planned phase/epic decomposition and decides whether the tickets are thin enough, reviewable enough, and aligned with the intended product boundary.

3. Final review and approval of delivered slices

The developer reviews what the AI actually produced and decides whether a slice is acceptable to merge or advance.

Between those control points, the AI should have room to move. Son-of-Anton is not about constraining the agent every minute. It is about being strict about the boundaries that matter.

## What This Workflow Optimizes For

Son-of-Anton optimizes for:

- reviewability over raw output volume
- durable artifacts over chat-memory dependence
- explicit advancement over implicit momentum
- preserving developer ownership over outsourcing judgment

This is why the workflow values:

- thin vertical slices
- ticket-boundary handoffs
- explicit review states
- rationale captured in durable docs
- verification before advancement
- the ability to resume after context loss

The system is designed so the answer to "what happened?" does not live only in an AI thread.

## Durable Context Matters More Than Session Memory

One of the main failure modes in AI-assisted development is that the real state of the work lives in transient conversational memory.

Son-of-Anton treats durable artifacts as first-class:

- plans
- ticket docs
- handoff artifacts
- review outcomes
- rationale notes

These are not decorative process leftovers. They are the session bridge.

They make it possible to stop, resume later, switch threads, or recover from drift without pretending the AI will perfectly remember the earlier context.

## Planning Passes And `soa-grill-me`

For new product-scope expansion, Son-of-Anton requires an explicit planning pass before implementation.

That planning pass should:

- use `soa-grill-me` to pressure-test scope and decomposition
- end with a developer-approved set of thin, reviewable tickets

Plan Mode can be a useful way to run that conversation, but Son-of-Anton does not require it as a repo policy. The durable requirement is the planning pass plus `soa-grill-me`, not the conversation mode label.

This is an intentional control surface, not optional ceremony.

Without it, the agent is too likely to invent scope while "implementing," and the developer loses the ability to distinguish:

- what was actually intended
- what was opportunistically improvised
- what should have been deferred

## What Son-of-Anton Is Not

Son-of-Anton is not:

- a promise that every repo must use stacked PRs
- a generic automation platform
- a universal replacement for engineering judgment
- a way to avoid reading diffs or making decisions
- a defense of process for its own sake

If a workflow addition does not reduce ambiguity, improve reviewability, or preserve context, it probably does not belong here.

## The Human-AI Contract

The intended contract is simple:

- the human owns product direction and advancement decisions
- the AI owns bounded execution inside the approved slice
- the workflow makes that boundary explicit and durable

That is how a solo developer can use AI heavily without drifting into either chaos or passive authorship.

## On Standalone PRs

Son-of-Anton does not require every meaningful code change to become a new phase/epic.

When a change is smaller, bounded, and still reviewable as one standalone PR, that is a valid path. In this repo, the orchestrator still supports that mode through the standalone `triage-standalone` flow for non-ticket PRs.

The distinction is:

- new product-scope expansion should go through an explicit planning pass, `soa-grill-me`, and approved decomposition
- smaller bounded product, ergonomics, docs, or tooling changes may still use a standalone PR path when the review surface stays human-sized

Standalone does not mean "skip internal review discipline." It means the orchestrator does not track ticket-state checkpoints for that PR shape.

- the post-verify review pass is still required before running standalone `triage-standalone`
- for non-trivial code changes, run a subagent review pass (e.g. `subagent-review --subagent <claude-cli|codex-cli|cursor-cli>`) before `triage-standalone`
- doc-only or genuinely trivial changes may skip the subagent pass
- if a change feels too risky without recorded post-verify / subagent-review gates, it should move to ticketed delivery instead of stretching the standalone path

## Why This Repo Uses It

This repo uses Son-of-Anton because the goal is not merely to generate code faster.

The goal is to be able to say:

> I delivered this with AI help.

instead of:

> I asked an AI to build this and hoped it was right.

That difference is the ethos.
