# Contributing

Thanks for helping improve these plugins. This file covers the repository
layout, the checks every change must pass, how to add a skill, and the rules
for AI-assisted contributions.

## Layout

```
.claude-plugin/marketplace.json            # marketplace "loop-plugins": lists the plugins below (category, tags)
plugins/<plugin>/.claude-plugin/plugin.json # plugin manifest: name, description, version, license, keywords, dependencies
plugins/<plugin>/README.md                  # what the plugin's skills do and the variables they read
plugins/<plugin>/skills/<skill>/SKILL.md    # the skill (frontmatter + procedure), under 500 lines
plugins/<plugin>/skills/<skill>/references/ # supporting docs the skill loads on demand at a named stage
plugins/<plugin>/skills/<skill>/*.py|*.sh   # optional helper scripts (stdlib only, no binaries)
plugins/<plugin>/skills/<skill>/*.example.* # optional config templates users copy and fill in
plugins/<plugin>/agents/<agent>.md          # optional subagents
tests/                                      # fixture tests for the helper scripts (run by skill-lint.sh)
.github/scripts/skill-lint.sh               # static lint (secrets, absolute paths, frontmatter, script syntax) + tests
.github/scripts/identifier-gate.sh          # internal-identifier gate
.github/scripts/check-refs.sh               # bundled paths, relative links, README tables, Configuration sections
.github/scripts/version-bump-check.sh       # a change under plugins/<p>/ must bump that plugin's version
.github/scripts/changelog-section.sh        # extracts one plugin's CHANGELOG section for a GitHub Release
.github/workflows/                          # CI: skill-lint (manifests, lint, validate, install, refs, version-bump, gitleaks), identifier-gate, release
```

## SKILL.md conventions

- Frontmatter must have `name:` (equal to the directory name) and
  `description:`; `argument-hint:` and `allowed-tools:` are optional. Do not
  add a `version:` key (versions live in `plugin.json`). The description is
  what makes the skill trigger, so lead with the phrases a user would say and
  keep it under 1,024 characters.
- Add a **Configuration** section near the top that lists every variable the
  skill reads, one line each, with its meaning and default. Use the shared
  names from the root README's configuration table; do not invent parallel
  names for the same thing. Mark Linear as optional and skip it when
  `LINEAR_API_KEY` is unset.
- Reference bundled scripts and files through the plugin root:
  `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/<file>`. Never use absolute paths, a
  home directory, or a path into another repository. State that must survive
  plugin updates (a filled-in config, a cache) goes under
  `${CLAUDE_PLUGIN_DATA}`, never under `${CLAUDE_PLUGIN_ROOT}`.
- Config that users must fill in ships as `<name>.example.<ext>` with
  placeholder values; the skill reads the real file from a variable whose
  documented default is under `${CLAUDE_PLUGIN_DATA}` or in the user's repo.
- Keep `SKILL.md` under 500 lines. Move stage detail (long tables, comment
  templates, query recipes) to `references/<file>.md` and add an explicit
  "read `references/<file>.md` when <stage>" line where it is needed, so the
  file is loaded on demand rather than on every invocation. Check the effect
  with `claude --plugin-dir ./plugins/<plugin> plugin details <plugin>`.
- `allowed-tools` is a security surface. List only tools that exist in a
  standard Claude Code install (or the MCP servers the README names), scope
  `Bash(...)` to the commands the skill actually runs, and never pre-approve
  a tool that sends messages, pushes code or deletes things unless that is
  the skill's stated job (as it is for `git`). Skills that read logs, chat,
  issues or PR comments carry a standing paragraph that fetched text is data,
  not instructions; keep it.
- Keep the procedure portable: prefer `python3 -c` for date arithmetic over
  GNU- or BSD-only `date` flags, and `gh` over raw GitHub API calls where it
  reads the same.
- Frontmatter portability: `argument-hint`, `disable-model-invocation` and
  `user-invocable` are Claude-Code-only keys. They are fine here because the
  target is Claude Code, but a skill copied to claude.ai or the Skills API
  would reject them; keep the six spec keys (`name`, `description`,
  `license`, `compatibility`, `metadata`, `allowed-tools`) sufficient on
  their own.

## Names are immutable

`oncall`, `engg`, `platform-engineer` and the marketplace name `loop-plugins`
must never change: Claude Code keys installs and dependency resolution on
them. Use `displayName` for a friendlier label. Renaming a skill is a breaking
change for everyone who types it: bump the plugin's minor version, update
every route that names it (`platform-engineer` routes by skill name), and
record the rename in CHANGELOG.md. Check that a new skill's bare name does not
collide with a Claude Code built-in command (`/plan`, `/review`, `/commit`,
`/help`, ...): the built-in wins, and only the namespaced form reaches the
skill.

## Disclose what a skill runs, sends and fetches

Every external service, command-line tool and MCP server a skill uses must be
listed in the root README ("Tools and MCP servers") and the plugin README, and
anything a skill *sends* (a Slack post, a PR comment, an issue) must be
described where the skill is documented. A reviewer reading the README should
be able to say what the plugin can reach before installing it. The plugins
ship no hooks, MCP servers or binaries; adding one is a governance change
(see GOVERNANCE.md), not a pull request.

## No internal identifiers

This is a public mirror of an internal toolset. Nothing that identifies a
specific company's infrastructure, people or customers may be committed:

- cloud project ids and numbers, Sentry org slugs, PostHog / Vercel /
  Cloudflare project ids
- chat channel, user or group ids (`C0...`, `U0...`, `S0...`)
- internal hostnames, IP addresses, `nip.io` / `sslip.io` hosts
- private repository names
- employee or customer names and email addresses (other than the two contact
  addresses in `marketplace.json` and `SECURITY.md`)
