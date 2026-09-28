---
name: rca
description: Root Cause Analysis for production issues. Investigates data mismatches, blank pages, missing data, API latency, page load issues, waterfall problems using Sentry, PostHog, GCloud logs, Vercel, Firebase, and GitHub issues, and writes a markdown RCA document. Triggers on "investigate issue", "root cause", "debug production", "why is this broken", "blank page", "data mismatch", "slow page", "api latency".
---

# RCA — Root Cause Analysis

Systematic investigation of production issues using the full observability stack: PostHog, Sentry, GCloud Logs, Vercel, Firebase Auth, and GitHub issues, with the findings written into a markdown RCA document in the repository. Use this when a user reports a problem — blank data, missing graphs, slow pages, data mismatches, API failures, etc.

## Configuration

This skill reads the environment variables below. Set them in your shell profile or in the project's `.claude/settings.json` `env` block. Steps that depend on an unset optional variable are skipped and noted in the RCA doc.

| Variable | Meaning | Default |
|----------|---------|---------|
| `GCP_PROJECT` | GCP project id that hosts the production backend (Cloud Run, Cloud Logging). Used in every `gcloud logging read` and every console link. | required |
| `GCP_STAGING_PROJECT` | GCP project id for staging; used only when the report concerns staging. | unset (production only) |
| `SENTRY_ORG` | Sentry organization slug. | required for Step 4 |
| `SENTRY_REGION_URL` | Sentry API base URL for the org's region. | `https://us.sentry.io` |
| `SENTRY_PROJECTS` | Comma-separated Sentry project slugs to search. | unset (search the whole org) |
| `SENTRY_AUTH_TOKEN` | Sentry API token with alert-rule read access, used by the alert check in Step 4. A secret: never paste it into the RCA doc. | required for the alert check |
| `GITHUB_REPO` | `owner/name` of the repository where RCA issues are filed and RCA docs are committed. | required |
| `POSTHOG_PROJECT_ID` | PostHog project id used to build session-replay links (Step 11). | unset (omit replay links) |
| `APP_URL` | Customer-facing app host, e.g. `https://app.example.com`. | unset |
| `ADMIN_URL` | Admin console host. | unset |
| `API_URL` | Primary API host the app calls. | unset |
| `VERCEL_PROJECTS` | Comma-separated Vercel project names to check for deployments (Step 7). | unset (skip Step 7, or use your own deploy tool) |
| `RCA_DOCS_DIR` | Directory, relative to the repo root, where RCA markdown documents are written. | `docs/rca/` |

## References

Two files are yours to fill in. They live in your repository under
`$RCA_DOCS_DIR` (default `docs/rca/`), next to the RCA documents, never inside
the installed plugin: the plugin directory is a versioned cache that
`claude plugin update` and reinstall replace, so anything written under
`${CLAUDE_PLUGIN_ROOT}` is lost. Copy the shipped `*.example.md` templates and
edit the copies.

- For automated frontend-facing backend 5xx sweeps, load
  `$RCA_DOCS_DIR/routing-table.md` (your filled-in copy; not shipped)
  before assigning an owner or posting to chat. Create it from
  [`references/routing-table.example.md`](references/routing-table.example.md)
  (`${CLAUDE_PLUGIN_ROOT}/skills/rca/references/routing-table.example.md`):
  it holds the product-channel map, shared-service path overrides, and the
  evidence bar for naming a regression owner.
- Keep your Sentry alert inventory in `$RCA_DOCS_DIR/alerts.md`, created from
  [`references/alerts.example.md`](references/alerts.example.md)
  (`${CLAUDE_PLUGIN_ROOT}/skills/rca/references/alerts.example.md`). Step 4
  reads it. If either file is missing, say so in the RCA doc and continue with
  the live sources.

## RCA Template & Documentation

