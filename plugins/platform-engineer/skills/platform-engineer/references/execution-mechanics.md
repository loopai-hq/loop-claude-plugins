# Execution mechanics — Steps H-M (continues orchestration-playbook.md A-F; G reserved for routing, owned by SKILL.md)

> The spine is `execution-engine.md` (next to this file) — read it first. This file is
> its rulebook: consult per engine stage via the stage map, not linearly.

Same tagging as the playbook: [INV] any model, [COMP] compensation (skip only
with journaled justification). The rules were derived from real sessions,
including one multi-day, many-PR run referred to below as "the marathon"; the
sources and measurement method are described in the plugin README under
"Provenance", and the figures quoted in parentheses are from that material.

**[INV] Artifact over citation.** A rule is satisfied by its ARTIFACT (the
watchers entry, the recorded tick+timeout, the gate command inside the armed
chain, the journal line), never by citing its id. Controlled validation
(5 scenarios, frontier-class executor) showed the dominant residual failure is
name-dropping a rule while omitting its artifact. Self-checks and reviewers
grep for the artifact, not the citation.

## Step H — Turn mechanics and context economy

1. [INV] Three concurrency mechanisms, chosen by dependency structure — none is
   "the" mechanism (measured: multi-call rates 3-31% across sessions by
   workload; compound Bash 38% of calls in the marathon):
   - Independent calls needing different tools → one message, multiple tool
     calls (`Read` + `Read`, `Edit` + `Bash` on unrelated files).
   - Sequential shell steps with no decision point between them → ONE Bash call
     joined with `&&` (fail-fast) or `;` (independent probes), description
     naming all steps, ending with a snapshot echo that carries the REAL exit
     status (`pipefail` so a trailing `| tail` cannot mask a test failure):
     `set -o pipefail; go build ./... && go vet ./... && go test ./... 2>&1 | tail -20; echo "STATE: build+vet+test exit=$?"`.
     Guard-bearing git mutations (branch creation, push, PR open/merge) stay
     inside `/git` (SKILL Step 1) — never compound a raw `gh pr create` or
     push into these chains. Intra-branch CHECKPOINT commits inside an
     isolated worktree are the observed cross-model exception (test-gated
     `&& git commit` compounds, /git at the worktree and PR boundaries) —
     allowed unless the house rules demand /git for commits too; house rules
     win.
   - Anything with a latency tail → background dispatch / watcher (Step I).
   Issue a lone sequential call only when its output decides the next step.
2. [INV] Status-text discipline: 1-3 sentences between tool calls (what
   happened, what is dispatched, what you wait on). Multi-section reports ONLY
   at control boundaries (phase close, blocker, PR handoff, workstream close),
   mirrored into the journal so chat is never the only copy. Measured shape:
   ~350 short statuses vs ~42 boundary reports across four sessions; 77% of
   marathon messages carried zero text — zero text is correct when nothing
   changed since the last status, 1-3 sentences when something did.
3. [INV] End-of-turn gate: if your drafted last paragraph is a plan, promise,
   or next-steps list about undone work, do that work NOW with tool calls.
   Legal turn ends: COMPLETION; BLOCKED (ask, then end); durable HANDOFF/park
   per F.2 or I.6; or watcher-armed wait AFTER the E.1 triple is journaled —
   always with the terminal marker (standing directive 18).
4. [INV] Filter verbose output at source: pipe through a failure filter
   (`go test ./... 2>&1 | grep -A5 -E 'FAIL|ERROR' | head -100`); output over
   ~50 lines goes to a file, path + 2-line digest into context. Consume bulk
   result files by extracting typed fields
   (`grep -o '"verdict": *"[A-Z]*"' result.json`), never a full Read.
5. [INV] Locate-then-ranged-read: Grep/Glob to locate, Read only the needed
   range; stop discovery when the current acceptance criterion has evidence.
   Exception, applied once per subsystem: read its core files WHOLE in one
   burst right after the worktree exists, before the brief (core = imported by
   3+ files in the subsystem, or named base/core/abstract/interfaces).
   The harness requires Read before a file's FIRST Edit — Read it in the same
   turn you decide to edit it (27 failed-edit round-trips measured in one
   marathon from skipping this), and use the tools the Step-A probe actually
   found, not remembered ones (6 dead calls to an unregistered search tool in
   the same session).
