# Reference tables

Loaded by the `rca` skill in Step 13 when it classifies the root cause and
fills the Infrastructure State table, and whenever it needs to know which tool
provides what.

## Issue Categories

| Category | Description | Example |
|----------|-------------|---------|
| **Data Gap** | Backend returned 200 but sparse/empty data | Missing datewise entries for date range |
| **API Error** | Non-200 status, timeout, or exception | 500 error, CORS failure, timeout |
| **Frontend Bug** | Data received correctly but rendered wrong | Empty state not handled, chart config issue |
| **Backend Bug** | Logic error, wrong computation, missing handling | Wrong aggregation, missing filter |
| **User Config** | User's filter/date selection caused expected behavior | Single-day range showing 1 data point |
| **Infra Issue** | Service degradation, cold start, resource limits | Cloud Run scaling, DB connection pool |
| **Auth Issue** | Token expired, permission denied, account disabled | 401/403 responses, stale Firebase token |
| **Deploy Regression** | Recent deployment introduced the bug | New code broke existing functionality |
| **Feature Flag** | A/B test or flag changed behavior | User in experiment variant with broken flow |
| **Performance** | Latency regression, resource exhaustion | Slow LLM generation, unoptimized query |
| **Third-Party** | External dependency failure | LLM provider timeout, payment API down |

## Key Reference

### Tools & What They Provide

| Tool | Use For | MCP Available |
|------|---------|---------------|
| **PostHog** | User sessions, API_latency + trace_id, exceptions, feature flags, session recordings | Yes |
| **Sentry** | JavaScript errors, unhandled exceptions, stack traces, AI analysis (Seer), **alerts** | Yes + REST API |
| **GCloud Logs** | Backend request bodies, response sizes, trace correlation, multi-service logs | Via `gcloud` CLI |
| **Vercel** | Deployment history, build logs, runtime logs | Yes |
| **Firebase** | User auth state, token validity, account status | Yes |
| **GitHub Issues** | Known issues, existing bug reports, incident tracking | Via `gh` CLI |
| **GitHub** | Deployed code changes, PR diffs, CI/CD status, commit history | Via `gh` CLI |
| **RCA docs** | RCA documentation in `$RCA_DOCS_DIR`, bundled template, prior-incident search | Via file read/write + `grep` |
| **Datadog** | Full distributed trace waterfall (DB, cache, microservice hops) | Via `dd.trace_id` in GCloud logs |
| **Frontend Code** | Data flow, rendering logic, empty state handling | Via file read |

### Infrastructure Reference

Values come from the Configuration section; nothing here is hardcoded.

| Resource | Value |
|----------|-------|
| GCloud Production Project | `$GCP_PROJECT` |
| GCloud Staging Project | `$GCP_STAGING_PROJECT` |
| Sentry Org | `$SENTRY_ORG` |
| Sentry Region | `$SENTRY_REGION_URL` (default `https://us.sentry.io`) |
| Sentry Projects | `$SENTRY_PROJECTS` |
| PostHog Project | `$POSTHOG_PROJECT_ID` |
| Production URL | `$APP_URL` |
| Admin URL | `$ADMIN_URL` |
| API Domain | `$API_URL` |
| GitHub Issues Repo | `$GITHUB_REPO` |
| Vercel Projects | `$VERCEL_PROJECTS` |
| RCA Docs Directory | `$RCA_DOCS_DIR` (default `docs/rca/`) |
| RCA Template | `${CLAUDE_PLUGIN_ROOT}/skills/rca/references/rca-template.md` |
| Routing table | `$RCA_DOCS_DIR/routing-table.md` (from `${CLAUDE_PLUGIN_ROOT}/skills/rca/references/routing-table.example.md`) |
| Alert inventory | `$RCA_DOCS_DIR/alerts.md` (from `${CLAUDE_PLUGIN_ROOT}/skills/rca/references/alerts.example.md`) |

### Backend Services

Example rows — replace with your own services. The request host tells you which service to query in Step 6.

| Service | Domain | Handles |
|---------|--------|---------|
| `api` | `$API_URL` | The endpoints the customer app at `$APP_URL` calls |
| `admin-api` | `$ADMIN_URL` | Admin console backend |
