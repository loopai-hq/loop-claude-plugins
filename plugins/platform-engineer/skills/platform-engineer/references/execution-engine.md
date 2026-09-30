# Execution engine — the northstar spine (read FIRST; A-F and H-M are its rulebook)

This file is the distillation of everything the rulebook files encode: six
generative principles, one operating loop, one complexity ladder, one
confidence discipline. The playbook (Steps A-F) and execution mechanics
(Steps H-M) are the APPENDIX — per-situation rules the engine consults by
stage, evidence-backed and unchanged. When this file and a rulebook rule seem
to conflict, the engine's principle states the WHY; the rule states the HOW;
follow the rule and journal the tension.

Validated: on frontier-class executors, doctrine roughly doubles scenario conformance
(3-6/10 → 8-9/10); the dominant residual failure is citing a rule without
producing its artifact. Hence the engine's one meta-law: **a principle is held
by its artifact, never by its mention.** The spine never substitutes for the
rulebook — 3-arm validation showed spine-first readers drop rulebook setup
artifacts unless they are enumerated, so the two tables below are the MINIMUM
disk state, not the whole.

## Stage-zero artifacts — exist before the first component runs (tier S and up)

| Artifact | Rule | Written where |
|---|---|---|
| Capability inventory | A.1-A.2 | `state.json.capabilities` |
| Effort/model journal line (xhigh floor on frontier-class) | B.1 | `<ws>/journal.md` |
| Cost receipt file opened | M.4 | `<ws>/costs.jsonl` |
| Baseline failure ledger (whenever code will change) | K.1 | `<ws>/baseline.md` |
| Tier classification | ladder below | `state.json.tier` |

## The six principles (everything else falls out of these)

P1. **Disk is truth; context is cache.** Any belief that matters either cites
    a tool result from this session or lives in a file that a cold session
    could re-derive it from. Context windows compact, die, and hallucinate;
    files do not. This generates: `brief.md`/`state.json`/journal/ledger,
    resume-verifies-never-trusts (F.3), evidence fields (C.3), handoff over
    compaction (F.2).

P2. **Intent is pinned before work and everything is measured against the
    pin.** The user's verbatim ask plus a reconstructed intent, definition of
    done, exclusions, and assumptions-each-with-a-check, written BEFORE
    execution. Restated prompts are diffed against the pin (M.3); "Continue"
    after COMPLETION refutes the marker (M.2); delivery is graded against the
    reconstruction, not the literal words.

P3. **Work is shaped into review-sized verifiable components.** Decomposition
    grain = one review pass can verify one component (C.1); every component is
    born with NON-EMPTY binary acceptance criteria and an empty evidence slot. Ambiguity
    is shrunk by evidence acquisition, never by silent assumption: each
    unknown becomes a cheap probe, a research task, or a recorded assumption
    with a falsification check (SKILL Step 0.4 research fan-out; SKILL Step 2
    validate-then-modify).

P4. **The turn is a scheduler, not a script.** A lead turn reads state,
    restores whichever invariant below is most broken, advances every
    unblocked component, backgrounds everything with a latency tail (failure-
    covering wake conditions), and CLOSES with two artifacts: the state write
    (including the `state.json.stall_count` update, E.3) and the one-line
    six-question journal answer (E.2 — the turn's own heartbeat; a turn
    without its line did not happen). Plans are revisable artifacts; the invariants are not:
    - I1: every part of the pinned intent has an owner and a verifiable
      terminal state (C).
    - I2: every wait is a triple — failure-covering wake, timeout, on-timeout
      action — registered on disk (E.1).
    - I3: every claim carries evidence at or above its confidence label (K).
    - I4: every failure has a triage class and exactly one changed fact before
      any retry (I.5, E.3).
    - I5: disk state is fresh enough that a cold session resumes without
      re-deriving anything (F.1).

P5. **Verification is uncorrelated with production.** The producer never
    grades its own work; reviewers get task + rubric + end-state, never
    rationale (D-REVIEW); one evidenced refutation kills any number of
    approvals; claims about the world are probed world-side (negative-path
    K.7, post-action windows K.2, two-point sampling K.3, provenance K.6).

P6. **Loops are bounded and escalate; claims are capped by evidence.** Two
    no-progress turns force a re-plan (E.3); retries change one named fact;
    effort and model tier escalate and never degrade (B.1, E.3); every
    component carries a confidence state — `verified` (uncorrelated check
    passed) > `observed` (own tool result) > `assumed` (recorded, checkable)
    > `unknown` — and no report ever states a conclusion above its label.
    DONE is a per-part fixpoint against the intent pin (M.1) closed by one
    question: what is missing — part unverified, probe unrun, source unread?

## The ladder — classify BEFORE executing, escalate on evidence

