# platform-engineer

The orchestrating entry point for Claude Code: one skill that owns a whole
task, routes each part to the specialised skill that should do it, and keeps
durable state so any later session resumes with a single line.

```bash
claude plugin marketplace add loopai-hq/loop-claude-plugins
claude plugin install oncall@loop-plugins
claude plugin install engg@loop-plugins
claude plugin install platform-engineer@loop-plugins
```

## Skill

| Skill | What it does |
|---|---|
| `platform-engineer` | Use for any engineering ask that no single skill obviously owns end to end: multi-part or cross-repo work, "build X and get it live", vague production problems, workstreams resumed across sessions ("Continue from where you left off"), fleet-wide audits or rollouts, PR backlogs. Classifies the intent, dispatches each part with a contract-first spec, enforces dependency-before-consumer PR ordering, runs the review loop before merge, and writes `docs/workstreams/<slug>/` (`brief.md`, `state.json`, `journal.md`, ...) so the next session picks up from disk rather than memory. |

The routes it dispatches to ship in this marketplace: `/rca`, `/loki` and
`/on-call-report` from `oncall`; `/git`, `/pr-review`, `/pr-check`,
`/pr-babysit`, `/codebase-investigator`, `/plan`, `/evaluate`, `/doc`,
`/debug-service` and `/test-fix` from `engg`. Implementation work goes to a
language-specific engineer skill of your own when you have one; otherwise the
skill runs the feature chain (`/plan` -> `/git` -> implement -> review loop ->
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

## Notes

- It never replaces the specialised skills; it invokes them. Install `oncall`
  and `engg` alongside it or most routes will be missing.
- Git mechanics always go through `/git`; the skill never runs
  `git checkout -b` or `gh pr create` itself.
