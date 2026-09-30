# Comment templates and deduplication

Loaded by the `pr-review` skill in Phase 9.3 (deduplication) and Phase 10.2
(writing each inline comment). Every comment must be self-contained.

## Deduplicated finding (Phase 9.3)

If the same pattern appears in multiple files (e.g., same unused import in 5 files), consolidate into a single finding:

```markdown
**[MINOR]** Deep relative imports instead of the path alias — found in 5 files

Files: `ComponentA.tsx`, `ComponentB.tsx`, `ComponentC.tsx`, `ComponentD.tsx`, `ComponentE.tsx`

All use `../../../utils/` instead of `src/utils/`. Consider updating to match the `src/` path alias convention.
```

Post the consolidated finding as a general review comment (not inline), with a single inline comment on the most representative instance.

Each line comment must be **self-contained** — a developer reading it should understand the issue without looking at any summary. Include full code context in every comment.

#### Inline Comment Template (Line-Level)

```markdown
**[SEVERITY]** Brief description

**Why**: Deep explanation with full context:
- What the surrounding code does and how this line fits in
- How the issue manifests (runtime error, data corruption, UX bug, security gap)
- What downstream code is affected (name specific functions, components, hooks)
- Evidence: cite specific lines, patterns, or instruction-file rules

<details>
<summary>Suggestion</summary>

\`\`\`suggestion
// The corrected code — GitHub renders this as a one-click applicable fix
\`\`\`

</details>

```

#### For findings without a specific code suggestion:

```markdown
**[SEVERITY]** Brief description

**Why**: Deep explanation with full context — same depth as above. Reference the actual code path, what calls this, what breaks, and why it matters.

**Action**: Specific, actionable fix. Not "handle the error" but "wrap in try/catch and surface the failure through the app's notification helper, e.g. `showError('Failed to load sessions')`".

```

#### What "full context" means:

- **BAD**: "Silent error swallowing" → too vague, developer has to figure out what happens
- **GOOD**: "If `updateStep` fails (network error, 500), the user believes they completed the onboarding step but nothing was persisted to the backend. On page reload, their progress is lost. The `catch {}` on line 28 hides this entirely — the `useOnboardingComplete` hook reports success to `OnboardingStepper` which advances the stepper, but the step state in the DB is unchanged."
