# Appendix G, Agent Orchestration & Context Management

*Appendable specification for the Coder iOS/iPadOS client engineering plan. Harness assumption: Claude Code (verified against docs current to ~v2.1.218, July 2026). Audience: implementing engineer. Sourcing tags used throughout. **[DOC]** = official Anthropic/Apple/tool documentation; **[FIELD]** = practitioner convention; **[INFER]** = my reasoning to be validated against your setup. Claude Code's subagent surface has changed materially across v2.1.x, re-check §G.3 field names against `code.claude.com/docs/en/sub-agents` before you build.*

---

## TL;DR

- **Adopt a single-threaded orchestrator with one implementer-writer per scoped task, two independent clean-context reviewers per diff, and deterministic machine gates (Swift 6 compile + `swift test`/`xcodebuild test` + SwiftLint) that are enforced by hooks, not requested in prose.** This is precisely the architecture both Anthropic and Cognition independently converged on for *code* (as opposed to research): writes stay single-threaded; extra agents contribute *intelligence*, not concurrent *actions*.
- **Parallelize only across genuinely independent SPM modules (CoderKit vs. TerminalFeature vs. WebAppFeature), each in its own git worktree; serialize everything that touches the Xcode project file, shared protocols/DI wiring, or the AppShell.** Coding has far fewer safely-parallel tasks than research, and conflicting parallel writes are the dominant documented failure mode.
- **Keep the orchestrator's context clean by offloading all state to the filesystem** (`tasks/`, `reviews/`, `PROGRESS.md`, ADRs) and running **one task per session** with `/clear` between tasks. The orchestrator holds only a task index + phase state + architectural invariants; subagents burn tokens in isolated windows and return ~1-2 KB summaries.

---

## Key Findings

1. **The two most-cited industry sources agree on the shape of the answer for coding.** Anthropic's orchestrator-worker research system beat single-agent Opus by a wide margin but is a *research* pattern; Anthropic explicitly cautions it does not transfer wholesale to coding. Cognition, which initially argued *against* multi-agents, now ships a narrow multi-agent pattern that maps almost exactly onto your four stated requirements. Your requirement set (scoped tasks → single implementer → two reviewers → incorporate all feedback) is the validated pattern, not a speculative one.

2. **Clean-context review is a feature, not a limitation.** The counterintuitive, empirically-backed finding is that the reviewer should *not* inherit the implementer's context. A fresh reviewer reasons backward from the diff, escapes context rot, and catches issues the implementer literally cannot see. Give each reviewer the **original task spec + the diff**, nothing else, which is exactly what you asked for.

3. **Deterministic gates beat LLM judgment wherever they exist, and Swift/iOS is unusually rich in them.** Swift 6 strict-concurrency is a compile-time data-race checker; `swift test` + `xcodebuild test`, SwiftLint, and `swift-format --lint` are all machine-checkable. Structure every task so it has at least one binary pass/fail gate, and wire those gates as Claude Code hooks so they run automatically.

4. **The single biggest iOS-specific hazard for agents is the `.xcodeproj`/`.pbxproj` file.** It is merge-hostile and LLM-hostile; agents routinely corrupt it. The mitigation is architectural: keep the project structure in local SPM packages and/or generate the `.xcodeproj` declaratively (XcodeGen/Tuist) so agents edit YAML/`Package.swift`, never the pbxproj.

5. **Two reviewers with *different* rubrics is the right count**, enough to cover orthogonal lenses (correctness/tests vs. security/architecture) and to break single-judge biases, without the coordination overhead and diminishing returns of a larger panel.

---

## Details

### G.1 Evidence base and the core architectural decision

**Anthropic, "How we built our multi-agent research system" (Jun 13, 2025) [DOC].** Orchestrator-worker: a lead agent plans, spawns 3-5 subagents in parallel with their own context windows, each returns a distilled summary. Key quantified claims, verbatim: *"a multi-agent system with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents outperformed single-agent Claude Opus 4 by 90.2% on our internal research eval"*; and on cost, *"agents typically use about 4× more tokens than chat interactions, and multi-agent systems use about 15× more tokens than chats."* Critically for us, Anthropic scopes this away from coding: *"most coding tasks involve fewer truly parallelizable tasks than research, and LLM agents are not yet great at coordinating and delegating to other agents in real time."* Also load-bearing for your task-spec format: *"Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries. Without detailed task descriptions, agents duplicate work, leave gaps, or fail to find necessary information."*

