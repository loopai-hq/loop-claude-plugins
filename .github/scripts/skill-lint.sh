#!/usr/bin/env bash
# Static lint for marketplace skills. Blocks on embedded secrets, non-portable
# absolute paths, malformed SKILL.md frontmatter, and scripts that don't
# compile. With no arguments it also runs the fixture tests under tests/.
#
# Usage:
#   skill-lint.sh <file> [file ...]   # lint the given files
#   skill-lint.sh                      # no args: lint every file under plugins/ and run tests/
#
# Exits non-zero if any check fails.
set -uo pipefail

if [ "$#" -gt 0 ]; then
  FILES=$(printf '%s\n' "$@")
else
  FILES=$(find plugins -type f 2>/dev/null)
fi

fail=0
report() { printf '::error::%s\n' "$1"; fail=1; }

# Length-bounded so doc placeholders (lin_api_..., AIza) don't match real keys.
SECRET_RE='xox[baprs]-[0-9A-Za-z-]{20,}|lin_api_[A-Za-z0-9]{32,}|phx_[A-Za-z0-9]{32,}|apk_[A-Za-z0-9]{24,}|sk-(ant-)?[A-Za-z0-9_-]{24,}|AIza[0-9A-Za-z_-]{35}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}|cal_live_[A-Za-z0-9]{20,}|-----BEGIN[A-Z ]*PRIVATE KEY-----'
# [U] and [w] keep this script from flagging itself when linted.
PATH_RE='/[U]sers/|/home/[a-z]|/[w]orkspace/'

frontmatter() {
  awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$1"
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue

  # 1. embedded secrets (report location only, never the value)
  while IFS= read -r ln; do
    [ -n "$ln" ] && report "$f:$ln: possible embedded credential — use env var / Secret Manager"
  done < <(grep -nEI "$SECRET_RE" "$f" 2>/dev/null | cut -d: -f1)

  # 2. non-portable absolute paths
  while IFS= read -r ln; do
    [ -n "$ln" ] && report "$f:$ln: hardcoded absolute path — use \${CLAUDE_PLUGIN_ROOT}/skills/<skill>/<file> or an env var"
  done < <(grep -nEI "$PATH_RE" "$f" 2>/dev/null | cut -d: -f1)

  case "$f" in
    */SKILL.md)
      # 3. frontmatter contract
      fm=$(frontmatter "$f")
      printf '%s\n' "$fm" | grep -q '^name:' || report "$f: SKILL.md frontmatter missing 'name:'"
      printf '%s\n' "$fm" | grep -q '^description:' || report "$f: SKILL.md frontmatter missing 'description:'"
      printf '%s\n' "$fm" | grep -q '^version:' && report "$f: SKILL.md has disallowed 'version:' frontmatter key"
      ;;
    *.py)
      # ast.parse rather than py_compile: the latter writes __pycache__ into the tree.
      python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>/dev/null \
        || report "$f: python syntax check failed"
      ;;
    *.sh)
      bash -n "$f" 2>/dev/null || report "$f: bash -n syntax check failed"
      ;;
  esac
done <<EOF
$FILES
EOF

# 4. fixture tests (whole-tree runs only): parse_logs.py against tests/fixtures
if [ "$#" -eq 0 ] && [ -f tests/test_parse_logs.py ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 tests/test_parse_logs.py || report "tests/test_parse_logs.py failed"
fi

if [ "$fail" -ne 0 ]; then
  echo "skill-lint: FAILED"
  exit 1
fi
echo "skill-lint: OK"
