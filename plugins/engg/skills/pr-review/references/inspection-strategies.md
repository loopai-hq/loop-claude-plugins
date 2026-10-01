# Type-specific inspection strategies (Phase 8, Pass D)

Loaded by the `pr-review` skill in Phase 8 after Phase 3 classified the PR.
Read only the strategy sections that match the PR's types; a PR with several
types gets several strategies. The cross-package impact check (Phase 2.2)
and the foundational principles every finding is judged against are here too.

## Foundational engineering principles (every pass)

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

## Cross-package impact detection (Phase 2.2, monorepos)

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
