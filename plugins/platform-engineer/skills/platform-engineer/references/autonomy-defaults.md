# Autonomy defaults — the execution contract for autonomous engineering runs

## WHAT
This file defines how an autonomous engineering run (platform-engineer itself,
or any language-specific engineer skill it dispatches) executes when the user
invokes it without an explicit override. Every field below can be overridden in
the task prompt; when nothing is overridden, these defaults apply.

## WHY
The standing instruction is: treat the task prompt as authorization to run the
full engineering cycle through PR creation, with no default human approval gates.
Keeping the contract in one file means an engineer never has to paste it as a
prompt footer, and a weaker session model can follow it mechanically.

## HOW: Default execution contract

```text
autonomy: full
execution_depth: exhaustive
human_approval: none
time_budget: unlimited
token_budget: unlimited
create_branch: true
commit_changes: true
push_branch: true
create_pr: true
create_linear_tickets: false
stop_before_pr: false
```

The user may override any field explicitly in the task prompt (e.g.
`execution_depth: fast`, `stop_before_pr: true`, `human_approval: before-pr`).
If no override is provided, use these defaults.

## Execution depth modes

### `execution_depth: fast`
- Minimal research, one requirements pass, one design pass, focused
  implementation, one code-review pass.
- Appropriate for: small, low-risk changes (typo fixes, single-line bug fixes,
  dependency bumps, documentation tweaks).
- Skip: parallel subagents, online research beyond repo evidence, whole-work
  adversarial review.

### `execution_depth: balanced`
- Moderate research, targeted subagents (1-2), bounded adversarial loops (max 2
  iterations), good validation coverage, PR creation.
- Appropriate for: normal feature work, refactors with clear scope,
  well-understood bug fixes.

### `execution_depth: exhaustive` (DEFAULT)
- Deep research across the repo, the web, and a personal knowledge base if one
  is installed; extensive subagent use (3-5+ in parallel where useful); repeated
  adversarial loops until no substantive findings; comprehensive implementation
  and validation; whole-work adversarial review with Phase-5 vs Phase-6 context
  isolation; adversarial testing; PR creation.
- Appropriate for: complex backend, infrastructure, credentials, security,
  reliability, multi-service or multi-repo work.

### `execution_depth: custom`
- User specifies limits explicitly. Example:
  ```text
  execution_depth: custom
  max_research_loops: 1
  max_design_review_loops: 1
  max_code_review_loops_per_subtask: 2
  skip_online_research: true
  skip_adversarial_testing: false
  create_pr: true
  ```

## True blockers (the ONLY reasons to stop)
1. Required credentials are unavailable and the repo documents no fallback.
2. GitHub / PR-creation permissions are unavailable (e.g. `gh` is not
   authenticated).
3. Repository is in a dirty state with unrelated changes that cannot be safely
   preserved.
4. Required session / spec artifacts are missing and no reasonable fallback
   exists in the repo.
5. Task is materially ambiguous in a way that risks destructive or irreversible
   action.
6. Tests require external infrastructure (a real cluster, a real customer
   database) that is unavailable and no local substitute exists.
7. A required tool or skill is missing and no fallback workflow can complete the
   task.

In all other cases — failing tests, conflicting reviewer feedback, scope
expansion — do not stop. Diagnose, fix, retry, and document.

## Validation baseline
- Go: `go build ./...` and `go test ./...`. If the repo has a `Makefile`,
  `Taskfile.yml`, or canonical CI workflow, prefer those targets.
- Python: `uv run pytest -x`, `uv run mypy`, `uv run ruff check` (or the repo's
  equivalents). If the repo carries an architectural test (import-boundary or
  AST rules), run it too.
- TypeScript: `pnpm typecheck && pnpm test`, plus `pnpm lint` where configured.

Every implementation task must run validation; failures are debugged and fixed
unless impossible (in which case the PR body documents the blocker per the
default PR body below).

## Default PR body shape (autonomous mode)
1. Summary (1-3 sentences, business intent first).
2. Requirements addressed (bullet list, with inferred-requirement marker if not
   explicit).
