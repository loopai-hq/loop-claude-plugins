# Support

## Where to ask

| I want to... | Go to |
|---|---|
| Report a skill that misbehaves, a broken command or a wrong doc | [Bug report](https://github.com/loopai-hq/loop-claude-plugins/issues/new?template=bug_report.yml) |
| Propose a new skill or a change to an existing one | [Skill request](https://github.com/loopai-hq/loop-claude-plugins/issues/new?template=skill_request.yml) |
| Ask a usage question | A [bug report](https://github.com/loopai-hq/loop-claude-plugins/issues/new?template=bug_report.yml) with the "question" label until GitHub Discussions are enabled for this repository |
| Report a security problem | [SECURITY.md](SECURITY.md): private vulnerability reporting first, `security@loopai.com` as the fallback. Never a public issue. |
| Ask about Claude Code itself (install, login, plugin system) | Anthropic's [Claude Code documentation](https://code.claude.com/docs). This project is not affiliated with or endorsed by Anthropic and cannot answer for the product. |

## What to include

For anything that did not work, paste:

- `claude --version` (these plugins are tested with Claude Code 2.1.285)
- `claude plugin list` (shows the installed plugin versions)
- The exact invocation (`/oncall:loki api ERROR 6h`, `/engg:git "..."`)
- Operating system and shell
- The relevant environment variables **with their values replaced by
  placeholders** (`SENTRY_ORG=<redacted>`). Never paste a token, a channel id
  or an internal hostname.

## Response expectations

This repository is maintained by a small team alongside its day job. Issues
are triaged weekly; there is no support SLA for feature requests. Security
reports follow the timeline in [SECURITY.md](SECURITY.md).