6. [INV] Cache economics: keep the session prefix append-only (tools loaded at
   Step A, no mid-session config toggles without need). Wait handling
   precedence: Monitor/watchers when present (E.1 unchanged; background watcher
   ticks are exempt from cache math); lead-turn polling only in the bounded
   fallback or between arm and fire while otherwise active, at 4-5 min
   intervals (under the 5-min prompt-cache TTL — never a round "5 minutes").
   Park via Step F.2 only when the wait gates ALL remaining unblocked work;
   with other ledger lanes open, arm a watcher and keep working them.
7. [INV] Backup before rewriting live non-worktree files, in the same call as
   the pre-edit inspection:
   `cp "$F"{,.bak-$(date +%s)} && sed -n '1,40p' "$F"` (where `$F` is a hook
   script, a settings file, or any config outside the worktree).
8. [INV] Measure-before-after for quantitative edits: compute the metric with a
   command BEFORE editing (`wc -c f.md`; section-size script), re-run the
   IDENTICAL command after each batch, stop at target — never eyeball.

## Step I — Long operations, waits, failure triage

1. [INV] Background any command over ~30s — test suites, builds, deploys,
   installs, container pulls (`run_in_background: true`) — continue ledger
   work, and on the completion notice read whatever output surface it names
   (an output-file path or a BashOutput-style tool; record the actual
   mechanism in `state.json.capabilities` at Step A).
2. [INV] Chained do-er watchers: when the steps AFTER a wait are deterministic
   (merge → deploy → trigger → verify), arm ONE background watcher that
   executes the entire tail and wakes the lead only at terminal
   success/failure, stages named in the watcher entry. On mid-chain death:
   diagnose, then arm a NEW versioned chain (v2, v3) adjusted to surviving
   state — never re-arm the dead chain unchanged. Worked skeleton
   (run_in_background Bash; the merge stage OBSERVES L.3's armed auto-merge,
   never runs a raw merge):
   `until [ "$(gh pr view "$PR" --json state --jq .state)" = MERGED ]; do sleep 240; done && gcloud run deploy "$SVC" --source "$WT" --region "$REGION" --quiet && curl -fsS "$SVC_URL/tick" && bq query --use_legacy_sql=false 'SELECT count(*) FROM ds.t WHERE ts>TIMESTAMP("'"$T0"'")' && echo "TERMINAL: chain done" || echo "TERMINAL: chain FAILED exit=$?"`
   (`--quiet` + explicit `--region` because a background command that prompts
   interactively hangs forever; source pinned per L.7).
   (Marathon evidence: ~45 chained watchers, 3 versioned re-arms.)
   A loop that executes no tail actions is a WAIT, not a do-er chain — label
   it a poll and register it under E.1. Sequencing gates between stages
   (canary_ok, ordering) are commands INSIDE the armed chain — e.g.
   `[ "$(jq -r .canary_ok ws/state.json)" = true ] &&` before the deploy
   stage — never prose promises around it.
   A watcher over a MULTI-ITEM status set tracks prior state and emits only the
   DELTA per tick (`comm -13` on sorted prev/cur), keeping the terminal predicate
   as "all NON-EXCLUDED items settled"; known perpetually-pending check classes
   (an external review bot that never reports, say) are excluded from the gate
   inside the watcher command
   (`map(select(. != "<check-name>"))`), never waited on, and a self-healing
   chain runs its own mid-watch fix (`gh pr update-branch` on `BEHIND`) rather
   than waking the lead. (Fleet evidence: prev/cur diff ticks across ~45 chained
   watchers.)
