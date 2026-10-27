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

# 3. Check every branch before writing anything
for i in "${!matched_branches[@]}"; do
  b="${matched_branches[$i]}"
  head_sha="${matched_heads[$i]}"
  leaf="${b#mutation/}"
  patch_file="$patch_dir/$leaf.patch"

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

  commit_sha=$(git rev-list "$base_sha..$head_sha")
  subject=$(git log -n 1 --format="%s" "$commit_sha")
  prefix="MUTATION — do not merge: "
  if [[ "$subject" != "$prefix"* ]]; then
    echo "Error: Branch '$b' commit subject '$subject' does not start with '$prefix'." >&2
    exit 1
  fi

  trailers=$(git log -n 1 --format="%(trailers:key=Signed-off-by,valueonly)" "$commit_sha")
  if [ -z "$trailers" ]; then
    echo "Error: Branch '$b' commit $commit_sha is missing a Signed-off-by: trailer." >&2
    exit 1
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

if [ "$dry_run" -eq 1 ]; then
  echo "Dry-run completed successfully."
  echo "Would commit archive for slice '$slice_id':"
  if [ "$any_needs_archive" -eq 1 ]; then
    for b in "${matched_branches[@]}"; do
      if [ "${branch_needs_archive[$b]}" -eq 1 ]; then
        leaf="${b#mutation/}"
        echo "  mutations/$slice_id/$leaf.patch"
      fi
    done
    echo "  mutations/MANIFEST.tsv"
  else
    echo "  (All branches already archived in MANIFEST.tsv; no new commit needed)"
  fi
  echo "Would delete remote branches with leases:"
  for i in "${!matched_branches[@]}"; do
    echo "  ${matched_branches[$i]} (lease head: ${matched_heads[$i]})"
  done
  exit 0
fi

# 7. Commit and push the archive
if [ "$any_needs_archive" -eq 1 ]; then
  git add mutations/
  # Ensure no changes outside mutations/
  status_outside=$(git status --porcelain | grep -v '^.. mutations/' || true)
  if [ -n "$status_outside" ]; then
    echo "Error: Unexpected uncommitted changes outside mutations/ directory." >&2
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

# 8. Delete remote branches with atomic push & lease per branch
delete_args=()
for i in "${!matched_branches[@]}"; do
  b="${matched_branches[$i]}"
  head_sha="${matched_heads[$i]}"
  delete_args+=("--force-with-lease=refs/heads/$b:$head_sha" ":refs/heads/$b")
done

if ! git push --atomic origin "${delete_args[@]}"; then
  echo "Error: Atomic leased deletion push failed. One or more branch leases were refused." >&2
  exit 1
fi

# 9. Print ls-remote after retirement
echo "Remote mutation branches matching slice '$slice_id' after retirement:"
git ls-remote --heads origin "refs/heads/mutation/${slice_id}-*" || true

echo "Successfully retired ${#matched_branches[@]} mutation branch(es) for slice '$slice_id'."