**Cognition, "Don't Build Multi-Agents" (Jun 12, 2025) and "Multi-Agents: What's Actually Working" (Apr 22, 2026) [DOC].** Two principles that must constrain your design: *(1) Share context, and share full agent traces, not just individual messages; (2) Actions carry implicit decisions, and conflicting decisions carry bad results.* The consequence for coding: **writes must stay single-threaded.** Their 2026 follow-up reports the review loop working in production: *"even on PRs written by Devin, Devin Review catches an average of 2 bugs per PR, of which roughly 58% are severe (logic errors, missing edge cases, security vulnerabilities)."* And the crucial design guidance that validates your dual-review requirement: *"we found this technique to work best when the coding and review agents do not share any context beforehand"*, because a clean context escapes context rot and forces the reviewer to reason backward from the implementation.

**MAST, Cemri et al., "Why Do Multi-Agent LLM Systems Fail?" (UC Berkeley, arXiv:2503.13657, NeurIPS 2025) [DOC].** 1,642 annotated traces across 7 frameworks, 14 failure modes, inter-annotator agreement Cohen's κ = 0.88. Failures cluster as **Specification/System-Design 41.77%, Inter-Agent Misalignment 36.94%, Task Verification 21.30%.** The takeaway: **most multi-agent failures are your fault (bad specs, weak verification), not the model's.** This is why §G.4 (task schema) and §G.9 (gates) get the most detail.

**Anthropic, "Effective context engineering for AI agents" (Sep 29, 2025) [DOC].** Context is a finite resource subject to *context rot* (accuracy degrades as tokens grow). The three long-horizon techniques: **compaction, structured note-taking (filesystem as memory), and sub-agent architectures**, each subagent *"might explore extensively, using tens of thousands of tokens or more, but returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens)."* This is the mechanical basis for §G.8 (orchestrator context hygiene).

**Decision.** Use the orchestrator-worker skeleton from Anthropic but constrain it with Cognition's single-writer rule. Concretely: **the orchestrator and reviewers never write source; exactly one implementer (plus optionally one fixer) writes per task; reviewers run on clean context; every task ends at a deterministic gate.**

---

### G.2 How Claude Code subagents actually work (mechanics you're relying on) [DOC]

