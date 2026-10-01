---
name: plan-issue
description: Write a detailed implementation plan as a GitHub issue before any code is written. Use when the user wants to plan, design or architect a feature or change with alternatives and trade-offs, or says "plan this as an issue", "write the plan", "design doc issue". Invoke as /engg:plan-issue (the bare /plan is Claude Code's built-in plan mode, not this skill).
argument-hint: "[feature or change to plan]"
---

## Configuration

This skill reads no environment variables and needs no setup beyond an authenticated `gh`.

Analyze the user's request thoroughly. Create a detailed implementation plan with: multiple approaches, trade-offs for each approach, recommended solution with justification, and clear implementation phases.

Think hard about edge cases, long-term maintainability, and system-wide impacts. Create a GitHub issue using `gh issue create` with the plan as an engineering design doc, including acceptance criteria and test cases. Output the issue URL. Get user approval before starting implementation. Use `exit_plan_mode` when the task requires coding.