Every RCA is a markdown document written from the bundled template
[`references/rca-template.md`](references/rca-template.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/rca/references/rca-template.md`), which follows
[Google SRE Postmortems](https://sre.google/sre-book/example-postmortem/) and
[PagerDuty Incident Response](https://response.pagerduty.com/after/post_mortem_template/).

- **Location:** `$RCA_DOCS_DIR/RCA-<YYYY-MM-DD>-<slug>.md` inside the repository named by `$GITHUB_REPO` (default `docs/rca/`). Create the directory if it does not exist.
- **Lifecycle:** the file is created in Step 0 as a live investigation log, updated after every step, and finalized in Step 13. Commit it on a branch and link it from the GitHub issue.
- **One record:** the markdown file is the single RCA record. The GitHub issue tracks status and links to the file; do not maintain a second copy in another tool.

### Link Requirements — Time-Scoped & Filter-Specific

**CRITICAL:** All observability links in the RCA doc MUST be **time-scoped and filter-specific**. Generic dashboard links are NOT acceptable — they require manual filtering to find the relevant data.

**Every link must include:**
- **Time range** scoped to the incident window (not "last 7 days" or "all time")
- **Filters applied** (service name, endpoint, HTTP method, status code, etc.)
- **Specific resource** (trace ID, span ID, alert ID, revision name)

**GCloud Logs Explorer URL pattern:**
```
https://console.cloud.google.com/logs/query;query=<URL-encoded-query>;cursorTimestamp=<specific-log-timestamp>;startTime=<window-start>;endTime=<window-end>?project=$GCP_PROJECT
```
- `;startTime=` and `;endTime=` — define the visible time window (semicolon-separated, NOT `timeRange`)
- `;cursorTimestamp=` — highlights a specific log entry within the window
- `?project=` — always at the end after the query string separator

**GCloud Metrics URL pattern (time-scoped):**
```
https://console.cloud.google.com/run/detail/<region>/<service>/observability/metrics;startTime=<ISO>;endTime=<ISO>?project=$GCP_PROJECT
```

**Sentry Trace URL pattern (with full filters):**
```
https://$SENTRY_ORG.sentry.io/explore/traces/trace/<trace_id>/?end=<ISO>&fov=<start>%2C<duration>&node=span-<span_id>&pageEnd=<ISO>&pageStart=<ISO>&project=-1&query=trace%3A<trace_id>&source=traces&start=<ISO>&tab=waterfall&targetId=<root_span_id>&timestamp=<unix_epoch>
```
- Include ALL filter params from the Sentry URL bar — `end`, `start`, `pageStart`, `pageEnd`, `fov`, `query`, `source`, `targetId`, `timestamp`
- `node=span-<id>` — highlights the bottleneck span
- `fov=0%2C<duration>` — field of view covering the full trace

**Examples of BAD vs GOOD links:**

| BAD (generic — requires manual filtering) | GOOD (specific — opens directly to evidence) |
|-------------------------------------------|----------------------------------------------|
| `cloud.google.com/.../metrics` | `cloud.google.com/.../metrics;startTime=2026-03-09T00:00:00.000Z;endTime=2026-03-11T12:00:00.000Z` |
| `cloud.google.com/logs/query;query=...;timeRange=start%2Fend` | `cloud.google.com/logs/query;query=...;cursorTimestamp=2026-03-11T02:36:52Z;startTime=2026-03-11T02:36:00Z;endTime=2026-03-11T02:37:30Z` |
| `sentry.io/explore/traces/trace/<id>/` | `sentry.io/explore/traces/trace/<id>/?end=...&fov=...&node=span-<id>&pageStart=...&pageEnd=...&query=trace%3A<id>&source=traces&start=...&tab=waterfall&targetId=<root>&timestamp=<epoch>` |

> **IMPORTANT:** Never use `;timeRange=start%2Fend` for GCloud Logs — it does NOT apply filters correctly. Always use `;startTime=...;endTime=...` as separate parameters.

## Core Concept: Traceparent Correlation

The **traceparent** (or `trace_id`) is the single thread that ties the entire request lifecycle together across ALL systems:

```
 Browser                PostHog               GCloud Logs            Sentry           Datadog
    │                      │                      │                    │                 │
    │ generates trace_id   │                      │                    │                 │
    ├─── API call ────────►│ API_latency event    │                    │                 │
    │    (traceparent      │ (trace_id,           │                    │                 │
    │     header)          │  endpoint,           │                    │                 │
    │         │            │  status, latency)    │                    │                 │
    │         │            │                      │                    │                 │
    │         └───────────────────────────────────►│ HTTP request log  │                 │
    │                      │                      │ (trace, status,   │                 │
    │                      │                      │  responseSize)    │                 │
    │                      │                      │        │          │                 │
    │                      │                      │        ▼          │                 │
    │                      │                      │ App log           │                 │
    │                      │                      │ (request_id =     │                 │
    │                      │                      │  trace_id,        │                 │
    │                      │                      │  request body,    │                 │
    │                      │                      │  dates, filters)  │                 │
    │                      │                      │        │          │                 │
    │                      │                      │        └─────────►│ Error event     │
    │                      │                      │                   │ (if exception)  │
    │                      │                      │        │          │                 │
    │                      │                      │        └──────────────────────────►│
    │                      │                      │                   │  dd.trace_id    │
    │                      │                      │                   │  (full APM      │
    │                      │                      │                   │   waterfall)    │
```

**How it flows:**
1. Frontend generates a `trace_id` when making API calls and sends it as `traceparent` header
2. PostHog captures it in `API_latency` events as `properties.trace_id`
3. GCloud HTTP logs capture it as `trace` field
4. GCloud app logs capture it as `jsonPayload.dict_object.request_id` (or whichever field your request logger uses — adapt the queries below)
5. Sentry captures it if an error occurs on the same trace
6. If your services also emit Datadog trace ids, Datadog captures it as `dd.trace_id` for full distributed tracing (DB queries, cache, microservice hops); skip the Datadog column otherwise

**One page load = one trace_id = ALL API calls from that load.** Find it in PostHog first, then follow it everywhere.

## Input Required

Ask the user for (if not already provided):
1. **User email** — who experienced the issue
2. **Page/URL** — where the issue occurred (e.g., `/reports/trends`)
3. **Description** — what they saw (blank graph, wrong data, slow load, error)
4. **Time window** — when it happened (default: last 24 hours)
5. **Screenshot** — if available, analyze it to understand what loaded vs what didn't

## Investigation Workflow

Execute steps IN ORDER. Run independent queries in PARALLEL where possible.

**IMPORTANT:** Before starting any investigation, create a GitHub issue and the RCA document to track findings live. This is NOT optional.

---

### Step 0: Create GitHub Issue + RCA Document

Before investigating, create a GitHub issue and an **RCA markdown document** to track the full RCA lifecycle. The document serves as a live investigation log and the final RCA report.

**A) Create the GitHub issue:**

Use the `gh` CLI:
```bash
gh issue create --repo "$GITHUB_REPO" \
  --title "[RCA] <short description of the issue>" \
  --label "rca,incident,area:frontend" \
  --body "<brief issue report: reporter, affected user, page, time, description>"
```
- **Title:** `[RCA] <short description of the issue>` (e.g., `[RCA] Blank trends graph for one organization's users`)
- **Labels:** Pick severity (`sev-1`/`sev-2`/`sev-3`/`sev-4`), area (`area:frontend`/`area:admin`/`area:ui`), and `rca`/`incident`. Create any label that does not exist yet with `gh label create`.
- **Body:** Brief issue report with reporter, affected user, page, time, description
- Capture the issue number (`#NNN`) from the URL returned for use throughout the workflow

**B) Create the RCA document:**

