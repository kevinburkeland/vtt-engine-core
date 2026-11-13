#!/usr/bin/env bash
set -euo pipefail

# scripts/test_retire_mutation_branches.sh
# Self-test suite for scripts/retire_mutation_branches.sh (RM1 - RM15).

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
    if [ -f "$SCRIPT_DIR/check_mutation_branches.sh" ]; then
      cp "$SCRIPT_DIR/check_mutation_branches.sh" scripts/check_mutation_branches.sh
      chmod +x scripts/check_mutation_branches.sh
    fi
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
  local branch_id="${leaf#*-}"
  local msg="${3:-MUTATION — do not merge: $branch_id}"
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

head_a1=$(git -C "$bare1" rev-parse refs/heads/mutation/cs2-a)
head_b1=$(git -C "$bare1" rev-parse refs/heads/mutation/cs2-b)

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

# RM1 extended: archive/cs2-a and archive/cs2-b exist on bare origin and point at the two old branch heads
tag_a1=$(git -C "$bare1" rev-parse refs/tags/archive/cs2-a 2>/dev/null || true)
tag_b1=$(git -C "$bare1" rev-parse refs/tags/archive/cs2-b 2>/dev/null || true)
[ "$tag_a1" = "$head_a1" ] || { echo "FAIL RM1: archive/cs2-a missing or mismatch on remote"; exit 1; }
[ "$tag_b1" = "$head_b1" ] || { echo "FAIL RM1: archive/cs2-b missing or mismatch on remote"; exit 1; }

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
# RM7 extended: the dry run prints both tag names and creates no tag.
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
echo "$out7" | grep -q "archive/cs2-a" || { echo "FAIL RM7: dry-run did not mention archive/cs2-a"; exit 1; }
echo "$out7" | grep -q "archive/cs2-b" || { echo "FAIL RM7: dry-run did not mention archive/cs2-b"; exit 1; }
[ -z "$(git -C "$bare7" tag -l 'archive/*')" ] || { echo "FAIL RM7: tags created during dry run"; exit 1; }

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

# ------------------------------------------------------------------------------
# RM13: a pre-receive hook on bare origin refuses any ref under refs/tags/.
# Run fails, both branches still exist, and no tag exists.
# ------------------------------------------------------------------------------
echo "Running RM13..."
env13=$(setup_test_env "rm13")
repo13="$env13/local"
bare13="$env13/origin.git"
create_branch "$repo13" "cs2-a"
create_branch "$repo13" "cs2-b"

