# engg

Engineering workflow skills and review agents for Claude Code.

```bash
claude plugin marketplace add loopai-hq/loop-claude-plugins
claude plugin install engg@loop-plugins
```

## Skills

| Skill | What it does |
|---|---|
| `git` | Full git workflow in one command: branch from the default branch after pulling, run the formatter the repo already uses (pre-commit, black, ruff, gofmt, prettier, cargo fmt), commit, push, open or update a PR with a generated description, resolve addressed review threads. Standardised branch names. Optional Linear integration: creates or fetches a ticket when `LINEAR_API_KEY` is set, otherwise skips Linear entirely. `--autonomous` runs without prompts. |
| `pr-review` | Deep PR review from a principal engineer's perspective: triage, specialised passes, risk classification, security pass, cross-package impact analysis, line-level GitHub comments. Detects the stack from the repo's manifests. Triggers on "review PR", "deep review". |
| `pr-check` | After `/git` or any push: fetch review comments, plan fixes, check CI status. |
| `pr-babysit` | Carry one or more PRs from "opened" to "merged and deployed" without the user polling; `--sweep` walks a backlog of open PRs; follows up on merged PRs with unresolved threads. |
| `local-pr-review` | Offline review of a PR with a structured markdown report an AI agent can use to implement fixes. |
| `codebase-investigator` | Find where a feature is implemented, trace data flows, understand existing patterns, explain how things work. Triggers on "where is", "how does", "find the code", "what PR added". No configuration required. |
| `plan` | Detailed implementation plan as a GitHub issue, with alternatives and trade-offs, before any code is written. |
| `doc` | Search the codebase and write an engineering design doc for a system, module or pattern as a GitHub issue. |
| `evaluate` | Go/no-go evaluation of a major change: external docs and papers, codebase blast radius, risks, metrics, test strategy, recommendation. Writes the evaluation to `docs/evaluations/evaluate-<slug>.md`. |
| `deep-understanding` | Deliberate-learning walkthrough of a topic, decision, codebase, paper or bug: "teach me", "walk me through", "quiz me", "ELI5". |
| `test-fix` | Run pytest and fix failing tests iteratively until green. |
| `debug-service` | Debug a local development service that will not start or respond: port conflicts, import errors, missing dependencies, configuration. |
| `share-session` | Export a Claude Code session transcript as an interactive HTML page. Requires a `scripts/session_replayer.py` in the current repository (the replayer is not bundled with the plugin); the skill stops with a message when it is absent. |

## Agents

| Agent | What it does |
|---|---|
| `code-optimizer` | Optimisation-focused code review: duplication, performance, security and testing gaps, written to a prioritised report with before/after examples and measurable impact. `pr-review` loads it as its review-pattern catalog. |
| `security-reviewer` | Senior security review of authentication, authorisation, user input handling, database and external-system access, and credential use, with actionable remediation. Invoke proactively after writing security-sensitive code. |

## Configuration

Everything is optional. Inside a git checkout the skills infer the repository
with `gh repo view`.

| Variable | Required | Default | Meaning | Read by |
|---|---|---|---|---|
| `GITHUB_REPO` | no | inferred from the checkout | `owner/name` used for `gh --repo`, review-thread API calls and links when a skill runs outside a checkout or is given a bare PR number | `pr-review`, `pr-babysit`, `git` |
| `GITHUB_ORG` | no | none | Organisation for `pr-babysit --sweep` without a repo (`gh search prs --owner`) | `pr-babysit` |
| `SENTRY_ORG` | no | none | Sentry organisation slug; when set, `pr-review` cross-references changed files against active Sentry issues | `pr-review` |
| `SENTRY_PROJECTS` | no | every project in the org | Comma-separated Sentry project slugs to search | `pr-review` |
| `SENTRY_REGION_URL` | no | `https://us.sentry.io` | Sentry region base URL | `pr-review` |
| `LINEAR_API_KEY` | no | none | Linear personal API key. Unset means `git` performs no Linear calls | `git` |
| `LINEAR_TEAM_ID` | no | none | Linear team UUID used when `git` creates a ticket; unset makes `git` list your teams and ask | `git` |

File-based configuration:

| File | Meaning | Read by |
|---|---|---|
| `.claude/git-labels.json` in your repo, else `${CLAUDE_PLUGIN_ROOT}/skills/git/labels.json` | Path-prefix to PR-label map for deployment labels; copy `skills/git/labels.example.json` into your repo as `.claude/git-labels.json`. The `${CLAUDE_PLUGIN_ROOT}` fallback is a read-only cache that plugin updates replace. Absent means the label step is skipped | `git` (and `pr-babysit` relies on it when deploy labels gate merges) |

`codebase-investigator`, `pr-check`, `local-pr-review`, `plan`, `doc`,
`evaluate`, `deep-understanding`, `test-fix`, `debug-service` and
`share-session` read no environment variables.

## Requirements

- `git` and `gh` (GitHub CLI), authenticated. Everything that touches GitHub
  goes through `gh`.
- `python3` and `pytest` for `test-fix`. `git` runs whichever formatter the
  repository already configures and never introduces one.
- Optional: an MCP server named `sentry` for `pr-review`'s Sentry
  cross-reference and `evaluate`; `posthog` and `vercel` servers for
  `evaluate`'s metrics phase. All of these degrade to "skipped" when absent.

## Notes

- `git` never pushes to the default branch; it always creates a branch.
- `pr-review` posts inline comments and a summary on the PR. Use
  `local-pr-review` when you want a report without touching GitHub.
- The agents are plain subagent definitions; invoke them from any skill or
  directly by name.
