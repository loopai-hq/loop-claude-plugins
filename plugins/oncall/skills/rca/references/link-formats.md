# Link formats for RCA documents

Loaded by the `rca` skill when it writes or updates the Evidence Links table
(Step 0 onwards) and again when it finalizes the document in Step 13.

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
