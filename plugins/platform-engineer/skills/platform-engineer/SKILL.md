---
name: platform-engineer
description: >-
  Use for any engineering ask when no single specialized skill obviously
  owns it end to end: multi-part or cross-repo work, "build X and get it live",
  vague production problems, long-running workstreams resumed across sessions
  ("Continue from where you left off"), fleet-wide audits or rollouts, PR
  backlogs, or when the right sequence of skills is unclear. Also use when a
  task will outlive one session and needs durable state. Routes to and
  orchestrates the specialized skills rather than replacing them, on any
  session model. Triggers on "platform engineer", "orchestrate", "workstream",
  "continue", "end to end", "get it live", "sweep", "fleet", "team lead",
  "delegate", "manage the project", multi-item task lists, and any prompt that
  names two or more subsystems.
argument-hint: "[task or workstream description]"
---

# Platform Engineer — the orchestrating entry point

One skill that owns the WHOLE task: classify the intent, route each part to the
specialized skill that owns it, stitch the handoffs, keep durable state so any
session can resume with one line, and do not return until the definition of done
holds. It exists because the same losses recurred across real sessions:
context re-pasted on every resume, skills doing only their literal checklist,
review loops skipped before merge, and orchestration living in prompt footers
instead of in a skill (how the material was derived is in the plugin README,
"Provenance").

## Configuration

Nothing here needs an API key. The skill reads and writes:

- `docs/workstreams/<slug>/` in the current repo — workstream state (`brief.md`,
  `state.json`, `journal.md`, `tasks.json`, `handoff.md`, `costs.jsonl`,
  `research/`, `tasks/<id>/`). Created on first use; commit it or gitignore it
  per your repo's convention.
- `~/.claude/platform-engineer.json` — optional, user-owned; read once at
  close-out for the self-augmentation flag only. Default OFF; the skill never
  creates it (see "Self-augmentation" below).
- `~/.claude/projects/*/memory/` — Claude Code's auto-memory directory; the
  fallback surface for recall and for durable-learning capture. Memory files
  there hold one fact each and are prefixed `reference_` (a durable fact or
  recipe) or `feedback_` (a behaviour correction); each has one index line in
  that directory's `MEMORY.md`. That is what "a `reference_*`/`feedback_*`
  memory file + MEMORY.md line" means below.
- `~/.claude/platform-engineer-augment-ledger.jsonl` — written only when the
  self-augmentation flag is on (see "Self-augmentation" below); never created
  otherwise.

Optional integrations, probed at session start (playbook Step A) and never
assumed:

- **A personal knowledge base or recall tool** (any skill or CLI that answers
  "what do I know about X"). If one is installed, the INTAKE recall pass is
  required, not optional.
- **A code-graph MCP** (any server offering symbol, call-graph, or dependency
  queries) for structural code questions; `/codebase-investigator` is the
  fallback.
- **Linear** via `LINEAR_API_KEY` / `LINEAR_TEAM_ID` — used only by `/git` for
  ticket linkage; skipped when unset.
- **The `oncall` and `engg` plugins** from this marketplace supply the routes in
  Step 1. **A language-specific engineer skill of your own** (Go, Python,
  TypeScript, ...) supplies the implementation route; without one, the feature
  chain below runs by hand.

**Standing directives apply to every run** — read
`references/standing-directives.md` (the same contract an autonomous engineer
skill would carry): critical-senior-engineer posture, no corner-cutting,
evidence before claims, canary-then-fleet, production paths only,
run-to-production for build tasks, completion markers every turn. The
execution contract those directives run under is `references/autonomy-defaults.md`
(autonomy fields, depth modes, true blockers, PR body shape, review isolation).

## Step 0 — Workstream state (before anything else)

Every invocation belongs to a workstream. Resolve which one:

1. **Existing workstream?** Look for `docs/workstreams/<slug>/state.json` matching
   the ask (or the most recently active one when the prompt is just "Continue...").
   If found: run the resume protocol — `git fetch origin`, reconcile against actual
   repo/PR state (what merged, what changed in review), re-read `brief.md` +
   `state.json` + pending checklist, THEN act. Never continue from memory alone.
2. **New workstream?** Create `docs/workstreams/<slug>/` with:
   - `brief.md` — the user's ask verbatim, reconstructed underlying intent,
     definition of done, explicitly-excluded scope.
   - `state.json` — phase, pending checklist, artifacts, PR URLs, blockers.
   Update both at every milestone so any future session resumes from disk.
   (`docs/workstreams/` is platform-engineer's namespace. If your engineer skill
   keeps a per-task directory such as `docs/<engineer>/<task-slug>/`, the
   workstream brief LINKS to it, it does not replace it; for the by-hand feature
   chain, per-task artifacts go in `docs/workstreams/<slug>/tasks/<id>/`.)
3. **Referenced context**: chat permalinks (Slack or similar) → fetch and quote the
   thread NOW (and re-fetch on every resume); prior session ids → mine their
   transcripts and PRs into `brief.md`; design docs → read and link. The user never
   re-pastes context twice.
