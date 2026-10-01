# Traceparent correlation

Loaded by the `rca` skill before Step 2 (the first step that extracts trace
ids). The trace id is the thread that ties every system together.

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

### General
- Check ALL sessions if user visited the page multiple times — the issue may be in an earlier session with different filters
- When the user provides a screenshot, analyze what DID load (summary cards, filters) vs what DIDN'T (charts, tables) to narrow the investigation
- Compare response sizes across APIs in the same trace — if one is much smaller, that's likely the broken one
- If the issue is intermittent, check for feature flags that might be toggling behavior
