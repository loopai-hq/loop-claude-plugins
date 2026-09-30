# Roadmap

What we intend to do next, with enough of the recipe that someone else could
pick an item up. Items are not dated. Things we decided *not* to do are at
the end so the question is not reopened every quarter.

## Planned

### Behavioural evals (`claude plugin eval`)
- One `evals/<case>/` per skill with cheap graders first (`tool_used`,
  `regex`, `file_exists`), an `llm` grader only where a regex cannot judge.
- A `workflow_dispatch` + weekly job running
  `claude plugin eval . --trust-plugin --json --threshold 0.8 --no-publish --max-cost-usd <N>`.
  Not in PR CI: every run and every judge is a real model call on the
  maintainers' account.
- Blocked on deciding the cost cap and which skills justify behavioural
  tests versus the static checks CI already runs.

### `userConfig` for the configuration variables
- Declare the variables from the README table as `userConfig` entries
  (`sensitive: true` for `SENTRY_AUTH_TOKEN`, `LINEAR_API_KEY`,
  `LOKI_AUTH_HEADER`) so `/plugin configure` prompts for them.
- Environment variables stay the primary mechanism (portable to any shell and
  to CI); the skills would read `${user_config.KEY}` only as a fallback, and
  the precedence must be documented in every SKILL.md "Configuration"
  section.

### `share-session` returns to `engg`
- Removed in 0.2.0 because it depended on a `scripts/session_replayer.py`
  that the plugin never shipped, so it could not run from a clean install.
- Comes back when the replayer is bundled under the skill directory
  (`skills/share-session/session_replayer.py`, stdlib only, `--upload`
  pluggable) and the macOS-only `open` call is replaced by a portable
  fallback.

### Submission to the Anthropic plugin directory
- Pre-submission checklist items still open: `userConfig` for the tokens
  the skills read from the environment, evals, and a decision on the
  repository name (see "Decisions for the maintainers" below).

### Quality gates
- `skills-ref validate` per skill (the Agent Skills reference validator) in
  the `lint` job, once it is packaged for CI.
- A release-notes check that every `plugins/<p>/` change also touches its
  CHANGELOG section (today only the version bump is enforced).

### Decisions for the maintainers
- Repository name: the marketplace is `loop-plugins`; the repository is
  `loop-claude-plugins`. Renaming the repository to match would touch every
  install line and badge; the marketplace name cannot change.
- Canonical contact domain (`tryloop.ai` in `marketplace.json` vs
  `loopai.com` in `SECURITY.md`).

## Declined

- **`disable-model-invocation` on `git` and `pr-babysit`.** `platform-engineer`
  dispatches both of them by name; disabling model invocation would break
  every feature chain. Pushes and merges are still gated by Claude Code's
  own permission prompts, which the plugins do not pre-approve.
- **Widening the identifier gate's Slack-id pattern** to
  `[CDGSUW][0-9A-Z]{8,10}`: it matches ordinary all-caps words (`DASHBOARD`,
  `WORKSTREAM`), and the private pattern set in CI covers the real ids.
- **Hooks, MCP servers or binaries in the plugins.** The trust story is that
  there are none; see GOVERNANCE.md.
