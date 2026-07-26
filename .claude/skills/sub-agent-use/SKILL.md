---
name: sub-agent-use
description: Run the orchestrated implement/review/adjudicate/integrate loop for the Coder iOS client using the orchestrator, spec-writer, implementer, reviewer-a, reviewer-b, and fixer subagents. Use when starting or resuming work on a TASK-###, decomposing a phase item into a task spec, running dual review on a diff, adjudicating reviewer findings, or deciding what to parallelize. Covers task-spec schema, adjudication rules, loop control, and context hygiene.
---

# Sub-Agent Orchestration

Operating manual for the multi-agent loop that builds the Coder iOS client.
The system is already built and running: six agents in
[`.claude/agents/`](../../agents/), rubrics in [`reviews/`](../../../reviews/),
gates wired as hooks in [`.claude/settings.json`](../../settings.json). Your
job is to run it, not to rebuild it.

Read [`PROGRESS.md`](../../../PROGRESS.md) first on every session. It is the
durable state: task index, phase, architectural invariants.

## Core rules

These are non-negotiable; everything else in this skill is procedure.

1. **One writer per task.** Exactly one implementer (or one fixer during
   remediation) writes source. Orchestrator and both reviewers never write.
2. **Reviewers get clean context.** Pass the original task spec plus the diff
   and nothing else. A reviewer that inherits the implementer's reasoning
   stops being able to catch the implementer's blind spots.
3. **Gates are supreme.** Any failed machine gate is REQUEST_CHANGES no matter
   what either reviewer said.
4. **Union of REQUIRED findings.** Both reviewers' REQUIRED findings must be
   addressed. Never average verdicts; one APPROVE does not cancel the other's
   REQUEST_CHANGES.
5. **Never edit `.pbxproj` / `.xcodeproj`.** Structure changes go through
   `project.yml`. A PreToolUse hook blocks this, but do not rely on the hook.

## The loop

```text
DECOMPOSE → IMPLEMENT → GATE CHECK → DUAL REVIEW → ADJUDICATE → INTEGRATE
                            ↑                           │
                            └──── REMEDIATE ────────────┘
```

### 1. DECOMPOSE

Delegate to `spec-writer` to turn a phase item into `tasks/TASK-###.md`. The
orchestrator (not spec-writer) fills `depends_on`, `blocks`,
`parallel_safe_with`, and `worktree`; it owns the dependency graph.

The spec must be **self-contained**: the implementer sees nothing but this
file. Copy [`tasks/TASK-014.md`](../../../tasks/TASK-014.md) as the shape.
Required sections:

- **Goal**: one paragraph, what and why.
- **In scope**: explicit file list the task MAY create or modify.
- **Explicitly OUT of scope**: files that must not be touched, with the
  reason or owning task.
- **Contracts**: exact public surface, inline. Not a pointer to go read it.
- **Acceptance criteria**: each machine- or reviewer-verifiable.
- **Test requirements**: framework, injection strategy, cases to cover.
- **Definition of Done**: the gate commands, as a checklist.

Spec defects are the dominant failure mode of systems like this one. If
remediation keeps hitting the iteration cap, the spec was under-scoped, so
tighten this step rather than raising the cap.

### 2. IMPLEMENT

Spawn **one** `implementer` with the task id. It reads the spec, writes code
and tests together, runs every gate, and returns a ≤300-word summary plus the
diff and gate outputs.

Tests ship with the implementation. Never split them into a follow-up task.

### 3. GATE CHECK

All four must pass before review. Substitute the task's module for `<M>`:

```bash
swift build --package-path Modules/<M> -Xswiftc -strict-concurrency=complete
swift test  --package-path Modules/<M>
swiftlint lint --strict Modules/<M>
swift-format lint -r Modules/<M>
```

A failed gate sends the task straight back to REMEDIATE and counts as an
iteration. Do not spend reviewer tokens on a red diff.

### 4. DUAL REVIEW

Spawn `reviewer-a` and `reviewer-b` **in parallel**. They are read-only, so
concurrency is safe. Give each the original spec and the diff.

- `reviewer-a` (sonnet): spec conformance, correctness, test adequacy.
  Rubric: [`reviews/RUBRIC-A.md`](../../../reviews/RUBRIC-A.md)
- `reviewer-b` (opus): security, concurrency, iOS architecture.
  Rubric: [`reviews/RUBRIC-B.md`](../../../reviews/RUBRIC-B.md)

