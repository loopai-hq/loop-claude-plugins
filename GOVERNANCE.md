# Governance

`loop-plugins` is a single-vendor open-source project: the plugins are
written and maintained by Loop AI engineers and published under the MIT
license. This file says who decides what, so that contributors know what to
expect.

## Roles

- **Maintainers** (listed in [MAINTAINERS.md](MAINTAINERS.md)) review and
  merge pull requests, cut releases, triage issues and handle security
  reports. Every path in the repository has a maintainer as code owner
  (`.github/CODEOWNERS`).
- **Contributors** are anyone who opens an issue or a pull request. Accepted
  contributions are credited by the commit history and, for substantial
  work, in [AUTHORS.md](AUTHORS.md).

There is no separate steering body. Adding a maintainer is a pull request
that edits `MAINTAINERS.md` and `CODEOWNERS`, approved by every current
maintainer.

## How decisions are made

- **Pull requests** need one maintainer approval and green CI
  (`skill-lint`, `identifier-gate`). The author cannot approve their own
  change. A maintainer re-runs the identifier gate with the private pattern
  set before merging a fork PR.
- **New skills or plugins** start as a skill-request issue so the scope is
  agreed before the work. See "Adding a skill" in
  [CONTRIBUTING.md](CONTRIBUTING.md).
- **Plugin and marketplace names are immutable** once published (`oncall`,
  `engg`, `platform-engineer`, marketplace `loop-plugins`). Claude Code keys
  installs on those names; a rename would strand every installer. Display
  changes use `displayName`.
- **Versions** are per plugin and follow semver. Any change under
  `plugins/<plugin>/` bumps that plugin's `version` in the same pull request
  (CI enforces it); the maintainer who merges tags `<plugin>--v<version>` and
  the release workflow publishes a GitHub Release from the matching
  [CHANGELOG.md](CHANGELOG.md) section.
- **Roadmap** items live in [ROADMAP.md](ROADMAP.md). Being on the roadmap is
  a statement of intent, not a commitment to a date.
- **Disagreements** are resolved in the pull request or issue thread. If
  maintainers disagree among themselves, the change waits until they agree;
  the status quo wins ties.

## What this project will not do

- Accept content that identifies a specific company's infrastructure, people
  or customers (see "No internal identifiers" in CONTRIBUTING.md).
- Add hooks, MCP servers or binaries to the plugins without a governance
  change recorded here first; the "Trust and security" section of the README
  promises there are none.
- Require a CLA or DCO. Contributions are accepted under the repository's
  MIT license (inbound = outbound).

## Changing this document

Governance changes are pull requests against this file, approved by every
current maintainer.
