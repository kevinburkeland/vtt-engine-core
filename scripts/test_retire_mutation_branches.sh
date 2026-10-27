#!/usr/bin/env bash
set -euo pipefail

# scripts/test_retire_mutation_branches.sh
# Self-test suite for scripts/retire_mutation_branches.sh (RM1 - RM12).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETIRE_SCRIPT="$SCRIPT_DIR/retire_mutation_branches.sh"

TMP_BASE=$(mktemp -d)
trap 'rm -rf "$TMP_BASE"' EXIT

setup_test_env() {
  local name="$1"
  local env_dir="$TMP_BASE/$name"
  mkdir -p "$env_dir"

  local bare_origin="$env_dir/origin.git"
  git init --bare -b main "$bare_origin" >/dev/null 2>&1

  local local_repo="$env_dir/local"
  git init -b main "$local_repo" >/dev/null 2>&1

  (
    cd "$local_repo"
    git config user.name "Test Committer"
    git config user.email "test@example.com"
    mkdir -p scripts mutations
    cp "$RETIRE_SCRIPT" scripts/retire_mutation_branches.sh
    chmod +x scripts/retire_mutation_branches.sh
    echo "# Test Repo" > README.md
    git add .
    git commit -s -m "Initial commit on main" >/dev/null 2>&1
    git remote add origin "$bare_origin"
    git push -u origin main >/dev/null 2>&1
  )

  echo "$env_dir"
}

create_branch() {
  local repo="$1"
  local leaf="$2"
  local msg="${3:-MUTATION — do not merge: $leaf}"
  local signoff="${4:-yes}"

  (
    cd "$repo"
    git checkout -b "mutation/$leaf" main >/dev/null 2>&1
    echo "mutation content for $leaf" > "file_$leaf.txt"
    git add .
    if [ "$signoff" = "yes" ]; then
      git commit -s -m "$msg" >/dev/null 2>&1
    else
      git commit --no-gpg-sign -m "$msg" >/dev/null 2>&1
    fi
    git push origin "mutation/$leaf" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1
  )
}

# ------------------------------------------------------------------------------
# RM1: two good branches. Patches written, two rows appended, one archive commit
# on remote main touching only mutations/, both branches gone.
# ------------------------------------------------------------------------------
echo "Running RM1..."
env1=$(setup_test_env "rm1")
repo1="$env1/local"
bare1="$env1/origin.git"
create_branch "$repo1" "cs2-a"
create_branch "$repo1" "cs2-b"

(
  cd "$repo1"
  ./scripts/retire_mutation_branches.sh cs2
)

# Assertions
[ -f "$repo1/mutations/cs2/cs2-a.patch" ] || { echo "FAIL RM1: cs2-a.patch missing"; exit 1; }
[ -f "$repo1/mutations/cs2/cs2-b.patch" ] || { echo "FAIL RM1: cs2-b.patch missing"; exit 1; }
manifest_rows=$(tail -n +2 "$repo1/mutations/MANIFEST.tsv" | wc -l)
[ "$manifest_rows" -eq 2 ] || { echo "FAIL RM1: expected 2 rows in manifest, got $manifest_rows"; exit 1; }

remote_head_commit=$(git -C "$bare1" log -n 1 --format="%s" main)
[[ "$remote_head_commit" == "Mutation archive: cs2" ]] || { echo "FAIL RM1: unexpected remote main commit: $remote_head_commit"; exit 1; }

