# Evaluation document template

Loaded by the `evaluate` skill in Phase 8 when it writes
`docs/evaluations/evaluate-<slug>.md`, and in Phase 9.1 for the console
summary. Replicate the structure exactly; leave a placeholder you cannot fill
rather than deleting the section.

### Document Fields

```
title: "Evaluate: <short description>" (e.g., "Evaluate: Zustand to Jotai Migration")
path:  docs/evaluations/evaluate-<slug>.md (Markdown)
```

## Document content

````markdown
# Evaluate: <Short Description>

> **Status**: Evaluation Complete | **Date**: <today> | **Verdict**: <PENDING>

## 1. Proposal

### What
<The specific change being proposed>

### Why
<The motivation — what problem does this solve?>

### Success Criteria
<What does success look like from the user's perspective?>

### Constraints
<Timeline, budget, team size, backwards compatibility needs>

---

## 2. External Research

### Official Documentation
<Key findings from official docs, migration guides, feature parity>

### Community Experience
| Source | Key Finding | Relevance to Us |
|--------|------------|-----------------|
| <source> | <finding> | <relevance> |

### Benchmarks & Data
| Metric | Current (<technology>) | Proposed (<technology>) | Source |
|--------|----------------------|------------------------|--------|
| <metric> | <value> | <value> | <source> |

### Research Verdict
<1-2 sentence summary: Does external evidence support this change?>

---

## 3. Blast Radius

### Affected Files
| Impact | Count | Key Files |
|--------|-------|-----------|
| CRITICAL | <N> | <list> |
| HIGH | <N> | <list> |
| MEDIUM | <N> | <list> |
| LOW | <N> | <list> |

**Total files affected**: <N>

### Feature Parity
| Feature We Use | Equivalent in Proposed? | Gap? |
|---------------|------------------------|------|
| <feature> | <yes/no/partial> | <description if gap> |

### Scary Areas
<List of highest-risk areas with explanation of why they're scary>

---

## 4. Risk Assessment

### Risk Matrix
| ID | Risk | Likelihood | Impact | Severity | Mitigation |
|----|------|-----------|--------|----------|------------|
| R1 | <risk> | <L/M/H> | <L/M/H> | <severity> | <mitigation> |

### Reversibility
**Classification**: <Easily Reversible / Reversible with Effort / Partially Reversible / Irreversible>
**Rollback plan**: <description>
**Estimated rollback time**: <duration>

### Risk Summary
- **Critical risks**: <count> — <summary>
- **High risks**: <count> — <summary>
- **Mitigatable risks**: <count>
- **Accepted risks**: <count>

---

## 5. Migration Strategy

### Recommended Approach
**<Big Bang / Incremental / Parallel Run>**
<Rationale for chosen approach>

### Phase Breakdown
| Phase | Scope | Rollback Plan |
|-------|-------|---------------|
| 1 | <scope> | <rollback> |
| 2 | <scope> | <rollback> |

---

## 6. Metrics & Observability

### Baseline (Before)
| Metric | Current Value |
|--------|--------------|
| <metric> | <value or TBD> |

### During Migration
| Signal | Threshold | Action if Breached |
|--------|-----------|-------------------|
| <signal> | <threshold> | <action> |

### Convergence (After)
| Metric | Target | Measurement Period |
|--------|--------|-------------------|
| <metric> | <target> | <period> |

---

## 7. Test Strategy

### Automated Tests
| Type | What | Priority | New? |
|------|------|----------|------|
| <type> | <what> | P1/P2 | Yes/No |

### Manual Test Cases
| ID | Scenario | Priority |
|----|----------|----------|
| MT1 | <scenario> | P1/P2/P3 |

### Canary Plan
<How to validate in production before full rollout>

---

## 8. Verdict

### Recommendation: <GO / NO-GO / CONDITIONAL GO>

### Reasoning
<3-5 bullet points explaining the recommendation>

### If GO:
- **Estimated effort**: <size>
- **Recommended approach**: <approach>
- **First step**: <what to do first>
- **Critical prerequisites**: <what must be true before starting>

### If NO-GO:
- **Primary blockers**: <what makes this inadvisable>
- **Alternative approaches**: <what to do instead>
- **Revisit conditions**: <under what conditions should we reconsider>

### If CONDITIONAL GO:
- **Conditions that must be met**: <list>
- **Reduced scope recommendation**: <what to do if full scope is too risky>

---

## 9. References
- <Link to official docs>
- <Link to relevant blog posts>
- <Link to benchmarks>
- <Link to codebase files>

---
*Evaluated with the `evaluate` skill from [loop-claude-plugins](https://github.com/loopai-hq/loop-claude-plugins).* (omit this line when `PLUGIN_FOOTER=off`)
````

## Console summary (Phase 9.1)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  EVALUATION COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Document:    docs/evaluations/evaluate-<slug>.md
Proposal:    <1-line summary>
Verdict:     <GO / NO-GO / CONDITIONAL GO>

Blast Radius:
  CRITICAL:  <N> files
  HIGH:      <N> files
  MEDIUM:    <N> files
  Total:     <N> files affected

Risks:
  Critical:  <N> risks
  High:      <N> risks
  Mitigated: <N> risks

Feature Gaps: <N> gaps found
Reversibility: <classification>

Key Findings:
  + <pro 1>
  + <pro 2>
  - <con 1>
  - <con 2>
  ! <warning 1>

Recommended Approach: <approach>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
