#!/usr/bin/env bash
# Print one plugin's section for one version from CHANGELOG.md, for use as a
# GitHub Release body. The changelog has one "## <plugin>" heading per plugin
# and "### [<version>] - <date>" headings beneath it.
#
# Usage: changelog-section.sh <plugin> <version> [CHANGELOG.md]
#   changelog-section.sh oncall 0.2.0
# Exits 1 (and prints nothing) when the section does not exist.
set -uo pipefail

plugin=${1:?usage: changelog-section.sh <plugin> <version> [file]}
version=${2:?usage: changelog-section.sh <plugin> <version> [file]}
file=${3:-CHANGELOG.md}

section=$(awk -v plugin="$plugin" -v version="$version" '
  /^## /  { in_plugin = ($0 == "## " plugin); in_version = 0; next }
  /^### / {
    if (in_plugin && $0 ~ "^### \\[" version "\\]") { in_version = 1; found = 1; next }
    in_version = 0; next
  }
  in_version { print }
  END { exit found ? 0 : 1 }
' "$file") || { echo "changelog-section: no section '### [$version]' under '## $plugin' in $file" >&2; exit 1; }

# Trim leading and trailing blank lines.
printf '%s\n' "$section" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/./,$!d'