Write the document from the bundled template. Do not write it from memory:
1. Read `${CLAUDE_PLUGIN_ROOT}/skills/rca/references/rca-template.md` in full — every section, every table column, every placeholder format
2. Copy it to `$RCA_DOCS_DIR/RCA-<YYYY-MM-DD>-<slug>.md` (default `docs/rca/`; create the directory if missing). Use the incident date, and a short kebab-case slug from the issue title
3. Replicate the EXACT structure, replacing `[placeholder]` values with real data as it arrives; leave placeholders you cannot fill yet rather than deleting them
4. Keep all screenshot placeholders (`[Screenshot placeholder: ...]`)
5. Keep all observability URL rows in the Evidence Links table (GCloud, Sentry, PostHog, deployment, GitHub) — fill with time-scoped, filter-specific links

The template sections (ALL mandatory — do not skip or summarize):

1. **Metadata** — RCA ID, title, incident date, RCA date, severity (SEV-1/2/3/4), status, GitHub issue, incident commander, investigator, backend/frontend owners, reviewer; severity matrix
2. **Summary** — 2-3 sentences (write LAST)
3. **Customer Impact** — Quantified metrics: duration, users, organizations, pages, revenue impact, data loss, SLA breach, support tickets; user-experience paragraph; screenshot placeholder
4. **Timeline** — All events in UTC with a second column in the reporter's local timezone, and a source column of clickable links
5. **Detection** — How detected, TTD, who, existing alerts covering the path, alerting gap
6. **Root Cause** — What happened, **5 Whys analysis**, trigger vs root cause, category
7. **Contributing Factors** — What made it more likely, wider, or longer
8. **Resolution** — Mitigation, fix (PR + deploy time), verification, rollback plan
9. **Action Items** — Table with: action, type (Prevent/Mitigate/Detect/Process), owner, GitHub issue, priority, due date, status
10. **Evidence Links** — Dashboard URLs (mandatory), key log snippets, trace waterfall, infrastructure state

Sections 11 (Lessons Learned) and 12 (Sign-off) are optional; fill them for SEV-1 and SEV-2.

**Severity Matrix:**

| Level | Criteria | RCA Due |
|-------|----------|---------|
| **SEV-1** | Revenue-impacting outage, data loss, security breach, >50% users | 24 hours |
| **SEV-2** | Major feature degradation, >10% users, SLA breach | 3 business days |
| **SEV-3** | Minor feature degradation, performance regression, <10% users | 5 business days |
| **SEV-4** | Cosmetic issue, intermittent bug, single-user impact | 10 business days |

**C) Link the RCA doc from the GitHub issue:**

Use `gh issue comment` to post the RCA document path onto the GitHub issue so humans scanning the issue can jump straight to the live investigation log. Once the doc is pushed on a branch, replace the path with the blob URL (and later the PR link):
```bash
gh issue comment <number> --repo "$GITHUB_REPO" \
  --body "RCA doc: \`$RCA_DOCS_DIR/RCA-<YYYY-MM-DD>-<slug>.md\` (branch: <branch>)"
```

**After creating both**, note the GitHub issue number and the RCA doc path. As you complete EACH step below, update the **RCA document** with findings (edit the file in place). This creates a real-time audit trail. The markdown file remains the single RCA record — there is no separate ticket-tool document.

---

### Step 1: Identify the User in PostHog

Find the user's PostHog person record. The email property is `properties.email` (lowercase):