cat << 'HOOK' > "$bare13/hooks/pre-receive"
#!/usr/bin/env bash
while read oldrev newrev refname; do
  if [[ "$refname" == refs/tags/* ]]; then
    echo "Push of tag rejected by test hook: $refname" >&2
    exit 1
  fi
done
HOOK
chmod +x "$bare13/hooks/pre-receive"

set +e
out13=$(cd "$repo13" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc13=$?
set -e
[ "$rc13" -ne 0 ] || { echo "FAIL RM13: expected failure when tags rejected"; exit 1; }
[ -n "$(git -C "$bare13" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM13: cs2-a deleted despite failed push"; exit 1; }
[ -n "$(git -C "$bare13" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM13: cs2-b deleted despite failed push"; exit 1; }
[ -z "$(git -C "$bare13" tag -l 'archive/*')" ] || { echo "FAIL RM13: archive tag created despite failure"; exit 1; }

# ------------------------------------------------------------------------------
# RM14: archive/cs2-a already exists on origin pointing at some other commit.
# Run fails naming the tag; no archive commit was pushed, no branch deleted.
# ------------------------------------------------------------------------------
echo "Running RM14..."
env14=$(setup_test_env "rm14")
repo14="$env14/local"
bare14="$env14/origin.git"
create_branch "$repo14" "cs2-a"
create_branch "$repo14" "cs2-b"

remote_main_before=$(git -C "$bare14" rev-parse main)
git -C "$bare14" tag "archive/cs2-a" main

set +e
out14=$(cd "$repo14" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc14=$?
set -e
[ "$rc14" -ne 0 ] || { echo "FAIL RM14: expected failure when archive tag points to other commit"; exit 1; }
echo "$out14" | grep -q "archive/cs2-a" || { echo "FAIL RM14: error message does not name archive/cs2-a: $out14"; exit 1; }
remote_main_after=$(git -C "$bare14" rev-parse main)
[ "$remote_main_before" = "$remote_main_after" ] || { echo "FAIL RM14: archive commit was pushed to main"; exit 1; }
[ -n "$(git -C "$bare14" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM14: cs2-a deleted"; exit 1; }
[ -n "$(git -C "$bare14" branch -l 'mutation/cs2-b')" ] || { echo "FAIL RM14: cs2-b deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM15: archive/cs2-a already exists pointing at mutation/cs2-a's head.
# Run succeeds, deletes both branches, and creates only archive/cs2-b.
# ------------------------------------------------------------------------------
echo "Running RM15..."
env15=$(setup_test_env "rm15")
repo15="$env15/local"
bare15="$env15/origin.git"
create_branch "$repo15" "cs2-a"
create_branch "$repo15" "cs2-b"

head_a15=$(git -C "$bare15" rev-parse refs/heads/mutation/cs2-a)
head_b15=$(git -C "$bare15" rev-parse refs/heads/mutation/cs2-b)
git -C "$bare15" tag "archive/cs2-a" "$head_a15"

(
  cd "$repo15"
  ./scripts/retire_mutation_branches.sh cs2
)

[ -z "$(git -C "$bare15" branch -l 'mutation/cs2-*')" ] || { echo "FAIL RM15: branches not deleted"; exit 1; }
tag_a15=$(git -C "$bare15" rev-parse refs/tags/archive/cs2-a)
tag_b15=$(git -C "$bare15" rev-parse refs/tags/archive/cs2-b 2>/dev/null || true)
[ "$tag_a15" = "$head_a15" ] || { echo "FAIL RM15: archive/cs2-a mismatch"; exit 1; }
[ "$tag_b15" = "$head_b15" ] || { echo "FAIL RM15: archive/cs2-b missing or mismatch"; exit 1; }

# ------------------------------------------------------------------------------
# RM16: a branch whose subject id doesn't match the branch name. Fails.
# ------------------------------------------------------------------------------
echo "Running RM16..."
env16=$(setup_test_env "rm16")
repo16="$env16/local"
bare16="$env16/origin.git"
create_branch "$repo16" "cs2-a" "MUTATION — do not merge: wrong" "yes"

set +e
out16=$(cd "$repo16" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc16=$?
set -e
[ "$rc16" -ne 0 ] || { echo "FAIL RM16: expected failure on mismatched id in subject"; exit 1; }
[[ "$out16" == *"MUTATION — do not merge: a"* ]] || { echo "FAIL RM16: unexpected error message: $out16"; exit 1; }
[ -n "$(git -C "$bare16" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM16: branch deleted despite error"; exit 1; }

# ------------------------------------------------------------------------------
# RM17: an excused branch with wrong subject passes when exact SHA is in exceptions.
# ------------------------------------------------------------------------------
echo "Running RM17..."
env17=$(setup_test_env "rm17")
repo17="$env17/local"
bare17="$env17/origin.git"
create_branch "$repo17" "cs2-a" "Wrong subject excused" "yes"
head_a17=$(git -C "$bare17" rev-parse refs/heads/mutation/cs2-a)

(
  cd "$repo17"
  echo -e "mutation/cs2-a\t$head_a17\t2027-02-01\tExcused wrong subject" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exception" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
  ./scripts/retire_mutation_branches.sh cs2
)
[ -z "$(git -C "$bare17" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM17: branch not deleted"; exit 1; }

# ------------------------------------------------------------------------------
# RM18: an excused branch fails when its head is at another SHA (the other-SHA case).
# ------------------------------------------------------------------------------
echo "Running RM18..."
env18=$(setup_test_env "rm18")
repo18="$env18/local"
bare18="$env18/origin.git"
create_branch "$repo18" "cs2-a" "Wrong subject excused" "yes"

(
  cd "$repo18"
  echo -e "mutation/cs2-a\t0123456789abcdef0123456789abcdef01234567\t2027-02-01\tDifferent sha" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exception" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
)
set +e
out18=$(cd "$repo18" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc18=$?
set -e
[ "$rc18" -ne 0 ] || { echo "FAIL RM18: expected failure on different SHA"; exit 1; }
[[ "$out18" == *"does not match exception SHA"* ]] || { echo "FAIL RM18: unexpected error: $out18"; exit 1; }
[ -n "$(git -C "$bare18" branch -l 'mutation/cs2-a')" ] || { echo "FAIL RM18: branch deleted despite error"; exit 1; }

# ------------------------------------------------------------------------------
# RM19: stale row in mutation_subject_exceptions.tsv matching prefix fails.
# ------------------------------------------------------------------------------
echo "Running RM19..."
env19=$(setup_test_env "rm19")
repo19="$env19/local"
bare19="$env19/origin.git"
create_branch "$repo19" "cs2-a"

(
  cd "$repo19"
  echo -e "mutation/cs2-stale\t0123456789abcdef0123456789abcdef01234567\t2027-02-01\tStale exception" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exception" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
)
set +e
out19=$(cd "$repo19" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc19=$?
set -e
[ "$rc19" -ne 0 ] || { echo "FAIL RM19: expected failure on stale row"; exit 1; }
[[ "$out19" == *"Stale mutation subject exception"* ]] || { echo "FAIL RM19: unexpected error: $out19"; exit 1; }

# ------------------------------------------------------------------------------
# RM20: exception row with review_by in the past fails.
# ------------------------------------------------------------------------------
echo "Running RM20..."
env20=$(setup_test_env "rm20")
repo20="$env20/local"
bare20="$env20/origin.git"
create_branch "$repo20" "cs2-a"

(
  cd "$repo20"
  head_a20=$(git -C "$bare20" rev-parse refs/heads/mutation/cs2-a)
  echo -e "mutation/cs2-a\t$head_a20\t2020-01-01\tExpired exception" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exception" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
)
set +e
out20=$(cd "$repo20" && ./scripts/retire_mutation_branches.sh cs2 2>&1)
rc20=$?
set -e
[ "$rc20" -ne 0 ] || { echo "FAIL RM20: expected failure on past review_by"; exit 1; }
[[ "$out20" == *"is in the past"* ]] || { echo "FAIL RM20: unexpected error: $out20"; exit 1; }

# ------------------------------------------------------------------------------
# RM21: retiring a prefix with rows in mutation_subject_exceptions.tsv removes
# them in the archive commit, preserves other rows, and check_mutation_branches passes.
# ------------------------------------------------------------------------------
echo "Running RM21..."
env21=$(setup_test_env "rm21")
repo21="$env21/local"
bare21="$env21/origin.git"
create_branch "$repo21" "cs2-a"
create_branch "$repo21" "cs2-b"
create_branch "$repo21" "other-x"

(
  cd "$repo21"
  head_a21=$(git -C "$bare21" rev-parse refs/heads/mutation/cs2-a)
  head_b21=$(git -C "$bare21" rev-parse refs/heads/mutation/cs2-b)
  head_other=$(git -C "$bare21" rev-parse refs/heads/mutation/other-x)
  printf "# Header\nmutation/cs2-a\t%s\t2027-02-01\tRow 1\nmutation/other-x\t%s\t2027-02-01\tKeep this\nmutation/cs2-b\t%s\t2027-02-01\tRow 2\n" "$head_a21" "$head_other" "$head_b21" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exceptions" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
)

(cd "$repo21" && ./scripts/retire_mutation_branches.sh cs2)
# Check that the two cs2 rows were removed from mutation_subject_exceptions.tsv in main
grep -q "mutation/cs2-a" "$repo21/mutation_subject_exceptions.tsv" && { echo "FAIL RM21: cs2-a still in exceptions"; exit 1; }
grep -q "mutation/cs2-b" "$repo21/mutation_subject_exceptions.tsv" && { echo "FAIL RM21: cs2-b still in exceptions"; exit 1; }
grep -q "mutation/other-x" "$repo21/mutation_subject_exceptions.tsv" || { echo "FAIL RM21: other-x missing from exceptions"; exit 1; }
# check_mutation_branches passes afterwards
(cd "$repo21" && ./scripts/check_mutation_branches.sh 20) || { echo "FAIL RM21: check_mutation_branches failed after retirement"; exit 1; }

# ------------------------------------------------------------------------------
# RM22: --dry-run shows removed exception rows and does not edit files.
# ------------------------------------------------------------------------------
echo "Running RM22..."
env22=$(setup_test_env "rm22")
repo22="$env22/local"
bare22="$env22/origin.git"
create_branch "$repo22" "cs2-a"

(
  cd "$repo22"
  head_a22=$(git -C "$bare22" rev-parse refs/heads/mutation/cs2-a)
  printf "mutation/cs2-a\t%s\t2027-02-01\tRow 1\n" "$head_a22" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exception" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
)

out22=$(cd "$repo22" && ./scripts/retire_mutation_branches.sh cs2 --dry-run)
[[ "$out22" == *"Would remove from mutation_subject_exceptions.tsv:"* ]] || { echo "FAIL RM22: missing dry-run notice: $out22"; exit 1; }
[[ "$out22" == *"mutation/cs2-a"* ]] || { echo "FAIL RM22: missing branch name in dry-run output"; exit 1; }
grep -q "mutation/cs2-a" "$repo22/mutation_subject_exceptions.tsv" || { echo "FAIL RM22: dry-run modified exceptions file"; exit 1; }

# ------------------------------------------------------------------------------
# RM23: prefix with no rows leaves mutation_subject_exceptions.tsv byte-identical.
# ------------------------------------------------------------------------------
echo "Running RM23..."
env23=$(setup_test_env "rm23")
repo23="$env23/local"
bare23="$env23/origin.git"
create_branch "$repo23" "cs2-a"

(
  cd "$repo23"
  printf "# Header\nmutation/other-x\t0123456789abcdef0123456789abcdef01234567\t2027-02-01\tKeep this\n" > mutation_subject_exceptions.tsv
  git add mutation_subject_exceptions.tsv
  git commit -s -m "Add exception" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
)
hash_before=$(sha256sum "$repo23/mutation_subject_exceptions.tsv" | awk '{print $1}')
(cd "$repo23" && ./scripts/retire_mutation_branches.sh cs2)
hash_after=$(sha256sum "$repo23/mutation_subject_exceptions.tsv" | awk '{print $1}')
[ "$hash_before" = "$hash_after" ] || { echo "FAIL RM23: exceptions file changed"; exit 1; }

echo "All retire mutation branch self-tests passed (RM1 - RM23)."