| Tier | Signature | Engine behavior |
|---|---|---|
| T — trivial | one obvious action, no ambiguity | Do it, verify it, done. No ceremony: no ledger, no contracts. P1/P6 still bind (evidence before claims). |
| S — single-session, clear | hours of work, known shape | Light pin (brief.md), turn-scheduler loop, self-verify + one uncorrelated check on the production path, fixpoint close. |
| C — complex, clear | decomposable, multiple components or writers | Full pin, review-grain decomposition, delegation contracts (D), per-component uncorrelated review, whole-work adversarial pass. |
| A — ambiguous and/or multi-day | intent underspecified, spans sessions, evidence contradicts itself | Research-FIRST: ambiguity register (each unknown → probe / research task / assumption-with-check), adversarial completeness gate on research, THEN run as C with session chaining. Claiming tier A OBLIGATES three artifacts, checkable on disk at any moment: `<ws>/handoff.md` current at every session boundary (F.2), `state.json.watchers` non-empty whenever any calendar wait exists (E.1), and a resume-verification journal line opening every resumed session (F.3). Tier A without these three is tier A in name only. |

Misclassification is the expensive error in both directions: A-treated-as-S
drifts and dies at the first session boundary; T-treated-as-C drowns in
ceremony. Classify explicitly in `state.json.tier`, and RE-classify upward the
moment evidence contradicts the tier (an "S" that spawns a second writer is a
C; a "C" whose requirements moved twice is an A). Never escalate silently and
never downgrade to avoid ceremony.

## The loop — one task's life through the engine

1. **INTAKE** (P2): pin intent. When a personal knowledge base or recall tool
   is present (probe once at Step A), INTAKE opens with ONE recall pass on the
   task text via whichever recall surface the probe FOUND (a recall skill, a
   local search CLI, a wiki query) — hits skimmed into the pin:
   prior decisions and incident recipes are cheaper than rediscovery, and
   left optional the pass is almost never run (README, "Provenance").
   Absent → skip silently. For tier A,
   build the ambiguity register before anything else; the first components
   ARE its probes.
2. **DECOMPOSE** (P3): components at review grain. Each ledger entry is born
   with FOUR engine fields on top of the standard ledger fields
   (id/subject/status/blockedBy, C.3) — NON-EMPTY binary acceptance criteria, an empty evidence
   slot, dependency edges/priority (C.1), and `confidence: "unknown"`
   (promoted only by an own tool result → `observed`, or an uncorrelated
   check → `verified`; a recorded assumption-with-check enters as `assumed`,
   and its falsification check either promotes it or kills the component —
   `assumed` never survives to CLOSE unpromoted).
   Discovered work becomes a new component immediately — scope changes are
   ledger events, not vibes.
3. **EXECUTE** (P4): run the turn-scheduler until no unblocked components
   remain. Delegation follows D (contract → isolated execute → uncorrelated
   review → bounded follow-up → accept); solo execution follows H-I (turn
   mechanics, background-first waits).
4. **VERIFY** (P5): per-component review at accept time, whole-work
   adversarial pass against the intent pin before any completion claim,
   world-claims probed world-side (K).
5. **CLOSE** (P6): per-part fixpoint ledger in the marker (M.1), completeness
   question answered explicitly, receipts rolled up (M.4), durable learnings
   captured (F.4), state closed with a retrospective.

## The judgment layer — tie-breakers where rules run out

These are the calls the rulebook cannot make mechanically; make them
explicitly and journal them:

- A fork mid-run → classify REVERSIBILITY first. Reversible (internal design,
  naming, ordering, anything a later commit can undo) → decide, journal the
  assumption with its falsification check, announce and proceed ("proceeding
  with X unless you object"; I.4 push notification when unattended). Irreversible or
  high-blast-radius (data deletion, prod schema, external comms, spend) →
  E.4 durable gate. Measured: 17.4 hours of one marathon was the lead idle
  on question-gates for forks it was authorized to decide.
- Two defensible decompositions → pick the one whose components are CHEAPER TO
  VERIFY, not fewer or more elegant.
- Confidence borderline (`observed` but consequential) → spend one probe to
  reach `verified` before reporting; the probe is always cheaper than the
  retraction.
- Scope and intent conflict mid-run → intent wins, the conflict is surfaced to
  the user in the same turn, work continues on the non-conflicted parts.
- A rule and fresh evidence conflict → evidence wins for this run; the
  divergence gets a journal line (and, if recurring, an augmentation-ledger
  entry) — rules are updated by PRs, not violated silently.
- Proportionality everywhere: ceremony scales with tier; report length scales
  with information content, never with effort spent.

## Stage → rulebook map (consult per stage, not linearly)

| Engine stage | Rulebook steps |
|---|---|
| Session start / resume | A (probe), F.1/F.3 (startup, resume), B (model contract) |
| INTAKE | SKILL Step 0 (workstream state), M.3 (restatement diff) |
| DECOMPOSE | C (ledger), Step 0.4 (research fan-out), J.1 (digest-before-fanout) |
| EXECUTE — delegation | D (state machine), J (fan-out mechanics) |
| EXECUTE — solo turns | H (turn mechanics), I (long-running ops), E (waits, stall) |
| EXECUTE — knowledge writes | N (shared knowledge structures) |
| VERIFY | D-REVIEW, K (verification fidelity) |
| Git/PR lanes | L (+ /git routing per SKILL Step 1) |
| CLOSE | M (completion integrity), SKILL Step 3 (definition of done) |
