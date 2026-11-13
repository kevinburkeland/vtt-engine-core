#!/usr/bin/env bash
set -euo pipefail

# scripts/retire_mutation_branches.sh <slice-id> [--dry-run]
# Archives and deletes remote mutation branches for a given slice ID.

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <slice-id> [--dry-run]" >&2
  exit 1
fi

slice_id="$1"
dry_run=0

if [ "$#" -eq 2 ]; then
  if [ "$2" = "--dry-run" ]; then
    dry_run=1
  else
    echo "Error: Unknown option '$2'. Usage: $0 <slice-id> [--dry-run]" >&2
    exit 1
  fi
fi

if ! [[ "$slice_id" =~ ^[a-z0-9]+$ ]]; then
  echo "Error: <slice-id> must match ^[a-z0-9]+$, got: '$slice_id'" >&2
  exit 1
fi

# Precondition: working tree is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: Working tree is dirty. Commit or stash changes before retiring branches." >&2
  exit 1
fi

# Precondition: current branch is main
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "main" ]; then
  echo "Error: Current branch is '$current_branch', must be 'main'." >&2
  exit 1
fi

# Precondition: local main equals origin/main after fetch
if ! git fetch origin main; then
  echo "Error: Failed to fetch origin main." >&2
  exit 1
fi

local_main_sha=$(git rev-parse refs/heads/main)
origin_main_sha=$(git rev-parse refs/remotes/origin/main)
if [ "$local_main_sha" != "$origin_main_sha" ]; then
  echo "Error: Local main ($local_main_sha) does not match origin/main ($origin_main_sha)." >&2
  exit 1
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

