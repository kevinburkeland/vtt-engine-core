#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:-.github/workflows}"

if [ ! -d "$target_dir" ]; then
  echo "Error: Directory '$target_dir' does not exist." >&2
  exit 1
fi

files=()
while IFS= read -r f; do
  [ -n "$f" ] && files+=("$f")
done < <(find "$target_dir" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No workflow files found in '$target_dir'."
  exit 0
fi

failed=0
total_checked=0

for file in "${files[@]}"; do
  line_num=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    if [[ "$line" =~ ^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*([^#[:space:]]+) ]]; then
      action="${BASH_REMATCH[2]}"
      # Strip quotes if any
      action="${action%\"}"
      action="${action#\"}"
      action="${action%\'}"
      action="${action#\'}"

      # Local actions starting with ./ are exempt
      if [[ "$action" =~ ^\./ ]]; then
        continue
      fi
      total_checked=$((total_checked + 1))
      if [[ ! "$action" =~ @[0-9a-fA-F]{40}$ ]]; then
        echo "Error: $file:$line_num: Action '$action' is not pinned to a 40-character commit SHA." >&2
        failed=$((failed + 1))
      fi
    fi
  done < "$file"
done

if [ "$failed" -gt 0 ]; then
  echo "Found $failed unpinned action reference(s)." >&2
  exit 1
fi

echo "Verified $total_checked action reference(s) across ${#files[@]} workflow file(s); all correctly pinned."
exit 0
