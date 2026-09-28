# Security policy

## Reporting a vulnerability

Please do not open a public issue for security problems.

1. **Preferred:** use GitHub private vulnerability reporting for this
   repository: <https://github.com/loopai-hq/loop-claude-plugins/security/advisories/new>.
   This keeps the report private between you and the maintainers until a fix
   is published.
2. **Fallback:** email <security@loopai.com>. Include the affected file, the
   skill or agent involved, reproduction steps, and the impact you expect.

We acknowledge reports within five business days and keep you informed while
we work on a fix.

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

Only the latest release on `main` receives fixes.