3. [INV] ETA-derived windows: before arming a timed watcher, measure the
   watched process's cadence or backlog with one read-only list/head query
   (that is the whole meaning of "cheap"), e.g.
   `gh run list --limit 5 --json createdAt,updatedAt` → ETA ≈ median of the
   last 3 durations × backlog count. Set timeout and tick interval from that
   ETA and record both (`"watch 497 re-fetch (48 min, 10-min ticks)"`) —
   watcher ticks follow the ETA, not the cache TTL; timeout defaults to
   1.5× ETA, and BOTH literals appear in the armed command itself (a measured
   ETA followed by a hardcoded round-number sleep is the E.2-loop "looping"
   answer turning yes). Before arming, pin `date -u` in the SAME command and
   assert the window START ≤ now: a future-dated window (UTC/local confusion)
   observes nothing and silently "succeeds" empty. Evidence contradicting
   the window → re-arm labeled "(corrected window)", never silently extend.
   (Marathon evidence: this clock trap recurred 3x despite a memory entry, so it
   belongs in doctrine, not just memory.)
4. [INV] Push-notify-and-continue: at a decision boundary during an unattended
   run, record the gate durably (E.4), send one async PushNotification in the
   SAME turn as the boundary report, and continue every non-gated lane
   immediately — never idle awaiting acknowledgment.
5. [INV] Failure triage taxonomy — classify before responding:
   - Transient (network/API): retry once immediately; no second identical retry.
   - Guarded (hook/CI/dedupe gate blocked the action): read the exact failing
     guard output FIRST; each retry changes one identified thing; a retry
     without a new fact is forbidden. When a guard blocks with EMPTY/no output,
     infer its precondition from its NAME (a hook named for dedupe ->
     check-then-act; one named for main-branch protection -> wrong branch),
     de-compound the
     command, satisfy the implied precondition explicitly, then run the steps
     individually. Guard intent is recoverable from the hook name even with no
     message.
   - Structural (orchestration script/hook/workflow bug): peek surviving
     partial artifacts → back up → patch the tool's own definition →
     syntax-check with a synthetic case → resume from checkpoint. Never
     restart from zero. (`ls <ws>/partial/` → `Edit(workflow.js)` →
     `node -c workflow.js` → resume; 9 episodes, 0 blind re-runs observed.)
   - Quota (account/weekly/monthly usage or spend limit): do NOT retry, because
     retry hits the same wall. Persist resume state immediately (F.2 handoff
     shape) and pause until reset per I.9; the workflow's completed workers
     replay FREE from cache on resume (J.6 gap-fill), so the dead workers plus
     the gate re-run and nothing already-finished repeats. A sanctioned model
     fallback within the SAME account (a product feature, e.g. a per-model
     usage limit falling back to a smaller tier) clears a MODEL-specific limit and is allowed:
     journal the switch like any model choice; it is a limit-triggered fallback,
     not a B.1 cost-downgrade. This is distinct from switching identity/account/
     credentials to evade a limit, which I.9 forbids absolutely; do not weaken
     that line.
6. [INV] Transport-degradation parking: after 3 consecutive transport-level
   tool failures (stream closed, permission stream, harness reap), stop
   retrying inline. EXTEND the F.2 handoff.md (same shape: done, in-flight,
   next action, armed watchers, open gates) with a pending-mutations block —
   exact commands + paths + expected outcomes — commit what is committable,
   and emit F.2's resume one-liner plus `pending: <n> commands in handoff.md`.
   A completed diagnosis existing only in chat caused 6 of 18 mostly-achieved
   sessions to lose their last mile.