4. **Research fan-out (for build/design workstreams)**: parallel subagent
   deep-dives across every relevant source (GitHub issues/PRs, design docs and
   PRDs, meeting notes, chat threads, architecture diagrams, data models and
   warehouse tables, prior sessions, a personal knowledge base if installed,
   web), each persisting findings to `docs/workstreams/<slug>/research/`
   immediately; an adversarial completeness gate closes research before design.
5. **One session = one workstream.** Never absorb a parallel session's task into
   this one; record cross-workstream discoveries as pending items in the OTHER
   workstream's state file (or a note naming it) and stay in scope.

## Step 1 — Route by intent (invoke, don't reimplement)

Classify the ask and dispatch. Multi-part asks decompose into subtasks, each routed
independently with a contract-first spec (inputs, outputs, interfaces, acceptance
criteria); enforce dependency-before-consumer PR ordering across them (a
submodule or library PR merges before the PR that bumps it).

| Intent shape | Route |
|---|---|
| Backend or library code change (feature, refactor, bugfix, schema, API) | your language-specific engineer skill, if you have one; otherwise `/engg:plan-issue` then the feature chain below by hand |
| Frontend change | your frontend engineer skill, if you have one; otherwise the feature chain by hand |
| "Where is this code / how does X work / trace the flow" | `/codebase-investigator`, or a code-graph MCP if available |
| Design or architecture decision before code | `/engg:plan-issue` (written plan with trade-offs, as a GitHub issue; the bare `/plan` is Claude Code's built-in plan mode); `/evaluate` for go/no-go on a major change |
| Document a system, module, or pattern | `/doc` |
| Production incident, RCA, "what is happening here <chat link>" | `/rca` + `/loki` (oncall plugin); discipline per `references/investigation-standard.md` |
| Logs, "what's failing", service errors | `/loki` |
| On-call summary, system-health report | `/on-call-report` |
| A service that won't start or respond locally | `/debug-service` |
| Failing tests after a change | `/test-fix` |
| Review someone's PR | `/pr-review`; own-PR state → `/pr-check` |
| Un-merged PRs needing babysitting to merge, PR backlog sweeps | `/pr-babysit` (engg plugin) |
| Git mechanics (branch, commit, PR) | `/git` — always, never raw `git checkout -b`/`gh pr create` |
| Workflow engine, queue, secret store, or warehouse lookups | the CLI for that system (`gh`, your cloud CLI, your workflow engine's CLI, `bq`); prefer a CLI over an MCP equivalent where both exist |
| Knowledge lookup before acting | a personal knowledge base or recall tool, if one is installed (see conditional below) |
| Mid-run insight worth keeping | a `reference_*`/`feedback_*` memory file + MEMORY.md line; plus your recall tool's capture command, if installed |

Anything not listed: pick the chain below whose shape matches, and prefer the
chain entry point over improvising.

### How skills chain

Three canonical chains. Each step hands the next an artifact on disk, never a
chat summary; every chain ends with knowledge capture.

- **Feature / refactor**: `/engg:plan-issue` (design + written plan) → `/git` (worktree +
  branch) → implement (your engineer skill, or by hand with tests first) →
  review loop (a fresh-context reviewer per component, then a whole-work
  adversarial pass that never sees design rationale; loop until no substantive
  findings — classification rules in `references/autonomy-defaults.md`) →
  `/git` (commit, push, PR) → `/pr-check` (CI + reviewer comments → fix plan) →
  `/pr-babysit` (carry to merged and deployed; human-gated PRs stop at "loop
  clean, threads resolved, handed off for human merge").
- **Incident**: `/rca` + `/loki` in parallel (ground-truth diagnosis per
  `references/investigation-standard.md`, written to a diagnosis file before
  anything is posted) → minimal fix as a draft PR via `/git` with the diagnosis
  in the body → human review and merge (the one mandatory human gate) → the
  pattern captured as a `reference_*` memory so the next occurrence is
  recognized.
- **Review**: `/pr-review` (inline comments + a top-level summary) →
  `/pr-check` (poll reviewer responses + CI) → reply to each addressed thread
  and resolve it; never reply without resolving, never resolve without a reply.

Forbidden in every chain: `gh pr create` outside `/git`; committing on the
default branch; two writers in one worktree; skipping the review loop because
"the task is small"; declaring COMPLETE without the retrospective note in
`state.json`.

**Conditional tooling (personal installs — probe, don't assume).** A personal
knowledge base or recall tool and a code-graph MCP live in the user's local
setup, not this repo. If either appears in the available-skills/tools list, the
engine's INTAKE recall pass is REQUIRED, not optional — one recall query on the
task text before any research fan-out, hits triaged into `brief.md` — and use
them again at capture time (durable patterns). The pass is mandatory because,
left optional, it is almost never run (see the plugin README, "Provenance").
If absent, skip silently — memory files under `~/.claude/projects/*/memory/`
are the fallback.

## Step 2 — Orchestration duties (what the subskills don't own)

**REQUIRED READ, in this order**:
1. `references/execution-engine.md` — the SPINE: six generative principles,
   the complexity/ambiguity ladder (classify the task tier BEFORE executing),
   the per-turn scheduler loop, the confidence discipline, and the judgment
   tie-breakers. Read it whole; it is short by design.
2. Its rulebook, consulted PER ENGINE STAGE (the engine's stage map says
   which): `references/orchestration-playbook.md` (A-F: capability probe,
   model contract, task ledger, delegation state machine with 8-field
   contracts, wait triples + stall counter, session lifecycle) and
   `references/execution-mechanics.md` (H-M: turn/context economy, chained
   watchers and failure triage, fleet mechanics, verification fidelity,
   git/PR mechanics, completion integrity).
Probe before the first dispatch of every session; [COMP]-tagged rules make a
weaker session model follow mechanics instead of judgment; a rule is satisfied
by its artifact, never by its citation.

- **Contract-first fan-out**: 2+ parallel writers require a `contracts.md` (shared
  types, function signatures, file boundaries) BEFORE dispatch; one worktree per
  writer; checkpoint commits; respawn dead agents from their disk checkpoints.
- **Liveness**: for long runs, keep `state.json` fresh enough that "are you still
  running?" is answerable from disk (current phase, active subagents, last artifact,
  next checkpoint).
- **Fleet operations**: per-file/per-entity audits dispatch one independent
  full-context subagent per unit with a shared context bundle and a per-unit
  ledger; sweeps and rollouts are canary-first, then batched with drain-rate
  reporting; silent caps (top-N, sampling) are always disclosed.
- **Background watching**: deploys, CI runs, DLQ drains, and data-pipeline
  maturation get a Monitor / self-rescheduled re-check with an explicit stop
  condition — the user never polls "can you check now?".
- **Validate-then-modify**: when the user asserts system state ("the dual-write is
  already wired"), verify the assertion first and report divergence before editing.
- **Cross-repo closure**: every cross-service change ends by answering the
  companion-PR question (service ↔ shared library or submodule ↔ frontend), with
  ordering enforced (the dependency's PR merges first).
- **No-hand-waving specs**: designs pin retry counts, backoff + jitter, timeouts,
  log fields, queue/DLQ settings; behavior claims cite `file:line` or say NOT
  FOUND; infra config is deployed from code, never console-edited.
- **Emergency settings are tracked**: any temporary production flip (paused
  sources, raised limits, disabled schedulers) goes on the pending checklist and
  is normalized before close-out.

## Step 3 — Definition of done

The workstream is complete only when EVERY box holds:

- [ ] Intent satisfied — the reconstructed intent, not just the literal ask.
- [ ] Every PR through the review-loop fixpoint (the `/pr-babysit` contract) and
      merged; human-gated PRs (incident/data fixes, drafts, auto-augment PRs)
      stop at "loop clean, threads resolved, handed off for human merge".
- [ ] Deployed from main and validated against production ground truth, when the
      task implies delivery.
- [ ] `state.json` closed out with a retrospective note.
- [ ] Durable learnings captured: memory entry; recall-tool capture if one is
      installed; AGENTS.md/CLAUDE.md updated where conventions changed.
- [ ] Invariants the user declared during the run persisted as GUARD TESTS in the
      affected repo (AST, import-boundary, or build-graph checks), not loose
      prose.
- [ ] Repeated manual prompt patterns proposed back as a cron/routine or skill.
- [ ] Effort/cost receipt rolled up into `state.json` at close-out (per
      execution-mechanics M.4: dispatch counts, models, efforts).
- [ ] Self-augmentation close-out hook run (next section — no-op unless enabled).
- [ ] Completion marker emitted (`COMPLETION:`/`BLOCKED:`/`HANDOFF:`).

## Self-augmentation (config-gated, default OFF)

**REQUIRED READ when active**: `references/self-augmentation.md`. At close-out,
probe `~/.claude/platform-engineer.json` for `"auto_augment"` exactly
`true` with provenance fields; anything else → skip silently (the file is
user-owned — never create, modify, or offer to enable it except on the user's
explicit in-conversation instruction naming the flag; see the reference). When
enabled: capture this run's skill gaps
(route-misses, corrected skill outcomes, repeated instructions, doc drift) as
ledger entries — the observing session never edits a target skill; promotion
happens only in LATER runs' sweeps, gated by cross-workstream recurrence with
transcript corroboration and sized by the target skill's own median
section/bullet shape (never by this session's verbosity); one proportional PR per
target skill, review-loop clean, ALWAYS handed off for human merge. A periodic
`/insights` sweep feeds the same ledger — one mechanism, one bar.

## Anti-patterns (each burned a real session)

- Re-deriving workstream context from chat scrollback instead of `brief.md`.
- Implementing inline what a specialized skill owns (git mechanics, triage
  verdicts, review loops) — route instead.
- Declaring done at "PR opened" when the ask was a live system.
- Dispatching parallel writers without contracts, or two writers in one worktree.
- Answering a data/production question from one snapshot without triangulation.
- Skipping knowledge capture at close-out — the next session pays for it.