temp_dirs=()
cleanup() {
  for d in "${temp_dirs[@]}"; do
    if [ -d "$d" ]; then
      git worktree remove --force "$d" >/dev/null 2>&1 || true
      rm -rf "$d" >/dev/null 2>&1 || true
    fi
  done
  git worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 2. List refs/heads/mutation/<slice-id>-* with git ls-remote
if ! raw_ls=$(git ls-remote --heads origin "refs/heads/mutation/${slice_id}-*"); then
  echo "Error: git ls-remote failed to query origin." >&2
  exit 1
fi

matched_branches=()
matched_heads=()

while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  sha=$(echo "$line" | awk '{print $1}')
  ref=$(echo "$line" | awk '{print $2}')
  if [[ "$ref" == refs/heads/mutation/${slice_id}-* ]]; then
    branch_name="${ref#refs/heads/}"
    matched_branches+=("$branch_name")
    matched_heads+=("$sha")
  fi
done <<< "$raw_ls"

if [ "${#matched_branches[@]}" -eq 0 ]; then
  echo "Error: No remote mutation branches found matching slice id '$slice_id'." >&2
  exit 1
fi

echo "Remote mutation branches matching slice '$slice_id' before retirement:"
for i in "${!matched_branches[@]}"; do
  echo "  ${matched_heads[$i]} refs/heads/${matched_branches[$i]}"
done

repo_root=$(git rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")
exceptions_file="$repo_root/mutation_subject_exceptions.tsv"

declare -A exc_sha
declare -A exc_used

if [ -f "$exceptions_file" ]; then
  while IFS=$'\t' read -r exc_branch exc_sha_val exc_review_by exc_reason || [ -n "$exc_branch" ]; do
    [ -z "$exc_branch" ] && continue
    [[ "$exc_branch" =~ ^# ]] && continue

    if [ -z "$exc_sha_val" ] || [ -z "$exc_review_by" ] || [ -z "$exc_reason" ]; then
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
" "$exc_review_by" "${MUTATION_CHECK_TODAY:-}" || date_rc=$?

    if [ "$date_rc" -eq 2 ]; then
      echo "Error: Exception review_by date '$exc_review_by' for '$exc_branch' is in the past." >&2
      exit 1
    elif [ "$date_rc" -eq 3 ]; then
      echo "Error: Exception review_by date '$exc_review_by' for '$exc_branch' is more than 90 days in the future." >&2
      exit 1
    elif [ "$date_rc" -eq 4 ]; then
      echo "Error: Invalid date format in review_by '$exc_review_by' for '$exc_branch'." >&2
      exit 1
    fi

    clean_b="${exc_branch#refs/heads/}"
    exc_sha["$clean_b"]="$exc_sha_val"
    exc_used["$clean_b"]=0
  done < "$exceptions_file"
fi

if [ "$dry_run" -eq 1 ]; then
  dry_dir=$(mktemp -d)
  temp_dirs+=("$dry_dir")
  git worktree add --detach "$dry_dir" origin/main >/dev/null 2>&1
  run_root="$dry_dir"
else
  run_root="$repo_root"
fi

manifest_file="$run_root/mutations/MANIFEST.tsv"
patch_dir="$run_root/mutations/$slice_id"

declare -A branch_needs_archive
declare -A branch_base_sha
declare -A branch_patch_sha
declare -A branch_needs_tag

# 3. Check every branch before writing anything
for i in "${!matched_branches[@]}"; do
  b="${matched_branches[$i]}"
  head_sha="${matched_heads[$i]}"
  leaf="${b#mutation/}"
  patch_file="$patch_dir/$leaf.patch"

  # Check archive tag on origin
  tag_remote=$(git ls-remote origin "refs/tags/archive/$leaf" | awk '{print $1}' | head -n 1)
  if [ -n "$tag_remote" ]; then
    if [ "$tag_remote" = "$head_sha" ]; then
      branch_needs_tag["$b"]=0
    else
      echo "Error: Tag 'archive/$leaf' already exists on origin pointing at $tag_remote, but branch '$b' head is $head_sha." >&2
      exit 1
    fi
  else
    branch_needs_tag["$b"]=1
  fi

  # Step 10 check: if patch and manifest row already exist and match
  already_archived=0
  if [ -f "$manifest_file" ]; then
    existing_row=$(awk -F'\t' -v repo="$repo_name" -v branch="$b" '$1 == repo && $2 == branch' "$manifest_file" || true)
    if [ -n "$existing_row" ]; then
      row_head=$(echo "$existing_row" | awk -F'\t' '{print $3}')
      row_patch_sha=$(echo "$existing_row" | awk -F'\t' '{print $5}')
      if [ -f "$patch_file" ]; then
        current_patch_sha=$(hash_file "$patch_file")
        if [ "$row_head" = "$head_sha" ] && [ "$row_patch_sha" = "$current_patch_sha" ]; then
          already_archived=1
        else
          echo "Error: Manifest row for '$b' exists but head_sha or patch_sha256 differs (manifest: $row_head / $row_patch_sha, current: $head_sha / $current_patch_sha)." >&2
          exit 1
        fi
      else
        echo "Error: Manifest row for '$b' exists but patch file '$patch_file' is missing." >&2
        exit 1
      fi
    fi
  fi

  if [ "$already_archived" -eq 1 ]; then
    branch_needs_archive["$b"]=0
    continue
  fi

  branch_needs_archive["$b"]=1

  # Fetch branch to verify its commit
  git fetch origin "$b" >/dev/null 2>&1
  base_sha=$(git merge-base origin/main "$head_sha")
  branch_base_sha["$b"]="$base_sha"

  commit_count=$(git rev-list --count "$base_sha..$head_sha")
  if [ "$commit_count" -ne 1 ]; then
    echo "Error: Branch '$b' has $commit_count commit(s) between origin/main and head; expected exactly 1." >&2
    exit 1
  fi

  # Check subject rule or exception
  if [ -n "${exc_sha[$b]:-}" ]; then
    if [ "${exc_sha[$b]}" != "$head_sha" ]; then
      echo "Error: Branch '$b' head SHA ($head_sha) does not match exception SHA (${exc_sha[$b]})." >&2
      exit 1
    fi
    exc_used["$b"]=1
  else
    commit_sha=$(git rev-list "$base_sha..$head_sha")
    subject=$(git log -n 1 --format="%s" "$commit_sha")
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

  trailers=$(git log -n 1 --format="%(trailers:key=Signed-off-by,valueonly)" "$head_sha")
  if [ -z "$trailers" ]; then
    echo "Error: Branch '$b' commit $head_sha is missing a Signed-off-by: trailer." >&2
    exit 1
  fi
done

# Check for stale exceptions matching this slice_id
for exc_b in "${!exc_sha[@]}"; do
  if [[ "$exc_b" == "mutation/${slice_id}-"* ]]; then
    if [ "${exc_used[$exc_b]:-0}" -eq 0 ]; then
      echo "Error: Stale mutation subject exception for branch '$exc_b' (expected SHA: ${exc_sha[$exc_b]}). Branch does not exist or SHA differs." >&2
      exit 1
    fi
  fi
done

# Check if any branches need archiving
any_needs_archive=0
for b in "${matched_branches[@]}"; do
  if [ "${branch_needs_archive[$b]}" -eq 1 ]; then
    any_needs_archive=1
    break
  fi
done

if [ "$any_needs_archive" -eq 1 ]; then
  mkdir -p "$patch_dir"

  # 4. Archive & 5. Verify
  for i in "${!matched_branches[@]}"; do
    b="${matched_branches[$i]}"
    if [ "${branch_needs_archive[$b]}" -eq 0 ]; then
      continue
    fi

    head_sha="${matched_heads[$i]}"
    base_sha="${branch_base_sha[$b]}"
    leaf="${b#mutation/}"
    patch_file="$patch_dir/$leaf.patch"

    # Write patch
    git format-patch --stdout "$base_sha..$head_sha" > "$patch_file"

    # Test-only hook for RM3: corrupt patch diff if env var matches leaf
    if [ -n "${RETIRE_TEST_CORRUPT_PATCH:-}" ] && [ "$RETIRE_TEST_CORRUPT_PATCH" = "$leaf" ]; then
      sed -i 's/^\+\([^+]\)/+corrupted_\1/' "$patch_file"
    fi

    # 5. Verify tree SHA matches
    verify_wt=$(mktemp -d)
    temp_dirs+=("$verify_wt")
    git worktree add --detach "$verify_wt" "$base_sha" >/dev/null 2>&1

    (
      cd "$verify_wt"
      # git am will fail if patch cannot apply cleanly
      git am "$patch_file" >/dev/null 2>&1
      am_tree=$(git rev-parse HEAD^{tree})
      expected_tree=$(git rev-parse "${head_sha}^{tree}")
      if [ "$am_tree" != "$expected_tree" ]; then
        echo "Error: Tree mismatch for patch '$patch_file'. Expected $expected_tree, got $am_tree." >&2
        exit 1
      fi
    )

    git worktree remove --force "$verify_wt" >/dev/null 2>&1 || true
    rm -rf "$verify_wt" >/dev/null 2>&1 || true

    branch_patch_sha["$b"]=$(hash_file "$patch_file")
  done

  # 6. Manifest
  if [ ! -f "$manifest_file" ]; then
    mkdir -p "$(dirname "$manifest_file")"
    printf "repo\tbranch\thead_sha\tbase_sha\tpatch_sha256\ttree_match\n" > "$manifest_file"
  fi

  for i in "${!matched_branches[@]}"; do
    b="${matched_branches[$i]}"
    if [ "${branch_needs_archive[$b]}" -eq 0 ]; then
      continue
    fi
    head_sha="${matched_heads[$i]}"
    base_sha="${branch_base_sha[$b]}"
    p_sha="${branch_patch_sha[$b]}"
    printf "%s\t%s\t%s\t%s\t%s\tyes\n" "$repo_name" "$b" "$head_sha" "$base_sha" "$p_sha" >> "$manifest_file"
  done
fi

# Track exceptions matching slice_id to remove from mutation_subject_exceptions.tsv
removed_exceptions=()
target_exceptions_file="$run_root/mutation_subject_exceptions.tsv"
if [ -f "$target_exceptions_file" ]; then
  temp_exc_file=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
      echo "$line" >> "$temp_exc_file"
      continue
    fi
    row_branch=$(echo "$line" | cut -f1)
    row_clean="${row_branch#refs/heads/}"
    if [[ "$row_clean" == "mutation/${slice_id}-"* ]]; then
      removed_exceptions+=("$row_clean")
    else
      echo "$line" >> "$temp_exc_file"
    fi
  done < "$target_exceptions_file"
  if [ "${#removed_exceptions[@]}" -gt 0 ]; then
    cp "$temp_exc_file" "$target_exceptions_file"
  fi
  rm -f "$temp_exc_file"
fi

if [ "$dry_run" -eq 1 ]; then
  echo "Dry-run completed successfully."
  echo "Would commit archive for slice '$slice_id':"
  if [ "$any_needs_archive" -eq 1 ] || [ "${#removed_exceptions[@]}" -gt 0 ]; then
    for b in "${matched_branches[@]}"; do
      if [ "${branch_needs_archive[$b]}" -eq 1 ]; then
        leaf="${b#mutation/}"
        echo "  mutations/$slice_id/$leaf.patch"
      fi
    done
    if [ "$any_needs_archive" -eq 1 ]; then
      echo "  mutations/MANIFEST.tsv"
    fi
    if [ "${#removed_exceptions[@]}" -gt 0 ]; then
      echo "  mutation_subject_exceptions.tsv"
    fi
  else
    echo "  (All branches already archived in MANIFEST.tsv; no new commit needed)"
  fi
  if [ "${#removed_exceptions[@]}" -gt 0 ]; then
    echo "Would remove from mutation_subject_exceptions.tsv:"
    for exc_row in "${removed_exceptions[@]}"; do
      echo "  $exc_row"
    done
  fi
  echo "Would create archive tags:"
  for i in "${!matched_branches[@]}"; do
    b="${matched_branches[$i]}"
    if [ "${branch_needs_tag[$b]}" -eq 1 ]; then
      leaf="${b#mutation/}"
      echo "  refs/tags/archive/$leaf -> ${matched_heads[$i]}"
    fi
  done
  echo "Would delete remote branches with leases:"
  for i in "${!matched_branches[@]}"; do
    echo "  ${matched_branches[$i]} (lease head: ${matched_heads[$i]})"
  done
  exit 0
fi

# 7. Commit and push the archive
if [ "$any_needs_archive" -eq 1 ] || [ "${#removed_exceptions[@]}" -gt 0 ]; then
  if [ "$any_needs_archive" -eq 1 ]; then
    git add mutations/
  fi
  if [ "${#removed_exceptions[@]}" -gt 0 ]; then
    git add mutation_subject_exceptions.tsv
  fi
  # Ensure no unexpected changes outside mutations/ and mutation_subject_exceptions.tsv
  status_outside=$(git status --porcelain | grep -v '^.. mutations/' | grep -v '^.. mutation_subject_exceptions.tsv' || true)
  if [ -n "$status_outside" ]; then
    echo "Error: Unexpected uncommitted changes outside mutations/ directory and mutation_subject_exceptions.tsv." >&2
    exit 1
  fi

  git commit -s -m "Mutation archive: $slice_id"
  if ! git push origin main; then
    echo "Error: Failed to push archive commit to origin main." >&2
    exit 1
  fi
fi

# Test-only hook between steps 7 and 8 (e.g. for RM4 to mutate remote branch)
if [ -n "${RETIRE_TEST_POST_ARCHIVE_HOOK:-}" ]; then
  eval "$RETIRE_TEST_POST_ARCHIVE_HOOK"
fi

# 8. Delete remote branches and create archive tags with atomic push & lease per branch and tag
push_args=()
for i in "${!matched_branches[@]}"; do
  b="${matched_branches[$i]}"
  head_sha="${matched_heads[$i]}"
  push_args+=("--force-with-lease=refs/heads/$b:$head_sha" ":refs/heads/$b")
  if [ "${branch_needs_tag[$b]}" -eq 1 ]; then
    leaf="${b#mutation/}"
    push_args+=("--force-with-lease=refs/tags/archive/$leaf:" "$head_sha:refs/tags/archive/$leaf")
  fi
done

if ! git push --atomic origin "${push_args[@]}"; then
  echo "Error: Atomic leased deletion and tag creation push failed." >&2
  exit 1
fi

# 9. Print ls-remote after retirement
echo "Remote mutation branches matching slice '$slice_id' after retirement:"
git ls-remote --heads origin "refs/heads/mutation/${slice_id}-*" || true

echo "Remote archive tags matching slice '$slice_id' after retirement:"
git ls-remote origin "refs/tags/archive/${slice_id}-*" || true

echo "Successfully retired ${#matched_branches[@]} mutation branch(es) for slice '$slice_id'."
