---
name: pr-review
description: Deep PR review from a principal engineer's perspective. Multi-stage pipeline (Triage → Specialized Passes → Filter → Output) with risk classification, security pass, cross-package impact analysis, and line-level GitHub comments. Triggers on "review PR", "review this PR", "review PR changes", "deep review", "PR review".
---

# PR Review — Deep Pull Request Inspection

## Configuration

This skill reads the following environment variables. None are required when run inside a git checkout of the repository under review.

| Variable | Meaning | Default |
|----------|---------|---------|
| `GITHUB_REPO` | `owner/name` of the repository whose PRs are reviewed. Used for `gh --repo`, linked-issue lookups, and links in review comments. | Parsed from `git remote get-url origin` |
| `SENTRY_ORG` | Sentry organization slug. When set, Phase 4.4 cross-references changed files against active Sentry issues. | Unset — the Sentry cross-reference is skipped |
| `SENTRY_PROJECTS` | Comma-separated Sentry project slugs to search. | Unset — every project in `SENTRY_ORG` |
| `SENTRY_REGION_URL` | Sentry region base URL for API calls. | `https://us.sentry.io` |

Everything else the skill needs comes from the repository itself: instruction files (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`), lockfiles and manifests (`package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`), and the `gh` CLI.

Resolve `GITHUB_REPO` once at the start of every run:

```bash
GITHUB_REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
[ -n "$GITHUB_REPO" ] || { echo "Set GITHUB_REPO=owner/name or run inside a git checkout"; exit 1; }
```

## Repo and stack detection

The pipeline below is language-agnostic; the focus areas inside each pass are not. Before applying the pipeline, detect what the repo is built with and load only the focus areas that apply:

| Marker in repo | Stack | Focus areas to enable |
|----------------|-------|-----------------------|
| `package.json` with `react` (or `next`, `remix`) | Frontend — React + TypeScript | All frontend focus areas in Pass B (naming, shared-package reuse, theme system, state management) |
| `package.json` without `react` | Node / TypeScript service | Language-agnostic checks + TypeScript typing checks |
| `go.mod` | Go | Language-agnostic checks; `go vet` / `go build` in Phase 11 |
| `pyproject.toml`, `setup.py`, `requirements.txt` | Python | Language-agnostic checks; type checker / linter from the manifest in Phase 11 |
| `Cargo.toml` | Rust | Language-agnostic checks; `cargo check` in Phase 11 |
| `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `go.work`, `[workspace]` in `Cargo.toml`, `workspaces` in `package.json`, `[tool.uv.workspace]` | Monorepo (any of the above) | Cross-package impact detection (Phase 2.2) and the monorepo consistency check (Phase 8.4) |

Rules:

- **Universal**: Apply the LEVER framework from `references/lever-framework.md` to every review regardless of stack.
- **Backend / service repos**: LEVER is the primary lens. Apply the pattern-specific focus areas below only where the concept generalizes (duplication, dead code, typing, error handling, naming). Skip the frontend-only passes (theme system, component extraction, React state management).
- **Frontend repos**: Apply the full pipeline, including the frontend focus areas.
- **Mixed monorepos**: Classify each changed file by the package it lives in and apply the matching focus areas per file.

A principal-engineer-grade inspection skill built on a **multi-stage pipeline architecture** (inspired by Uber's uReview and Google's Tricorder). It classifies PR type and risk, runs specialized review passes, filters for noise, and posts **line-level findings only** on GitHub.

**Output philosophy: Line comments only, no summaries.** Every finding is posted as an inline comment on the exact line in the diff. Each comment is self-contained with full code context — the developer reading it should understand the issue, its impact, and the fix without needing any summary table. The review body is minimal (just skill attribution).

**Architecture:**
```
PR → Triage → Specialized Passes → Filter & Dedupe → Line Comments on GitHub
```

**Differentiators from other skills and agents:**
- `code-optimizer` agent — Checks local patterns and writes an optimization report. `/pr-review` walks dependency trees and adapts to PR type.
- `/local-pr-review` — Offline review to a markdown report. `/pr-review` posts line comments on GitHub.
- `/pr-check` — Reads existing reviewer comments and plans fixes. `/pr-review` creates new findings proactively.
- `/pr-review` — Read-only. Does NOT modify code, push commits, or resolve threads.

## When to Use

Run `/pr-review` when:
- A PR is ready for review and you want a thorough inspection before human reviewers look at it
- You want to catch implementation gaps, leftover references, or missing edge cases
- You want a principal-engineer-level review with major/minor/trivial classifications

**Input**: A GitHub PR URL (e.g., `https://github.com/<owner>/<repo>/pull/<number>`) or a bare PR number when running inside the repository checkout.

---

# STAGE 1: TRIAGE

The triage stage determines **what to review** and **how deeply**. It runs before any inspection logic.

## Phase 1: Authentication & PR Setup

### 1.1 Authentication Check
```bash
gh auth status
```
If not authenticated, stop and instruct: `gh auth login`.

### 1.2 Extract PR Metadata
```bash
# Full PR metadata
gh pr view <PR_NUMBER> --repo "$GITHUB_REPO" --json number,title,headRefName,baseRefName,author,reviewRequests,labels,state,url,body,commits,additions,deletions,changedFiles

# Changed files list
gh pr diff <PR_NUMBER> --repo "$GITHUB_REPO" --name-only

# Full diff
gh pr diff <PR_NUMBER> --repo "$GITHUB_REPO"
```

### 1.3 Checkout PR Branch
```bash
gh pr checkout <PR_NUMBER>
```

If checkout fails due to local uncommitted changes:
```bash
git stash
gh pr checkout <PR_NUMBER>
```
Remember to `git stash pop` at the end of the review to restore the user's working state.

### 1.4 Identify Linked Issue
Check PR body and branch name for issue references (e.g., `$GITHUB_REPO#NNN`, `Closes #NNN`, `Fixes #NNN`, or a `gh-NNN` / `issue-NNN` branch segment). If found, fetch context:
```bash
gh issue view <number> --repo "$GITHUB_REPO" --json title,body,labels,state,assignees,comments
```
Use issue context to understand the **intent** — this is the source of truth for what the PR should accomplish. If the repo tracks work in an external tracker (Linear, Jira) and the PR body links to it, read the linked ticket the same way; skip when no link is present.

### 1.5 Check for Existing Inspection

Before proceeding, check if a `/pr-review` review already exists:
```bash
gh api "repos/$GITHUB_REPO/pulls/<PR_NUMBER>/reviews" --jq '
  .[] | select(.body | contains("/pr-review")) | {id: .id, submitted_at: .submitted_at, commit_id: .commit_id}
'
```
- If a previous inspection exists and the PR has **no new commits** since its `commit_id` — skip and inform the user
- If new commits exist since last inspection — proceed with a fresh review

#### Re-Review After Fix Commits

When running a fresh review after a previous inspection's findings were addressed:
1. **Read the previous review comments** to understand what was already flagged
2. **Verify fixes**: Confirm each previous Major finding was actually fixed (don't re-report resolved issues)
3. **Note resolution status** in the review body: "Previous inspection found X Major findings — all addressed in commit `abc123`"
4. **Focus on remaining/new issues**: The fresh review should only flag issues that still exist or were newly introduced by the fix commits

---

## Phase 2: Risk Classification
Not all code is equal. Auth changes need deeper scrutiny than docs changes. Classify risk **per file** to calibrate review depth.

### 2.1 Risk Tiers by File Path

The patterns below are defaults. If the repo's `CLAUDE.md` names its own sensitive paths, those take precedence.

| Risk | Path Patterns | Review Depth | Requires |
|------|--------------|--------------|----------|
| **Critical** | Auth and session code (`**/auth*`, `**/session*`, `**/permission*`), HTTP client interceptors / middleware that attach credentials, database migrations, IAM / infrastructure definitions, any file whose path or content matches `secret`, `token`, `credential`, `payment`, `billing`, `crypto` | Deep line-by-line + security pass + cross-impact | Senior reviewer |
| **High** | Shared packages consumed by more than one app, `services/*`, `stores/*`, `routes/*`, API handlers, data-access layer, public export barrels (`index.ts`, `__init__.py`), CI / deploy config | Deep line-by-line | Standard review |
| **Medium** | Feature code: `pages/**`, `components/**`, `hooks/*`, `utils/*`, request handlers, internal modules | Standard inspection | Standard review |
| **Low** | `*.test.*`, `*.spec.*`, `*_test.go`, `test_*.py`, `docs/*`, `*.md`, version-only manifest bumps, formatter / linter config, storybook and fixtures | Light inspection — correctness only | AI-only acceptable |

### 2.2 Cross-Package Impact Detection (Monorepos)

When the repo is a monorepo (see the stack detection table), check if changes in one package break others:

| Changed Package | Downstream Impact Check |
|----------------|------------------------|
| A shared library package (e.g. `packages/ui/`, `packages/core/`, `internal/common/`) | Search every consuming app for imports of the changed exports. Check if signatures changed, symbols were renamed, or exports were removed. |
| Shared utilities inside one app | Check whether a sibling app imports the changed file (via a workspace alias or relative path). |
| Root config files (`tsconfig.json`, `package.json`, `turbo.json`, `go.work`, `pyproject.toml`) | All packages potentially affected — verify the build still works. |

```bash
# Example: Check if a shared package's export changes break consumers
# 1. Changed exports in the shared package (adapt the regex to the language)
gh pr diff <PR_NUMBER> -- '<shared-package-dir>/**' | grep -E '^[-+]\s*(export |func [A-Z]|def |pub )'

# 2. Who imports the package
rg -l "from '<package-name>'|\"<module-path>\"" --glob '!<shared-package-dir>/**'
```

### 2.3 Aggregate Risk Score

The overall PR risk is the **highest risk** among all changed files:
- If **any** file is Critical → PR is Critical risk
- If **any** file is High (and none Critical) → PR is High risk
- And so on

This risk level determines:
- Whether the Security Pass runs (Critical/High only)
- Whether cross-impact analysis runs (Critical/High + shared-package changes)
- The verdict threshold (Critical PRs need zero Major findings to approve)

---

## Phase 3: PR Type Classification

Analyze the PR title, description, linked issue, commit messages, and diff to classify the PR into one or more types.

### 3.1 PR Type Taxonomy

| Type | Signals | Inspection Strategy |
|------|---------|---------------------|
| **Cleanup / Removal** | "remove", "delete", "deprecate", "dead code", net-negative lines, file deletions | **Reference Sweep** |
| **Feature / Implementation** | "add", "implement", "create", new files, new routes, new components, new endpoints | **Completeness Walk** |
| **Bugfix** | "fix", "resolve", "patch", linked to bug ticket, small targeted change | **Root Cause Validation** |
| **Refactor** | "refactor", "restructure", "migrate", "rename", same behavior different structure | **Equivalence Check** |
| **Configuration / Infra** | env vars, build config, CI/CD, dependency updates | **Side-Effect Scan** |
| **UI / Design** | component changes, styling, layout, UX improvements | **Visual Consistency** |

A PR can have **multiple types** (e.g., "Feature + Cleanup"). Apply all relevant strategies.

### 3.2 Document Classification

Record:
- Primary type and confidence level
- Secondary types (if any)
- The PR's **intent statement** in one sentence
- **Scope boundary** — what the PR should NOT touch

---

## Phase 4: Load Codebase Context

### 4.1 Read Instruction Files

**Always read** (repo-wide rules):
1. **Root `CLAUDE.md`** — `./CLAUDE.md` (also `AGENTS.md` and `CONTRIBUTING.md` if present)

**Conditionally read** based on which files the PR touches:
2. Every `CLAUDE.md` / `AGENTS.md` found by walking up from each changed file's directory to the repo root. List candidates once:
   ```bash
   git ls-files '**/CLAUDE.md' '**/AGENTS.md'
   ```
   Read the ones whose directory is an ancestor of at least one changed file.

### 4.2 Load Historical Review Patterns

Read the `code-optimizer` agent that ships with this plugin for the LEVER / SAFE / ADAPT / TEST review lenses:
```
Read: ${CLAUDE_PLUGIN_ROOT}/agents/code-optimizer.md
```

If the repo keeps its own catalog of recurring review findings (e.g. `.claude/skills/code-optimizer/SKILL.md`, `docs/review-patterns.md`, a "common mistakes" section in `CLAUDE.md`), read it too — a team's own mined review history is the strongest signal for what to flag. Keep the anti-pattern codes used in Pass B in mind: LOG (leftover debug output), ANY (untyped escape hatches), ENUM (string literals for enums), REUSE (bypassing the repo's shared layer), DEP (bad dependency arrays), FILE (bloated files), NAME (vague names), ICON (inline assets instead of the icon library), CALLBACK (unmemoized handlers), PROPS (untyped props), CONST (magic values), TEST (tests that duplicate implementation).

### 4.3 Understand the PR's Neighborhood

For every file changed in the PR, read:
- The **full file** (not just the diff hunk) to understand the complete context
- **Files that import** the changed file (downstream dependents) — for High/Critical risk files
- **Files imported by** the changed file (upstream dependencies) — for High/Critical risk files

Depth of neighborhood reading scales with risk:
- **Critical/High**: Full dependency graph (imports + importers)
- **Medium**: Direct imports only
- **Low**: File itself only

### 4.4 Sentry Cross-Reference (optional — requires `SENTRY_ORG`)

Skip this phase entirely when `SENTRY_ORG` is unset or no Sentry MCP tools are available. Note "Sentry cross-reference: Skipped (not configured)" in the console output and continue.

Query Sentry for **active errors related to the files being changed**. This reveals:
- Whether this PR fixes a known production error
- Whether the changed code path has a history of instability
- Whether similar changes have caused regressions before

#### 4.4.1 Search for Related Sentry Issues

```
mcp__sentry__search_issues with organizationSlug: "$SENTRY_ORG", projectSlug: <each of $SENTRY_PROJECTS>, regionUrl: "$SENTRY_REGION_URL", query: "file:<changed-file-path>"
```

For each changed file (Critical/High risk), search Sentry for recent issues:
- Search by filename: issues mentioning the changed file in their stack trace
- Search by function name: issues in functions being modified
- Search by error type: if the PR is a bugfix, search for the error pattern being fixed

**Graceful degradation**: Sentry MCP tools may return HTTP 500 or timeout. If any Sentry API call fails:
1. Log the failure: "Sentry API returned [error] — skipping Sentry cross-reference for this file"
2. Continue the review without Sentry data — do NOT block the entire review pipeline
3. Note in the final report: "Sentry cross-reference: Skipped (API unavailable)" instead of failing

#### 4.4.2 Cross-Reference Analysis

| Scenario | What to check | Action |
|----------|---------------|--------|
| **PR fixes a known Sentry issue** | Does the fix match the stack trace? Does it handle all variants of the error? | Note in review: "This appears to fix Sentry issue X — verify the fix covers all stack trace variants" |
| **Changed code has active Sentry errors** | Is the PR aware of these errors? Could the change make them worse? | Flag as context: "Note: this file has X active Sentry errors — ensure changes don't exacerbate" |
| **Similar past regressions** | Has this area of code caused issues after previous changes? | Flag as risk: "History: similar changes caused Sentry issue X on <date>" |
| **No Sentry issues found** | Clean area of code | No action needed |

#### 4.4.3 Use Sentry Issue Details for Bugfix Validation

For bugfix PRs, fetch full details of the issue being fixed:
```
mcp__sentry__get_issue_details with organizationSlug: "$SENTRY_ORG", regionUrl: "$SENTRY_REGION_URL", issueId (its response includes the latest event and its stack trace)
```

Compare the Sentry stack trace against the PR's fix location. If they don't align, flag as:
```markdown
**[MAJOR]** Fix location mismatch — the Sentry stack trace points to
`<file>:<line>` but this PR modifies `<different-file>:<different-line>`.
Verify the root cause is correctly identified.
```

### 4.5 Engineering Principles Context

Keep these principles in mind during all review passes (supplement them with whatever the repo's `CLAUDE.md` states). They are the **foundational evaluation criteria** for every finding:

| Principle | What it means for review |
|-----------|-------------------------|
| **DRY** | Flag duplicated logic (3+ occurrences). Check if the repo's shared package already has what's being built — see the Shared-Package Reuse & Extraction pass in Phase 6. Generic code must be moved to the shared package **before** being consumed, not after. |
| **KISS** | Flag over-engineering: unnecessary abstractions, premature optimization, config for things that won't change. |
| **YAGNI** | Flag speculative features, "just in case" code, unused parameters, over-designed interfaces. |
| **SRP** | Flag files/functions doing too many things. A 500+ line component or module likely violates SRP. |
| **Performance** | Flag expensive work on hot paths: unmemoized computations in render (React `useMemo` / `useCallback`), missing virtualization for large lists, N+1 queries, allocations inside tight loops. |
| **Immutability** | Flag direct state mutation, `Array.push` on state, object property assignment on state, mutation of function arguments. |
| **Separation of Concerns** | Flag business logic in UI components, API calls in render methods, data transformation in event handlers, SQL in HTTP handlers. |
| **Fail Fast** | Flag silent error swallowing (empty `catch` blocks, `except Exception: pass`, ignored `err`), missing validation at boundaries, defensive coding that hides bugs. |
| **Single Source of Truth** | Flag the same API endpoint called from multiple components independently. Flag shared state managed via prop drilling instead of a store. Flag manual polling/caching that duplicates what the app's data-fetching layer provides. |

---

# STAGE 2: SPECIALIZED REVIEW PASSES

Run each pass independently. Each pass has a focused objective and produces findings tagged with its pass identifier. This mirrors Uber's uReview sub-agent architecture.

## Phase 5: Pass A — Bug & Logic Review

**Objective**: Find correctness issues, runtime errors, and logic bugs.

**Run on**: All changed files (all risk levels).

### Checklist

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Null/undefined access** | Accessing properties without null checks, missing optional chaining, nil dereference, `Optional` unwrapped without a guard | Major |
| **Missing error handling** | API calls without try/catch, promises without `.catch()`, ignored error returns (`_ = err`, `res, _ :=`) | Major |
| **Race conditions** | State updates after unmount, stale closures in async callbacks, unsynchronized shared state, goroutine / thread access without locks | Major |
| **Infinite loops/renders** | `useEffect` with deps that change every render, missing dep arrays, recursion without a base case | Major |
| **Off-by-one errors** | Array bounds, pagination calculations, index arithmetic, inclusive/exclusive range confusion | Major |
| **Type coercion bugs** | `==` instead of `===`, implicit string/number conversion, truthiness checks on `0` / `""` | Minor |
| **Incomplete cleanup** | `useEffect` without cleanup for subscriptions, timers, event listeners; unclosed files / connections / contexts | Major |
| **Dead code paths** | Unreachable branches, always-true/false conditions | Minor |

---

## Phase 6: Pass B — Pattern & Convention Review

**Objective**: Enforce team coding standards and catch common anti-patterns from the review-pattern catalog loaded in Phase 4.2.

**Run on**: All changed files (all risk levels). Sections marked **(frontend)** apply only when the changed file belongs to a React / TypeScript app.

### Code Quality Checks

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Leftover debug output** | `console.log` / `console.error` / `console.warn` (all console methods, not just log), `print(...)`, `fmt.Println`, `dbg!` left in non-logging code | Major |
| **Untyped escape hatches** | New `any` usage in TypeScript (see systematic detection below), `# type: ignore` / `Any` in typed Python, `interface{}` where a concrete type is known in Go | Major |
| **Unused imports** | Imported but never referenced | Major |
| **Dead variables** | Declared but never used | Major |
| **Hardcoded secrets** | API keys, tokens, `.env` values in source | Major |
| **XSS / HTML injection vectors** | `dangerouslySetInnerHTML`, `innerHTML =`, `template.HTML(...)`, `Markup(...)` without sanitization | Major |

#### Systematic `any` Type Detection (TypeScript)

For each new/modified file, run a mental grep for `: any`, `as any`, `<any>`, and `Record<string, any>`. Count total new instances introduced by the PR.

**When flagging `any` types:**
- If >5 new instances: consolidate into a **single MAJOR finding** listing all locations (don't post separate comments for each)
- **Suggest specific library types** — don't just say "don't use any", research what types the library exports:
  - Recharts: `TooltipProps<number, string>`, `LabelProps`, `CategoricalChartState`
  - MUI: `SxProps<Theme>`, `GridProps`, `SelectChangeEvent`
  - React: `MouseEvent<HTMLElement>`, `ChangeEvent<HTMLInputElement>`
  - Recharts bar click: `import { CategoricalChartState } from 'recharts/types/chart/types'`
- For callback props (`onDataPointSelection: (event: any, ...) => any`), suggest the actual shape based on how the callback is used downstream

### Convention Checks (from the repo's instruction files)

Enforce only the conventions the repo's `CLAUDE.md` / `CONTRIBUTING.md` actually state. Typical examples:

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **File naming** | Not matching the repo's file naming scheme (e.g. `ComponentName.component.tsx`, `snake_case.py`) | Minor |
| **Import order** | Not following the repo's order (typically external → shared package → relative) | Minor |
| **Import paths** | Deep relative paths (`../../../`) where the repo defines a path alias (`src/`, `@/`) | Minor |
| **ID fields** | Bare `id` where the repo's convention is `userId`, `orgId`, etc. | Minor |
| **Component suffixes** | Modal / dialog components not using the repo's designated suffix | Minor |

### Semantic Naming Standards (Variables, Functions, Handlers, Types)

**Rule**: Every identifier must reveal intent. A reviewer reading the name alone — without reading the implementation — should understand what the value represents or what the function does. Flag any name that forces the reader into the body to learn its purpose. Names are the first layer of documentation; vague names = missing docs.

**Why this is a dedicated pass**: Naming drift is one of the top sources of review churn in most codebases. Generic names like `data`, `result`, `temp`, `info` survive code review because each one looks harmless in isolation — but they compound into unreadable call sites. Catch them at PR time.

| Check | What to look for | Good | Bad | Severity |
|-------|-----------------|------|-----|----------|
| **Vague variables** | Generic nouns that convey no type/purpose | `activeOrdersCount`, `pendingInvoices`, `orderResponse` | `data`, `result`, `list`, `obj`, `info`, `val`, `temp` | Minor |
| **Single-letter names** | Single letters outside tight `for (let i = 0; ...)` loops | `orderIndex`, `rowCell` | `x`, `a`, `b` (outside indices) | Minor |
| **Abbreviations** | Non-industry-standard abbreviations | `orderResponse`, `userProfile`, `config` | `ordRes`, `usrPrf`, `cfg`, `mgr`, `ctx` (except React Context / Go `context.Context`) | Minor |
| **Boolean naming** | Booleans without `is`/`has`/`can`/`should`/`did` prefix | `isLoading`, `hasError`, `canSubmit`, `shouldRefetch`, `didMount` | `submit`, `visible`, `active` (for custom bool state) | Minor |
| **Function verbs** | Functions named like nouns | `getUserById`, `computeTotal`, `fetchOrders`, `buildQuery` | `user()`, `total()`, `orders()` | Minor |
| **Event handlers** | Handlers without `handle`/`on` prefix | `handleClick`, `onSubmit`, `handleOrderCancel` | `click`, `submit`, `cancelOrder` (as handler) | Minor |
| **Hook naming** (frontend) | Hooks without `use` prefix | `useOrderData`, `useAuth`, `useDebounce` | `orderData()`, `getAuth()` (returns hook) | Major |
| **Collection names** | Arrays/maps without plural or descriptive shape | `activeOrders`, `userRoleMap`, `ordersById` | `arr`, `map`, `items`, `things` | Minor |
| **Magic values** | Unnamed numbers/strings with business meaning | `const MAX_RETRIES = 3`, `const EMPTY_ORG_ID = 'default'` | `if (retries > 3)`, `if (org === 'default')` | Minor |
| **Type/interface naming** | `I` prefix, generic names, or `Type`/`Data`/`Object` suffixes | `User`, `OrderRequest`, `ApiError` | `IUser`, `Type1`, `UserData`, `OrderObject` | Minor |
| **Callback prop naming** (frontend) | Props that receive functions without `on`/`handle` | `onSelect`, `onOrderSubmit` | `select`, `orderSubmit`, `cb`, `fn` | Minor |
| **State setter drift** (frontend) | Setter names not matching React's `set*` convention | `setIsOpen`, `setOrders` | `updateOpen`, `changeOrders` (for useState) | Trivial |

#### When NOT to Flag (Naming)

- **Library API-matching names**: names that mirror a library's own contract — e.g. MUI's `open` (Dialog, Menu, Drawer, Popover, Tooltip, Modal, Snackbar, Collapse, Accordion), `anchorEl`, `value`, `selected`. Renaming to `isOpen` would diverge from the library's prop interface.
- **Library-returned destructured names**: `const { data, error, isLoading } = useSWR(...)` — `data` and `error` are canonical SWR / React Query return names. Prefer aliased destructuring (`const { data: orders } = useSWR(...)`) but flag as **Trivial**, not Minor.
- **Widely established state patterns**: `const [loading, setLoading] = useState(false)` — while `isLoading` is preferable for new code, don't flag this in files that consistently use the `loading` convention.
- **Props that mirror the component library**: If a component wraps a library component and passes through props like `open`, `loading`, `disabled`, `error`, keep the library-matching name for API consistency.
- **Language idioms**: Go's `err`, `ctx`, `i`/`j` loop indices, receiver names; Python's `self`, `cls`, `_`.

#### Named Functions Over Inline Callbacks (frontend)

Inline arrow functions are acceptable only when the body is a **single expression or single statement** with no branching. Flag any inline callback that:
- Has more than 3 lines
- Contains `if`/`switch`/`try` blocks
- Contains multiple statements
- Is re-created on every render and passed to a memoized child

**Extract to a named function declared above the JSX.** Benefits:
- Stack traces show the function name (debugging)
- Enables `useCallback` memoization with a stable reference
- Documents intent at the declaration site
- Reduces cognitive load when scanning JSX

**Good**:
```tsx
const handleOrderSubmit = useCallback(async (values: OrderFormValues) => {
  if (!activeOrgId) return;
  const response = await submitOrder(values);
  if (response.ok) onOrderCreated(response.orderId);
}, [activeOrgId, onOrderCreated]);

return <Form onSubmit={handleOrderSubmit} />;
```

**Bad**:
```tsx
return <Form onSubmit={async (values) => {
  if (!activeOrgId) return;
  const response = await submitOrder(values);
  if (response.ok) onOrderCreated(response.orderId);
}} />;
```

**Comment template for naming findings:**
```markdown
**[MINOR]** Vague variable name — `data` does not reveal intent

**Why**: `data` here holds the response of `getActiveOrders()`, an array of `Order` objects
scoped to the current org. Readers downstream (`OrdersTable`, `OrderSummary`) have to
trace back to this declaration to learn the type. Rename so the call site is self-documenting.

**Suggestion**: `activeOrders` (matches the function name and shape).
```

### Shared-Package Reuse & Extraction (CRITICAL — monorepos with a shared UI/library package)

**Applies when**: the repo has a shared package (call it `<shared-ui-package>`, e.g. `packages/ui` published as `@acme/ui`) that is consumed by two or more apps. Detect it from the workspace manifest and the import graph; skip this pass when there is no such package.

**Rule**: Reusable UI lives in the shared package — NOT in app-specific folders. Every new visual component, dialog, chart, form primitive, button variant, badge, empty state, or layout element added inside `apps/*/src/components/` must be evaluated against this rule:

1. **Already exists in the shared package?** → Flag as duplicate. Use the existing export.
2. **Generic enough to be reused by the sibling app?** → Flag as extraction opportunity. Move to the shared package **before** consuming.
3. **Truly app-specific (depends on app stores, routes, domain types)?** → OK to keep local.

**Why this is a dedicated pass**: Copy-pasting UI between sibling apps is the single largest source of divergence debt in a frontend monorepo. A `ConfirmDialog` drifts, a `LoadingSkeleton` gets re-implemented four times, theme tokens fork. Catching this at PR time is cheaper than a future consolidation sprint.

#### Detection Checklist

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Existing component duplicated** | A new component in an app that already exists in `<shared-ui-package>/src/components/` (check by name, props signature, visual shape — not just identical names) | Major |
| **Generic primitive in app folder** | New component with no app-specific logic (pure UI primitive: `Button`, `Card`, `Badge`, `Chip`, `Skeleton`, `EmptyState`, `ErrorBoundary`, `Tooltip`, `Avatar`, `StatusPill`) living in `apps/*/src/components/` | Major |
| **Likely cross-app reuse** | Component the sibling app will plausibly need (generic confirmation dialog, loading indicator, chart wrapper, data table, filter chip row, metric card). Extraction should happen NOW, not later. | Major |
| **Library wrapper duplication** | Thin wrapper around the component library (styled `Button`, `Dialog` with common layout, `TextField` with label pattern) duplicated across apps instead of lifted to the shared package | Major |
| **Shared theme/style tokens** | `sx` props, `styled()` definitions, or color/spacing tokens duplicated across apps that could be a shared-package export (theme constants, shared `sx` helpers) | Minor |
| **Hook duplication** | Generic hook (`useDebounce`, `useClickOutside`, `useMediaQuery` wrapper) defined in app folder instead of `<shared-ui-package>/src/hooks/` | Minor |

#### Verification Steps (before flagging)

Always verify against the actual shared-package surface before posting a finding:

```bash
# 1. Search for existing component by name or pattern
rg -n "ComponentName" <shared-ui-package>/src/components/

# 2. Check the public exports barrel
rg "^export" <shared-ui-package>/src/index.ts

# 3. If the new component already matches something in the shared package by prop shape,
#    flag as a duplicate; otherwise flag as an extraction opportunity.
```

#### Comment Template — Extract Before Consuming

```markdown
**[MAJOR]** Reusable component should live in `<shared-ui-package>`, not in the app

**Why**: `ComponentName` is a generic <one-line description — e.g., "status pill that
renders a colored chip with an icon and label"> with no app-specific dependencies
(no `authStore`, no domain types, no app-specific routes). Placing it in
`apps/<app-a>/src/components/` means:
- `<app-b>` cannot consume it (cross-app import is not allowed).
- The next person who needs the same pattern in `<app-b>` will copy-paste it,
  causing divergence.
- Visual consistency between apps drifts silently.

**Action** (do this BEFORE merging, not "in a follow-up"):
1. Move the component to `<shared-ui-package>/src/components/ComponentName/ComponentName.component.tsx`
2. Add a story: `<shared-ui-package>/.storybook/stories/ComponentName.stories.tsx`
3. Add to the public barrel: `<shared-ui-package>/src/index.ts`
4. Import here as `import { ComponentName } from '<shared-ui-package>'`
5. Accept `sx?: SxProps<Theme>` (or the equivalent style override prop) in props to allow app-level styling overrides

If the intent is to prototype in-app first, leave a `TODO(<shared-ui-package> extraction)`
comment with an issue link — but generic primitives should go straight to the shared package.
```

#### Comment Template — Duplicate of Existing Shared-Package Export

```markdown
**[MAJOR]** Duplicate of existing `<shared-ui-package>` component

**Why**: `<shared-ui-package>` already exports `<ExistingComponent>` (see
`<shared-ui-package>/src/components/<ExistingComponent>/`). Its prop surface
covers the usage here: `<list props that match>`. Re-implementing it in-app
drifts from the shared design system and violates DRY.

**Action**: Replace this local definition with:
\`\`\`tsx
import { ExistingComponent } from '<shared-ui-package>';
\`\`\`
If `ExistingComponent` is missing a prop you need, **extend it in `<shared-ui-package>`**
rather than forking here. That keeps one source of truth.
```

**When NOT to flag**: The component is tightly coupled to app-specific business logic — it imports from `authStore`, uses the app's routes, or depends on domain-specific types that only exist in one app. In that case, local placement is correct.

### Theme System & Design Constraints (CRITICAL — frontend)

**Applies when**: the app uses a themed component library. The examples below use Material UI (MUI); map them to the equivalent tokens for Chakra, Mantine, Ant Design, or a Tailwind theme config.

**Rule**: Every PR that touches UI must conform to the established theme system. No component may diverge from the library's styling contract — no custom CSS that bypasses the theme, no hardcoded design tokens, no one-off color/spacing/typography that ignores `theme.*`.

**Why this is a dedicated pass**: Theme drift is invisible in code review because each individual hardcoded value looks harmless (`color: '#1976d2'`, `padding: '16px'`, `fontSize: 14`). But hundreds of such values across a codebase make design-system migrations impossible and dark-mode / theme-token changes unsafe. Catch them at PR time, not during a future rebrand.

#### Design-System Detection Checklist

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Hardcoded colors** | Hex codes (`#1976d2`), named colors (`'red'`), `rgb()/rgba()` literals in `sx`, `styled()`, or inline styles. Should use `theme.palette.*` (`theme.palette.primary.main`, `theme.palette.error.light`, `theme.palette.grey[500]`). | Major |
| **Hardcoded spacing** | Numeric px in `padding`/`margin`/`gap`/`top`/`left` (`padding: '16px'`, `margin: 8`). Should use `theme.spacing(n)` or the library's shorthand (`p: 2`, `mx: 3`, `gap: 1.5`). | Minor |
| **Hardcoded typography** | Raw `fontSize`, `fontWeight`, `lineHeight`, `fontFamily` values. Should use `theme.typography.*` variants (`variant="body1"`, `variant="h4"`) or `theme.typography.body2.fontSize`. | Minor |
| **Hardcoded breakpoints** | Media queries with px values (`@media (min-width: 600px)`). Should use `theme.breakpoints.up('sm')`, `theme.breakpoints.down('md')`, or responsive `sx` (`sx={{ display: { xs: 'none', md: 'block' } }}`). | Minor |
| **Hardcoded border radius** | `borderRadius: '8px'`, `borderRadius: 4`. Should use `theme.shape.borderRadius` or consistent tokens. | Trivial |
| **Hardcoded shadows** | Custom `boxShadow: '0 2px 4px ...'`. Should use `theme.shadows[n]` (MUI ships 25 elevation levels). | Minor |
| **Hardcoded z-index** | Magic `zIndex: 1000`, `zIndex: 9999`. Should use `theme.zIndex.*` (`modal`, `tooltip`, `drawer`, `appBar`). | Minor |
| **Raw HTML over library components** | `<button>`, `<input>`, `<div role="dialog">`, `<table>` used instead of library equivalents (`<Button>`, `<TextField>`, `<Dialog>`, `<Table>`). Breaks theme inheritance, a11y, and interaction states. | Major |
| **Off-library icons** | Custom inline SVG or icons from other libraries when the app's icon set (e.g. `@mui/icons-material`) has an equivalent. See ICON anti-pattern. | Minor |
| **Styling libraries outside the theme** | New files using `styled-components`, raw `emotion` without the library's `styled()` helper, or CSS modules — all bypass the theme. | Major |
| **Global CSS / inline `<style>`** | New global CSS files, `<style>` tags, `!important` overrides, or CSS variables that shadow theme tokens. | Major |
| **Unstable / lab components** | Lab or experimental components (`@mui/lab`) when a stable equivalent exists. | Minor |
| **Custom theme at component level** | `ThemeProvider` wrapping a single component with a forked theme. Fragments the theme contract. | Major |
| **Library version divergence** | Component imports from a different major version of the component library than the rest of the app. | Major |
| **Dark mode regressions** | Hardcoded light-only values (`backgroundColor: '#fff'`, `color: '#000'`) that won't flip in dark mode. Use `theme.palette.background.paper`, `theme.palette.text.primary`. | Minor |

#### How to Detect

For every changed `.tsx`/`.ts` file that renders UI:

```bash
# 1. Hardcoded hex/rgb colors in sx, styled, or style props
grep -nE "(sx|style|styled)[^}]*(#[0-9a-fA-F]{3,8}|rgb[a]?\()" <file>

# 2. Hardcoded px spacing/sizes (exempt: border: 1px, outline: 1px — guideline, not hard rule)
grep -nE "(padding|margin|gap|top|left|right|bottom|width|height|fontSize):\s*['\"]?[0-9]+(px)?['\"]?" <file>

# 3. Raw HTML UI elements and role-based dialogs
grep -nE '<(button|input|textarea|select|table|dialog)\b|role="dialog"' <file>

# 4. Alternative styling libraries
grep -nE "from ['\"](styled-components|@emotion/styled)['\"]" <file>

# 5. Inline <style> / global CSS imports
grep -nE "<style\b|import\s+['\"].+\.css['\"]" <file>
```

#### Comment Template — Theme Divergence

```markdown
**[MAJOR]** Hardcoded color diverges from theme — breaks dark mode and rebrand safety

**Why**: `color: '#1976d2'` on line 42 is a raw hex literal. This codebase uses the
theme system (`theme.palette.primary.main`) which:
- Automatically flips values in dark mode (`theme.palette.mode === 'dark'`).
- Lets product design change the brand palette globally without grep-and-replace.
- Preserves WCAG contrast pairings (`primary.main` ↔ `primary.contrastText`).

Hardcoding `#1976d2` silently opts this component out of all three. Next time we
tune the brand blue, this component diverges visually.

<details>
<summary>Suggestion</summary>

\`\`\`suggestion
sx={{ color: 'primary.main' }}
// or inside styled()/useTheme(): color: theme.palette.primary.main
\`\`\`

</details>
```

#### Comment Template — Raw HTML Instead of a Library Component

```markdown
**[MAJOR]** Raw `<button>` bypasses the theme — use `<Button>`

**Why**: `<button>` inherits the browser user-agent style, not `theme.components.MuiButton`.
This means:
- No theme-driven hover/focus/active/disabled states.
- No ripple, no focus ring, no keyboard affordance.
- No automatic dark-mode handling.
- Divergent look-and-feel from every other button in the app.

<details>
<summary>Suggestion</summary>

\`\`\`suggestion
<Button variant="contained" onClick={handleSubmit}>Save</Button>
\`\`\`

</details>
```

#### Comment Template — New Component Without Theme Awareness

```markdown
**[MINOR]** New component should accept `sx?: SxProps<Theme>` for theme extensibility

**Why**: Components that hardcode their own styling can't be themed or overridden by
consumers. Every shared/primitive component in this codebase accepts `sx` so call
sites can layer theme-aware overrides without forking the component.

**Action**: Add `sx?: SxProps<Theme>` to the props interface and spread onto the root
element: `<Box sx={[baseSx, ...(Array.isArray(sx) ? sx : [sx])]} />`.
```

#### When NOT to flag

- Third-party vendor widgets that can't be styled via the theme (flag once, note the exception in the file — don't re-report).
- A single `1px` border or similar structural constant where `theme.spacing(0.125)` would obscure intent.
- CSS imported from a design-system package explicitly (e.g., `mapbox-gl/dist/mapbox-gl.css`, Storybook addon CSS).
- Storybook files (`*.stories.tsx`) demonstrating theme comparisons.

### Anti-Pattern Checks (from the review-pattern catalog)

| Check | Code | What to look for | Severity |
|-------|------|-----------------|----------|
| **String literals for enums** | ENUM | `'pending'` instead of `OrderStatus.PENDING` when an enum / const object exists | Major |
| **Bypassing the API client layer** | REUSE | Direct `axios.get()` / `fetch()` / `http.Get()` instead of the repo's generated or shared API client (which carries auth, retries, and typing) | Major |
| **Duplicate shared-package code** | REUSE | See dedicated **Shared-Package Reuse & Extraction** pass above — covers detection, verification, and comment templates | — |
| **Setters in useEffect deps** (frontend) | DEP | `[setData, setState]` in dependency array | Minor |
| **Missing useCallback** (frontend) | CALLBACK | Handlers passed as props without memoization | Trivial |
| **Missing props interface** (frontend) | PROPS | Components without typed props | Minor |
| **Inline SVGs** (frontend) | ICON | SVGs instead of the app's icon library | Minor |
| **Second date library** | - | Introducing `dayjs` when the app standardizes on `date-fns` / `moment` (or vice versa) — one date library per app | Minor |
| **Bypassing the notification helper** (frontend) | - | Direct `toast.error(...)` instead of the app's notification hook / context | Minor |
| **Unstable components** (frontend) | - | Lab / experimental components instead of stable equivalents | Minor |
| **Context refetching** (frontend) | - | Fetching data already available in context or a store | Minor |
| **Bloated files** | FILE | Files exceeding 500 lines | Minor |

### State Management & Data Fetching Checks (frontend)

**Objective**: Detect patterns where ad-hoc local state should be replaced with the app's store and/or server-state library for deduplication, cache sharing, and reduced boilerplate.

#### Duplicate API Call Detection

When a PR introduces or modifies service calls, check if the **same endpoint** is called independently from multiple components/hooks:

| Signal | What to look for | Severity |
|--------|-----------------|----------|
| **Same service function called 2+ times** | Grep for the function name (e.g., `getOnboardingStatus`) across all changed and related files. If called in separate `useEffect`/`useState` patterns in different components, flag as duplicate. | Major |
| **Same data fetched at different tree levels** | A parent route guard and a child page both fetch the same data independently. The parent's result is never passed down or shared. | Major |
| **Manual polling reimplemented** | `setInterval` + `useState` + `useEffect` pattern for periodic fetching. The app's server-state library (`refreshInterval` in SWR, `refetchInterval` in React Query) handles this with deduplication, window-focus pause, and error retry built in. | Minor |

**How to detect:** For each new service call in the PR:
1. Grep the codebase for all call sites of that function
2. If 2+ independent call sites exist (each with their own `useState` + `useEffect`), flag with a store or server-state recommendation
3. Include all call sites in the comment so the developer sees the full duplication

#### Store Opportunity Detection

| Signal | What to look for | Severity |
|--------|-----------------|----------|
| **Props drilled 3+ levels** | A piece of data originates in a page component and is passed through 3+ intermediate components via props before being consumed. The intermediate components only forward it. | Major |
| **Cross-component shared state via props** | The same state value appears in 3+ component Props interfaces in the same feature area. | Minor |
| **Derived state recomputed in multiple places** | The same `useMemo` or derivation logic (e.g., filtering, mapping, aggregating) is duplicated across sibling components instead of being computed once in a store. | Major |
| **State that should survive navigation** | Data fetched on page A is lost when navigating to page B and back, causing a re-fetch. A store would preserve it. | Minor |

**How to detect:** For each new feature area in the PR:
1. Count how many `interface Props` definitions pass the same data fields
2. Check if the same derived computation (e.g., `steps.filter(...)`, `steps.every(...)`) appears in multiple files
3. Look for data that flows: Service → Hook → Page → Component → SubComponent → Panel (3+ hops = store candidate)

#### Query Layer Pattern Detection

**App-aware**: Each app has its own query convention. Detect it from the app's `package.json` dependencies before recommending anything:

| Dependency present | Query convention | Recommendation |
|--------------------|-----------------|----------------|
| `swr` | SWR (`useSWR`) | Use SWR for server-state deduplication, polling (`refreshInterval`), stale-while-revalidate |
| `@tanstack/react-query` | React Query | Use `useQuery` / `useMutation`; `refetchInterval` for polling, `staleTime` for gates |
| `zustand` / `redux` / `jotai` only | Store + manual fetch | Use the store's async actions; consider adding a server-state library for complex server state |
| None of the above (greenfield) | Team decision | Recommend whatever the sibling apps already use; note alternatives |

**IMPORTANT**: Do NOT recommend a library the app does not already depend on. Always check which app the changed files belong to (and its `package.json`) before suggesting a query layer.

| Signal | What to look for | Severity |
|--------|-----------------|----------|
| **Manual `useState` + `useEffect` + fetch** | Hook that calls a service in `useEffect`, stores result in `useState`, manages `loading`/`error` states manually. This is what the app's query layer replaces. | Minor |
| **Manual cache in sessionStorage/localStorage** | Auth tokens or API responses cached manually instead of using the app's query cache or a store. Risk of stale data without invalidation. | Major |
| **Missing stale-while-revalidate** | A loading gate (spinner/redirect) blocks UI while fetching data that could show stale cached data immediately. SWR / React Query provide this by default; stores can serve cached data while refetching. | Minor |
| **No mutation invalidation** | After a POST/PATCH (mutation), the component manually calls `refetch()` on related queries. SWR's `mutate()`, React Query's `invalidateQueries()`, or a store's action-based refetch is more reliable. | Minor |

**Comment template for state management findings:**
```markdown
**[SEVERITY]** Duplicate API call / Store opportunity / Query layer candidate

**Why**: `functionName()` is called independently in N places:
1. `FileA.tsx` — via `useEffect` on mount
2. `FileB.tsx` — via `useEffect` with polling
3. `FileC.tsx` — via `useEffect` on mount

Each maintains its own `useState` for the response. Changes in one don't propagate to others.

**Recommendation**:
- **Store** for derived client state (`enrichedData`, `computedFlags`)
- **[App's query layer]** for server state (automatic dedup, polling, stale-while-revalidate)
  - SWR app: `useSWR` with `refreshInterval` for polling
  - React Query app: `useQuery` with `refetchInterval`
  - Store-only app: store with async actions
```

### Architecture Checks (from app-level instruction files)

Enforce the architectural rules each app's `CLAUDE.md` states. Typical examples:

| Check | Scope | What to look for | Severity |
|-------|-------|-----------------|----------|
| **Designated state container** | apps that standardize on a store | New shared state using ad-hoc Context instead of the app's store | Major |
| **Designated data-fetching layer** | apps with a server-state library | API data fetched without it | Minor |
| **Style override prop** | shared UI package | New components missing `sx?: SxProps<Theme>` (or the equivalent) in props | Minor |
| **Barrel exports** | apps with an export barrel | New pages / modules not exported through the barrel (`pages/index.ts`) | Minor |

### Code Comment Standard

Only when the repo's instruction files require it:

| Check | Applies to | What to look for | Severity |
|-------|-----------|-----------------|----------|
| **File header** | New files | Missing the repo's required header tags (e.g. `@ticket`, `@purpose`, `@context`) | Minor |
| **Function doc** | Non-obvious functions >20 lines | Missing the repo's required doc tags (e.g. `@why`, `@edge-cases`) | Trivial |

---

## Phase 7: Pass C — Security Review

**Objective**: Dedicated security-focused pass for OWASP Top 10 and auth/data patterns.

**Run on**: Only files classified as **Critical** or **High** risk (Phase 2). Skip entirely for Medium/Low risk PRs unless the PR type is explicitly security-related.

### Security Checklist

| Check | Category | What to look for | Severity |
|-------|----------|-----------------|----------|
| **Hardcoded secrets** | Secrets | API keys, tokens, passwords, connection strings in source code | Major |
| **Sensitive data in logs** | Data leakage | User emails, tokens, PII in `console.log` / logger calls or error messages | Major |
| **SQL/NoSQL injection** | Injection | Unsanitized user input in queries, string-built SQL | Major |
| **XSS** | Injection | `dangerouslySetInnerHTML`, unescaped user content in DOM or templates | Major |
| **Auth bypass** | Authentication | Routes/actions without auth checks, missing token validation | Major |
| **Authorization gaps** | Authorization | Actions not checking user roles/permissions, missing org- / tenant-level isolation | Major |
| **Insecure data storage** | Storage | Sensitive data in localStorage/sessionStorage without encryption | Minor |
| **CORS misconfiguration** | Network | Overly permissive CORS headers | Major |
| **Dependency vulnerabilities** | Supply chain | New dependencies with known CVEs (check with the package manager's audit command — `npm audit`, `yarn audit`, `pnpm audit`, `pip-audit`, `govulncheck`, `cargo audit` — if new deps were added) | Major |
| **Prototype pollution** | JavaScript | Deep merge of user-controlled objects without sanitization | Major |
| **SSRF / path traversal** | Input handling | User-controlled URLs or file paths reaching `fetch`, `http.Get`, `open()` without validation | Major |

### Auth-Specific Checks (adapt to the repo's auth stack)

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Identity-provider token handling** | Tokens (Firebase, Auth0, Cognito, JWT) stored insecurely, missing refresh logic, tokens in URLs | Major |
| **Route guard bypasses** | New routes that skip the app's private-route wrapper / auth context / middleware | Major |
| **Role-based access** | New features without checking the app's access-level helper or user role | Major |
| **API calls without auth** | Direct `fetch`/`axios`/`http` calls that skip the authenticated client (whose interceptors add auth tokens) | Major |

---

## Phase 8: Pass D — Type-Specific Deep Inspection

**Objective**: Apply the PR-type-specific inspection strategy identified in Phase 3.

### 8.1 Strategy: Reference Sweep (Cleanup / Removal PRs)

**Goal**: Ensure every trace of the removed code is gone.

#### Build a Removal Manifest

From the diff, identify everything being removed:
- Deleted files (services, components, utils, types)
- Removed imports and exports
- Removed function/method calls
- Removed type definitions, interfaces, enums
- Removed configuration keys, env vars, constants

#### Full-Codebase Reference Search

For **each item** in the removal manifest, search the **entire codebase** (not just changed files):

```
Grep for: function names, class names, type names, import paths,
          config keys, env vars, URL patterns, string literals,
          comment mentions, doc-comment references, file path references

Use -w (whole-word) matching to prevent partial matches
(e.g., searching for removed `getUser` won't incorrectly match `getUsers`).
```

Search patterns:
- Direct imports: `import { X } from '...'`, `from pkg import X`, `"module/path"` in Go imports
- Type references: `X extends`, `: X`, `<X>`
- String mentions: `'X'`, `"X"`, `` `${X}` ``
- Comment references: `// X`, `/* X */`, `@see X`, `@param X`
- File path references: `from 'path/to/removed-file'`
- Configuration references: env vars, config objects, CI workflow inputs
- URL/endpoint references: API endpoints served by removed code

#### Leftover Detection Checklist

| Category | What to check | Severity |
|----------|---------------|----------|
| **Unused imports** | Imports only used by removed code | Major |
| **Dead variables** | Variables assigned from removed imports, never used elsewhere | Major |
| **No-op functions** | Functions whose body was gutted, now empty or returning nothing | Major |
| **Stale comments** | Comments referencing removed services, features, or files | Minor |
| **Stale doc comments** | `@param`, `@see`, `@dependency` referencing removed code | Minor |
| **Orphaned types** | Type definitions only used by removed code | Major |
| **Orphaned config** | Config keys, env vars, feature flags for removed features | Minor |
| **Stale test code** | Tests for removed functionality that weren't deleted | Major |
| **Stale documentation** | README, docs/ files referencing removed features | Trivial |
| **Empty directories** | Directories left empty after file deletions | Trivial |

---

### 8.2 Strategy: Completeness Walk (Feature / Implementation PRs)

**Goal**: Verify the implementation is complete by walking the execution tree.

#### Identify Entry Points

From the diff, identify: new routes or endpoints, new components or handlers, new API calls, new event handlers or message consumers, new context providers or stores, new CLI commands or jobs.

#### Walk the Execution Tree

```
Entry point → Handler / Page → Child units → Helpers → Data access / API calls → Error handlers
  │                                                     │
  ├── Are all imports resolved?                         ├── Is error handling present?
  ├── Are all inputs typed and validated?               ├── Is loading state handled? (UI)
  ├── Are edge cases handled?                           ├── Is empty state handled? (UI)
  └── Are permissions checked?                          └── Is the response typed?
```

#### Implementation Completeness Checklist

| Category | What to check | Severity |
|----------|---------------|----------|
| **Missing error handling** | API calls without try/catch or `.catch()`; ignored error returns | Major |
| **Missing loading states** (UI) | Async operations without loading indicators | Major |
| **Missing empty states** (UI) | Lists/tables without empty state UI | Minor |
| **Missing types** | New functions/components without type annotations | Major |
| **Missing permissions** | New routes/actions without auth checks | Major |
| **Incomplete cleanup** | `useEffect` without cleanup for subscriptions/timers; unclosed resources | Major |
| **Missing edge cases** | Null checks, array bounds, division by zero, empty input | Minor |
| **Missing accessibility** (UI) | Interactive elements without keyboard/screen reader support | Minor |
| **Hardcoded values** | Magic numbers, hardcoded URLs, embedded strings | Minor |

#### State Management Completeness Check (frontend)

For feature PRs that introduce new hooks, services, or data flows:

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Duplicate fetches** | Same service function called from 2+ independent components with separate `useState`. Should share via store or the server-state cache. | Major |
| **Deep prop drilling** | Data passed through 3+ component levels. Intermediate components only forward it. Should use a store for direct access. | Major |
| **Manual polling without dedup** | `setInterval` + `useState` pattern. The server-state library's polling option deduplicates across consumers and pauses on window blur. | Minor |
| **No cache/store for gate data** | Auth gates or route gates that fetch data on every render without caching. A store or `staleTime` prevents redundant blocking fetches. | Major |
| **Stale token caching** | Auth tokens cached in sessionStorage/localStorage without expiry checks. Most identity providers issue tokens that expire within an hour. | Major |

#### PM Perspective Check

Think like a product manager:
- Does the implementation match the linked issue's requirements?
- Are all acceptance criteria from the issue satisfied?
- Are there user-facing scenarios that aren't handled?
- Would a user encounter a dead end or confusing state?
- Is the happy path complete? What about error/edge paths?

---

### 8.3 Strategy: Root Cause Validation (Bugfix PRs)

**Goal**: Verify the fix addresses the actual root cause, not just the symptom.

| Check | Question | Severity if failed |
|-------|----------|-------------------|
| **Root cause match** | Does the fix address the actual root cause, or just mask the symptom? | Major |
| **Regression risk** | Could this fix break existing behavior elsewhere? | Major |
| **Edge cases** | Does the fix handle all variants of the bug, or just one case? | Major |
| **Test coverage** | Is there a test that would catch this bug recurring? | Minor |
| **Similar code** | Are there other places with the same pattern that need the same fix? | Minor |

---

### 8.4 Strategy: Equivalence Check (Refactor PRs)

**Goal**: Verify the refactored code behaves identically to the original.

| Check | Question | Severity if failed |
|-------|----------|-------------------|
| **Export parity** | Are all public exports preserved? | Major |
| **Type parity** | Are all type signatures preserved? | Major |
| **Behavioral parity** | Same output for same input? | Major |
| **Import updates** | All consumers updated to new import paths? | Major |
| **Side-effect parity** | Side effects preserved? | Major |
| **Test compatibility** | Existing tests pass without modification? | Minor |
| **Monorepo consistency** | When the same logic exists in multiple apps (parallel copies in `apps/<app-a>` and `apps/<app-b>`), are ALL copies updated consistently? | Major |

#### Monorepo Consistency Check (monorepos with parallel app copies)

Some monorepos keep duplicated code between sibling apps (a main app and an admin app, a web app and an embedded variant). When a refactor or fix touches code that exists in more than one app:

1. **Build a change manifest**: For each changed file, check if a parallel version exists in a sibling app:
   - `apps/<app-a>/src/components/X.tsx` → check `apps/<app-b>/src/components/X.tsx`
   - `apps/<app-b>/src/pages/Y.tsx` → check `apps/<app-a>/src/pages/Y.tsx`
   ```bash
   # Find same-named files in sibling apps
   for f in $(gh pr diff <PR_NUMBER> --name-only); do
     git ls-files "apps/*/${f#apps/*/}" | grep -v "^$f$"
   done
   ```
2. **Compare implementations**: Ensure the same fix/change was applied to ALL copies
3. **Flag inconsistencies**: If a fix was applied to one app but not the other, flag as MAJOR:
   ```markdown
   **[MAJOR]** Inconsistent fix between apps — `<fix description>` was applied to
   `apps/<app-a>/...` but not `apps/<app-b>/...`. Both copies need the same update.
   ```

This catches a common pattern where a reviewer's fix is applied to one app copy but the parallel file in the sibling app is missed.

---

### 8.5 Strategy: Side-Effect Scan (Configuration / Infra PRs)

| Check | Question | Severity if failed |
|-------|----------|-------------------|
| **Build impact** | Does the change affect build output or bundle size? | Major |
| **Runtime impact** | Does the change affect runtime behavior? | Major |
| **Environment parity** | Works in all environments (dev, staging, prod)? | Minor |
| **Dependency conflicts** | Version changes create peer dependency conflicts? | Major |
| **Selective deploy** | If the repo uses path filters or a change-detection script to decide what to deploy (CI `paths:` filters, `turbo-ignore`, a `should-deploy` script), does it correctly pick up this change? | Minor |

---

### 8.6 Strategy: Visual Consistency (UI / Design PRs)

| Check | Question | Severity if failed |
|-------|----------|-------------------|
| **Design system compliance** | Uses the component library and the shared UI package where available? Any new generic UI primitive (Button, Card, Badge, EmptyState, Skeleton, etc.) must be added to the shared package before being consumed in an app — see the Shared-Package Reuse & Extraction pass in Phase 6. | Major |
| **Theme usage** | Uses `theme.spacing()`, `theme.palette` instead of hardcoded values? | Minor |
| **Responsive design** | Uses the theme's breakpoints? | Minor |
| **Accessibility** | Proper ARIA labels, keyboard support? | Major |
| **Consistent patterns** | Follows existing patterns in similar pages/components? | Minor |

---

# STAGE 3: FILTER & DEDUPLICATE

This stage is critical for trust. Research shows 5-15% false positive rates erode developer confidence. Filter aggressively.

## Phase 9: Confidence Filtering

### 9.1 Confidence Levels

Assign a confidence score to each finding:

| Confidence | Criteria | Action |
|------------|----------|--------|
| **High** (90%+) | Deterministic check (unused import, `console.log`, `any` type, missing null check with clear crash path) | Always include |
| **Medium** (60-90%) | Pattern-based (convention violation, missing error handling where failure is plausible) | Include with evidence |
| **Low** (< 60%) | Speculative (might be intentional, unclear if it's actually a problem, subjective preference) | **Exclude** — do not post |

### 9.2 Filtering Rules

**Exclude findings that are:**
- Pre-existing issues NOT introduced by this PR (the PR didn't make it worse)
- In auto-generated files (`**/generated/**`, `**/client/**`, `*.pb.go`, `*_pb2.py`, `*.gen.ts`)
- In files marked as `@generated`, `@auto-generated`, or `Code generated ... DO NOT EDIT`
- Duplicates of another finding in the same review (keep the most specific one)
- Style-only preferences with no functional impact and no instruction-file rule backing them

### 9.3 Deduplication

If the same pattern appears in multiple files (e.g., same unused import in 5 files), consolidate into a single finding:

```markdown
**[MINOR]** Deep relative imports instead of the path alias — found in 5 files

Files: `ComponentA.tsx`, `ComponentB.tsx`, `ComponentC.tsx`, `ComponentD.tsx`, `ComponentE.tsx`

All use `../../../utils/` instead of `src/utils/`. Consider updating to match the `src/` path alias convention.
```

Post the consolidated finding as a general review comment (not inline), with a single inline comment on the most representative instance.

### 9.4 Risk-Based Threshold

Adjust the minimum confidence threshold based on PR risk:

| PR Risk | Min Confidence to Post | Rationale |
|---------|----------------------|-----------|
| **Critical** | Medium (60%) | Better safe than sorry on auth/security paths |
| **High** | Medium (60%) | Standard thoroughness |
| **Medium** | High (90%) | Only high-confidence findings to reduce noise |
| **Low** | High (90%) | Minimal noise on trivial changes |

---

# STAGE 4: OUTPUT & FEEDBACK

## Phase 10: Post Line-Level Review Comments on GitHub

**CRITICAL: Line comments only. No summary body.** The review body must be minimal (just the skill attribution line). ALL findings go as inline line-level comments. This is the only output that matters.

### 10.1 Create a Pull Request Review with Inline Comments Only

Use the GitHub API to create a review with **only** line-level comments. No summary tables, no pipeline reports, no "What Looks Good" sections in the review body.

**IMPORTANT**: Comments can only be posted on lines that appear in the PR diff. If a finding references a line outside the diff, post it as a line comment on the nearest relevant line in the diff with a note like "Note: the root issue is at `file.ts:123` (outside diff)".

#### Step A: Determine Diff Positions

For each finding, verify the target line appears in the PR diff before posting:

1. Run `gh pr diff <PR_NUMBER>` and parse the unified diff output
2. For each finding's file and line number, check if that line falls within a `@@` hunk range on the RIGHT side (new version)
3. If the line is **in the diff** → include it in the `comments[]` array with `path`, `line`, `side: "RIGHT"`
4. If the line is **outside the diff** → attach to the nearest related line that IS in the diff

A line-level comment requires:
- `path`: File path relative to repo root
- `line`: Line number in the **new version** of the file (right side of diff) — must be within a diff hunk
- `side`: Always `"RIGHT"` for comments on the new version

#### Step B: Post the Review

Write the payload to a temp file (handles special characters safely):

```bash
# Write review payload to temp file
PAYLOAD="$(mktemp)"
cat > "$PAYLOAD" <<'PAYLOAD_EOF'
{
  "event": "<APPROVE|REQUEST_CHANGES|COMMENT>",
  "body": "---\n*Reviewed by [`/pr-review`](https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/engg/skills/pr-review/SKILL.md)*",
  "comments": [
    {
      "path": "path/to/file.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "**[MAJOR]** Description...\n\n**Why**: Explanation with full code context — reference the surrounding code, what it does, how the issue manifests, and what the downstream impact is.\n\n<details>\n<summary>Suggestion</summary>\n\n```suggestion\n// The corrected code — GitHub renders this as a one-click applicable fix\n```\n\n</details>"
    }
  ]
}
PAYLOAD_EOF

# Post the review
gh api "repos/$GITHUB_REPO/pulls/<PR_NUMBER>/reviews" \
  -X POST \
  --input "$PAYLOAD"

# Clean up
rm -f "$PAYLOAD"
```

### 10.2 Comment Format — Full Context is King

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

### 10.3 Review Body

The review body must be **minimal** — just the skill attribution. No summaries, no tables, no pipeline reports. The line comments ARE the review.

```markdown
---
*Reviewed by [`/pr-review`](https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/engg/skills/pr-review/SKILL.md)*
```

---

## Phase 11: Build Validation

After inspection (no code changes — read-only), validate the current build state using the repo's own tooling. Detect it, don't assume it:

### 11.1 Type Check / Static Check

| Detected | Command |
|----------|---------|
| `package.json` with a `typecheck` script | `<pm> run typecheck` where `<pm>` is `pnpm` / `yarn` / `npm` / `bun` by lockfile (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lockb`) |
| `package.json` without `typecheck` but with `tsconfig.json` | `npx tsc --noEmit` (or the workspace-wide equivalent, e.g. `turbo run typecheck`) |
| `go.mod` | `go build ./... && go vet ./...` |
| `pyproject.toml` | The type checker / linter the manifest configures: `uv run pyright`, `uv run mypy`, `ruff check` |
| `Cargo.toml` | `cargo check --all-targets` |

If the repo's `CLAUDE.md` names a canonical verification command, use that instead.

### 11.2 Report Build Status

- **PASS**: Build is clean (or only pre-existing errors)
- **FAIL**: New errors introduced by this PR (list them)

Pre-existing errors should be flagged as pre-existing, not attributed to this PR. Determine what is pre-existing by running the same command against the base branch — in a throwaway worktree so the PR checkout is untouched:

```bash
BASE_WT="$(mktemp -d)"
git worktree add --detach "$BASE_WT" "origin/<baseRefName>"
( cd "$BASE_WT" && <same check command> ) > "$BASE_WT.log" 2>&1
git worktree remove --force "$BASE_WT"
```

Any error present in the base run is pre-existing; anything new in the PR run is attributable to the PR.

---

## Phase 12: Console Output

Keep console output minimal. Just report what was posted:

```
Review posted: <review_url>
Line comments: X Major, Y Minor, Z Trivial
Verdict: <APPROVE | REQUEST_CHANGES | COMMENT>
Sentry cross-reference: <Ran | Skipped (not configured) | Skipped (API unavailable)>
```

No pipeline reports, no summary tables, no "What Looks Good" sections in console output. The line comments on GitHub ARE the deliverable.

### 12.1 Verdict Logic

| Condition | Verdict |
|-----------|---------|
| 0 Major findings | **APPROVE** |
| 1+ Major findings on Medium/Low risk PR | **REQUEST_CHANGES** |
| 1+ Major findings on Critical/High risk PR | **REQUEST_CHANGES** (flag for senior reviewer) |
| Only ambiguous/debatable issues | **COMMENT** |

Set the GitHub API `event` field to match: `"APPROVE"`, `"REQUEST_CHANGES"`, or `"COMMENT"`.

#### Own-PR Fallback

GitHub API returns HTTP 422 when you try to `REQUEST_CHANGES` or `APPROVE` on your own PR. When the authenticated user is the PR author:
1. Always use `"COMMENT"` as the `event` field
2. State the intended verdict in the review body: `### Verdict: REQUEST_CHANGES` (or APPROVE)
3. This makes the intent clear even though the API can't enforce it

---

## Important Guidelines

### Inspection Principles

- **Full context in every comment**: Each line comment must be self-contained. Include what the surrounding code does, how the issue manifests, what breaks downstream, and the specific fix. A developer should never need to read a summary to understand a comment.
- **Read before judging**: Always read the full file context, not just the diff hunk.
- **Understand intent before critiquing**: Know what the PR is trying to do before saying it's wrong.
- **Evidence over opinion**: Every finding must cite specific code, a specific rule (from the repo's instruction files), or a technical reason.
- **Proportional feedback**: Match review depth to PR scope. Don't produce 30 nits on a 5-line bugfix.
- **Scope discipline**: Only inspect code in the PR diff or directly affected by it.
- **Precision over recall**: Better to miss a real issue than flood with false positives. Trust is the currency.
- **No summaries**: Do NOT post summary tables, pipeline reports, or "What Looks Good" sections. Line comments are the only output.

### What NOT to Do

- Do NOT make code changes — this is a read-only inspection skill
- Do NOT resolve threads or comment on existing review discussions
- Do NOT push commits or modify the branch
- Do NOT post duplicate reviews — check for existing inspection first
- Do NOT block PRs for trivial issues alone
- Do NOT suggest refactors outside the PR's scope
- Do NOT re-report pre-existing issues the PR didn't introduce
- Do NOT post low-confidence findings — filter aggressively

---

## Phase 13: Self-Healing

**After every `/pr-review` execution**, run this phase.

### 13.1 Evaluate Skill Accuracy

Re-read this skill file (`Read` tool on `${CLAUDE_PLUGIN_ROOT}/skills/pr-review/SKILL.md`) and compare against what actually happened:

| Check | What to look for |
|-------|-----------------|
| **GitHub API calls** | Did review posting work? Did `--input` flag work? Did `line`/`side` format change? |
| **PR type classification** | Was the classification accurate? Did the taxonomy miss a PR type? |
| **Risk classification** | Were risk levels appropriate? Should any file paths be reclassified? |
| **Stack detection** | Did the marker table pick the right focus areas? Was a frontend pass applied to a backend file (or vice versa)? |
| **Inspection passes** | Did any pass produce false positives? Are checklists still valid? |
| **Severity calibration** | Were Major/Minor/Trivial ratings appropriate? |
| **Confidence filtering** | Were any low-quality findings posted? Were any high-quality findings filtered? |
| **Sentry integration** | If configured, did `mcp__sentry__search_issues` work? Were results relevant or noisy? |
| **Codebase conventions** | Have the repo's instruction-file rules changed? Is the review-pattern catalog still current? |
| **Tool names** | Did any `mcp__sentry__*` calls fail? Did `gh issue` / `gh pr` CLI calls fail? |
| **Build commands** | Did the detected type-check command work as expected? |
| **New patterns** | Were issues found that aren't in any checklist? Add them. |

### 13.2 Fix Issues Found

This skill ships inside a plugin, so the installed copy is overwritten on every plugin update. If discrepancies are found:
1. Record them in the console output under `Self-Healing Log` (see below)
2. If the repo keeps a local override of this skill (`.claude/skills/pr-review/SKILL.md`), apply the fix there with the `Edit` tool — keep changes minimal and targeted
3. Otherwise, open an issue or PR against the plugin repository with the proposed change
4. Log:

   ```
   Self-Healing Log:
   - Fixed: <what was wrong> → <what it was changed to>
   - Reason: <why the original was inaccurate>
   ```

### 13.3 Append Trigger Documentation

**GitHub review body** (included in Phase 10 template):
```markdown
---
*Reviewed by [`/pr-review`](https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/engg/skills/pr-review/SKILL.md) — Triggers: "review PR", "review this PR", "review PR changes", "deep review", "PR review"*
```

**Console output** (included in Phase 12 template):
```
Skill: /pr-review
File:  ${CLAUDE_PLUGIN_ROOT}/skills/pr-review/SKILL.md
Repo:  https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/engg/skills/pr-review/SKILL.md
```
