# loop-claude-plugins

Public [Claude Code](https://code.claude.com/docs/en/plugins) plugins from
Loop AI. These are the skills our engineers run every day, published with our
own identifiers (cloud projects, chat channels, hostnames, repositories)
replaced by a small set of configuration variables. The value is the
procedure each skill encodes, not the ids, so the method is unchanged.

Three plugins ship from the `loop-plugins` marketplace:

| Plugin | What it is for |
|---|---|
| `oncall` | Incident response: query Grafana Loki logs, run a structured root cause analysis, produce an on-call health report |
| `engg` | Day-to-day engineering: git and PR lifecycle, PR review and babysitting, codebase investigation, plans and design docs, plus two review agents |
| `platform-engineer` | Orchestration: classifies a task, routes it through the `oncall` and `engg` skills (or your own engineer skill), and keeps durable workstream state across sessions |

## Install

```bash
claude plugin marketplace add loopai-hq/loop-claude-plugins
claude plugin install oncall@loop-plugins
claude plugin install engg@loop-plugins
claude plugin install platform-engineer@loop-plugins
```

Plugins install at user scope (`~/.claude/`) and do not modify any repository.
Skills are invoked as `/oncall:loki`, `/engg:git`, and so on; the bare name
(`/loki`, `/git`) also works when no other plugin defines it.
`platform-engineer` routes to the other two, so install all three for the
full set of routes.

Update later with:

```bash
claude plugin marketplace update loop-plugins
```

## Configuration

Every skill reads its settings from environment variables. Set them in the
shell that launches Claude Code, or in the `env` block of your
`.claude/settings.json`. Each `SKILL.md` has a "Configuration" section near
the top listing exactly the variables it reads; the table below is the union.

| Variable | Required | Default | Meaning | Read by |
|---|---|---|---|---|
| `LOKI_URL` | yes, for `loki` | none | Base URL of your Grafana Loki gateway, e.g. `https://loki.internal.example.com` | `loki` |
| `LOKI_AUTH_HEADER` | no | none | Full header for gateways that need one, e.g. `Authorization: Bearer <token>` | `loki` |
| `GCP_PROJECT` | for `rca` | none | Google Cloud project id of production (log explorer links, `gcloud logging read`) | `rca` |
| `GCP_STAGING_PROJECT` | no | none | Google Cloud project id of staging | `rca` |
| `SENTRY_ORG` | for `rca`, `on-call-report` | none | Sentry organisation slug. `pr-review` skips its Sentry cross-reference when unset | `rca`, `on-call-report`, `pr-review` |
| `SENTRY_REGION_URL` | no | `https://us.sentry.io` | Sentry API base for your org's region | `rca`, `on-call-report`, `pr-review` |
| `SENTRY_PROJECTS` | for `on-call-report` | none (`rca`, `pr-review`: every project in the org) | Comma-separated Sentry project slugs to scan | `rca`, `on-call-report`, `pr-review` |
| `SENTRY_AUTH_TOKEN` | for `rca` step 4 | none | Sentry API token (a secret) used by the alert-inventory check | `rca` |
| `GITHUB_ORG` | for `on-call-report` | none | GitHub organisation whose issues and PRs are scanned; `pr-babysit --sweep` uses it for org-wide sweeps | `on-call-report`, `pr-babysit` |
| `GITHUB_REPO` | for `rca`, `on-call-report` | inferred from the current checkout by the `engg` skills | `owner/name` of the primary repository; `engg` PR skills use it when the repository cannot be inferred from the checkout | `rca`, `on-call-report`, `pr-review`, `pr-babysit`, `git` |
| `POSTHOG_PROJECT_ID` | no | none | PostHog project id used to build session-replay and error links | `rca`, `on-call-report` |
| `APP_URL` | no | none | Public URL of your main web app | `rca` |
| `ADMIN_URL` | no | none | URL of your admin app, if separate | `rca` |
| `API_URL` | no | none | URL of your API host | `rca` |
| `VERCEL_PROJECTS` | no | none | Comma-separated Vercel project names to check for deployments | `rca` |
| `RCA_DOCS_DIR` | no | `docs/rca/` | Directory (relative to the repo) where RCA documents are written; `on-call-report` saves reports to its sibling `reports/` directory | `rca`, `on-call-report` |
| `ONCALL_CHANNELS_FILE` | no | `${CLAUDE_PLUGIN_ROOT}/skills/on-call-report/channels.json` | Tiered Slack channel config; copy `channels.example.json` to a path outside the plugin directory and point this at it | `on-call-report` |
| `COMPANY_NAME` | no | `GITHUB_ORG` | Name printed in report titles and document headings | `on-call-report` |
| `LINEAR_API_KEY` | no | none | Linear personal API key. When unset, `git` skips ticket creation and lookup entirely | `git` |
| `LINEAR_TEAM_ID` | no | none | Linear team id (UUID) used when creating tickets | `git` |

Linear is optional throughout. Nothing else in these plugins depends on it.
`platform-engineer` reads no environment variables of its own.

### Files you fill in

Some skills read a config file you create from a shipped `*.example.*`
template. Keep the filled-in copy in your own repository or at a path you
choose, never inside the installed plugin: a marketplace install lives in a
version-keyed cache directory (`~/.claude/plugins/cache/loop-plugins/<plugin>/<version>/`)
that is replaced on every `claude plugin update` and reinstall, so anything
written under `${CLAUDE_PLUGIN_ROOT}` is lost. The `${CLAUDE_PLUGIN_ROOT}`
defaults below are read-only fallbacks that only make sense in a git clone of
this repository (whose `.gitignore` keeps the filled-in copies out of version
control).

| File | Template (in the plugin) | Read by |
|---|---|---|
| `ONCALL_CHANNELS_FILE=/path/outside/the/plugin/channels.json` (fallback `${CLAUDE_PLUGIN_ROOT}/skills/on-call-report/channels.json`) | `skills/on-call-report/channels.example.json` | `on-call-report` |
| `$RCA_DOCS_DIR/routing-table.md` in your repo (default `docs/rca/routing-table.md`) | `skills/rca/references/routing-table.example.md` | `rca` |
| `$RCA_DOCS_DIR/alerts.md` in your repo (default `docs/rca/alerts.md`) | `skills/rca/references/alerts.example.md` | `rca` |
| `.claude/git-labels.json` in your repo (fallback `${CLAUDE_PLUGIN_ROOT}/skills/git/labels.json`) | `skills/git/labels.example.json` | `git` (optional deploy labels) |
| `~/.claude/platform-engineer.json` | none; optional, never created by the skill | `platform-engineer` (self-augmentation flag, default off) |
| `~/.claude/platform-engineer-augment-ledger.jsonl` | none; written by the skill only when that flag is on | `platform-engineer` (self-augmentation ledger) |

### Tools and MCP servers

- `gh` (GitHub CLI), authenticated: `git`, `pr-*`, `plan`, `doc`, `rca`, `on-call-report`.
- `curl` and `python3`: `loki` (the bundled `parse_logs.py` summarises query results).
- `gcloud`, authenticated against `GCP_PROJECT`: `rca` log queries.
- MCP servers named `slack`, `sentry` and `posthog`: `on-call-report`,
  `rca`, `pr-review` and `evaluate` call `mcp__slack__*`, `mcp__sentry__*`
  and `mcp__posthog__*` tools. `rca` and `evaluate` can also use `vercel`
  and `firebase` servers when present. Configure the servers with those
  names in your Claude Code MCP settings; the skills degrade to CLI and manual
  steps when a server is missing.

## Plugins

### oncall

| Skill | What it does |
|---|---|
| `loki` | Query production logs from Grafana Loki by service, time range, severity and search text; lists services and labels, summarises results with the bundled parser. Triggers on "check logs", "production errors", "what's failing". |
| `rca` | Root cause analysis for production issues (blank pages, data mismatches, API latency, page load problems) across Sentry, PostHog, cloud logs, Vercel and GitHub, with traceparent correlation; writes an RCA document from the bundled template. |
| `on-call-report` | On-call health report: scans Slack channels (tiered config), Sentry, GitHub issues and PRs, and PostHog; categorises findings as Frontend / Backend / Infra / Customer impact and emits task briefs an agent can pick up. |

See [`plugins/oncall/README.md`](plugins/oncall/README.md).

### engg

| Skill | What it does |
|---|---|
| `git` | Branch from the default branch, run the repo's formatter, commit, push and open a PR in one command; standardised branch naming; optional Linear ticket creation or lookup; resolves addressed review threads. |
| `pr-review` | Deep, multi-stage PR review from a principal engineer's perspective: triage, specialised passes, risk classification, security pass, cross-package impact, line-level GitHub comments. |
| `pr-check` | After pushing: fetch review comments, plan the fixes, check CI status. |
| `pr-babysit` | Carry one or more PRs from "opened" to "merged and deployed" without polling; sweep a backlog of open PRs; follow up on merged PRs with unresolved threads. |
| `local-pr-review` | Offline review of a PR that produces a structured markdown report an agent can implement fixes from. |
| `codebase-investigator` | Find where a feature is implemented, trace data flows, explain how something works, find the PR that introduced a change. No configuration required. |
| `plan` | Write a detailed implementation plan as a GitHub issue, with alternatives and trade-offs. |
| `doc` | Search the codebase and document a system, module or pattern as an engineering design doc in a GitHub issue. |
| `evaluate` | Go/no-go evaluation of a major change: external research, blast radius, risks, metrics, test strategy, recommendation; writes the evaluation to `docs/evaluations/`. |
| `deep-understanding` | Deliberate-learning walkthrough of a topic, codebase, decision or paper ("teach me", "walk me through", "quiz me"). |
| `test-fix` | Run pytest and fix failing tests iteratively. |
| `debug-service` | Debug a local development service that will not start or respond: ports, imports, dependencies, configuration. |
| `share-session` | Export a Claude Code session transcript as an interactive HTML page. Expects a `scripts/session_replayer.py` in the current repository; the replayer is not bundled. |

| Agent | What it does |
|---|---|
| `code-optimizer` | Optimisation-focused review: duplication, performance, security and testing gaps, written up as a prioritised report with before/after examples. |
| `security-reviewer` | OWASP-style security review of authentication, authorisation, input handling, data access and credential use. |

See [`plugins/engg/README.md`](plugins/engg/README.md).

### platform-engineer

| Skill | What it does |
|---|---|
| `platform-engineer` | The orchestrating entry point for any ask that no single skill owns end to end: classifies the intent, routes each part to the right `oncall` / `engg` skill (or your own language-specific engineer skill), enforces dependency-before-consumer PR ordering, keeps durable workstream state under `docs/workstreams/<slug>/` so any session resumes with one line, and does not return until the definition of done holds. Triggers on "orchestrate", "workstream", "continue", "end to end", "get it live", "sweep", and multi-item task lists. |

It reads no environment variables; see the "Files you fill in" table for the
optional self-augmentation flag. See
[`plugins/platform-engineer/README.md`](plugins/platform-engineer/README.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). In short: one directory per skill,
run `.github/scripts/skill-lint.sh` and `.github/scripts/identifier-gate.sh`
before opening a PR, and never commit a real project id, channel id,
hostname, token, or customer or employee name.

## Security

See [SECURITY.md](SECURITY.md): GitHub private vulnerability reporting first,
<security@loopai.com> as the fallback.

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Loop AI.