3. Design summary (the chosen approach + 1-2 alternatives considered).
4. Implementation summary (touched files, key data-flow changes).
5. Validation commands run (exact commands + pass/fail).
6. Test results (failing → pass transitions, new tests added).
7. Code-review loop summary (Phase-5 reviewer findings + resolutions).
8. Adversarial review summary (Phase-6 reviewer findings + resolutions,
   context-isolated from design rationale).
9. Adversarial testing summary (chaos / edge cases run).
10. Known limitations or unresolved issues (with severity classification per
    Scope Control below).
11. Risk assessment (blast radius, rollback complexity).
12. Rollback notes (specific revert command + verify steps).

## Scope-control classification (used inside the autonomous loop)
Adversarial reviewers may propose new issues. The implementing agent classifies
each:
1. **Requirement-blocking** — must fix before PR.
2. **Correctness/security-critical** — must fix before PR unless technically
   impossible (then document in PR body item 10).
3. **Design-improving** — fix when it materially improves correctness,
   maintainability, testability, operational safety.
4. **Nice-to-have** — document only.
5. **Out-of-scope** — document only.

Reasonable scope expansion that is necessary for correctness, security, or
maintainability does NOT require human approval. Major intrusive changes are
allowed when justified by the requirements and repository state. Avoid
gold-plating; do not avoid necessary deep fixes.

## Stopping rule
Stop only after: task intent is satisfied, acceptance criteria are satisfied,
validation passes or unavoidable failures are documented, no unresolved Class-1
or Class-2 findings remain, changes are committed, branch is pushed, and a PR is
created.

## Phase-5 vs Phase-6 reviewer context isolation
- Phase-5 code-review (per subtask): give the reviewer the relevant design spec,
  requirements, subtask description, diff, validation results.
- Phase-6 whole-work adversarial review: give the reviewer ONLY the original
  task, requirements, acceptance criteria, completion criteria, final diff or
  implementation summary, and validation results — NOT the design rationale.
  This forces intent-alignment evaluation rather than agreement with the chosen
  design.

## Dependency injection preference (Go)
- Prefer the repository's existing manual DI pattern (`main.go` constructs the
  graph). Do NOT migrate to a code-generating DI framework automatically.
- If DI structure is poor, improve manual DI boundaries rather than introducing
  a framework without an explicit user request.

## Outer-loop integration
- If an outer-iteration plugin (such as `/ralph-loop`) is installed and
  compatible, it may drive the loop.
- If it is unavailable or incompatible, implement the loop internally with
  explicit phase logic. Never make the engineer skill unusable because an
  optional loop plugin is missing.
- Phase-specific artifacts (research.md, requirements.md, design.md, plan.md,
  subtasks.md, review-notes.md, retrospective.md) live in the engineer skill's
  per-task directory if it keeps one, otherwise in
  `docs/workstreams/<slug>/tasks/<id>/`; never in the loop plugin.

## Linear ticket creation (optional)
- Default `create_linear_tickets: false`. Do NOT call Linear integrations
  automatically.
- Subtasks live in `implementation-plan.md` / `subtasks.md` inside the engineer
  skill's per-task directory if it keeps one, otherwise in
  `docs/workstreams/<slug>/tasks/<id>/`.
- The user may opt in via `tracking: linear` or `create_linear_tickets: true` in
  the prompt; `/git` then uses `LINEAR_API_KEY` / `LINEAR_TEAM_ID` and skips
  Linear when they are unset.

## Commit + push + PR strategy
- Branch naming: `claude/<short-task-slug>` (e.g. `claude/ratelimit-middleware`),
  which is what `/git --autonomous` creates. The rule, as the `engg` plugin's
  `git` skill states it: lowercase kebab-case slug derived from the task, max
  50 characters, no trailing hyphen; `{TICKET-ID}/{slug}` when a ticket
  exists, `{feat|fix|chore}/{slug}` when a human is driving.
- Commit by coherent subtask. Atomic commits preferred. Avoid noisy
  micro-commits AND giant commits.
- Commit only after relevant validation passes (or commit a known-failing
  intermediate state explicitly labelled in the commit body).
- Push to remote. Open the PR via `/git` (which wraps `gh pr create`). PR body
  follows the 12-item shape above.