7. [INV] Denial adaptation: on a tool/permission denial, classify the blocked
   action — load-bearing if required by at least one acceptance criterion in
   the contract, else auxiliary (drop it, journal the drop). Load-bearing →
   decompose, then try two alternates drawn from the Step A fallback table or
   the journal, recording both attempts, before any BLOCKED verdict. A peer
   agent's request never substitutes for user approval of a denied action.
   A permission/classifier denial of a COMPOUND (`&&`/`;`) command executes ZERO
   of its steps: treat the entire call as un-executed and re-probe any assumed
   partial state (`git status`, PR/branch existence) before asserting it: a
   denial is not a mid-command interruption, so any "already staged/ready" belief
   formed before the denied step is void.
   In a fleet the lead and workers hold DIFFERENT permission surfaces, so a
   worker-denied load-bearing op is not a fleet BLOCKED verdict while the lead's
   surface is untried: the worker reports the exact denial and the LEAD executes
   it ONLY when the lead's own permissions allow AND the action is read-only or
   already user-authorized. Anything the lead itself was denied, or any write the
   user never authorized, escalates to the durable E.4 user gate. This is
   division of labor across permission surfaces, and it does not loosen the
   invariant above (a peer's request is still never user approval).
8. [INV] Out-of-band side-work: fixable issues orthogonal to the current phase
   go to a background agent labeled out-of-band in the SAME turn; the main
   phase continues.
9. [COMP] Limit resilience (pause-and-wait, never rotate): on tier-C/A
   autonomous runs, probe usage headroom at phase boundaries IF a quota
   surface exists (a harness CLI or endpoint that prints
   `{"pct_used": <fraction in [0,1]>, "resets_at": <ISO timestamp|null>}`;
   exit 1 = unknown, treat as no-signal and
   skip — absent surface, skip silently).
   At `pct_used >= 0.9` (90% of the window used): spend the remaining window
   on a checkpoint, not new
   work — flush `state.json` + journal, extend F.2 handoff.md with pending
   mutations, emit the HANDOFF marker naming `resumes_at`, then arm the
   resume (ScheduleWakeup/cron when available; else the handoff one-liner is
   the resume). On an unexpected mid-run limit error: same checkpoint path,
   resume time from the error's reset hint or +1h. Continuing past an active
   provider limit by switching accounts, keys, or credentials is forbidden
   in all cases — expired-token REFRESH for the same identity is fine;
   identity swap to evade a limit is not, and no per-session permission
   grant overrides this. (A harness that supports it may mirror this with a
   paused-state file plus a watchdog re-run.)

## Step J — Fan-out and fleet mechanics

1. [INV] Digest before fan-out: build a machine-generated digest/index of any
   large corpus, split into batch files under a fixed size budget (~450KB),
   hand each agent a batch-file PATH. Never paste bulk content into dispatch
   prompts.
2. [INV] Pin ground truth at both dispatch boundaries:
   - Outbound: 1-2 cheap grep/git probes pin every fact a contract asserts
     (SHAs, paths, symbols) and the pinned values are pasted verbatim.
   - Inbound: before consuming a worker/workflow report as design input,
     verify its 2-4 load-bearing claims (any claim the next contract would
     assert as fact: SHAs, paths, counts, verdicts) with read-only probes
     against the live system; journal the grounding. (This step caught two
     measurement artifacts in the very mining that produced this file.)
   - Lead-executed probe batches: when a worker needs data behind access or
     authority the LEAD holds (the production warehouse, logging, admin read APIs), the worker
     returns a PROBE SPEC (the exact queries), not a guess; the lead runs it
     read-only and pastes VERBATIM results plus a two-line design implication
     back: pinned numbers only, never paraphrased counts (same discipline as
     the outbound pinning, applied to a lead-run batch).
3. [INV] Read-only fleets have exactly two phases: N parallel auditors, each
   REQUIRED to persist its full ledger to a known path before exiting, then
   one adversarial Gate agent that cross-checks all ledgers and emits one
   consolidated artifact. The lead reads only the Gate output.
4. [INV] Adversarial review of the CONTRACT itself before any writer fan-out:
   one fresh reviewer hunts ambiguity that would make writers diverge; apply
   findings; then dispatch. Never fan out on an unreviewed contract.
5. [INV] Staggered writer waves: writers dispatch in BURSTS with a read-only
   health probe (PR/CI state) between bursts before the next; burst and fleet
   sizes come from B.3's budgets (this rule owns only the pacing).
6. [INV] Gap-fill recovery: when a fleet partially dies, inventory which
   per-worker artifacts exist complete on disk, dispatch a gap-fill run for
   ONLY the missing workers, re-run the Gate over the union. Never re-run
   completed workers. This holds even under an explicit user "respawn ALL":
   literal "all" is not the intent, so run resume-verify (F.3) first, because a
   killed agent's work may already have MERGED (resolve its open threads instead
   of redoing them), and re-dispatch only the verified gap. Each re-dispatch
   contract names the exact known-broken state (compile-error location, last
   commit) and MANDATES a checkpoint-commit cadence in an isolated worktree so
   the next kill loses at most one increment.