```sql
SELECT id, properties.email, properties
FROM persons
WHERE properties.email ILIKE '%<user_email_domain>%'
LIMIT 5
```

Note the exact email value for subsequent queries.

**→ Update RCA doc:** Record the Person ID and email property in the Timeline source notes and under Evidence Links (PostHog events).

---

### Step 2: Gather Events + Trace IDs from PostHog (PARALLEL with Steps 3, 4, 5)

Get all events for the user on the affected page. **The trace_id is the most critical field** — it's the key to unlock backend logs.

```sql
SELECT
    event,
    timestamp,
    properties.trace_id AS trace_id,
    properties.endpoint AS endpoint,
    properties.status_code AS status_code,
    properties.latency_ms AS latency_ms,
    properties.$current_url AS current_url
FROM events
WHERE
    event = 'API_latency'
    AND person.properties.email = '<email>'
    AND properties.$current_url LIKE '%<page_path>%'
    AND timestamp >= now() - INTERVAL <time_window>
ORDER BY timestamp DESC
LIMIT 50
```

From this, extract:
- **Trace IDs** — MOST IMPORTANT: group API calls by trace_id to identify distinct page loads/sessions. Each page load generates one trace_id shared across all API calls from that load
- **API calls made** — which endpoints were hit per trace
- **Status codes** — any non-200 responses
- **Latency** — any slow calls (>3s)
- **Session timeline** — multiple trace_ids = user loaded the page multiple times (possibly with different filters each time)

**→ Update RCA doc:** Add a per-trace table (trace_id, timestamp, APIs, statuses, latency) under Evidence Links, and the page loads as Timeline rows.

---

### Step 3: Check for Exceptions in PostHog (PARALLEL with Steps 2, 4, 5)

```sql
SELECT event, timestamp, properties.$current_url,
       properties.$exception_message, properties.$exception_type
FROM events
WHERE
    person.properties.email = '<email>'
    AND timestamp >= now() - INTERVAL <time_window>
    AND (event = '$exception' OR properties.$exception_message IS NOT NULL)
ORDER BY timestamp DESC
LIMIT 20
```

**→ Update RCA doc:** Record exceptions (or "No exceptions found") under Evidence Links.

---

### Step 4: Check Sentry for Errors AND Alerts (PARALLEL with Steps 2, 3, 5)

**A) Check for errors:**

Use Sentry MCP tools:
1. `search_events` — search for errors from the user's email in the time window
2. `search_events` — search for errors on the affected URL/page in the time window
3. If issues found, use `get_issue_details` or `analyze_issue_with_seer` for deep analysis
4. `get_trace_details` — if a trace ID is provided, get the full trace waterfall

Organization slug: `$SENTRY_ORG`, Region URL: `$SENTRY_REGION_URL`. Scope searches to `$SENTRY_PROJECTS` when set.

**B) Check existing Sentry alerts:**

ALWAYS check if alerts already exist for the affected endpoint/page. Never claim "no alerting exists" without verifying first. Check `$RCA_DOCS_DIR/alerts.md` (your copy of `${CLAUDE_PLUGIN_ROOT}/skills/rca/references/alerts.example.md`) and then the live API:

```bash
: "${SENTRY_AUTH_TOKEN:?export a Sentry API token with alert-rule read access}"
curl -s -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  "${SENTRY_REGION_URL:-https://us.sentry.io}/api/0/organizations/${SENTRY_ORG}/alert-rules/" \
  | python3 -c "
import json, sys
rules = json.load(sys.stdin)
for r in rules:
    print(f'ID: {r.get(\"id\",\"\")} | Name: {r.get(\"name\",\"\")} | Triggers: {[(t.get(\"label\",\"\"), t.get(\"alertThreshold\",\"\")) for t in r.get(\"triggers\",[])]}')
"
```

For any matching alert, get full details:
```bash
curl -s -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  "${SENTRY_REGION_URL:-https://us.sentry.io}/api/0/organizations/${SENTRY_ORG}/alert-rules/" \
  | python3 -c "
import json, sys
rules = json.load(sys.stdin)
for r in rules:
    if '<keyword>' in r.get('name', '').lower() or '<keyword>' in r.get('query', '').lower():
        print(json.dumps(r, indent=2))
"
```

If the live list differs from `$RCA_DOCS_DIR/alerts.md`, update that file as part of this RCA (see Self-Healing).

**→ Update RCA doc:** Record Sentry issue links (or "No Sentry errors found") under Evidence Links. Document any existing alerts in the Detection section — never claim alerting is missing without checking first.

---

### Step 5: Check PostHog Feature Flags & Experiments (PARALLEL with Steps 2, 3, 4)

The user might be in an A/B test or feature flag that changes page behavior.

Use PostHog MCP tools:
1. `feature-flag-get-all` — list all active feature flags
2. `experiment-get-all` — list all running experiments

Cross-reference with the user's properties from Step 1. Check if any flag targets their email, company, or cohort. Also check the PostHog events for `$feature_flag_called` events for this user:

