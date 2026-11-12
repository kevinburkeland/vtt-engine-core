#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Error: Missing required argument LIMIT." >&2
  echo "Usage: $0 LIMIT [LIST_FILE]" >&2
  exit 1
fi

limit="$1"

if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
  echo "Error: LIMIT must be a non-negative whole number, got: '$limit'" >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exceptions_file="$repo_root/mutation_subject_exceptions.tsv"

# Parse and validate exceptions file if present
declare -A exc_sha
declare -A exc_used

if [ -f "$exceptions_file" ]; then
  while IFS=$'\t' read -r branch sha review_by reason || [ -n "$branch" ]; do
    [ -z "$branch" ] && continue
    [[ "$branch" =~ ^# ]] && continue

    if [ -z "$sha" ] || [ -z "$review_by" ] || [ -z "$reason" ]; then
      echo "Error: Malformed exception row in '$exceptions_file': expected 4 tab-separated fields." >&2
      exit 1
    fi

    # Validate review_by date
    date_rc=0
    python3 -c "
import sys
from datetime import datetime, timezone, timedelta
today_str = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
today = datetime.strptime(today_str, '%Y-%m-%d').date() if today_str else datetime.now(timezone.utc).date()
try:
    r_date = datetime.strptime(sys.argv[1], '%Y-%m-%d').date()
except Exception:
    sys.exit(4)
if r_date < today:
    sys.exit(2)
if r_date > today + timedelta(days=90):
    sys.exit(3)
sys.exit(0)
" "$review_by" "${MUTATION_CHECK_TODAY:-}" || date_rc=$?

    if [ "$date_rc" -eq 2 ]; then
      echo "Error: Exception review_by date '$review_by' for '$branch' is in the past." >&2
      exit 1
    elif [ "$date_rc" -eq 3 ]; then
      echo "Error: Exception review_by date '$review_by' for '$branch' is more than 90 days in the future." >&2
      exit 1
    elif [ "$date_rc" -eq 4 ]; then
      echo "Error: Invalid date format in review_by '$review_by' for '$branch'." >&2
      exit 1
    fi

    clean_b="${branch#refs/heads/}"
    exc_sha["$clean_b"]="$sha"
    exc_used["$clean_b"]=0
  done < "$exceptions_file"
fi

raw_output=""
if [ "$#" -ge 2 ]; then
  list_file="$2"
  if [ ! -f "$list_file" ]; then
    echo "Error: Branch list file not found: '$list_file'" >&2
    exit 1
  fi
  raw_output=$(cat "$list_file")
else
  # Fetch all mutation branches into origin/mutation/* tracking refs (Fix 5.2)
  if ! git fetch origin '+refs/heads/mutation/*:refs/remotes/origin/mutation/*'; then
    echo "Error: Failed to fetch remote mutation branches from origin." >&2
    exit 1
  fi
  if ! raw_output=$(git ls-remote --heads origin 'refs/heads/mutation/*'); then
    echo "Error: git ls-remote failed to query origin." >&2
    exit 1
  fi
fi

branches=()
branch_shas=()

while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  sha=$(echo "$line" | awk '{print $1}')
  ref=$(echo "$line" | awk '{print $2}')
  if [[ "$ref" == refs/heads/mutation/* ]]; then
    branch_name="${ref#refs/heads/}"
    branches+=("$branch_name")
    branch_shas+=("$sha")
  fi
done <<< "$raw_output"

count="${#branches[@]}"

echo "Mutation branches count: $count"
echo "Mutation branches limit: $limit"
if [ "$count" -gt 0 ]; then
  echo "Counted branches:"
  for b in "${branches[@]}"; do
    echo "  $b"
  done
fi

if [ "$count" -gt "$limit" ]; then
  echo "Error: Mutation branch count ($count) exceeds limit ($limit)." >&2
  exit 1
fi

# Verify each mutation branch commit rule
for i in "${!branches[@]}"; do
  b="${branches[$i]}"
  head_sha="${branch_shas[$i]}"

  # Check if commit exists in repository
  if ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
    # Try fetching the single branch commit if not present
    git fetch origin "$b" >/dev/null 2>&1 || true
    if ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
      echo "Error: Cannot resolve commit '$head_sha' for branch '$b'." >&2
      exit 1
    fi
  fi

  # Find merge base with origin/main (or main)
  base_sha=$(git merge-base refs/remotes/origin/main "$head_sha" 2>/dev/null || git merge-base refs/heads/main "$head_sha" 2>/dev/null || git merge-base main "$head_sha" 2>/dev/null || true)
  if [ -z "$base_sha" ]; then
    echo "Error: Cannot find merge base between main and branch '$b' ($head_sha)." >&2
    exit 1
  fi

  # Exactly 1 commit above merge base
  commit_count=$(git rev-list --count "$base_sha..$head_sha")
  if [ "$commit_count" -ne 1 ]; then
    echo "Error: Branch '$b' has $commit_count commit(s) between main and head; expected exactly 1." >&2
    exit 1
  fi

  # Check Signed-off-by trailer
  trailers=$(git log -n 1 --format="%(trailers:key=Signed-off-by,valueonly)" "$head_sha")
  if [ -z "$trailers" ]; then
    echo "Error: Branch '$b' commit $head_sha is missing a Signed-off-by: trailer." >&2
    exit 1
  fi

  # Check subject rule or exception
  if [ -n "${exc_sha[$b]:-}" ] && [ "${exc_sha[$b]}" = "$head_sha" ]; then
    exc_used["$b"]=1
  else
    subject=$(git log -n 1 --format="%s" "$head_sha")
    leaf="${b#mutation/}"
    branch_id="${leaf#*-}"

    # Subject must start with "MUTATION — do not merge: <id>" (case-insensitive on id)
    shopt -s nocasematch
    req_prefix="MUTATION — do not merge: $branch_id"
    if [[ "$subject" != "$req_prefix"* ]]; then
      shopt -u nocasematch
      echo "Error: Branch '$b' commit subject '$subject' does not match required subject '$req_prefix'." >&2
      exit 1
    fi
    shopt -u nocasematch
  fi
done

# Check for stale exceptions
for exc_b in "${!exc_sha[@]}"; do
  if [ "${exc_used[$exc_b]:-0}" -eq 0 ]; then
    echo "Error: Stale mutation subject exception for branch '$exc_b' (expected SHA: ${exc_sha[$exc_b]}). Branch does not exist or SHA differs." >&2
    exit 1
  fi
done

exit 0
