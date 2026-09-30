# Sentry cross-reference (Phase 4.4, optional)

Loaded by the `pr-review` skill in Phase 4.4 only when `SENTRY_ORG` is set and
Sentry MCP tools are available. Otherwise the phase is skipped with
"Sentry cross-reference: Skipped (not configured)".

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
