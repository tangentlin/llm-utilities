#!/usr/bin/env bash
# repo-tree.sh — Generate a token-efficient directory tree for LLM agents.
#
# Usage:
#   bash repo-tree.sh <directory> [depth]
#
# Arguments:
#   directory   Root directory to scan (required)
#   depth       Max depth, default 4
#
# Output:
#   A clean directory tree excluding noise (node_modules, dist, .git, etc.)
#   plus a summary line count.
#
# Why this exists:
#   An always-fresh tree beats a static REPO_MAP.md that goes stale
#   on every file add/delete. Run this instead of maintaining a doc.

set -euo pipefail

DIR="${1:?Usage: repo-tree.sh <directory> [depth]}"
DEPTH="${2:-4}"

# Resolve to absolute path
DIR="$(cd "$DIR" && pwd)"

echo "# Repo Tree: ${DIR}"
echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "# Depth: ${DEPTH}"
echo ""

# Use find + sed for a portable tree that excludes noise directories.
# We skip: node_modules, dist, build, .git, __pycache__, .next, coverage,
#          .turbo, .cache, .DS_Store, *.pyc
find "$DIR" -maxdepth "$DEPTH" \
  -name 'node_modules' -prune -o \
  -name 'dist' -prune -o \
  -name 'build' -prune -o \
  -name '.git' -prune -o \
  -name '__pycache__' -prune -o \
  -name '.next' -prune -o \
  -name 'coverage' -prune -o \
  -name '.turbo' -prune -o \
  -name '.cache' -prune -o \
  -name '.DS_Store' -prune -o \
  -name '*.pyc' -prune -o \
  -print | \
  sed "s|^${DIR}|.|" | \
  sort | \
  while IFS= read -r path; do
    # Calculate indent depth
    depth=$(echo "$path" | tr -cd '/' | wc -c)
    indent=$(printf '%*s' "$((depth * 2))" '')
    name=$(basename "$path")

    if [ -d "${DIR}/${path#./}" ] 2>/dev/null || [ -d "$path" ] 2>/dev/null; then
      echo "${indent}${name}/"
    else
      echo "${indent}${name}"
    fi
  done

echo ""

# Summary stats
file_count=$(find "$DIR" -maxdepth "$DEPTH" \
  -name 'node_modules' -prune -o \
  -name 'dist' -prune -o \
  -name 'build' -prune -o \
  -name '.git' -prune -o \
  -name '__pycache__' -prune -o \
  -type f -print | wc -l | tr -d ' ')

dir_count=$(find "$DIR" -maxdepth "$DEPTH" \
  -name 'node_modules' -prune -o \
  -name 'dist' -prune -o \
  -name 'build' -prune -o \
  -name '.git' -prune -o \
  -name '__pycache__' -prune -o \
  -type d -print | wc -l | tr -d ' ')

echo "# Summary: ${file_count} files, ${dir_count} directories"
