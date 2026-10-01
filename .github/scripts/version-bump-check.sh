#!/usr/bin/env bash
# Fails when a change under plugins/<p>/ leaves that plugin's manifest
# version unchanged. Claude Code ships a new copy of a plugin only when the
# version string differs, so an unbumped change is invisible to installers.
#
# Usage: version-bump-check.sh <base-commit>
#   version-bump-check.sh origin/main
#   version-bump-check.sh "$PR_BASE_SHA"      # CI: the pull request's base commit
# Compares the working tree's HEAD against <base-commit> (two-dot diff, which
# is exact when HEAD is the PR's merge commit or a descendant of the base).
set -uo pipefail

base=${1:?usage: version-bump-check.sh <base-commit>}
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "::error::base commit $base is not available"; exit 2; }

fail=0
for plugin_dir in plugins/*/; do
  plugin=$(basename "$plugin_dir")
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  changed=$(git diff --name-only "$base" HEAD -- "plugins/$plugin/")
  [ -n "$changed" ] || { echo "ok  $plugin: no changes"; continue; }
  if ! git cat-file -e "$base:$manifest" 2>/dev/null; then
    echo "ok  $plugin: new plugin"; continue
  fi
  old=$(git show "$base:$manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))')
  new=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$manifest")
  if [ "$old" = "$new" ]; then
    printf '::error file=%s::%s changed (%s file(s)) but version is still %s; bump it and add a CHANGELOG entry\n' \
      "$manifest" "$plugin" "$(printf '%s\n' "$changed" | wc -l | tr -d ' ')" "$old"
    fail=1
  else
    echo "ok  $plugin: $old -> $new"
  fi
done
[ "$fail" -eq 0 ] && echo "version-bump-check: OK"
exit "$fail"