- **Context isolation.** A subagent runs in a fresh conversation. Only its final message returns to the parent; all intermediate reads/tool calls stay in the subagent. The *only* channel parent→subagent is the Agent-tool prompt string, so **the task spec must be self-contained** (file paths, contracts, acceptance criteria all inline).
- **What a subagent inherits:** its own system prompt (the agent file body) + the Agent-tool prompt + project `CLAUDE.md` + tool definitions. It does **not** inherit the parent's conversation history or system prompt. (This is exactly the clean-context property Cognition exploits for reviewers.)
- **Tool restriction** per subagent: omit `tools` to inherit all; list tools to restrict. A tool left out is simply absent (no prompt, no error). Read-only reviewers get `Read, Grep, Glob` (+ `Bash` only if they must run tests).
- **Model override** per subagent via `model:`, accepts `sonnet`, `opus`, `haiku`, `fable`, `inherit`, or a full model ID.
- **Version-sensitive behaviors (re-verify):** As of **v2.1.198**, subagents run **in the background by default** and the `/agents` interactive wizard was removed (create/edit files directly or ask Claude). Nesting: from v2.1.172-v2.1.216 subagents could nest up to 5 layers by default; **post-v2.1.216 nesting is OFF by default** and gated by `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (set to `2`+ to allow). Concurrency caps: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20), `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (default 200). The subagent-model override env var is `CLAUDE_CODE_SUBAGENT_MODEL` and it *overrides per-agent `model:` frontmatter*, leave it unset (`inherit`) so your per-agent choices in §G.3 take effect.
- **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH ≥ 2` is required** for your design, because the *orchestrator is itself run as (or drives) an agent that must spawn implementer/reviewer subagents.* [INFER, validate: if you drive the orchestrator as the main interactive session rather than a subagent, depth 1 suffices; if you wrap it as an `--agent`, you need depth ≥ 2.]

---

### G.3 Agent roster (minimal effective set)

Recommend **6 roles**. Do *not* add more; MAST shows role proliferation increases mis-coordination. Fold "test-author" into the implementer (tests are part of Definition of Done, not a separate handoff; separating them invites the Flappy-Bird inconsistency Cognition warns about).

| Role | Model | Tools | Writes source? | Purpose |
| --- | --- | --- | --- | --- |
| **orchestrator** | opus | Read, Grep, Glob, Bash, Agent, TodoWrite | No | Decompose plan → tasks; delegate; adjudicate reviews; route fixes; integrate; own `PROGRESS.md` |
| **spec-writer** | opus | Read, Grep, Glob, Write(`tasks/**`) | No (specs only) | Turn a phase item into a fully-scoped `TASK-###.md` |
| **implementer** | sonnet | Read, Edit, Write, Grep, Glob, Bash | **Yes (sole writer)** | Implement one task incl. tests; make gates green |
| **reviewer-A** (spec+correctness+tests) | sonnet | Read, Grep, Glob, Bash | No | Verify diff against spec & acceptance criteria; run tests; find logic bugs |
| **reviewer-B** (security+architecture+iOS idioms) | opus | Read, Grep, Glob | No | Adversarial: concurrency, Keychain, retain cycles, main-actor, secrets, API misuse |
| **fixer** | sonnet | Read, Edit, Write, Grep, Glob, Bash | **Yes** | Apply adjudicated findings; re-green gates |

**Model rationale [FIELD]:** Sonnet is the cost/quality default for implementation and covers ~most coding work; Opus is reserved for the two roles where reasoning depth pays off: decomposition/adjudication (orchestrator) and the adversarial security/architecture review (reviewer-B). Using a *different* model for reviewer-B than for the implementer also structurally reduces self-preference bias (see §G.5). Haiku is fine for a read-only **scout** if you add one for API discovery, but it's optional, the built-in `Explore` subagent already covers read-heavy codebase search. Reviewer-A on Sonnet keeps the two reviewers on different model tiers, which is deliberate.

**`.claude/agents/reviewer-B.md`, copy-paste template** (markdown file, YAML frontmatter, body = system prompt) [DOC, field names verified v2.1.x]:

```markdown
---
name: reviewer-b-security-arch
description: >
  Adversarial security, concurrency, and iOS-architecture reviewer. Invoke with
  the ORIGINAL task spec plus the diff. Assumes nothing; reasons backward from code.
tools: Read, Grep, Glob
model: opus
---
You are an adversarial iOS security & architecture reviewer for a Swift 6 / SwiftUI
app. You receive an ORIGINAL TASK SPEC and a DIFF. You did not write this code and
share no prior context with the author, use that to your advantage.

Reason backward from the implementation. Question decisions the author may have made
under user pressure or incomplete instructions. Do NOT rubber-stamp.

Evaluate ONLY against the rubric in `reviews/RUBRIC-B.md`. For every finding, output:
  - severity: blocker | major | minor | nit
  - location: file:line
  - evidence: the exact code snippet
  - rule: which rubric item it violates
  - required_change: concrete, minimal fix (do not write the patch)
Classify each as REQUIRED (blocker/major) or OPTIONAL (minor/nit).

End with exactly one verdict line: `VERDICT: APPROVE | REQUEST_CHANGES | REJECT`
A single blocker or major = REQUEST_CHANGES at minimum. Be terse. No praise.
```

The implementer/reviewer-A/fixer/spec-writer/orchestrator files follow the same shape; only `tools`, `model`, and the body change. Keep bodies short and imperative. Anthropic's guidance is that the system prompt should be the *minimal* set of high-signal tokens at the "right altitude" (specific enough to guide, not brittle if-else).

---

### G.4 Task specification schema

MAST says 41.77% of failures are specification/design defects, so this template is the highest-leverage artifact in the whole system. One file per task at `tasks/TASK-###.md`. It must be **self-contained** (the subagent sees nothing else).

```markdown
---
id: TASK-013
title: PTY WebSocket client with reconnect (TerminalFeature)
phase: 2
module: TerminalFeature
depends_on: [TASK-004]        # CoderKit auth/session types
blocks: [TASK-014]            # SwiftTerm view binding
parallel_safe_with: [TASK-011, TASK-012]   # WebAppFeature tasks; different module
context_budget_tokens: 60000
worktree: wt/task-013-pty
---

## Goal
Implement a reconnecting PTY client over URLSessionWebSocketTask that speaks Coder's
reconnecting-PTY protocol, exposing an AsyncStream<Data> of terminal output and an
async send(_:) for input. Reconnect with exponential backoff, resuming the session
by reconnect token.

## In scope (files this task MAY create/modify)
- Sources/TerminalFeature/PTYClient.swift            (new)
- Sources/TerminalFeature/PTYReconnectPolicy.swift   (new)
- Tests/TerminalFeatureTests/PTYClientTests.swift    (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring (orchestrator does this)
- SwiftTerm UIViewRepresentable (TASK-014)
- CoderKit public API (consume only; do not modify)

## Contracts / interfaces it MUST honor
- Consumes `CoderKit.WorkspaceAgent` and `CoderKit.SessionToken` (see @Sources/CoderKit/Models).
- Public surface MUST be:
      public protocol PTYSession: Sendable {
          var output: AsyncStream<Data> { get }
          func send(_ data: Data) async throws
          func resize(cols: Int, rows: Int) async throws
      }
- All public types Sendable; the client is an `actor`. No @MainActor on the client.

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Reconnects after a simulated socket drop within backoff schedule (unit test with a
   mock WebSocket transport injected via protocol).
3. Backoff is capped and jittered; no busy-loop on repeated failure (test asserts call
   spacing).
4. No secrets (session tokens) written to os_log/print (reviewer-B checks).

## Test requirements
- Swift Testing (`@Test`), transport injected via a `PTYTransport` protocol + fake.
- Cover: happy path, single drop+resume, N consecutive failures → gives up with typed error.

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/TerminalFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/TerminalFeature` green
- [ ] `swiftlint lint --strict Modules/TerminalFeature` clean
- [ ] `swift-format lint -r Modules/TerminalFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
```

The **spec-writer** produces this; the **orchestrator** fills `depends_on`/`blocks`/`parallel_safe_with`/`worktree` (it owns the dependency graph). Note the spec carries a **context budget**, this is the mechanism that keeps implementers from over-exploring.

---

### G.5 Dual-review protocol and bias mitigation

Your requirement: two reviewers each receive **the original task spec + the output (diff)** and evaluate. Here is how to make the two reviewers genuinely distinct and the review trustworthy.

**Why two, and why different:** A single LLM judge exhibits documented, reproducible biases, **position bias, verbosity bias, and self-preference/self-enhancement bias** (a judge scores its own family's output measurably higher). Mitigations, applied here [DOC, multiple arXiv sources + Cognition]:

- **Different rubrics / lenses** (reviewer-A = spec-conformance + correctness + test adequacy; reviewer-B = adversarial security + architecture + iOS idioms). Decomposing into dimensions reduces global-stylistic-cue dominance.
- **Different model tier for reviewer-B (opus) than the implementer (sonnet)**, reduces self-preference.
- **Clean context** for both reviewers (Cognition's finding), no implementer trace, no praise inheritance.
- **Read-only tools**, the reviewer *cannot* silently "fix and approve"; it must produce findings. (Tool restriction is a correctness feature, not just safety.)
- **Evidence + severity required** for every finding (see agent body in §G.3), forces grounding, defeats vague rubber-stamping.

**Review output schema** (each reviewer returns this; orchestrator parses it):

```yaml
task: TASK-013
reviewer: B
verdict: REQUEST_CHANGES          # APPROVE | REQUEST_CHANGES | REJECT
findings:
  - id: B1
    severity: blocker             # blocker | major | minor | nit
    class: REQUIRED               # REQUIRED (blocker/major) | OPTIONAL (minor/nit)
    location: PTYClient.swift:88
    evidence: "os_log(\"connect token=\\(token)\")"
    rule: RUBRIC-B/secrets-in-logs
    required_change: "Remove token from log; log a redacted session id only."
  - id: B2
    severity: major
    class: REQUIRED
    location: PTYClient.swift:41
    evidence: "final class PTYClient { var socket: ... }"
    rule: RUBRIC-B/concurrency
    required_change: "Convert to `actor`; `socket` is mutable shared state."
```

**Adjudication / disagreement resolution (orchestrator, deterministic rules, no LLM debate):**

1. **Union of REQUIRED findings** from both reviewers must be addressed. (Do not average verdicts; do not let one APPROVE cancel the other's REQUEST_CHANGES.)
2. **Deterministic gates are supreme.** If any machine gate fails, the task is REQUEST_CHANGES regardless of what either reviewer said.
3. **Genuine conflict** (reviewer-A says a pattern is required, reviewer-B says it's forbidden) → orchestrator uses its full task/architectural context to decide, records the decision as a one-line ADR, and passes the resolved instruction to the fixer. Cognition's key point: the *orchestrator*, holding the broad context, is the right place to filter/reconcile reviewer output, this "communication bridge" is what prevents looping and out-of-scope churn.
4. **OPTIONAL findings** are logged to `reviews/TASK-###-optional.md` and not blocking.

Reviewers may run **in parallel** (they only read), this is a safe use of concurrency because there are no writes.

---

### G.6 The full loop (state machine)

```text
                 ┌─────────────┐
   phase item →  │  DECOMPOSE  │  orchestrator → spec-writer → tasks/TASK-###.md
                 └──────┬──────┘
                        v
                 ┌─────────────┐
                 │  IMPLEMENT  │  one implementer, own worktree; makes gates green
                 └──────┬──────┘
                        v
                 ┌─────────────┐   gates run automatically (hooks)
                 │  GATE CHECK │──fail──┐
                 └──────┬──────┘        │ (counts as an iteration)
                    pass│               │
                        v               │
                 ┌─────────────┐        │
                 │ DUAL REVIEW │  A + B in parallel, clean context, spec+diff
                 └──────┬──────┘        │
                        v               │
                 ┌─────────────┐        │
                 │  ADJUDICATE │  orchestrator: union of REQUIRED + gate supremacy
                 └──┬───────┬──┘        │
        all REQUIRED│       │ findings  │
        cleared     │       v remain    │
                    │  ┌─────────────┐  │
                    │  │  REMEDIATE  │──┘  fixer applies findings; re-green gates
                    │  └─────────────┘
                    v
              ┌─────────────┐
              │  INTEGRATE  │  orchestrator merges worktree → main; updates PROGRESS.md
              └─────────────┘
```

**Loop control (prevents infinite review) [INFER/FIELD, tune to taste]:**

- **`MAX_REMEDIATION_ITERATIONS = 3`** per task. Each REMEDIATE→re-review counts as one. On the 3rd failure, **escalate to human** with a written summary of the outstanding REQUIRED findings and the diffs attempted. (This mirrors Claude Code's own built-in `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` default of 8 consecutive Stop-hook blocks before it force-ends a turn, keep your product-level cap lower.)
- **No new scope during remediation.** The fixer addresses only the enumerated findings; if it wants to change anything else, it must return to the orchestrator (prevents scope creep / new bugs).
- **Verify feedback was incorporated:** re-review is not "trust the fixer." Reviewer-A re-runs and must confirm each prior REQUIRED finding id is resolved (the finding `id`s from §G.5 make this checkable), and all gates re-run. Only when the union of REQUIRED findings is empty *and* gates are green does the task reach INTEGRATE.
- **Escalation triggers** (immediate human, don't spend iterations): task requires editing `.pbxproj`/`Package.swift` target graph; task touches a shared protocol consumed by ≥2 modules; a reviewer flags a security blocker it cannot see a safe fix for; two reviewers hard-conflict on an architectural invariant.

---

### G.7 Repository layout for agent artifacts

```text
.
├─ .claude/
│  ├─ agents/            orchestrator.md, spec-writer.md, implementer.md,
│  │                     reviewer-a.md, reviewer-b.md, fixer.md
│  ├─ commands/          new-task.md, implement.md, review.md, adjudicate.md, integrate.md
│  ├─ settings.json      hooks (gates), env (subagent depth), permissions
│  └─ CLAUDE.md          lean project memory (see §G.8)
├─ docs/
│  ├─ plan/              the existing engineering plan + THIS appendix
│  └─ adr/               ADR-0001…  one-line decisions from adjudication
├─ tasks/                TASK-001.md … (specs; git-tracked)
├─ reviews/
│  ├─ RUBRIC-A.md  RUBRIC-B.md
│  └─ TASK-###-reviewA.md  TASK-###-reviewB.md  TASK-###-optional.md
├─ PROGRESS.md           phase state + task index + status (orchestrator-owned)
├─ project.yml           XcodeGen spec (generated .xcodeproj is gitignored)
├─ Package.swift         umbrella or per-module Package.swift under Modules/
└─ Modules/
   ├─ CoderKit/  CoderAuth/  TerminalFeature/  WebAppFeature/  CoderUI/  AppShell/
```

`PROGRESS.md` is the durable state that lets you **resume across days/weeks**: it is the first thing the orchestrator reads on a fresh session and the last thing it writes. Structure it as a table (`TASK-### | phase | module | status | worktree | last-gate`), because Anthropic's note-taking guidance shows this is what survives context resets.

---

### G.8 Orchestrator context hygiene

**What stays in the lead context (small, durable):** the task index (`PROGRESS.md`), current phase state, architectural invariants (module boundaries, public contracts, Swift 6 rules), and the *adjudication rules* from §G.5-G.6. Nothing else.

**What gets offloaded to files (everything voluminous):** task specs, diffs, review outputs, exploration results, build logs. Subagents do the reading/writing; they return ≤300-word summaries. This is the "just-in-time context" + "structured note-taking" pattern from Anthropic's context-engineering post, the orchestrator keeps *lightweight identifiers* (file paths, task ids) and loads detail on demand.

**Discipline rules [FIELD, strongly recommended]:**

- **One task per session.** Run the loop for TASK-013 to INTEGRATE, then `/clear` before TASK-014. This is the highest-leverage habit; it keeps the orchestrator's window from accumulating cross-task noise (context rot).
- **`/clear` vs `/compact`:** `/clear` between *tasks* (you want a clean slate, state is in files). `/compact` only *within* a long single task if you approach the window limit mid-implementation. Note `/compact` re-reads all instruction files (CLAUDE.md, rules) from scratch after compacting, so it's not free.
- **`CLAUDE.md` is lean and imperative,** not a manual. Rule of thumb [FIELD]: *if a violation would fail CI, it belongs in a hook, not CLAUDE.md; if it would make a reviewer raise an eyebrow, it belongs in CLAUDE.md.* Use `@import` (e.g. `@docs/adr/INDEX.md`) to pull in shared standards, but remember imports expand inline and still cost tokens.

**Skeleton `CLAUDE.md`:**

```markdown
# Coder iOS, Agent Operating Rules
- Swift 6, strict concurrency = complete. New code MUST compile with zero concurrency warnings.
- Min iOS/iPadOS 17. SwiftUI + UIKit interop. Local SPM packages under Modules/.
- NEVER edit *.xcodeproj / *.pbxproj. Structure changes go through project.yml (XcodeGen), humans/orchestrator only.
- One writer per task. Reviewers and orchestrator never edit source.
- Secrets (tokens, cookies) NEVER logged. Keychain via CoderAuth only.
- New tests use Swift Testing (@Test/#expect). Every task ships tests for its acceptance criteria.
- Definition of Done = all gates in the task's DoD block are green AND diff is in-scope.
- Full plan: @docs/plan/  Current state: @PROGRESS.md
```

---

### G.9 Deterministic gate definitions and hook wiring

**Exact commands agents must run and pass.** Pure-SPM modules (CoderKit, CoderAuth logic, TerminalFeature protocol layer) use the fast `swift` toolchain; anything needing a simulator/UIKit uses `xcodebuild`.

```bash
# Pure SPM module, fast loop (no simulator)
swift build  --package-path Modules/CoderKit -Xswiftc -strict-concurrency=complete
swift test   --package-path Modules/CoderKit

# App / UIKit-dependent / UI tests, needs a simulator destination
set -o pipefail && xcodebuild test \
  -scheme CoderApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' \
  | xcbeautify   # parseable, token-cheap output for the agent

# Lint / format gates
swiftlint lint --strict Modules/<M>
swift-format lint -r -s Modules/<M>
```

`xcbeautify` is essential: raw `xcodebuild` output is thousands of lines and will blow the agent's context; xcbeautify (Swift static binary, `brew install xcbeautify`) compresses it to parseable pass/fail. For CI use `NSUnbufferedIO=YES xcodebuild … 2>&1 | xcbeautify --renderer github-actions` (or the Gitea/TeamCity renderer). [DOC, tuist/xcbeautify]

**Wire gates as hooks so they are *enforced*, not requested.** The distinction matters: CLAUDE.md instructions are advisory; hooks are deterministic and always run. `.claude/settings.json` [DOC, schema verified]:

```json
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/block-pbxproj.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/format-and-lint.sh" }
        ]
      }
    ]
  }
}
```

`block-pbxproj.sh` (a `PreToolUse` gate, **exit code 2 blocks the tool call**, stderr is fed back to Claude) [DOC]:

```bash
#!/bin/bash
path=$(jq -r '.tool_input.file_path // empty' < /dev/stdin)
case "$path" in
  *.pbxproj|*.xcodeproj/*)
    echo "BLOCKED: agents must not edit Xcode project files. Change project.yml instead." >&2
    exit 2 ;;
esac
exit 0
```

**Two hook caveats to honor [FIELD/DOC]:**

- Do **not** block `Edit`/`Write` mid-plan for *lint/test* reasons, blocking at write time breaks multi-step reasoning. Run tests/format on `PostToolUse` (after the write) or as a `Stop`/`SubagentStop` gate, and let exit-code-2 blocking be reserved for genuinely forbidden actions (pbxproj, secret files, `rm -rf`).
- A `Stop` hook defined in a subagent's frontmatter is automatically converted to a `SubagentStop` scoped to that subagent, use this to make the implementer's "run all gates before you're allowed to finish" check fire only when the implementer stops, not the whole session.

---

### G.10 Parallelism policy

**Safe to parallelize (independent SPM modules, separate worktrees):**

- CoderKit (API client/models) ↔ TerminalFeature (PTY) ↔ WebAppFeature (WKWebView host), once their *consumed* CoderKit contracts are frozen. These touch disjoint files.
- Within a module, independent leaf tasks with no shared file.

**Must be serialized (single-threaded):**

- **Anything touching the Xcode project / `project.yml` / `Package.swift` target graph.** This is the merge-hostile surface; one writer, orchestrator only.
- **Shared protocol / contract changes** (e.g. a change to a CoderKit public type consumed by Terminal + WebApp). Freeze the contract *first* as its own serialized task, then fan out consumers.
- **DI wiring in AppShell**, `UIScene`/`WindowGroup` composition, global state, implicit-decision magnet.
- Phase 0 (scaffolding/CI) and Phase 5 integration polish (multi-window, Stage Manager), inherently cross-cutting.

**Git worktrees [DOC, Claude Code supports `isolation: worktree` in agent frontmatter, or ask "use worktrees for your agents"]:** give each parallel implementer its own worktree so file edits never collide; shared `.git` keeps history consistent. Practical guardrails [FIELD]: agree a branch prefix (`wt/task-###`); expect a **practical ceiling around 4-5 concurrent worktrees on a laptop** (compile/simulator resource contention, relevant given your 3×3090 box is for inference, not Xcode); untracked files can block auto-cleanup; the orchestrator merges completed worktrees back serially and re-runs gates on the merge. **[INFER]** Given a 6-10 week / ~10-user scope, I'd cap real parallelism at **2-3 module tasks at once**; the coordination overhead above that isn't worth it for this project size.

---

### G.11 iOS-specific realities agents cannot handle (define human-verified gates)

Agents **cannot** run TestFlight/device builds or touch a physical iPad. The following must be on a **human manual-verification checklist** per relevant phase, *not* in an agent's Definition of Done [DOC/INFER]:

- **Face ID / LocalAuthentication** biometric flow (simulator can enroll a fake face but real behavior needs device).
- **VNC touch input & KasmVNC/noVNC gestures** (Phase 4), real touch latency/mapping.
- **Hardware-keyboard behavior & the keyboard accessory bar** (Phase 5), Stage Manager, external keyboard, iPad multitasking.
- **CA trust / self-signed cert acceptance** against your actual Coder deployment (your homelab PKI).
- **Cookie injection into WKWebView** for VS Code Web / subdomain apps against the live server (Phase 3), session semantics differ from mocks.
- **Clipboard bridging** across the WKWebView/native boundary.

What agents *can* verify on the simulator: build success, unit/integration tests, SwiftUI rendering via snapshot tests, and, if you install it, **XcodeBuildMCP** (getsentry/XcodeBuildMCP; per its v2.3.2 docs, *82 tools across 15 workflows* for build/test/simulator/LLDB; created by Cameron Cooke, acquired by Sentry in 2025, 4,000+ stars) plus **iOS Simulator MCP** (joshuayoes; tap/type/screenshot/accessibility-tree via `simctl`+IDB) for accessibility-tree-driven UI checks. Assessment [FIELD]: XcodeBuildMCP is the most-adopted, actively-maintained option and turns wall-of-text `xcodebuild` output into structured JSON the agent can act on, worth installing for Phases 2-4; simulator-driving MCPs are useful but treat their UI verification as *advisory*, with humans owning the checklist above.

**Testing framework guidance:** default new tests to **Swift Testing** (`@Test`/`#expect`/`#require`, `@Suite`), which ships with Swift 6/Xcode 16 and is Apple's stated direction; keep **XCUITest** for UI automation (Swift Testing does not do UI testing) and leave existing XCTest in place, the two coexist in one target. Swift Testing runs in parallel by default, which surfaces real isolation bugs (a feature under Swift 6). Snapshot testing (e.g. a SwiftUI snapshot library) is realistic for CoderUI screens and gives agents a deterministic visual gate.

---

### G.12 Anti-patterns and mitigations

| Anti-pattern (source) | Mitigation in this spec |
| --- | --- |
| **Parallel writers making conflicting implicit decisions** (Cognition Flappy-Bird) | Single writer per task; contracts frozen before fan-out (§G.10) |
| **Reviewer sycophancy / rubber-stamping** | Read-only reviewers, evidence+severity required, different model tier, clean context (§G.5) |
| **Self-preference bias** (judge favors own family) | reviewer-B on opus ≠ implementer on sonnet (§G.3/G.5) |
| **Context poisoning/distraction/rot in the lead** | One task/session, `/clear` between tasks, filesystem-as-memory (§G.8) |
| **Spec ambiguity → duplicated/gapped work** (MAST 41.77%) | Self-contained task schema with in/out-of-scope + contracts (§G.4) |
| **Infinite review loops** | MAX_REMEDIATION_ITERATIONS=3, then human escalation (§G.6) |
| **Agents corrupting `.pbxproj`** | PreToolUse hook blocks pbxproj edits; XcodeGen/SPM as source of truth (§G.7/G.9) |
| **Hallucinated APIs** | Deterministic compile gate + scout/Explore for real API discovery before implementation |
| **"Game of telephone" through the lead** | Subagents write artifacts to files; lead passes lightweight references (§G.8) |
| **LLM judgment where a machine check exists** | Gate supremacy: any failed machine gate overrides any APPROVE verdict (§G.5) |

---

## Recommendations

**Stage 0, Day-one bootstrap (do this before writing any feature code):**

```bash
# 1. Toolchain
brew install xcodegen swiftlint swift-format xcbeautify jq
# (optional, Phases 2-4) install XcodeBuildMCP
npm i -g xcodebuildmcp@latest   # then: claude mcp add …  (see xcodebuildmcp.com/docs)

# 2. Repo skeleton
mkdir -p .claude/{agents,commands,hooks} docs/{plan,adr} tasks reviews Modules
git rm -r --cached *.xcodeproj 2>/dev/null; echo "*.xcodeproj" >> .gitignore

# 3. Author the six agent files (§G.3), RUBRIC-A.md / RUBRIC-B.md (§G.5),
#    CLAUDE.md (§G.8), settings.json + hooks (§G.9), project.yml (XcodeGen).
chmod +x .claude/hooks/*.sh
xcodegen generate   # regenerate whenever project.yml changes

# 4. Prove the loop on ONE trivial task end-to-end before scaling:
#    e.g. TASK-001 "CoderKit: Codable Workspace model + decode test"
```

Do not proceed to real feature tasks until TASK-001 has gone spec→implement→gate→dual-review→integrate cleanly. This validates your hooks fire, reviewers parse, and worktree merge works, cheaply.

**Stage 1, Phases 0-1 (auth, workspace list, start/stop):** run **serial, single-worktree**. These tasks touch AppShell/DI and establish the CoderKit contracts everything else consumes. Freeze CoderKit's public surface as an explicit ADR before Phase 2.

**Stage 2, Phases 2-4 (terminal, VS Code Web, VNC):** now enable **2-3 parallel worktrees** across TerminalFeature / WebAppFeature since they're module-disjoint. Keep reviewer-B (security/opus) mandatory here, this is where Keychain, cookie injection, and PTY-token-logging risks live.

**Stage 3, Phase 5 (polish):** back to **serial** (multi-window/Stage Manager/DI are cross-cutting). Heavy reliance on the §G.11 human checklist; agents cannot verify most of this.

**Thresholds that should change the plan:**

- If **remediation routinely hits the 3-iteration cap**, your task specs are under-scoped, invest more in spec-writer output (MAST predicts this is where failures concentrate). Tighten §G.4, don't raise the cap.
- If **token/cost runs hot**, drop reviewer-A to haiku for mechanical spec-conformance and reserve opus only for reviewer-B; consider dropping the orchestrator to sonnet for pure integration sessions. (Multi-agent is ~15× chat token cost, budget for it.)
- If **parallel worktrees produce merge pain**, cut concurrency to 1-2; for a 10-user lab tool, throughput matters less than coherence.
- If you find yourself **wanting a 3rd reviewer**, resist it, instead sharpen the two existing rubrics. Add reviewers only if measured escape-defects (bugs both reviewers missed, caught later) justify it.

---

## Caveats

- **Claude Code's subagent/hook surface is changing fast.** Every field name, env var, and default in §G.2, §G.3, and §G.9 was verified against `code.claude.com/docs` current to ~v2.1.218 (July 2026), but several behaviors flipped within v2.1.x (background-by-default at v2.1.198; nesting default off after v2.1.216; `/agents` wizard removed). **Re-verify before building**, especially `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` semantics and whether your orchestrator runs as the main session or a nested agent, that determines the depth you need. [INFER items flagged inline.]
- **The 90.2% and 15×-token figures are Anthropic's own *research*-task numbers**, not coding benchmarks; I cite them to justify the *architecture skeleton*, not to promise a specific speedup on this app. Cognition's ~2-bugs-per-PR / 58%-severe figures are Devin-specific and directional.
- **The dual-clean-context-reviewer claim rests primarily on Cognition's April 2026 production report plus the LLM-as-judge bias literature**, it is well-supported but is practitioner evidence, not a controlled study on Swift code specifically. Treat MAX_REMEDIATION_ITERATIONS=3 and the 2-3 worktree cap as starting estimates to tune, not measured optima.
- **Model names/tiers drift.** "sonnet"/"opus"/"haiku" aliases are stable in Claude Code, but the underlying versions and their price/quality gaps move; re-check the current alias→model mapping and cost ratios when you set §G.3.
- **XcodeBuildMCP and simulator MCPs are third-party and evolving** (XcodeBuildMCP is now Sentry-maintained). Pin versions and treat their UI-verification output as advisory; the human checklist in §G.11 is the real gate for device-only behavior.