```sql
SELECT event, timestamp, properties.$feature_flag, properties.$feature_flag_response
FROM events
WHERE
    person.properties.email = '<email>'
    AND event = '$feature_flag_called'
    AND timestamp >= now() - INTERVAL <time_window>
ORDER BY timestamp DESC
LIMIT 20
```

**→ Update RCA doc:** Record active flags/experiments affecting the user (or "No relevant flags") under Contributing Factors and in the Infrastructure state table.

---

### Step 6: Correlate with GCloud Logs using Traceparent / Trace ID

This is the **most critical step**. The `trace_id` from PostHog is the same traceparent that flows through the entire backend. Use it to pull the exact request body and response metadata.

**For EACH distinct trace_id found in Step 2**, run these queries:

> **GCP Project ID:** Use `$GCP_PROJECT` for production, `$GCP_STAGING_PROJECT` for staging (see Infrastructure Reference table).

```bash
# 1. HTTP-level logs — gives you response size, status, latency for ALL APIs in this page load
gcloud logging read \
  'resource.type="cloud_run_revision" AND trace="projects/'"$GCP_PROJECT"'/traces/<trace_id>"' \
  --limit=50 --format="json" --project="$GCP_PROJECT"
```

Parse with:
```bash
| python3 -c "
import json, sys
logs = json.load(sys.stdin)
for log in logs:
    ts = log.get('timestamp', '')
    http = log.get('httpRequest', {})
    if http:
        print(f'[{ts}] {http.get(\"requestMethod\",\"\")} {http.get(\"requestUrl\",\"\")} -> {http.get(\"status\",\"\")} (size: {http.get(\"responseSize\",\"\")}, latency: {http.get(\"latency\",\"\")})')
"
```

```bash
# 2. Application-level logs — gives you the ACTUAL request body (date range, filters, granularity)
# <api_service> is the Cloud Run service that serves $API_URL. The message and request_id
# field names below are one common request-logger shape; adapt them to yours.
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="<api_service>" AND jsonPayload.message="Request/response log" AND jsonPayload.dict_object.request_id="<trace_id>"' \
  --limit=20 --format="json" --project="$GCP_PROJECT"
```

Parse with:
```bash
| python3 -c "
import json, sys
logs = json.load(sys.stdin)
for log in logs:
    ts = log.get('timestamp', '')
    d = log.get('jsonPayload', {}).get('dict_object', {})
    req = d.get('request', {})
    print(f'[{ts}] {d.get(\"request_url\", \"\")} | latency={d.get(\"latency\", \"\")}s')
    print(f'  body: {req.get(\"body\", \"\")}')
    print()
"
```

From GCloud logs, extract:
- **Request body** — date range, granularity, entity filters (store, platform, account, region), and any server-side date-adjustment flag
- **Response size** — small response = sparse/empty data (e.g., a summary endpoint returning < 1KB means very few datewise entries)
- **Latency** — backend processing time per endpoint
- **Any error logs** — exceptions, warnings around the same timestamp

**If multiple trace_ids exist**, compare the request bodies across traces to see if the user changed filters/dates between page loads — this often reveals the root cause.

**→ Update RCA doc:** Add a per-trace backend table (endpoint, request body: dates, filters, granularity; response size; latency) under Evidence Links, and paste the critical lines into Key Log Snippets.

#### Check Other Backend Services

The trace may span multiple services. Also search logs from other services:

```bash
# Check ALL services for this trace (not just the primary API service)
gcloud logging read \
  'resource.type="cloud_run_revision" AND trace="projects/'"$GCP_PROJECT"'/traces/<trace_id>" AND NOT logName=~"requests$"' \
  --limit=50 --format="json" --project="$GCP_PROJECT"
```

Known backend services (example — replace with your own; the host tells you which service served a request):
| Service | Domain | Purpose |
|---------|--------|---------|
| `api` | `$API_URL` | Main API — the endpoints the customer app calls |
| `admin-api` | `$ADMIN_URL` | Admin console backend |

#### Datadog Trace (if deeper investigation needed)

If your services also emit Datadog trace ids (`dd.trace_id` and `dd.span_id` in `jsonPayload` of the GCloud app logs), the same value opens the full distributed trace in Datadog APM, showing every microservice hop, DB query, and cache call. Skip this section otherwise; no configuration is needed.

---

### Step 7: Check Vercel Deployments

Was there a recent deployment that could have caused the issue? Check if a deploy happened right before or during the reported time.

Use Vercel MCP tools:
1. `list_deployments` — check recent deployments and their timestamps
2. `get_deployment` — get details of a specific deployment
3. `get_deployment_build_logs` — check for build warnings/errors
4. `get_runtime_logs` — check for server-side/edge function errors

Check each project listed in `$VERCEL_PROJECTS` (comma-separated), for example the project serving `$APP_URL` and the one serving `$ADMIN_URL`. If `$VERCEL_PROJECTS` is unset, or the frontend is hosted elsewhere, use that host's deployment history instead and record the tool used in the RCA doc.

If a deploy happened close to the issue time, proceed to Step 8 to check what changed.

