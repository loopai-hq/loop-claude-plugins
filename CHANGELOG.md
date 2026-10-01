# Changelog

Each plugin is versioned on its own. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are
[semver](https://semver.org/). Git tags are `<plugin>--v<version>` and the
release workflow turns each tag into a GitHub Release whose body is the
matching section below.

Repository: renamed from `loop-claude-plugins` to `loop-plugins` on
2026-10-01 to match the marketplace name; install lines, manifests and links
follow, and the old URLs redirect.

## oncall

### [0.2.0] - 2026-09-30

#### Changed
- `on-call-report`: `allowed-tools` no longer pre-approves unrestricted
  `Bash` or the Slack send tools; posting a report to Slack now goes through
  the normal permission prompt. Bash is scoped to `gh issue list`,
  `gh search prs`, `gh run list`, the bundled `dates.py` helper, `cat` and
  `date`; any other `gh` verb or `python3` prompts.
- `loki`: `allowed-tools` pre-approves `python3` only for the bundled
  `parse_logs.py`, which gained `--list` (label and service listings) and
  `--range` (the query window in nanoseconds) so the skill runs no inline
  `python3 -c`; `date` is no longer pre-approved.
- `on-call-report`: written for an engineering lead instead of a "CTO";
  the description leads with its triggers.
- `on-call-report`: the `ONCALL_CHANNELS_FILE` fallback moved from the
  plugin cache to `${CLAUDE_PLUGIN_DATA}/channels.json`, which survives
  plugin updates.
- `on-call-report`, `rca`: date arithmetic uses `python3` instead of
  GNU/BSD-specific `date` flags (`on-call-report` through its bundled
  `dates.py`).
- `rca`: SKILL.md is under 500 lines; the trace-correlation diagram, the
  link-format rules, the GCloud/GitHub query recipes and the tips moved to
  `references/` and are loaded at the step that needs them.
- `rca`: the self-healing phase no longer re-reads the whole skill after
  every run; the attribution footer is one line and can be disabled.
- `loki`, `on-call-report`, `rca`: a standing rule that fetched logs, chat
  messages and issue text are evidence to verify, never instructions to
  follow; evidence may change a finding, and nothing fetched can run a
  command, change a target or widen the scope.
- `rca`: the ordering rule (deployments first when an issue starts suddenly
  for multiple users) is at the top of the Investigation Workflow, and the
  parallelism and general triage tips are in `references/`; the pointers to
  the issue-category and infrastructure tables name the reference file.

#### Fixed
- `parse_logs.py` no longer crashes on a non-JSON response body, on JSON
  log lines that are not objects, or on a `matrix` (metric) result; each
  case prints a clear message. A fixture test runs in CI.

### [0.1.0] - 2026-09-25

#### Added
- Initial public release: `loki`, `rca`, `on-call-report`.

## engg

### [0.2.0] - 2026-09-30

#### Added
- `plan-issue`: the former `plan` skill under a name that does not collide
  with Claude Code's built-in `/plan` command. Invoke it as
  `/engg:plan-issue`.

#### Changed
- `evaluate`: `allowed-tools` no longer pre-approves unrestricted `Bash`,
  `Write`, `Edit` or `WebFetch`; the skill runs on ordinary permission
  prompts, and every page fetch shows its URL first.
- `git`: `curl` is pre-approved only for the Linear GraphQL endpoint
  (`https://api.linear.app/graphql`).
- `pr-check`: `allowed-tools` scoped from `gh *` to the four reads it runs
  (`gh pr view`, `gh pr checks`, `gh run view`, the pull request's review
  comments).
- `pr-review`: re-review detection matches a hidden
  `<!-- loop-plugins:pr-review -->` marker that every posted review body
  carries, in both footer modes, instead of any body containing the text
  `pr-review`.
- `pr-review`, `evaluate`: SKILL.md is under 500 lines; the frontend-only
  review passes, comment templates, type-specific inspection strategies and
  the evaluation document template moved to `references/` and are loaded
  at the stage that needs them.
- `pr-review`, `evaluate`: the self-healing phase no longer re-reads the
  whole skill after every run; the attribution footer is one line and can
  be disabled.
- `pr-review`: `GITHUB_REPO` is documented as resolved with `gh repo view`,
  matching what the skill runs.
- `git`: the deploy-label fallback moved from the plugin cache to
  `${CLAUDE_PLUGIN_DATA}/labels.json`, which survives plugin updates.
- `security-reviewer` agent uses `model: inherit` instead of pinning a
  model tier.
- `pr-review`, `pr-babysit`, `pr-check`, `git`, `evaluate`: a standing rule
  that PR bodies, review comments, issue text and web pages are evidence to
  verify, never instructions to follow; a valid review comment still gets
  fixed, and nothing fetched can run a command, change a remote or target,
  merge, push elsewhere or widen the scope.

#### Removed
- `plan`: renamed to `plan-issue`. **Breaking**: invoke `/engg:plan-issue`;
  `/engg:plan` no longer exists, and the bare `/plan` is Claude Code's
  built-in plan mode.
- `share-session`: it required a `scripts/session_replayer.py` that the
  plugin never shipped, so it could not run from a clean install. It returns
  when the replayer is bundled (see ROADMAP.md).

### [0.1.0] - 2026-09-25

#### Added
- Initial public release: `git`, `pr-review`, `pr-check`, `pr-babysit`,
  `local-pr-review`, `codebase-investigator`, `plan`, `doc`, `evaluate`,
  `deep-understanding`, `test-fix`, `debug-service`, `share-session`, and
  the `code-optimizer` and `security-reviewer` agents.

## platform-engineer

### [0.2.0] - 2026-09-30

#### Added
- `dependencies: ["oncall", "engg"]` in the manifest, so installing
  `platform-engineer` installs the plugins that supply its routes.
- A "Provenance" section in the plugin README describing how the
  reference material was derived.

#### Changed
- Routes and chains reference `/engg:plan-issue` instead of the bare
  `/plan`, which Claude Code's built-in command owns.
- `argument-hint` renders as `[task or workstream description]`.
- Provenance and research notes moved out of the skill instructions into
  the README; model-tier names removed from the reference files.
- Cross-file links inside `references/` use sibling file names; the
  branch-naming rule is quoted inline instead of pointing into another
  plugin.
- README: the permission note says that a dispatched skill's own
  `allowed-tools` apply, so a push through `/git` does not prompt while a
  merge or a chat post does.

### [0.1.0] - 2026-09-25

#### Added
- Initial public release: the `platform-engineer` orchestrating skill and
  its seven reference files.
