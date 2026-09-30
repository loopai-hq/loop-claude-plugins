# Query recipes

Loaded by the `rca` skill at the step that needs each recipe. Every command
reads its ids from the Configuration variables; nothing here is hardcoded.
Adapt the log field names to your request logger where the comments say so.

## Step 4 — Sentry alert rules (REST API)

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

## Step 6 — GCloud logs by trace id

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

### GCloud tips

- Response size in HTTP logs is a quick diagnostic: small response (< 1KB for summary APIs) = sparse/empty data
- App logs at `jsonPayload.message="Request/response log"` (or your logger's equivalent) contain the full request body with dates, filters, granularity
- If the backend can adjust the requested date range server-side, note that flag in the request body — the actual range may differ from what was sent
- Use `jsonPayload.dict_object.request_id` (or your logger's field) to match by trace_id in app logs
- Check multiple services — a trace may span the main API, an admin backend, and workers

## Step 8 — What was deployed (git and gh)

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

### Deployment tips

- Use `gh pr diff` to see exactly what code changed in a suspicious deployment
- Compare the deployment timestamp with the issue report timestamp


## Step 10 — Known issues and prior RCAs

```bash
# Search open issues for keywords related to the affected page, API endpoint, or error type
gh issue list --repo "$GITHUB_REPO" --state open \
  --search "<page name OR endpoint OR error type>" \
  --json number,title,author,assignees,labels,state,url,updatedAt --limit 50

# Also search recently closed issues in case a fix shipped but regressed
SINCE_30D=$(python3 -c 'import datetime as d; print((d.date.today()-d.timedelta(days=30)).isoformat())')
gh issue list --repo "$GITHUB_REPO" --state closed \
  --search "<keyword> updated:>=$SINCE_30D" \
  --json number,title,url,updatedAt --limit 20

# Search prior RCA documents for the same page, endpoint, or error
grep -ril "<keyword>" "${RCA_DOCS_DIR:-docs/rca/}"
```

Date arithmetic goes through `python3` on purpose: `date -d` is GNU-only and
`date -v` is BSD-only.

## Step 11 — Session recordings (HogQL)

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

### PostHog tips

- Email property is `properties.email` (lowercase) on persons table
- `API_latency` events contain: `trace_id`, `endpoint`, `status_code`, `latency_ms`
- Session recordings provide visual proof — always try to find the session_id