# Archive commit must touch only mutations/
changed_files=$(git -C "$bare1" diff-tree --no-commit-id --name-only -r HEAD)
for f in $changed_files; do
  [[ "$f" == mutations/* ]] || { echo "FAIL RM1: commit touches outside mutations/: $f"; exit 1; }
done

# Remote branches must be gone
rem_branches=$(git -C "$bare1" branch -l 'mutation/cs2-*')
[ -z "$rem_branches" ] || { echo "FAIL RM1: branches not deleted on remote: $rem_branches"; exit 1; }

# ------------------------------------------------------------------------------
# RM2: one of two branches has two commits. Fails; both branches still exist;
# remote main unchanged.
# ------------------------------------------------------------------------------
echo "Running RM2..."
env2=$(setup_test_env "rm2")
repo2="$env2/local"
bare2="$env2/origin.git"
create_branch "$repo2" "cs2-a"

(
  cd "$repo2"
  git checkout -b "mutation/cs2-b" main >/dev/null 2>&1
  echo "c1" > f1.txt && git add f1.txt && git commit -s -m "MUTATION — do not merge: c1" >/dev/null 2>&1
  echo "c2" > f2.txt && git add f2.txt && git commit -s -m "MUTATION — do not merge: c2" >/dev/null 2>&1
  git push origin "mutation/cs2-b" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
)

remote_main_before=$(git -C "$bare2" rev-parse main)
set +e
out2=$(cd "$repo2" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc2=$?
set -e
[ "$rc2" -ne 0 ] || { echo "FAIL RM2: expected script failure"; exit 1; }
remote_main_after=$(git -C "$bare2" rev-parse main)
[ "$remote_main_before" = "$remote_main_after" ] || { echo "FAIL RM2: remote main changed"; exit 1; }
[ -n "$(git -C "$bare2" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM2: branch cs2-a deleted"; exit 1; }
[ -n "$(git -C "$bare2" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM2: branch cs2-b deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM3: a patch that doesn't rebuild the tree. Fails; nothing committed, nothing deleted.
# ------------------------------------------------------------------------------
echo "Running RM3..."
env3=$(setup_test_env "rm3")
repo3="$env3/local"
bare3="$env3/origin.git"
create_branch "$repo3" "cs2-a"
create_branch "$repo3" "cs2-b"

remote_main_before=$(git -C "$bare3" rev-parse main)
set +e
out3=$(cd "$repo3" && RETIRE_TEST_CORRUPT_PATCH="cs2-a" ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc3=$?
set -e
[ "$rc3" -ne 0 ] || { echo "FAIL RM3: expected failure when patch is corrupted"; exit 1; }
remote_main_after=$(git -C "$bare3" rev-parse main)
[ "$remote_main_before" = "$remote_main_after" ] || { echo "FAIL RM3: remote main changed"; exit 1; }
[ -n "$(git -C "$bare3" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM3: branch cs2-a deleted"; exit 1; }
[ -n "$(git -C "$bare3" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM3: branch cs2-b deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM4: a branch moves after the archive push but before the delete.
# The lease refuses, atomic push deletes nothing, run fails.
# ------------------------------------------------------------------------------
echo "Running RM4..."
env4=$(setup_test_env "rm4")
repo4="$env4/local"
bare4="$env4/origin.git"
create_branch "$repo4" "cs2-a"
create_branch "$repo4" "cs2-b"

# We use RETIRE_TEST_POST_ARCHIVE_HOOK to mutate mutation/cs2-a on bare origin before atomic delete push
hook4="git -C '$bare4' branch -f mutation/cs2-a HEAD"
set +e
out4=$(cd "$repo4" && RETIRE_TEST_POST_ARCHIVE_HOOK="$hook4" ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc4=$?
set -e
[ "$rc4" -ne 0 ] || { echo "FAIL RM4: expected failure when lease refused"; exit 1; }
# Neither branch should be deleted because atomic push failed
[ -n "$(git -C "$bare4" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM4: cs2-a was deleted"; exit 1; }
[ -n "$(git -C "$bare4" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM4: cs2-b was deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM5: ls-remote fails (origin points to invalid path). Fails closed; no commit.
# ------------------------------------------------------------------------------
echo "Running RM5..."
env5=$(setup_test_env "rm5")
repo5="$env5/local"
(
  cd "$repo5"
  git remote set-url origin /path/does/not/exist
)
set +e
out5=$(cd "$repo5" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc5=$?
set -e
[ "$rc5" -ne 0 ] || { echo "FAIL RM5: expected failure for invalid origin"; exit 1; }

# ------------------------------------------------------------------------------
# RM6: no branch matches the slice id. Fails.
# ------------------------------------------------------------------------------
echo "Running RM6..."
env6=$(setup_test_env "rm6")
repo6="$env6/local"
create_branch "$repo6" "other-a"

set +e
out6=$(cd "$repo6" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc6=$?
set -e
[ "$rc6" -ne 0 ] || { echo "FAIL RM6: expected failure when no branches match"; exit 1; }

# ------------------------------------------------------------------------------
# RM7: --dry-run. Exit 0, no local commit, remote unchanged, working tree clean.
# ------------------------------------------------------------------------------
echo "Running RM7..."
env7=$(setup_test_env "rm7")
repo7="$env7/local"
bare7="$env7/origin.git"
create_branch "$repo7" "cs2-a"
create_branch "$repo7" "cs2-b"

remote_main_before=$(git -C "$bare7" rev-parse main)
local_head_before=$(git -C "$repo7" rev-parse HEAD)

out7=$(cd "$repo7" && ./scripts/retire_mutation_branches.sh cs2 --dry-run)
local_head_after=$(git -C "$repo7" rev-parse HEAD)
remote_main_after=$(git -C "$bare7" rev-parse main)

[ "$local_head_before" = "$local_head_after" ] || { echo "FAIL RM7: local HEAD changed"; exit 1; }
[ "$remote_main_before" = "$remote_main_after" ] || { echo "FAIL RM7: remote main changed"; exit 1; }
[ -z "$(git -C "$repo7" status --porcelain)" ] || { echo "FAIL RM7: working tree dirty"; exit 1; }
[ -n "$(git -C "$bare7" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM7: cs2-a was deleted"; exit 1; }
[ -n "$(git -C "$bare7" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM7: cs2-b was deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM8: the archive push is rejected (pre-receive hook on bare origin rejects main).
# Fails; no branch deleted.
# ------------------------------------------------------------------------------
echo "Running RM8..."
env8=$(setup_test_env "rm8")
repo8="$env8/local"
bare8="$env8/origin.git"
create_branch "$repo8" "cs2-a"
create_branch "$repo8" "cs2-b"

# Pre-receive hook rejecting push to main
cat << 'HOOK' > "$bare8/hooks/pre-receive"
#!/usr/bin/env bash
while read oldrev newrev refname; do
  if [ "$refname" = "refs/heads/main" ]; then
    echo "Push to main rejected by test hook" >&2
    exit 1
  fi
done
HOOK
chmod +x "$bare8/hooks/pre-receive"

set +e
out8=$(cd "$repo8" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc8=$?
set -e
[ "$rc8" -ne 0 ] || { echo "FAIL RM8: expected failure when push to main rejected"; exit 1; }
[ -n "$(git -C "$bare8" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM8: cs2-a deleted"; exit 1; }
[ -n "$(git -C "$bare8" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM8: cs2-b deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM9: rerun after RM4's failure, with the moved branch reset to its archived head.
# Completes the delete with no second archive commit and no duplicate rows.
# ------------------------------------------------------------------------------
echo "Running RM9..."
# Re-use env4 where archive was pushed to main but delete was rejected
(
  cd "$repo4"
  # Fetch archived head from MANIFEST.tsv
  archived_head=$(awk -F'\t' '$2 == "mutation/cs2-a" {print $3}' mutations/MANIFEST.tsv)
  # Reset remote cs2-a back to archived head
  git -C "$bare4" update-ref refs/heads/mutation/cs2-a "$archived_head"

  # Rerun retirement
  ./scripts/retire_mutation_branches.sh cs2
)

# Both branches now deleted on remote
[ -z "$(git -C "$bare4" branch -l 'mutation/cs2-*')" ] || { echo "FAIL RM9: branches still present on remote"; exit 1; }
manifest_rows9=$(tail -n +2 "$repo4/mutations/MANIFEST.tsv" | wc -l)
[ "$manifest_rows9" -eq 2 ] || { echo "FAIL RM9: expected exactly 2 manifest rows, got $manifest_rows9"; exit 1; }

# ------------------------------------------------------------------------------
# RM10: branches mutation/cs2-a and mutation/cs21-a exist; retiring cs2 deletes
# only cs2-a.
# ------------------------------------------------------------------------------
echo "Running RM10..."
env10=$(setup_test_env "rm10")
repo10="$env10/local"
bare10="$env10/origin.git"
create_branch "$repo10" "cs2-a"
create_branch "$repo10" "cs21-a"

(
  cd "$repo10"
  ./scripts/retire_mutation_branches.sh cs2
)

[ -z "$(git -C "$bare10" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM10: cs2-a not deleted"; exit 1; }
[ -n "$(git -C "$bare10" branch -l 'mutation/cs21-a')" ] || { echo "FAIL RM10: cs21-a was wrongly deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM11: a dirty working tree. Fails before touching anything.
# ------------------------------------------------------------------------------
echo "Running RM11..."
env11=$(setup_test_env "rm11")
repo11="$env11/local"
create_branch "$repo11" "cs2-a"

(
  cd "$repo11"
  echo "dirty modification" >> README.md
)

set +e
out11=$(cd "$repo11" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc11=$?
set -e
[ "$rc11" -ne 0 ] || { echo "FAIL RM11: expected failure on dirty working tree"; exit 1; }
[[ "$out11" == *"dirty"* ]] || { echo "FAIL RM11: unexpected error message: $out11"; exit 1; }

# ------------------------------------------------------------------------------
# RM12: a branch whose one commit has no Signed-off-by:. Fails; nothing deleted.
# ------------------------------------------------------------------------------
echo "Running RM12..."
env12=$(setup_test_env "rm12")
repo12="$env12/local"
bare12="$env12/origin.git"
create_branch "$repo12" "cs2-unsigned" "MUTATION — do not merge: unsigned" "no"

set +e
out12=$(cd "$repo12" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc12=$?
set -e
[ "$rc12" -ne 0 ] || { echo "FAIL RM12: expected failure on missing sign-off"; exit 1; }
[[ "$out12" == *"Signed-off-by"* ]] || { echo "FAIL RM12: unexpected error message: $out12"; exit 1; }
[ -n "$(git -C "$bare12" branch -l 'mutation/cs2-unsigned')" ] || { echo "FAIL RM12: unsigned branch was deleted"; exit 1; }

echo "All retire mutation branch self-tests passed (RM1 - RM12)."
