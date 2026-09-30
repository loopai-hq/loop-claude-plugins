**What this changes and why**

**Plugin(s) touched:** none / oncall / engg / platform-engineer

**Version bumped:** `plugins/<plugin>/.claude-plugin/plugin.json` `0.x.y` → `0.x.z`, CHANGELOG.md section updated (required for any change under `plugins/<plugin>/`)

**How you verified it**

Paste the relevant output if CI does not obviously cover it (for example the
transcript of running the changed skill from `claude --plugin-dir`).

**AI assistance:** none / <tool>: <what it produced> (see CONTRIBUTING.md "AI-assisted contributions")

**Checklist**

- [ ] `bash .github/scripts/skill-lint.sh`, `bash .github/scripts/identifier-gate.sh` and `bash .github/scripts/check-refs.sh` pass locally
- [ ] `claude plugin validate --strict` passes on `.`, the plugin directory and its `skills/` (and `agents/`) directories
- [ ] Root README and plugin README tables updated (skill or agent added, removed or renamed; variable added)
- [ ] Conventional commit subject; the body says why
- [ ] No company-specific identifiers, tokens, personal data or transcript content (the identifier gate checks the mechanical part)
- [ ] `allowed-tools` of any touched skill is scoped to what the skill runs; no send/push tool was pre-approved
- [ ] I can explain every change without the tool
