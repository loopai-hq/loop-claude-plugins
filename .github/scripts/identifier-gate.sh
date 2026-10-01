#!/usr/bin/env bash
# Identifier gate. Exits non-zero when a tracked file contains a
# company-internal identifier (cloud project ids, chat channel/user ids,
# internal hosts or IPs, private repo names, employee or customer names).
#
# Patterns:
#   $IDENTIFIER_GATE_PATTERNS  optional extended regex with the concrete strings
#                              that must never appear. In CI it comes from a
#                              repository secret so the list itself is never
#                              published. It is combined with the generic
#                              pattern below, never echoed.
#   DEFAULT_PATTERNS           generic shapes: Slack ids, home-directory paths,
#                              nip.io/sslip.io hosts, org-scoped Sentry hosts,
#                              GCP-style project ids, non-example email addresses.
#
# Allowed strings (removed from a line before it is re-tested): the marketplace
# owner contact, the security contact, links to this org's public repos,
# example.com addresses, and Sentry region hosts.
#
# Usage:
#   identifier-gate.sh                # whole tree (minus LICENSE and examples/)
#   identifier-gate.sh <path> [...]   # restrict to the given files or directories
# Run it from the repository root. Output lines are file:line:text.
set -uo pipefail

# The single-character bracket class ([U]) keeps this file from matching its
# own patterns when the gate is run over the repository.
DEFAULT_PATTERNS='(^|[^A-Za-z0-9])(C0|U0|S0|G0)[A-Z0-9]{8,}([^A-Za-z0-9]|$)|/[U]sers/[a-z]|/home/[a-z]|\.nip\.io|\.sslip\.io|[a-z0-9-]+\.sentry\.io|(^|[^a-z0-9-])[a-z]+(-[a-z]+)+-[0-9]{6}([^0-9]|$)|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[a-z]{2,}'

ALLOWED='engineering@tryloop\.ai|security@loopai\.com|github\.com/loopai-hq/(loop-sessions|loop-plugins)|(@|github\.com/)[b]havathi-loop|[A-Za-z0-9._%+-]+@example\.(com|org|net)|[A-Za-z0-9._%+-]+@users\.noreply\.github\.com|noreply@[A-Za-z0-9.-]+|(us|de)\.sentry\.io'

if [ -n "${IDENTIFIER_GATE_PATTERNS:-}" ]; then
  PATTERNS="${IDENTIFIER_GATE_PATTERNS}|${DEFAULT_PATTERNS}"
  echo "identifier-gate: using repository patterns + generic patterns"
else
  PATTERNS="${DEFAULT_PATTERNS}"
  echo "identifier-gate: using generic patterns only (IDENTIFIER_GATE_PATTERNS unset)"
fi

raw_hits() {
  # Plain grep rather than git grep on purpose: it behaves the same on a CI
  # checkout, also covers untracked files in a local run, and cannot be fooled
  # by an exported tree that happens to sit inside some other git work tree.
  # --exclude=.git as well as --exclude-dir=.git: in a linked git worktree
  # .git is a one-line pointer file, never tracked content.
  if [ "$#" -gt 0 ]; then
    grep -rnIE "$PATTERNS" --exclude-dir=.git --exclude=.git --exclude-dir=examples --exclude=LICENSE "$@"
  else
    grep -rnIE "$PATTERNS" --exclude-dir=.git --exclude=.git --exclude-dir=examples --exclude=LICENSE .
  fi
}

# Strip allowed substrings, then re-test so a line that mixes an allowed string
# with a forbidden one is still caught.
hits=$(raw_hits "$@" 2>/dev/null | sed -E "s#${ALLOWED}##g" | grep -E "$PATTERNS" || true)

if [ -n "$hits" ]; then
  echo "identifier-gate: FAILED — internal identifiers found:"
  printf '%s\n' "$hits" | while IFS= read -r line; do
    printf '::error::%s\n' "$line"
  done
  exit 1
fi
echo "identifier-gate: OK"
