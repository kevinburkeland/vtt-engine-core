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

raw_output=""
if [ "$#" -ge 2 ]; then
  list_file="$2"
  if [ ! -f "$list_file" ]; then
    echo "Error: Branch list file not found: '$list_file'" >&2
    exit 1
  fi
  raw_output=$(cat "$list_file")
else
  if ! raw_output=$(git ls-remote --heads origin 'refs/heads/mutation/*'); then
    echo "Error: git ls-remote failed to query origin." >&2
    exit 1
  fi
fi

branches=()
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  ref=$(echo "$line" | awk '{print $2}')
  if [[ "$ref" == refs/heads/mutation/* ]]; then
    branch_name="${ref#refs/heads/}"
    branches+=("$branch_name")
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

exit 0