---

### Step 8: Check GitHub for Deployment Changes (if Step 7 found a recent deploy)

If a deployment was identified near the issue time, check what code was deployed using both `git` and `gh` CLIs:

```bash
# Check recent commits on main around the issue time
git log --oneline --since="<issue_time_minus_2h>" --until="<issue_time>" --first-parent origin/main

# See what files changed in last N commits on main
git log --oneline --name-only -10 origin/main

# Check if a specific file/page was modified recently
git log --oneline --since="2 days ago" -- "<path/to/affected/page>"

# Diff between two commits to see exact changes
git diff <older_sha>..<newer_sha> -- "<path/to/frontend/src>"

# Check the PR that was merged (via GitHub CLI)
gh pr list --repo "$GITHUB_REPO" --state merged --base main --limit 10

# View a specific PR's changes
gh pr view <pr_number> --repo "$GITHUB_REPO"
gh pr diff <pr_number> --repo "$GITHUB_REPO"

# Check what files changed in recent commits via GitHub API
gh api "repos/$GITHUB_REPO/commits" --jq '.[0:5] | .[] | {sha: .sha[0:8], message: .commit.message, date: .commit.committer.date}'
```

Also check:
- **GitHub Actions** — any failed CI/CD runs: `gh run list --repo "$GITHUB_REPO" --limit 10`
- **Release tags** — `gh release list --repo "$GITHUB_REPO" --limit 5`
- **Blame** — who last touched the affected file: `git blame <file_path>`
- **Branch protection** — was a force push or bypass done?

If the deployment contained changes to the affected page/component, that's a strong signal for root cause.

**→ Update RCA doc:** Add deployment timestamps, commit SHAs, PR links, and relevant file changes to the Timeline and to the Deployment and GitHub rows of Evidence Links.

---

### Step 9: Check Firebase Auth (if auth-related suspicion)

If the issue might be auth-related (silent 401s, empty data due to expired tokens, permission issues):

Use Firebase MCP tools:
1. `auth_get_users` — look up the user by email to check:
   - Last sign-in time
   - Account disabled status
   - Provider data
   - Token validity

```
Look up user: user@example.com
Check: disabled, lastSignInTime, tokensValidAfterTime
```

Signs of auth issues:
- User's `lastSignInTime` is very old → stale token
- `disabled: true` → account deactivated
- API returning 200 with empty data → backend might silently return empty when token is invalid for certain endpoints

If your app uses a different identity provider, run the equivalent lookup there.

**→ Update RCA doc:** Record last sign-in time, account status, and token validity (or "Auth verified — no issues") in the Infrastructure state table.

---

### Step 10: Check GitHub Issues for Known Issues

Before concluding, check if there's already a known issue or ongoing incident:

```bash
# Search open issues for keywords related to the affected page, API endpoint, or error type
gh issue list --repo "$GITHUB_REPO" --state open \
  --search "<page name OR endpoint OR error type>" \
  --json number,title,author,assignees,labels,state,url,updatedAt --limit 50

# Also search recently closed issues in case a fix shipped but regressed
gh issue list --repo "$GITHUB_REPO" --state closed \
  --search "<keyword> updated:>=$(date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d)" \
  --json number,title,url,updatedAt --limit 20

# Search prior RCA documents for the same page, endpoint, or error
grep -ril "<keyword>" "${RCA_DOCS_DIR:-docs/rca/}"
```

This avoids duplicate investigation and may provide context from previous occurrences.

**→ Update RCA doc:** If known issues or prior RCAs are found, add links and context under Contributing Factors. Otherwise note "No existing related tickets found".

---

### Step 11: Check PostHog Session Recordings (visual confirmation)

PostHog captures session recordings. Link to the user's session for visual proof of what they experienced:

```sql
SELECT
    properties.$session_id AS session_id,
    min(timestamp) AS session_start,
    max(timestamp) AS session_end,
    count(*) AS event_count
FROM events
WHERE
    person.properties.email = '<email>'
    AND timestamp >= now() - INTERVAL <time_window>
GROUP BY properties.$session_id
ORDER BY session_start DESC
LIMIT 5
```

The session_id can be used to find the recording in PostHog UI:
`https://us.posthog.com/project/$POSTHOG_PROJECT_ID/replay/<session_id>` (use your PostHog region's host if it is not `us.posthog.com`)

Session recordings show the EXACT user experience — what loaded, what didn't, where they clicked, and any visual glitches.

**→ Update RCA doc:** Fill the PostHog session replay row of Evidence Links with session_id, recording link, and key observations from the recording.

---

### Step 12: Check Frontend Code (if needed)

If the API returned valid data but the UI still showed wrong output:
1. Find the page component that renders the affected area
2. Trace the data flow: API response → state → component → chart/table
3. Look for missing empty-state handling, data transformation bugs, or rendering conditions

**→ Update RCA doc:** Add code file paths, data flow notes, and any rendering bugs found under Root Cause or Contributing Factors.

---

### Step 13: Finalize RCA Report — RCA Doc + GitHub Issue

**A) Finalize the RCA document:**

