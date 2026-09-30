# Build validation (Phase 11)

Loaded by the `pr-review` skill in Phase 11, after the review is posted.
Read-only: it runs the repo's own checks and attributes new errors to the PR.

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
