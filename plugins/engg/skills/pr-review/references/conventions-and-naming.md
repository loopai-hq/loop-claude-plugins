# Conventions and naming standards

Loaded by the `pr-review` skill in Phase 6 (Pass B) for every stack. The
convention checks apply only where the repo's own instruction files state the
rule; the naming standards apply everywhere.

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

**Comment template for naming findings:**
```markdown
**[MINOR]** Vague variable name — `data` does not reveal intent

**Why**: `data` here holds the response of `getActiveOrders()`, an array of `Order` objects
scoped to the current org. Readers downstream (`OrdersTable`, `OrderSummary`) have to
trace back to this declaration to learn the type. Rename so the call site is self-documenting.

**Suggestion**: `activeOrders` (matches the function name and shape).
```

### Code Comment Standard

Only when the repo's instruction files require it:

| Check | Applies to | What to look for | Severity |
|-------|-----------|-----------------|----------|
| **File header** | New files | Missing the repo's required header tags (e.g. `@ticket`, `@purpose`, `@context`) | Minor |
| **Function doc** | Non-obvious functions >20 lines | Missing the repo's required doc tags (e.g. `@why`, `@edge-cases`) | Trivial |