Rewrite the RCA markdown file in full so that every section is complete.

> **CRITICAL:** Before writing the final doc, re-read the template at `${CLAUDE_PLUGIN_ROOT}/skills/rca/references/rca-template.md`. Match its structure EXACTLY — every section, every table column, every placeholder format, every screenshot placeholder. Do NOT summarize or skip sections. The template is the source of truth.

Every section must be populated:

1. **Metadata** — RCA ID (`RCA-YYYY-MM-DD-NNN`), title, date of incident, date of RCA, severity, status, GitHub issue link (`$GITHUB_REPO#NNN`), incident commander, investigator, backend/frontend owners, reviewer. Include severity matrix table.
2. **Summary** — Write LAST, 2-3 sentences for non-technical stakeholders
3. **Customer Impact** — Quantified metrics table (duration, users, orgs, pages, revenue, data loss, SLA, support tickets) + user experience description + `[Screenshot placeholder: ...]`
4. **Timeline** — Table with ALL events in UTC and the local-time column, with a **source** column containing clickable hyperlinks to GCloud Logs, Sentry, PostHog, etc.
5. **Detection** — Table (how detected, TTD, who, existing alerts, alerting gap) + warning callout if customer-reported
6. **Root Cause** — What happened, **5 Whys** (formatted as chain), trigger vs root cause table, category table
7. **Contributing Factors** — Bullet list; include what went well and where we got lucky if relevant
8. **Resolution** — Mitigation, fix PR + deploy time, verification links, rollback plan
9. **Action Items** — Table with columns: #, Action, Type (Prevent/Mitigate/Detect/Process), Owner, Issue (GitHub link `$GITHUB_REPO#NNN`), Priority, Due Date, Status (TODO). Include the action item types reference line.
10. **Evidence Links** — MANDATORY sections:
   - **Dashboard URLs table** — GCloud (HTTP logs, app logs, metrics), Sentry (trace/issue, alerts), PostHog (events, session replay), deployment, GitHub (issue, PRs). ALL must be clickable, time-scoped, filter-specific links. No generic links.
   - **Key Log Snippets** — code blocks with critical log lines
   - **Trace Waterfall** — `[Screenshot placeholder: ...]` + table with span/duration/description
   - **Infrastructure State** — table with service config values
11. **Lessons Learned** (optional; required for SEV-1/2) — What went well, what went wrong, where we got lucky
12. **Sign-off** (optional; required for SEV-1/2) — Table with Role, Name, Date, Approved. Include the post-RCA checklist.

> **IMPORTANT**: The Evidence Links table must ALWAYS be populated with clickable, time-scoped, filter-specific links. Screenshot placeholders must be marked with `[Screenshot placeholder: ...]` for manual insertion. No generic dashboard links — every URL must open directly to the relevant evidence.

Commit the finalized document on a branch and open a PR against `$GITHUB_REPO` (use `/git` if it is installed); reference the RCA issue in the PR body.

**B) Update the GitHub issue:**

Use the `gh` CLI:
1. Add a **comment** with a one-paragraph RCA summary linking to the RCA document (blob URL on the branch, or the PR):
   ```bash
   gh issue comment <number> --repo "$GITHUB_REPO" \
     --body "RCA summary: <one paragraph>. Full RCA: <rca-doc-url>"
   ```
2. Update issue **state** based on outcome:
   - If bug found → keep open, assign (`gh issue edit <number> --repo "$GITHUB_REPO" --add-assignee <github-handle>`), add area label
   - If user config / expected behavior → close with explanation (`gh issue close <number> --repo "$GITHUB_REPO" --comment "Closing as expected behavior: ..."`)
   - If needs follow-up → keep open, add follow-up task-list checkboxes via `gh issue edit <number> --repo "$GITHUB_REPO" --body-file ...`
3. Add relevant **labels** based on category (`gh issue edit <number> --repo "$GITHUB_REPO" --add-label "<category>"`)

**C) Present summary to user:**

| Section | Content |
|---------|---------|
| **RCA Doc** | Path (and URL) of the RCA markdown document |
| **GitHub Issue** | `$GITHUB_REPO#NNN` |
| **Severity** | SEV-1/2/3/4 with justification |
| **Root cause** | Clear explanation of WHY the issue occurred |
| **Category** | See categories below |
| **Key evidence** | Most critical log snippets or trace data |
| **Action items** | Summary of top recommendations |
| **Existing alerts** | Any Sentry alerts that cover this endpoint |

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

## Tips

### Traceparent is King
- The `trace_id` in PostHog = `trace` in GCloud HTTP logs = `request_id` in GCloud app logs (= `dd.trace_id` in Datadog, if you run it) — SAME value everywhere
- One page load = one trace_id shared by ALL API calls from that page load
- Multiple trace_ids for the same page = user loaded it multiple times (compare request bodies to spot filter changes)
- Always extract trace_ids FIRST from PostHog, then follow them through GCloud, Sentry, and Datadog