The split is deliberate: different rubrics, different model tiers. Reviewer-B
running a different model than the implementer reduces self-preference bias.
Do not add a third reviewer. Sharpen the two rubrics instead.

Write each to `reviews/TASK-###-reviewA.md` and `-reviewB.md`. Every finding
carries `id`, `severity`, `class`, `location`, `evidence`, `rule`, and
`required_change`. The `id` is what makes resolution checkable later.

- `class: REQUIRED` = blocker or major. Blocking.
- `class: OPTIONAL` = minor or nit. Logged, not blocking.

### 5. ADJUDICATE

Orchestrator only, deterministic, with no LLM debate between reviewers. Write
`reviews/TASK-###-adjudication.md` recording gate status, both verdicts,
REQUIRED findings with fix status, OPTIONAL findings, and the decision. See
[`TASK-013-adjudication.md`](../../../reviews/TASK-013-adjudication.md).

Apply rules 3 and 4 from Core rules. On genuine conflict (A requires a pattern
B forbids), the orchestrator decides using architectural context and records a
one-line ADR in `docs/adr/`. The orchestrator holds the broad context, so it
is the right place to reconcile, not the reviewers.

### 6. REMEDIATE

Spawn `fixer` with **only the enumerated REQUIRED findings**. No new scope: if
the fixer wants to change anything else, it returns to the orchestrator.

Re-review is not "trust the fixer." Reviewer-A confirms each prior REQUIRED
finding id is resolved, and all gates re-run. Only when the REQUIRED union is
empty and gates are green does the task reach INTEGRATE.

**`MAX_REMEDIATION_ITERATIONS = 3`.** On the third failure, stop and escalate
to a human with the outstanding findings and the diffs attempted.

### 7. INTEGRATE

Orchestrator merges the worktree, re-runs gates on the merge result, and
updates `PROGRESS.md`. Then `/clear` before the next task.

## Escalate to a human immediately

Do not spend iterations on these:

- Task requires editing `.pbxproj` or the `Package.swift` target graph.
- Task changes a shared protocol consumed by two or more modules.
- A reviewer flags a security blocker with no safe fix visible.
- The two reviewers hard-conflict on an architectural invariant.
- Anything on the device-only list below.

## Parallelism policy

**Safe to parallelize**: disjoint SPM modules, each in its own worktree
(`wt/task-###`), once their consumed CoderKit contracts are frozen:
CoderKit ↔ TerminalFeature ↔ WebAppFeature. Also independent leaf tasks
within a module that share no file.

**Must be serialized:**

- Anything touching `project.yml` or the `Package.swift` target graph.
- Shared protocol or contract changes. Freeze the contract as its own task
  first, then fan out consumers.
- DI wiring in AppShell, `UIScene` / `WindowGroup` composition.
- Phase 0 scaffolding and Phase 5 polish; inherently cross-cutting.

Cap real parallelism at **2-3 concurrent tasks**. Beyond that, coordination
overhead and simulator contention cost more than the throughput gains.
Conflicting parallel writes are the single most common way systems like this
fail, so when in doubt, serialize.

## Context hygiene

- **One task per session.** Run a task to INTEGRATE, then `/clear`. This is
  the highest-leverage habit in the whole system.
- **`/clear` between tasks; `/compact` only within one** long task that
  approaches the window limit.
- **Keep in the orchestrator's context:** task index, phase state,
  architectural invariants, adjudication rules. Nothing else.
- **Offload to files:** specs, diffs, review outputs, build logs. Subagents
  read and write them; they return ≤300-word summaries. The orchestrator
  passes lightweight references (paths, task ids), never pasted content.

## Agents cannot verify these

Device-only behavior belongs on a human checklist, never in a Definition of
Done:

- Face ID / LocalAuthentication biometric flow.
- VNC touch input and gesture mapping; real touch latency.
- Hardware-keyboard behavior, keyboard accessory bar, Stage Manager.
- CA trust and self-signed cert acceptance against the real deployment.
- Cookie injection into WKWebView against the live server. Session semantics
  differ from mocks.
- Clipboard bridging across the WKWebView/native boundary.

Agents can verify: build success, unit and integration tests, snapshot tests.
Treat any simulator-driving MCP's UI verification as advisory.

## Background

[`reference/background.md`](reference/background.md) holds the research this
design came from: the Anthropic orchestrator-worker and context-engineering
posts, Cognition's single-writer and clean-context-review findings, the MAST
failure taxonomy, and the bias literature behind the two-reviewer split. Read
it when you want to know *why* a rule exists or are considering changing one.
It is background, not procedure; the rules above govern.
