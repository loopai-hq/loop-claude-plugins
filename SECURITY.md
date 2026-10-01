# Security policy

## Reporting a vulnerability

Please do not open a public issue for security problems.

1. **Preferred:** use GitHub private vulnerability reporting for this
   repository: <https://github.com/loopai-hq/loop-plugins/security/advisories/new>.
   This keeps the report private between you and the maintainers until a fix
   is published.
2. **Fallback:** email <security@loopai.com>. Include the affected file, the
   skill or agent involved, reproduction steps, and the impact you expect.

We acknowledge reports within five business days, send a status update at
least every 14 days until the report is closed, and aim to publish a fix (a
new plugin version and a GitHub Release) within 30 days for confirmed
reports. If a fix will take longer, the update says why and what to do
meanwhile. We credit reporters in the CHANGELOG entry unless they ask us not
to. There is no bug bounty programme.

### Reports found with AI tools

Say so in the report: name the tool and what it found. You must have
reproduced the issue yourself, on a plugin installed from this repository,
before reporting; a report that only paraphrases a scanner's output, or that
describes behaviour we cannot reproduce, is closed without further action.
The same rule for contributions is in [CONTRIBUTING.md](CONTRIBUTING.md#ai-assisted-contributions).

## What counts

These plugins are Markdown instructions plus a few small scripts that run
inside Claude Code with the permissions you grant them. Reports we want:

- A skill or script that exfiltrates data, executes unexpected commands, or
  widens the permissions a user granted.
- A prompt-injection path: text that a skill reads from an external system
  (logs, issues, chat messages) being able to steer the skill into a
  destructive action.
- Embedded credentials, tokens, or internal identifiers in any tracked file.
- A bypass of the repository's lint or identifier gate.

Findings in the third-party services these skills call (Grafana Loki, Sentry,
PostHog, GitHub, Slack, Linear, Vercel, Google Cloud) belong with those
vendors, not here.

## Supported versions

Each plugin is versioned on its own (`oncall`, `engg`, `platform-engineer`;
tags `<plugin>--v<version>`). Only the latest version of each plugin, as
listed in [CHANGELOG.md](CHANGELOG.md) and on the Releases page, receives
fixes; there are no maintenance branches. Update with
`claude plugin update <plugin>@loop-plugins`.

| Plugin | Supported |
|---|---|
| `oncall` | 0.2.x |
| `engg` | 0.2.x |
| `platform-engineer` | 0.2.x |

These plugins are tested with Claude Code 2.1.285. They are not affiliated
with or endorsed by Anthropic; vulnerabilities in Claude Code itself go to
Anthropic, not here.
