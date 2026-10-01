# Orchestration playbook — frontier-parity mechanics on any session model

> The spine is `execution-engine.md` (next to this file) — read it first. This file is
> its rulebook: consult per engine stage via the stage map, not linearly.

The orchestration behaviors this skill demands (task graphs, delegation with
review loops, monitors, parallel fan-out with verification, durable resume)
are HARNESS capabilities plus a doctrine — not model magic. A frontier model
applies the doctrine spontaneously; any other model applies it when each
behavior is an explicit, checkable step with a worked example. This playbook
is that explicit form (sources: plugin README, "Provenance").

Rules are tagged **[INV]** (invariant — holds for any model) or **[COMP]**
(compensation for non-frontier session models — a stronger model may override
one only with a justification recorded in the journal).

**Workstream paths used throughout** (`<ws>` = `docs/workstreams/<slug>/`,
per SKILL.md Step 0): `state.json` (mutable coordination state), `tasks.json`
(append-only task ledger, fallback for the Task tools), `journal.md`
(append-only event log: one line per event, `ISO-ts | task | event |
evidence-path`), `tasks/<id>/contract.md`, `tasks/<id>/progress.md`,
`handoff.md`. The per-task `contract.md` (delegation contract, Step D) is
distinct from Step 2's `contracts.md` (shared interface spec for parallel
writers); fan-out work needs both.

## Step A — Capability probe (once per session, before the first dispatch)

1. [INV] Read your OWN tool list first: dispatch/orchestration tools (an
   `Agent`/`Task` subagent tool, `Workflow`, `ScheduleWakeup`) are top-level
   in some harnesses and invisible to ToolSearch. Then load deferred tools in
   ONE call: `ToolSearch("select:TaskCreate,TaskUpdate,TaskList,TaskGet,Monitor,SendMessage,CronCreate,CronList,EnterWorktree,ExitWorktree,WebSearch,WebFetch,PushNotification")`.
   Record ACTUAL names found — do not assume this file's names exist.
2. [INV] Write the inventory to `state.json.capabilities`, one entry per row
   below. Example shape:

```json
"capabilities": {
  "task_graph": {"tool": "TaskCreate", "status": "present"},
  "teammates":  {"tool": null, "fallback": "file-mailbox", "noted_to_user": true},
  "watching":   {"tool": "Monitor", "status": "present"}
}
```

3. [INV] Fallback chain, in order: preferred tool → documented equivalent →
   narrow the job → report blocker. "Narrow" is constrained: drop ONLY duties
   whose capability row is absent, and list each dropped duty by name in the
   journal and the completion marker — never silently shrink scope.
4. [INV] Resumed sessions re-probe and re-arm every watcher in
   `state.json.watchers` (Step E) — background tasks and monitors are NEVER
   restored by the harness on resume.

| Capability | Typical tool(s) | Fallback when absent |
|---|---|---|
| Task graph | TaskCreate/Update/List/Get | `<ws>/tasks.json` ledger (schema in Step C) |
| Subagent dispatch | Agent/Task tool (top-level) | lead executes tasks itself, ONE at a time, contract discipline unchanged; review must still be a fresh dispatch — if no dispatch tool exists at all, reviews degrade to deterministic checks only, journaled as a downgrade |
| Teammates (persistent) | Agent with `name:` + SendMessage | one-shot background dispatches + file mailbox `<ws>/mail/<agent>.md`; "same worker" = fresh re-dispatch seeded with contract + prior findings |
| Deterministic fan-out | Workflow (pipeline/parallel) | batched dispatch calls per stage; collect all results before the next stage |
| Event watching | Monitor | Bash `run_in_background` until-loop; else bounded polling (backoff 1s→30s cap, hard timeout, terminal condition) — journal the downgrade |
| Self-scheduling | ScheduleWakeup / CronCreate | park: durable next-action record in state.json + tell the user the exact resume one-liner |
| Isolated writers | EnterWorktree / `git worktree add` | serialize writes: one writer at a time |
| Workflow skills (/git etc.) | available-skills list | manual sequence preserving the SAME guards (PR-dedupe pre-check, no-main-push, dependency-repo-first ordering); guards unpreservable → blocker |
| Web research | WebSearch/WebFetch | local/cached evidence only; never fabricate sources |