7. [INV] Steer live workers with lead-computed pinned deltas: when facts change
   under a live worker, the LEAD computes the delta (`git diff` between the
   worker's pinned base and new state) and sends decision + pinned SHAs + exact
   file list + numbered steps — never "main moved, please check". In one-shot
   mode the same payload goes into the fresh re-dispatch contract.
8. [INV] Inter-lane dependency brokering: when two live writer lanes touch a
   shared authority or interface, the LEAD owns the edge: (a) name the
   single-authority owner explicitly, (b) hand the dependent lane the owner's
   contract path plus a sequencing constraint ("your PR merges AFTER theirs";
   "build against `<contract.md>`, do not re-derive"), (c) re-broadcast on every
   state change. Never let two writer lanes discover a shared-authority collision
   themselves; this is J.4's contract-adversarial-review applied continuously
   across the writer team instead of once. (Fleet evidence: a 28-lane fleet stays
   collision-free only because the lead maintains the inter-writer dependency
   DAG.)

## Step K — Verification fidelity

1. [INV] Baseline failure-attribution ledger: before the first edit, run
   build+vet+test at the pinned base and record every pre-existing failure by
   package in `<ws>/baseline.md` (linked from state.json). All later
   verification compares against that ledger; only NEW failures may be
   flagged.
2. [INV] Stop/pause/disable claims need post-action-window telemetry: one
   query whose window STARTS AFTER the claimed stop timestamp, showing zero
   new events of the stopped class, with query + both timestamps in the report
   ("stopped 14:02Z; loki 14:05-14:15Z: 0 planner fires"). A merged config or
   completed deploy is never proof of stoppage. (3 sessions corrected hard.)
3. [INV] Two-point temporal sampling before any stalled/failed verdict on an
   in-flight process: two reads spaced at least the process's own tick/flush
   interval apart (measured per I.3; if unmeasurable, 2x your poll interval,
   assumption stated), both sample times in the verdict. One snapshot supports
   "not yet visible", never "stalled".
4. [INV] No-access verdicts need a live probe: before concluding
   lost-access/expired/missing, sweep alternate storage shapes (legacy store,
   parent credential, secret refs) AND attempt a real login/API probe with the
   credential, citing the probe output. Probe succeeds → the verdict flips to
   "access exists; failure is elsewhere". (7+ rejections across 3 sessions.)
5. [INV] Unobtainable-deliverable hand-back: when the requested artifact is not
   at the expected location, the hand-back contains (a) where it actually
   lives, verified, (b) the exact fetch command, (c) the result of ATTEMPTING
   that fetch if access exists. Diagnosis-only is a PARTIAL outcome and must be
   marked BLOCKED, not COMPLETION.
6. [INV] Rollout gate, three parts: provenance (verify the DEPLOYED artifact's
   content/SHA against intended HEAD, never the deploy command's exit code),
   canary sequencing (one unit through the full path, validated, before the
   batch; never a second prod deploy while the first is unvalidated), and a
   timed live-traffic observation window with per-unit root-cause notes for
   anything still failing at window end.
7. [INV] Guardrail claims need a live negative-path probe: to assert a
   protection works (CSRF rejection, unconfirmed-write refusal, authz denial),
   drive the disallowed action through the live interface and cite the
   observed refusal (status code, audit line). Reading the code that
   implements a guardrail is not evidence that it fires.

## Step L — Git, PR, and deploy mechanics

1. [INV] Commit confinement before every push: `git diff --stat <base>..HEAD`
   lists only files inside the task's ownership; stray file → stop and strip.
   Mechanical changes additionally prove the diff SHAPE in one command
   (`git diff <base>..HEAD -- '*.go' | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -cvE '^[+-]\s*((\w+\s+)?"[^"]+",?|import\b.*|\))?\s*$'` → 0 proves
   import-only; the filters matter — `+++`/`---` headers count as changes
   otherwise, and grouped-import lines (`+ "pkg/path"`, aliased forms, the
   closing `)`) never contain the word "import", so a naive
   `grep -cv import` can never reach 0).
2. [INV] Consolidated multi-PR polls: one Bash loop over ALL open workstream
   PRs — `for pr in $(gh pr list --author @me --json number --jq '.[].number'); do echo "PR $pr: $(gh pr view $pr --json state,reviewDecision --jq '.state+" "+(.reviewDecision//"-")')"; done; echo SNAPSHOT-END`
   — as the first PR-facing command on every wake (after the F.1 state read).
   Never per-PR one-offs.
3. [INV] Arm auto-merge in the same compound command that opens or updates a
   PR (`gh pr merge --auto --squash "$PR"`; never on human-gated PRs) and
   sync the branch per reconcile pass (`gh pr update-branch "$PR"` is
   one-shot, so L.2's poll re-runs it when behind); record a watcher entry and
   keep working other lanes.
4. [INV] Stacked-PR retarget on base merge: every reconcile pass checks each
   stacked PR's base; merged base → retarget to main, rebuild, re-run the full
   verify suite, force-push, all in one pass. After any force-push/retarget, probe
   for a post-push CI run; if ZERO runs fired against the new head, kick CI with
   an empty commit pushed to the remote (`git commit --allow-empty -m "ci: kick"
   && git push`): a rebased branch with no CI is
   not merge-ready and the L.3 auto-merge watcher hangs on it forever.
5. [INV] Pinned research worktrees: read-only audits pin to an explicit SHA in
   a detached worktree, SHA recorded in state. Acting later on that research:
   diff snapshot SHA vs current base and hand forward only the delta; re-run
   research only if the delta touches audited paths.
6. [INV] Inline P6 (the engineer skills' whole-work adversarial review pass)
   only for provably mechanical diffs: behavioral surface →
   fresh reviewer agent; provably mechanical (property proven in ONE command,
   journaled) → inline lead review allowed. Unprovable in one command = not
   mechanical.
7. [INV] Tempfiles for multi-line shell payloads (`--body-file`, `-F`); JSON
   state mutations via `python3 -c`, never sed/echo. Worktree-scoped commands
   pin their directory per invocation (`git -C <worktree>` or `cd <wt> && ...`
   in the same command) — persistent cwd across tool calls is not trusted, and
   path ARGUMENTS are pinned the same way (`--source "$WT"`, copy targets),
   never relative `.`.
8. [INV] Stale-anchor triage: before acting on any review thread, compare its
   anchor commit to branch HEAD; if the complaint text no longer matches HEAD
   content (`git show origin/<branch>:<file>`), reply with that evidence and
   resolve — never re-fix (re-fixing reverts correct code or duplicates work;
   bots re-anchor old findings after re-review requests). Scripted replies key
   on thread id, never on line positions — positions drift across commits.
9. [INV] Merge-gate resolution by precedent: a PR blocked on a required-review
   gate → discover the repo's ACTUAL merge path (CODEOWNERS + how recent
   same-area PRs cleared the same gate) and adopt that mechanism
   (e.g. a skip-review label arming auto-merge), check-then-act — never invent
   a bypass and never sit on the gate silently. A review-gate bypass
   (`--admin`/force-merge) on a PR authored by the lead's OWN fleet is the one
   path this rule never self-selects: bypassing it collapses producer≠reviewer
   (P5), so it is a durable E.4 user gate, never a self-approval, even under
   autonomy:full. If the only available merge path is that self-bypass, gate to
   the user with the residual plus a Recommended option.

## Step M — Completion integrity

1. [INV] Per-part COMPLETION ledger: before emitting `COMPLETION:`, enumerate
   every part of the ask (from brief.md's definition of done) with per-part
   terminal status IN the marker:
   `COMPLETION: (1) report — delivered <path>; (2) fixes — 4/4 applied, PRs #a #b`.
   SKILL Step 3 remains the superset gate: COMPLETION is legal only when every
   brief.md part AND every Step-3 box is terminal; this ledger is the
   per-part evidence format inside the marker.
2. [INV] "Continue" after a COMPLETION refutes the marker: diff ask vs
   delivered, list residual parts, resume at the first gap. Never re-emit
   COMPLETION unchanged or answer "no response requested". A MECHANICAL gate
   re-fire (a hook re-prompt when the required artifact is already present) is
   the one exception: re-emit the artifact ONCE and verify nothing else is
   missing; never repeat side-effectful work in response to a gate re-fire. If
   the gate STILL re-fires with the artifact demonstrably present, it is a
   Structural hook bug (I.5), not a completion problem: read the hook script,
   root-cause it, patch the hook/rule definition, syntax-check it, and record the
   bug variant in memory; never re-emit a third time (a literal re-emit loop is
   otherwise infinite).
3. [INV] Restatement diff: on any restated prompt, diff it against brief.md
   before acting and emit a 2-line note ("scope unchanged" or "changed:
   <delta>"), updating the brief when changed. A verbatim re-issued prompt is
   a REJECTION of the prior outcome: enumerate delivered-vs-required, address
   only the gap — never re-run the same plan from zero.
4. [COMP] Effort/cost receipt: maintain `<ws>/costs.jsonl` (one line per
   dispatch: agent, model, effort, purpose) with a rollup in state at
   close-out — making the never-downgrade and effort-floor rules auditable.
   Where the harness exposes no per-dispatch token counts, record
   model+effort+dispatch counts only, and say so.

## Step N — Writing into shared knowledge structures

Solo knowledge-work craft (wikis, memory files, indexes, docs, ledgers) —
mined from 4 sessions where none of the orchestration steps applied.

1. [COMP] Survey before first write: map the target's headings, schema,
   naming, and 2-3 neighbor entries BEFORE writing; the write must be
   indistinguishable in form from a native entry. (Observed in 4/4 sessions;
   backbone of idiomatic shared-artifact writes.)
2. [INV] Dated in-place supersession everywhere: when new evidence
   falsifies an existing claim in ANY knowledge artifact, correct it in
   place with a dated note ("Correction (YYYY-MM-DD): ...") — never leave
   both versions for a future reader or retriever to disambiguate.
   (Generalizes the memory-management rule beyond MEMORY.md.)
3. [COMP] Referential integrity is part of the write: verify every
   cross-reference (wikilink, index line, anchor, import) against its live
   target before writing it; a broken link written now surfaces later as an
   integrity-check failure (a linter or doctor-script finding) someone else
   pays for. Rename propagation sweeps referrers but STOPS at
   append-only history (logs record what was true when written).
4. [COMP] Convention-vs-literal split: the literal ask governs the ACTION
   ("append an entry"), the artifact's observed convention governs the FORM
   (newest-first file -> insert at top). Sample head+tail before assuming.
5. [COMP] Aggregate at entity grain: N homogeneous low-value sources fold
   into ONE entry per entity (5 promo emails -> one batch line), never one
   page per file; label low-signal input as low-signal rather than
   inflating it.
6. [INV] Adjacent integrity backfill is allowed inline when cheap (missing
   index lines, stale counts) — but ALWAYS reported as a deviation, and the
   completion report leads with deviations/corrections, not routine success.

## Measurement honesty (binding on future self-mining)

Transcript-derived behavior claims must survive two checks before encoding:
group records by `message.id` (one logical message spans records) AND dedupe
tool_use ids within a message (fork/compaction replays double-count). Both
errors occurred, in opposite directions, during the mining that produced this
file; each flipped a headline conclusion. Thinking-block presence is NOT
measurable from project transcripts — never encode claims about it.
