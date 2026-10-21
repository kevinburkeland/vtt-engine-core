#!/usr/bin/env bash
set -euo pipefail

baseline="${1:-}"
head="${2:-HEAD}"

if [ -n "$baseline" ]; then
  rev_range="${baseline}..${head}"
else
  rev_range="${head}"
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Not inside a git repository." >&2
  exit 1
fi

commits=()
while IFS= read -r c; do
  [ -n "$c" ] && commits+=("$c")
done < <(git rev-list "$rev_range")

total=${#commits[@]}
if [ "$total" -eq 0 ]; then
  echo "Checked 0 commits (range: $rev_range); nothing to verify."
  exit 0
fi

failed=0

for commit in "${commits[@]}"; do
  short_sha=$(git log -n 1 --format="%h" "$commit")
  author=$(git log -n 1 --format="%an <%ae>" "$commit")
  trailers=$(git log -n 1 --format="%(trailers:key=Signed-off-by,valueonly)" "$commit")

  matched=0
  has_trailer=0

  if [ -n "$trailers" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      clean_line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      if [ -n "$clean_line" ]; then
        has_trailer=1
        if [ "$clean_line" = "$author" ]; then
          matched=1
          break
        fi
      fi
    done <<< "$trailers"
  fi

  if [ "$matched" -ne 1 ]; then
    failed=$((failed + 1))
    if [ "$has_trailer" -eq 0 ]; then
      echo "$short_sha missing Signed-off-by trailer (author: $author)"
    else
      echo "$short_sha Signed-off-by trailer does not match author: expected '$author'"
    fi
  fi
done

if [ "$failed" -gt 0 ]; then
  exit 1
fi

echo "Checked $total commit(s); all carry valid DCO sign-off."
exit 0
