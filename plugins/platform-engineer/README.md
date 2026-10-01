# platform-engineer

The orchestrating entry point for Claude Code: one skill that owns a whole
task, routes each part to the specialised skill that should do it, and keeps
durable state so any later session resumes with a single line.

```bash
claude plugin marketplace add loopai-hq/loop-plugins
claude plugin install platform-engineer@loop-plugins   # declares oncall and engg as dependencies; all three install
```

## How it works

One skill, `platform-engineer`, is the entry point. On every invocation it
resolves or creates a workstream directory (`docs/workstreams/<slug>/`) so
state lives on disk rather than in the chat; classifies the ask and routes
each part to a specialised skill from `oncall` or `engg` (or your own
engineer skill) with a contract-first spec; runs the review loop before any
merge; and refuses to declare completion until the definition of done holds.
The reference files under `skills/platform-engineer/references/` are read in
a fixed order at the stage that needs them: `standing-directives.md` and
`autonomy-defaults.md` at the start of every run, `execution-engine.md`
(the spine) before the first dispatch, then `orchestration-playbook.md` and
`execution-mechanics.md` per engine stage, `investigation-standard.md` for
production investigations, and `self-augmentation.md` only when its flag is
on.

## Try it

```
/platform-engineer:platform-engineer "add rate limiting to the public API and get it live"
```

The skill creates `docs/workstreams/api-rate-limiting/` with `brief.md` (the
ask, the reconstructed intent, the definition of done) and `state.json`,
classifies the ask as a feature chain, dispatches `/engg:plan-issue` for the
design issue and `/engg:git` for the branch and PR, runs a fresh-context
review pass, hands the PR to `/engg:pr-babysit`, watches the deploy, and ends
with `COMPLETION: PR #124 merged and deployed; state.json closed out`. A later
session resumes with "Continue the api-rate-limiting workstream" and picks up
from disk.

## Skill

| Skill | What it does |
|---|---|
| `platform-engineer` | Use for any engineering ask that no single skill obviously owns end to end: multi-part or cross-repo work, "build X and get it live", vague production problems, workstreams resumed across sessions ("Continue from where you left off"), fleet-wide audits or rollouts, PR backlogs. Classifies the intent, dispatches each part with a contract-first spec, enforces dependency-before-consumer PR ordering, runs the review loop before merge, and writes `docs/workstreams/<slug>/` (`brief.md`, `state.json`, `journal.md`, ...) so the next session picks up from disk rather than memory. |

The routes it dispatches to ship in this marketplace: `/rca`, `/loki` and
`/on-call-report` from `oncall`; `/git`, `/pr-review`, `/pr-check`,
`/pr-babysit`, `/codebase-investigator`, `/engg:plan-issue`, `/evaluate`, `/doc`,
`/debug-service` and `/test-fix` from `engg`. Implementation work goes to a
language-specific engineer skill of your own when you have one; otherwise the
skill runs the feature chain (`/engg:plan-issue` -> `/git` -> implement -> review loop ->
`/git` -> `/pr-check` -> `/pr-babysit`) by hand.

## Configuration

No environment variables. The skill reads and writes:

| Path | Meaning |
|---|---|
| `docs/workstreams/<slug>/` in the current repo | Workstream state, created on first use. Commit it or gitignore it per your repo's convention. |
| `~/.claude/platform-engineer.json` | Optional, user-owned. Read once at close-out for the self-augmentation flag only. Default off; the skill never creates it. |
| `~/.claude/platform-engineer-augment-ledger.jsonl` | Written only when that flag is on; holds the self-augmentation candidates until a later sweep. Never created otherwise. |
| `~/.claude/projects/*/memory/` | Claude Code's auto-memory directory, used as the fallback surface for recall and durable-learning capture. |

Optional integrations are probed at session start and never assumed: a
personal knowledge base or recall tool, a code-graph MCP server, and Linear
through `LINEAR_API_KEY` / `LINEAR_TEAM_ID` (used only by `/git`).

## References

The skill loads these from `skills/platform-engineer/references/` as needed:

| File | Contents |
|---|---|
| `standing-directives.md` | The 22 standing directives every run obeys (evidence before claims, canary-then-fleet, run-to-production, completion markers). |
| `autonomy-defaults.md` | The execution contract: autonomy fields, depth modes, the seven true blockers, PR body shape, review isolation. |
| `investigation-standard.md` | Discipline for production investigations: triangulate sources, quantify, never conclude from one snapshot. |
| `orchestration-playbook.md` | Capability probe, dispatch rules, house rules, rationalisation table. |
| `execution-engine.md` | Intake, research ladder, execution loop, judgment layer, stage map. |
| `execution-mechanics.md` | Hooks, watchers, quotas, guarded operations, worked commands. |
| `self-augmentation.md` | The config-gated close-out that proposes skill improvements from what the run learned. |

## Provenance

The reference material was distilled, not invented. The standing directives
are the instructions that were pasted as prompt footers on nearly every
engineer invocation across roughly seventy real sessions and a year-long
prompt archive. The orchestration playbook and execution mechanics were
mined from behaviour digests of six long sessions (about 8,700 assistant
messages from a shared transcript store, including one three-day, fifty-PR
run referred to in the text as "the marathon"), a control session on a
different model tier on the same harness, a corpus of 58 outcome-labelled
sessions, a first-person session introspection, a model-router assessment,
and a 2026-07 reading of Anthropic's multi-agent research and
long-running-harness posts, Building Effective Agents, the Claude Code
sub-agent and agent-team docs, Magentic-One, Temporal durability patterns,
Plan-and-Act / Pre-Act portability evidence and LLM-judge bias studies. The
figures quoted in parentheses in the reference files (parallel-call rates,
status-to-report ratios, idle hours on question gates, the "2 recalls across
1,975 transcripts" that makes the recall pass mandatory) come from that
material; parallel-call rates were deduplicated by tool-use id, and
digest-level counts without that deduplication were discarded. None of the
source sessions, people or customers are named anywhere in the plugin.

## Notes

- It never replaces the specialised skills; it invokes them. `oncall` and
  `engg` are declared dependencies, so installing this plugin installs them.
- It pre-approves no tools of its own; a dispatched skill's `allowed-tools`
  apply while it runs. So a push or a deploy label through `/git` does not
  prompt (that is `git`'s grant), while a merge, an issue comment or a chat
  post does.
- Git mechanics always go through `/git`; the skill never runs
  `git checkout -b` or `gh pr create` itself.
