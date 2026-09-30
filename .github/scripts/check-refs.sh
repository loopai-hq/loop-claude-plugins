#!/usr/bin/env bash
# Reference checker. Exits non-zero when the tree and its documentation
# disagree:
#   1. every ${CLAUDE_PLUGIN_ROOT}/<path> mentioned under plugins/<p>/ exists
#      inside plugins/<p>/ (paths with a <placeholder> are skipped);
#   2. every bare `references/<file>` token inside a skill resolves inside
#      that skill's own references/ directory (a longer
#      ${CLAUDE_PLUGIN_ROOT}/skills/<other>/references/<file> path is rule 1's
#      job; a bare cross-plugin path is a bug because the other plugin may
#      not be installed);
#   3. every relative Markdown link [text](path) in any tracked .md resolves
#      (targets holding {placeholders}, <angles>, quotes, | or $ are
#      templates and regexes, not links);
#   4. every skill and agent directory appears in the root README and in its
#      plugin README component tables, and every component row in those
#      tables names a skill, agent or plugin that exists;
#   5. every SKILL.md has a "## Configuration" section.
#
# Usage: check-refs.sh   (run from the repository root; no arguments)
set -uo pipefail

fail=0
report() { printf '::error::%s\n' "$1"; fail=1; }

# 1. ${CLAUDE_PLUGIN_ROOT} paths
for plugin_dir in plugins/*/; do
  plugin_dir=${plugin_dir%/}
  while IFS=: read -r file line ref; do
    [ -n "$ref" ] || continue
    rel=${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}
    case "$rel" in *'<'*) continue ;; esac   # <placeholder> paths are documentation
    [ -e "$plugin_dir/$rel" ] || report "$file:$line: $ref does not exist under $plugin_dir"
  done < <(grep -rnoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./<>-]+' "$plugin_dir" 2>/dev/null | sed -E 's/[.,`)]+$//')
done

# 2. bare references/<file> tokens inside a skill resolve inside that skill
for skill_dir in plugins/*/skills/*/; do
  skill_dir=${skill_dir%/}
  while IFS=: read -r file line ref; do
    [ -n "$ref" ] || continue
    ref="references/${ref#*references/}"
    [ -e "$skill_dir/$ref" ] || report "$file:$line: $ref does not resolve inside $skill_dir (use the sibling file name from references/, or quote the rule inline)"
  done < <(grep -rnoE '(^|[^/A-Za-z0-9_])references/[A-Za-z0-9_.-]+\.md' "$skill_dir" 2>/dev/null)
done

# 3. relative Markdown links
while IFS= read -r md; do
  dir=$(dirname "$md")
  while IFS=: read -r line link; do
    [ -n "$link" ] || continue
    target=${link#\]\(}; target=${target%\)}
    target=${target%% *}                       # drop an optional "title"
    case "$target" in
      http://*|https://*|mailto:*|\#*) continue ;;
      *'<'*|*'{'*|*'|'*|*'$'*|*"'"*|*'"'*) continue ;;
    esac
    target=${target%%#*}
    [ -n "$target" ] || continue
    [ -e "$dir/$target" ] || report "$md:$line: link target $target does not exist"
  done < <(grep -noE '\]\([^)]+\)' "$md" 2>/dev/null)
done < <(find . -path ./.git -prune -o -name '*.md' -type f -print | sed 's#^\./##')

# 4. README tables vs the tree
component_rows() {  # component rows look like: | `name` | ...
  # shellcheck disable=SC2016  # the backticks are literal Markdown, not command substitution
  grep -oE '^\| `[a-z][a-z0-9-]*` \|' "$1" | sed -E 's/^\| `([^`]+)` \|$/\1/' | sort -u
}
plugins=$(basename -a plugins/*/ | sort -u | tr '\n' ' ')
all_components=""
for plugin_dir in plugins/*/; do
  plugin=$(basename "$plugin_dir")
  components=""
  for s in "$plugin_dir"skills/*/; do [ -d "$s" ] && components="$components $(basename "$s")"; done
  for a in "$plugin_dir"agents/*.md; do [ -f "$a" ] && components="$components $(basename "$a" .md)"; done
  all_components="$all_components $components"
  readme="$plugin_dir/README.md"
  [ -f "$readme" ] || { report "$readme is missing"; continue; }
  rows=$(component_rows "$readme")
  for c in $components; do
    printf '%s\n' "$rows" | grep -qx "$c" || report "$readme: no table row for $c"
    component_rows README.md | grep -qx "$c" || report "README.md: no table row for $c (plugin $plugin)"
  done
  for r in $rows; do
    printf ' %s ' "$components" | grep -q " $r " || report "$readme: table row \`$r\` names nothing under $plugin_dir"
  done
done
for r in $(component_rows README.md); do
  printf ' %s ' "$all_components $plugins" | grep -q " $r " || report "README.md: table row \`$r\` names no skill, agent or plugin in the tree"
done

# 5. Configuration section in every SKILL.md
for skill in plugins/*/skills/*/SKILL.md; do
  grep -q '^## Configuration' "$skill" || report "$skill: missing a '## Configuration' section"
done

if [ "$fail" -ne 0 ]; then
  echo "check-refs: FAILED"
  exit 1
fi
echo "check-refs: OK"