## Step B — Model-independence contract

1. [INV] Children inherit the SESSION model. Before dispatch, check the agent
   definition (`.claude/agents/*.md` frontmatter) for `model:`; if present and
   lower than the session model, pass an explicit model override and journal it.
   Never pass a cheaper model to save cost. [COMP] On frontier-class session models,
   orchestration and delegated engineering run at `xhigh` effort; journal the
   effort choice like the model choice, and lowering it needs journaled
   justification.
2. [COMP] Plan-first: task graph + plan on disk BEFORE any execution. Every
   lead turn re-anchors by reading state first, writing state after — a written
   plan turns a planning problem (hard for mid-tier models) into a following
   problem (easy).
3. [COMP] Effort budgets are handed, not inferred — put them IN the contract:
   simple fact-find = 1 agent, 3-10 tool calls; direct comparison = 2-4 agents,
   10-15 calls each; complex decomposable READ-ONLY fan-out = up to 10+
   one-shot agents. Persistent WRITER teams stay at 3-5 teammates, 5-6 tasks
   each — never 10 writers.
4. [INV] Simplicity ratchet: single session > subagents > agent team. Escalate
   only when it demonstrably improves the outcome.
5. [COMP] Structured output AFTER freeform reasoning (small typed block last),
   never schema-first — schema-first costs mid-tier models 10-30% reasoning
   quality.
6. [INV] Deterministic operations run as recorded commands, not re-derived
   behavior: the first time you append to the ledger/journal or arm a watcher,
   record the exact command in `state.json.ops` and reuse it verbatim. Example:
   `"journal_append": "echo \"$(date -u +%FT%TZ) | $TASK | $EVENT | $EVIDENCE\" >> docs/workstreams/<slug>/journal.md"`.
7. [COMP] Contracts use numbered steps, decision rules, and one worked example
   per nontrivial procedure — prose paragraphs of guidance do not survive a
   weaker executor. (This file follows its own rule; keep it that way.)

## Step C — Task ledger