### Maximize Parallelism
- Steps 2, 3, 4, 5 can ALL run in parallel — they query different systems
- For each trace_id, run GCloud HTTP logs and app logs queries in parallel
- Run the deployment check in parallel with GCloud log queries

### PostHog
- Email property is `properties.email` (lowercase) on persons table
- `API_latency` events contain: `trace_id`, `endpoint`, `status_code`, `latency_ms`
- Session recordings provide visual proof — always try to find the session_id

### GCloud Logs
- Response size in HTTP logs is a quick diagnostic: small response (< 1KB for summary APIs) = sparse/empty data
- App logs at `jsonPayload.message="Request/response log"` (or your logger's equivalent) contain the full request body with dates, filters, granularity
- If the backend can adjust the requested date range server-side, note that flag in the request body — the actual range may differ from what was sent
- Use `jsonPayload.dict_object.request_id` (or your logger's field) to match by trace_id in app logs
- Check multiple services — a trace may span the main API, an admin backend, and workers

### Deployments + GitHub
- Check deployments FIRST if the issue started suddenly for multiple users
- Use `gh pr diff` to see exactly what code changed in a suspicious deployment
- Compare the deployment timestamp with the issue report timestamp

### General
- Check ALL sessions if user visited the page multiple times — the issue may be in an earlier session with different filters
- When the user provides a screenshot, analyze what DID load (summary cards, filters) vs what DIDN'T (charts, tables) to narrow the investigation
- Compare response sizes across APIs in the same trace — if one is much smaller, that's likely the broken one
- If the issue is intermittent, check for feature flags that might be toggling behavior

---

## Self-Healing

**After every `/rca` execution**, run this phase to keep the skill accurate and discoverable.

### Evaluate Skill Accuracy

Re-read this skill file (`Read` tool on `${CLAUDE_PLUGIN_ROOT}/skills/rca/SKILL.md`) and compare its instructions against what actually happened during this execution:

| Check | What to look for |
|-------|-----------------|
| **HogQL queries** | Did any PostHog SQL query fail due to changed column names, table names, or syntax? |
| **MCP tool names** | Did any `mcp__sentry__*`, `mcp__posthog__*`, or `mcp__firebase__*` calls fail? |
| **gh CLI** | Did any `gh issue create/view/list/comment/edit/close` calls fail due to wrong flags, changed JSON shapes, or label names that don't exist in `$GITHUB_REPO`? |
| **GCloud commands** | Did any `gcloud logging read` commands fail due to wrong project IDs, filter syntax, or field names? |
| **Service names** | Are the backend service names and log field names in Step 6 still accurate for your stack? |
| **Configuration** | Did any of the environment variables in the Configuration section turn out to be missing or stale? |
| **Trace correlation** | Did the traceparent flow (PostHog → GCloud → Sentry → Datadog) work as documented? |
| **New tools** | Were any new observability tools or MCP servers used that aren't documented here? |
| **RCA doc** | Did the template copy and per-step updates work? Is `$RCA_DOCS_DIR` still the right location? |
| **Sentry alerts** | Were existing alerts verified before claiming "no alerting"? Is `$RCA_DOCS_DIR/alerts.md` up to date with the live alert list? |

### Fix Issues Found

This skill ships inside a plugin, so the installed copy is overwritten on every plugin update. If discrepancies were found:
1. Record them in the console output under `Self-Healing Log` (see below)
2. `$RCA_DOCS_DIR/alerts.md` and `$RCA_DOCS_DIR/routing-table.md` are your own files: fix them with the `Edit` tool
3. If the repo keeps a local override of this skill (`.claude/skills/rca/SKILL.md`), apply skill fixes there with the `Edit` tool (Configuration table, HogQL column/table names, service names) — keep changes minimal and targeted
4. Otherwise, print the proposed change and open an issue or PR against the plugin repository
5. Log each fix:

   ```
   Self-Healing Log:
   - Fixed: <what was wrong> → <what it was changed to>
   - Reason: <why the original was inaccurate>
   ```

If nothing needs fixing, skip silently.

### Append Trigger Documentation

After execution, append a skill attribution footer to:

**RCA document** (add to the finalized document in Step 13):
```markdown
---
*Investigated by [`/rca`](https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/oncall/skills/rca/SKILL.md) — Triggers: "investigate issue", "root cause", "debug production", "why is this broken", "blank page", "data mismatch", "slow page", "api latency"*
```

**GitHub issue comment** (add to the RCA summary comment in Step 13):
```markdown
---
*Investigated by [`/rca`](https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/oncall/skills/rca/SKILL.md) — Triggers: "investigate issue", "root cause", "debug production", "why is this broken", "blank page", "data mismatch", "slow page", "api latency"*
```

**Output summary** displayed to the user:
```
Skill: /rca
File:  ${CLAUDE_PLUGIN_ROOT}/skills/rca/SKILL.md
Repo:  https://github.com/loopai-hq/loop-claude-plugins/blob/main/plugins/oncall/skills/rca/SKILL.md
```
