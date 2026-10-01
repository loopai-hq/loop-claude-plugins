# Frontend review passes (React / TypeScript apps)

Loaded by the `pr-review` skill in Phase 6 (Pass B) only when the stack
detection table marked the changed file as belonging to a React / TypeScript
app. Backend and service repos skip this file entirely. The examples use
Material UI and SWR / React Query; map them to the app's own libraries.

## Systematic `any` type detection (TypeScript)

For each new/modified file, run a mental grep for `: any`, `as any`, `<any>`, and `Record<string, any>`. Count total new instances introduced by the PR.

**When flagging `any` types:**
- If >5 new instances: consolidate into a **single MAJOR finding** listing all locations (don't post separate comments for each)
- **Suggest specific library types** — don't just say "don't use any", research what types the library exports:
  - Recharts: `TooltipProps<number, string>`, `LabelProps`, `CategoricalChartState`
  - MUI: `SxProps<Theme>`, `GridProps`, `SelectChangeEvent`
  - React: `MouseEvent<HTMLElement>`, `ChangeEvent<HTMLInputElement>`
  - Recharts bar click: `import { CategoricalChartState } from 'recharts/types/chart/types'`
- For callback props (`onDataPointSelection: (event: any, ...) => any`), suggest the actual shape based on how the callback is used downstream

## Named functions over inline callbacks

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