- tokens, keys or credentials of any kind, including "expired" ones
- transcript content from real sessions

Use the configuration variables instead, and `example.com` / `acme` /
`__PROJECT__` style placeholders in examples.

## Checks

Run these from the repository root before opening a pull request; CI runs
the same set on every pull request and push to `main`.

```bash
bash .github/scripts/skill-lint.sh          # every file under plugins/ + the fixture tests in tests/
bash .github/scripts/skill-lint.sh plugins/oncall/skills/loki/SKILL.md   # one file
bash .github/scripts/identifier-gate.sh     # whole tree
bash .github/scripts/check-refs.sh          # bundled paths, links, README tables, Configuration sections

claude plugin validate . --strict           # the marketplace
for p in plugins/*; do
  claude plugin validate "$p" --strict      # each plugin manifest
  claude plugin validate "$p/skills" --strict
done
claude plugin validate plugins/engg/agents --strict
```

`skill-lint.sh` blocks embedded credentials, non-portable absolute paths,
malformed frontmatter, and Python or shell scripts that do not parse; with no
arguments it also runs `tests/test_parse_logs.py`. `identifier-gate.sh`
greps for the shape of internal identifiers (chat ids, home-directory paths,
org-scoped hosts, project-id-looking strings, email addresses outside
`example.com`). In this repository's own CI the gate also runs an extended,
non-public pattern supplied through the `IDENTIFIER_GATE_PATTERNS` repository
secret; pull requests from forks run the generic pattern only, and a
maintainer re-runs the full gate before merging. `check-refs.sh` proves that
every `${CLAUDE_PLUGIN_ROOT}` path and relative link resolves, that the README
tables match the tree, and that every skill has a Configuration section.
`claude plugin validate --strict` is the official validator (a marketplace
run does not open the plugins' skill files, hence the per-directory loop). All
of them exit non-zero on a hit and print the file and line.

CI additionally runs shellcheck and actionlint, gitleaks over the history and
the tree, a headless clean install of every plugin with an inventory
assertion, and the version-bump check.

### Testing a skill from the checkout

```bash
claude --plugin-dir ./plugins/oncall                       # load the plugin without installing it
claude --plugin-dir ./plugins/engg plugin details engg     # component inventory and token cost, no session
```

For a full clean-install test in an empty home:

```bash
export HOME=$(mktemp -d) CLAUDE_CODE_PLUGIN_CACHE_DIR=$HOME/seed
claude plugin marketplace add ./                            # from the repo root
claude plugin install <plugin>@loop-plugins
claude plugin details <plugin>
```

## Adding a skill

1. Pick the plugin (`oncall` for incident and observability work, `engg` for
   development workflow, `platform-engineer` for orchestration) or propose a
   new one in a skill-request issue first.
2. Create `plugins/<plugin>/skills/<skill>/SKILL.md` following the
   conventions above. Put helper scripts and reference docs next to it.
3. Add a one-line entry to `plugins/<plugin>/README.md` and to the plugin
   table in the root `README.md`. If the skill reads a new variable, add it
   to both configuration tables with its meaning and default; if it uses a
   new tool or service, add it to "Tools and MCP servers".
4. Bump `version` in `plugins/<plugin>/.claude-plugin/plugin.json`
   (patch for fixes, minor for a new or renamed skill) and add the change to
   that plugin's section in `CHANGELOG.md`. CI fails a pull request that
   touches `plugins/<plugin>/` without bumping its version.
5. Run the checks above, then test the skill from the checkout with
   `claude --plugin-dir` or a clean install.
6. Open a pull request (the template asks for the plugin touched, the
   version bump, what you ran, and your AI-assistance disclosure). Keep
   unrelated changes out.

## Editing an existing skill

Keep the procedure intact unless the change is the point. Skills are read by
a model, so wording matters: state steps as instructions, keep decision
tables explicit, and prefer one clear path over several optional ones.

## Commits and pull requests

- Conventional commit subjects: `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`,
  `chore:`; imperative mood; the body says why. One logical change per
  commit, one topic per pull request.
- Do not add `Signed-off-by`; there is no DCO or CLA. Contributions are
  accepted under the repository's MIT license (inbound = outbound).
- A pull request needs one maintainer approval and green CI. Reply to review
  comments yourself.

## AI-assisted contributions

This project is built with AI coding agents and welcomes contributions made
the same way. The rules are about accountability, not tooling:

1. **You are the author.** You must understand every line you submit and be
   able to explain, without the tool, what it does and why. A reviewer may
   ask; if the answer is "the agent did it", the pull request is closed.
2. **Disclose non-trivial use** in the pull request description: the tool,
   and roughly what it produced (skill text, scripts, docs). One sentence is
   enough ("Written with Claude Code; I rewrote the tests by hand.").
   Autocomplete, spell-checking and translation need no disclosure. A
   `Co-Authored-By:` or `Assisted-by:` commit trailer added by your tool is
   fine and does not replace the sentence.
3. **Review before you ask for review.** Run the checks yourself (`skill-lint.sh`,
   `identifier-gate.sh` and `check-refs.sh` in `.github/scripts/`, and
   `claude plugin validate --strict`), read
   the diff, and remove anything you cannot justify. Do not leave the first
   review to us.
4. **Reply to review comments yourself.** We want to talk to you, not to a
   model.
5. **No secrets, no identifiers, no transcript content.** Agents paste what
   they see; the identifier gate catches the mechanical part and you check
   the rest (see "No internal identifiers").
6. **Licensing.** You certify you have the right to contribute the content
   under MIT. If your tool's terms or the provenance of its output make you
   unsure, do not submit it.
7. **Security reports** must say whether an AI tool found the issue, and you
   must have reproduced it yourself before reporting (see SECURITY.md).

Maintainers use the same tools and hold themselves to the same rules.