1. [INV] Decompose BEFORE dispatching: one task per unit, full contract in the
   description, `blockedBy` edges, `metadata.priority` P0-P3 set at
   decomposition (selection = highest priority, ties to lowest id). [COMP] Grain:
   split any task that cannot be verified in one review pass (e.g. "migrate 15
   handlers" becomes 5 tasks of 3) — the review loop, not task length, absorbs
   the executor's reliability gap.
2. [INV] Status vocabulary is the harness enum: `pending → in_progress →
   completed`. There is no failed/blocked status — record those as
   `metadata.outcome: "failed"` / `metadata.blocker: "<why>"` plus
   `addBlockedBy` edges. NEVER call TaskUpdate with `status: "deleted"`; a
   superseded task is completed with `metadata.superseded_by` set.
3. [INV] Fallback ledger `<ws>/tasks.json` entry shape (append-only; only
   `status`, `metadata`, `blockedBy` (adding edges per C.2), `confidence`, and
   evidence fields may change after creation — editing or removing entries is
   as unacceptable as editing tests). Entries are born with the engine's four fields: NON-EMPTY binary acceptance
   criteria, empty evidence slots, edges/priority, `confidence: "unknown"`
   (promotion rules in the engine's P6):

```json
{"id": "T3", "subject": "wire consumer DLQ replay", "status": "in_progress",
 "blockedBy": ["T1"], "metadata": {"priority": "P1"},
 "acceptance": "replayed DLQ message lands in ds.t within 5 min, count query cited",
 "confidence": "unknown",
 "evidence": {"pr": null, "commit": null, "test_output": null}}
```

4. [INV] `completed` requires evidence fields filled and verified against the
   acceptance criteria — never a worker's say-so. Discovered work becomes a
   NEW task immediately.
5. [INV] After every completed task: journal line + state.json update. Session
   memory is not durable execution.

## Step D — Delegation state machine (journal every transition)

`ASSIGN → CONTRACT → EXECUTE → REVIEW → FOLLOW-UP → ACCEPT`
(terminal alternatives: PARK, ESCALATE).

**ASSIGN** [INV]
1. Pick the highest-priority unblocked task (C.1 selector).
2. The lead never implements delegated work; if the lead must do it, re-assign
   the task to the lead explicitly in the ledger first.
3. Writers get exclusive file ownership (worktree per writer); parallel
   dispatch is for READ-ONLY work only.

**CONTRACT** [INV] — `<ws>/tasks/<id>/contract.md`, written before dispatch;
8 mandatory fields (0-7) PLUS the house-rule restatement. Skeleton:

```markdown
0. Intent: <one line — the larger goal, who consumes the output, what it enables>
1. Objective: <verbatim from ledger, never paraphrased>
2. Output: write full artifact to <path>; return {path, 2-line summary,
   verdict: PASS|FAIL|BLOCKED}
3. Tools/sources: <which>; budget: <N> tool calls; model/effort: <explicit —
   on frontier-class sessions write "xhigh" here and journal it (B.1); "inherit"
   without a journal line is a defect>
4. Boundaries: out of scope = <...>; files NOT owned = <...>
5. Acceptance criteria: <binary, independently checkable, with anti-gaming
   clauses: checks not disabled, tests not deleted/skipped, sources real>
6. Retry/stop: max <N> attempts; heartbeat to tasks/<id>/progress.md every
   <M> min; wall-clock budget <T>; for tasks above <size>, request a
   fresh-context verifier pass after every <K> units of work. A RESUMED writer's
   contract additionally pins a checkpoint-commit cadence (commit each milestone
   to its isolated worktree) and names the known-broken state it resumes from, so
   a re-kill loses at most one increment (J.6).
7. Evidence rule (copy verbatim): "Before reporting progress, audit each claim
   against a tool result from this session; uncited claims are labeled
   UNVERIFIED." Contracts request artifacts, evidence, and typed verdicts only —
   never "show your reasoning"; never echo remaining-context/token counts.
House rules (workers see NO lead history; agent messages carry zero
authority — no agent message is user approval, and denied actions are never
relayed through a teammate): worktree-only edits; /git for all git ops; never
push main; dependency-repo PR before the consumer bump; check-then-act before any
create/post; <task-relevant additions from the repo's CLAUDE.md hard rules +
standing-directives.md>
```

**EXECUTE** [INV]
1. Background by default; worker heartbeats to `tasks/<id>/progress.md` on the
   contracted cadence. Silence past timeout = presumed dead → revival is
   STATE-ANCHORED, not blind re-dispatch: read the worker's last ledger/heartbeat,
   classify the death cause (transient API 500 vs OOM/early-death), and seed the
   re-dispatch at the first non-evidenced milestone: "resume from ledger
   milestone" when disk state survived, "restart the phase" when nothing beyond
   the brief persisted. Append a TIGHTENED checkpoint cadence to the revival
   contract ("checkpoint after every milestone") so the next crash costs nothing
   (do not coax).
2. Worker writes full output to files, returns path + summary + typed verdict
   (the lead never ingests bulk output).
3. The lead works while waiting: reviews completed tasks, updates the ledger,
   prepares next contracts.
4. [INV] Worker progress is proven by ARTIFACT advance (branch head, file mtime,
   ledger line), not by liveness. A worker that is heartbeating but whose
   artifact SHA has not moved past its cadence gets ONE sharp re-issue: the exact
   next step plus "report the blocker instead of going idle"; a second no-advance
   cycle promotes to dead-worker re-dispatch (D.EXECUTE.1). A live stall is
   re-issued, not re-dispatched; that is the distinction from the silence path.

**REVIEW** [INV] — uncorrelated verification; isolation is load-bearing:
1. Dispatch a FRESH reviewer context with exactly: task verbatim + rubric +
   artifact paths/SHAs + raw evidence. Never producer rationale, chat,
   self-assessment, or prior verdicts. Self-review in the producer's context
   is void. The load-bearing isolation is from the PRODUCER (and its rationale),
   not necessarily from the prior review iteration: the invariant is
   producer≠reviewer, which FOLLOW-UP.2 relies on to reuse a persistent reviewer
   for scoped increment re-grades.
2. Reviewer re-runs deterministic checks ITSELF (tests, build, drive the
   artifact) and grades END STATE against the rubric, not process.
3. Reviewer returns per-criterion PASS/FAIL + evidence + findings with
   severity in exactly {critical, important, minor}, PLUS a mandatory
   "checks not run / failure classes not covered" section (an empty section is
   asserted explicitly); the lead converts a non-empty section into
   next-iteration scope or a journaled accepted-risk line.
4. Aggregation is asymmetric: ONE evidenced refutation kills a claim
   regardless of N approvals (parallel instances hallucinate identically);
   consensus voting only for subjective quality.
5. Substantive work (anything merging to a production path) gets a second,
   adversarial, rationale-blind pass: "break this; survival = acceptance". This
   whole-work pass ALWAYS uses a fresh reviewer with no producer context and no
   reused iteration rubric: the one place reviewer freshness (not just
   producer-isolation) is mandatory.

**FOLLOW-UP** [INV]
1. Findings route by worker state: alive (heartbeating) → SendMessage to the
   same worker; dead or fallback mode → re-dispatch fresh with contract +
   findings file appended. [COMP] On non-frontier session models, default to
   one-shot re-dispatch (contract + findings file) even when SendMessage exists;
   sustained peer messaging is a journaled exception.
2. Fix-verification iterations MAY reuse the same reviewer identity to re-grade
   ONLY the increment (`git diff <reviewed-head>..<new-head>`) against its named
   prior findings (cheaper and context-warm), provided that reviewer (a)
   re-runs the deterministic checks itself and (b) never received producer
   rationale. A FULL fresh re-grade is required only when the fix changed
   behavioral surface beyond the flagged findings; the whole-work adversarial
   pass (D.REVIEW.5) always stays fresh and isolated. Producer≠reviewer holds in
   every case.
3. Bounds: 3 iterations default; 4-5 only by explicit lead decision recorded
   in the journal; hard cap 5. Two consecutive no-progress iterations
   (no finding count reduction) = stall → the LEAD decides:
   retry-with-modification, accept-partial, escalate, or PARK as dead-letter.
   No automatic retry inside the loop.
4. [INV] A user's design opinion forwarded into a live worker goes as a
   HYPOTHESIS with the falsifiable check that would confirm or refute it, plus
   the standing "adjudicate honestly / validate-don't-fold" mandate, never as an
   order. A user preference does not collapse the worker's evidence obligation;
   only the pinned INTENT is non-negotiable, design opinions are testable. This
   guards the producer against being sycophantic to the user against its own
   evidence.

**ACCEPT** [INV]
1. Exit predicate: zero critical + zero important findings and all rubric
   criteria pass. Cap-hit without fixpoint → ESCALATE with residual findings
   attached; silent acceptance forbidden. Minor findings become new tasks.
2. Check-then-act on every side effect: query for the existing PR/branch/
   message BEFORE creating (eight duplicate "add provider X" PRs opened in one
   afternoon are this guard missing). Retrospective corollary: on a lead↔worker action RACE (both acted
   on the same PR/branch/file, e.g. messages crossed), the LEAD establishes the
   reconciled truth with a read-only probe, states it verbatim ("already open as
   #N, verified <delta>"), and hands the worker a RESUME-from-here instruction;
   never let both sides redo and never let both back off.
3. Flip ledger status with evidence fields, checkpoint commit, journal line.
4. Stop the worker on ACCEPT/PARK/ESCALATE (TaskStop or confirm the one-shot
   ended) and journal the stop — no idle worker survives its task.
5. [COMP] Quantitative targets require the improvement curve: per-iteration
   metrics, stopping only on plateau evidence (delta below the threshold set
   in the contract's acceptance criteria; default when unstated: <5% relative
   improvement, across 2 consecutive iterations) or budget exhaustion —
   "good enough" after one round fails acceptance.

## Step E — Waits, monitors, stall detection

1. [INV] Every wait is a triple (wake condition covering FAILURE modes too,
   timeout, on-timeout action), preferring Monitor/wakeups over sleep-polling.
   Two questions pick the wait mode: independent work available? wait
   long/uncertain? Any yes → watcher and keep working; both no → one blocking
   until-loop-with-timeout that waits AND reads the result in the same call.
   On a watcher firing, run a cheap count/title probe first; the full-content
   read happens exactly once, after the terminal condition.
   ON ARMING, append to `state.json.watchers`:
   `{"what": "PR 70 bots", "condition": "reviews stabilize|CI fail", "timeout_ms": 1800000, "on_timeout": "check manually + journal", "command": "<the Monitor/bash command>", "armed_at": "<ISO>", "status": "armed"}`
   — retire the entry when it fires or is stopped. Resume re-arms from this
   list (Step A.4). Arming and registering are ONE action: the same turn that
   starts the watcher appends the entry; an armed-but-unregistered watcher is
   a defect (it cannot survive resume) and counts as a stall-event for E.3.
2. [COMP] Six-question loop every lead turn, answers as one journal line:
   request satisfied? looping? progressing? who acts next? what exact
   instruction? does new evidence contradict the written plan? — on yes, revise
   the plan file BEFORE the next dispatch and journal the revision. Fill-in
   template (the artifact, not optional):
   `<ISO> | E2 | sat=N loop=N prog=Y next=reviewer:T3 instr="re-grade v2" contradiction=N`
3. [INV] Stall counter: progress = at least one ledger status flip or new
   evidence field this lead turn. Track `state.json.stall_count` (reset on
   progress, else increment); at 2 → stop dispatching, re-plan (update facts,
   revise the graph, reset the stuck worker) — never re-send the same
   instruction. [COMP] One legal re-plan response is ESCALATING effort/model
   tier for the retry (never lowering it); journal the escalation like any
   model/effort choice.
4. [INV] Human gates are durable records in state.json (`question`,
   `artifact_sha`, `asked_at`, `expires`), never chat messages; approval binds
   to the artifact version and parks safely across sessions. Gates are for
   IRREVERSIBLE or high-blast-radius forks only — a reversible fork is
   decided, journaled with its assumption-check, and announced, never parked
   on a question (engine judgment layer; the measured cost of over-asking was
   17.4 idle hours in one marathon). Authorization binds to (artifact version,
   action class, AND the session/day it was granted): a fresh artifact or a new
   session RE-OPENS the gate even after a prior blanket "full permission": a
   grant is consumed by the batch it was given for. When a classifier refusal
   PERSISTS across explicit user instruction and the lead judges the refusal
   correct (e.g. another team's resource), hand it back as a one-line manual step
   ("run it yourself: `<cmd>`") and never work around it; this is the I.7
   BLOCKED terminal, not an alternate-hunt.
   AskUserQuestion is an acceptable gate for a load-bearing, expensive-to-reverse
   ARCHITECTURAL fork at design time, but because it is a synchronous CHAT gate
   that does not survive a session boundary, the question AND its answer must be
   mirrored to `brief.md`/`state.json` (P1). If the tool is unavailable or the
   user re-issues "continue" instead of answering, the fork degrades to a
   reversible decision: decide, journal the assumption plus its falsification
   check, announce, and proceed (the standing "decide, don't be a pushover"
   directive). Prefer decide-and-journal over asking whenever the fork is
   later-reversible.
5. [INV] Service-boundary freeze: when evidence surfaces mid-run that a lane
   touches another team's owned surface (their data models, their tables/
   services), FREEZE that lane immediately: stop the worker, close its PR with a
   handoff comment carrying the analysis plus a reference branch, and WITHDRAW
   any cross-team mutation even one the user asked for. Boundary discovery is a
   re-classify event, journaled as such, never a thing to push through; the
   withdrawn action becomes a hand-off to the owning team, not a blocked task.

## Step F — Session lifecycle

1. [COMP] Startup: read `<ws>` state by slug → git log + journal tail → cheap
   baseline-green check → pick highest-priority unblocked task → work ONE task
   at a time → commit + journal + mergeable state → RETURN TO THE LEDGER and
   repeat until no unblocked tasks remain, a blocker fires, or context limits
   trigger F.2. One-task-then-stop is wrong; one-task-AT-A-TIME is right.
2. [COMP] At context pressure (or before a task that won't fit): context reset
   over compaction — write `<ws>/handoff.md` `{done, in-flight, next action,
   armed watchers, open gates}`, commit, emit `HANDOFF: resume with
   /platform-engineer "Continue <slug>"`. "Wrapping up early because context
   is low" is not a completion reason.
3. [INV] Resume verifies, never trusts: cheaply re-verify each claimed-done
   task (PR exists, file exists, tests pass) before building on it; continue
   at the first non-done task; never restart from zero; re-arm watchers; and
   verify worktrees still exist before writing into them — they can be reaped
   during long waits (recreate + rebase, then continue).
4. [INV] Reusable system facts discovered mid-run (semantics, deploy gotchas,
   incident patterns) get their `reference_*` memory file + index line written
   inside the current wait window — not at session end. Route by memory type:
   durable fact → `reference_*`; behavior correction → `feedback_*`; session
   narrative → session capture (a recall tool's capture command, if one is
   installed). Gate every write: verify
   the fact against this session's tool results and skip what the repo or git
   history already records — an incorrect memory is worse than none.

## Continuation

Steps H-M live in the sibling `execution-mechanics.md` (turn mechanics and
context economy; long operations and failure triage; fan-out and fleet
mechanics; verification fidelity; git/PR/deploy mechanics; completion
integrity). Read it whenever this file is read; its rules carry the same
[INV]/[COMP] tags and the same override discipline.

## Rationalizations that void the doctrine

| Excuse | Reality |
|---|---|
| "Small task; the ledger is overhead" | Interruption loses everything not on disk; the ledger costs seconds. |
| "The teammate said it's done" | Unverified completion is the #1 delegation failure; read the artifact against the rubric. |
| "I'll review it myself, I have the context" | That context is the bias; reviews run in a producer-free context or they are void (a reviewer that never saw producer rationale may be reused across scoped increments, D.FOLLOW-UP.2). |
| "N agents agreed, so it's verified" | Correlated agents hallucinate identically; one evidenced refutation outranks N approvals. |
| "One more retry will fix it" (at 2 stalls) | Stalls need re-planning, not repetition. |
| "Cheaper model for this small subtask" | Silent downgrades are unnoticed quality regressions; inherit the session model. |
| "Context is low, let me wrap up" | Write handoff.md and reset; premature wrap-up ships half-done work. |
| "This model doesn't need the checklist" | Then it costs nothing; if it does, the checklist IS the parity mechanism. [COMP] skips need journaled justification. |

Scope note: the Step D FOLLOW-UP bounds govern lead↔worker task review only;
GitHub PR review loops follow the `/pr-babysit` fixpoint contract unchanged.
