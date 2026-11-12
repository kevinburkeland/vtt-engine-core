#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_MUTATION="$SCRIPT_DIR/check_mutation_branches.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

setup_repo() {
  local dir="$1"
  mkdir -p "$dir"
  (
    cd "$dir"
    git init -b main >/dev/null 2>&1
    git config user.name "Tester"
    git config user.email "tester@example.com"
    echo "# Base" > README.md
    git add README.md
    git commit -s -m "Initial commit on main" >/dev/null 2>&1
  )
}

# Set up a clean default repo without exceptions for basic tests
default_repo="$TMP_DIR/default_repo"
setup_repo "$default_repo"

# MB1 an empty list with limit 20: pass, prints count 0.
empty_file="$TMP_DIR/empty.txt"
touch "$empty_file"
out1=$(cd "$default_repo" && "$CHECK_MUTATION" 20 "$empty_file")
if [[ "$out1" != *"Mutation branches count: 0"* ]]; then
  echo "FAIL: MB1 expected count 0, got: $out1" >&2
  exit 1
fi

# MB2 exactly 20 valid mutation refs with limit 20: pass.
repo2="$TMP_DIR/repo2"
setup_repo "$repo2"
f20="$TMP_DIR/20.txt"
(
  cd "$repo2"
  for i in $(seq 1 20); do
    git checkout -b "mutation/test-m$i" main >/dev/null 2>&1
    echo "content $i" > "file_$i.txt"
    git add "file_$i.txt"
    git commit -s -m "MUTATION — do not merge: m$i" >/dev/null 2>&1
    sha=$(git rev-parse HEAD)
    echo -e "$sha\trefs/heads/mutation/test-m$i" >> "$f20"
  done
  git checkout main >/dev/null 2>&1
  "$CHECK_MUTATION" 20 "$f20" >/dev/null
)

# MB3 21 mutation refs with limit 20: fail, and the output lists all 21 names.
f21="$TMP_DIR/21.txt"
for i in $(seq 1 21); do
  echo -e "0123456789abcdef0123456789abcdef01234567\trefs/heads/mutation/branch-$i" >> "$f21"
done
set +e
out3=$(cd "$default_repo" && "$CHECK_MUTATION" 20 "$f21" 2>&1)
rc3=$?
set -e
if [ "$rc3" -eq 0 ]; then
  echo "FAIL: MB3 expected failure with 21 refs and limit 20" >&2
  exit 1
fi
for i in $(seq 1 21); do
  if [[ "$out3" != *"mutation/branch-$i"* ]]; then
    echo "FAIL: MB3 output missing branch-$i" >&2
    exit 1
  fi
done

# MB4 a list with refs/heads/main, refs/heads/mutations/a, refs/heads/feature/mutation/b and 2 real mutation refs, limit 1: fail with count 2
f4="$TMP_DIR/mixed.txt"
cat << 'EOF4' > "$f4"
0123456789abcdef0123456789abcdef01234567	refs/heads/main
0123456789abcdef0123456789abcdef01234567	refs/heads/mutations/a
0123456789abcdef0123456789abcdef01234567	refs/heads/feature/mutation/b
0123456789abcdef0123456789abcdef01234567	refs/heads/mutation/real-1
0123456789abcdef0123456789abcdef01234567	refs/heads/mutation/real-2
EOF4
set +e
out4=$(cd "$default_repo" && "$CHECK_MUTATION" 1 "$f4" 2>&1)
rc4=$?
set -e
if [ "$rc4" -eq 0 ]; then
  echo "FAIL: MB4 expected failure" >&2
  exit 1
fi
if [[ "$out4" != *"Mutation branches count: 2"* ]]; then
  echo "FAIL: MB4 expected count 2, got: $out4" >&2
  exit 1
fi

# MB5 a missing list file: fail.
set +e
out5=$(cd "$default_repo" && "$CHECK_MUTATION" 20 "$TMP_DIR/does_not_exist.txt" 2>&1)
rc5=$?
set -e
if [ "$rc5" -eq 0 ]; then
  echo "FAIL: MB5 expected failure for missing file" >&2
  exit 1
fi
if [[ "$out5" != *"not found"* ]]; then
  echo "FAIL: MB5 output did not mention file not found: $out5" >&2
  exit 1
fi

# MB6 limit abc: fail. Limit missing: fail.
set +e
out6a=$(cd "$default_repo" && "$CHECK_MUTATION" abc "$empty_file" 2>&1)
rc6a=$?
out6b=$(cd "$default_repo" && "$CHECK_MUTATION" 2>&1)
rc6b=$?
set -e
if [ "$rc6a" -eq 0 ] || [[ "$out6a" != *"LIMIT"* ]]; then
  echo "FAIL: MB6 limit abc expected error: $out6a" >&2
  exit 1
fi
if [ "$rc6b" -eq 0 ] || [[ "$out6b" != *"LIMIT"* ]]; then
  echo "FAIL: MB6 missing limit expected error: $out6b" >&2
  exit 1
fi

# MB7 no list file, run inside a temporary git repo whose origin points at a path that doesn't exist: fail
repo7="$TMP_DIR/repo7"
mkdir -p "$repo7"
(
  cd "$repo7"
  git init -b main >/dev/null 2>&1
  git remote add origin /path/does/not/exist
  set +e
  out7=$("$CHECK_MUTATION" 20 2>&1)
  rc7=$?
  set -e
  if [ "$rc7" -eq 0 ]; then
    echo "FAIL: MB7 expected failure for invalid origin remote" >&2
    exit 1
  fi
)

# MB8 a correct branch passes.
repo8="$TMP_DIR/repo8"
setup_repo "$repo8"
f8="$TMP_DIR/list8.txt"
(
  cd "$repo8"
  git checkout -b "mutation/test-good" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "MUTATION — do not merge: good" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-good" > "$f8"
  git checkout main >/dev/null 2>&1
  "$CHECK_MUTATION" 20 "$f8" >/dev/null
)

# MB9 a wrong subject fails.
repo9="$TMP_DIR/repo9"
setup_repo "$repo9"
f9="$TMP_DIR/list9.txt"
(
  cd "$repo9"
  git checkout -b "mutation/test-bad" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "Wrong subject entirely" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-bad" > "$f9"
  git checkout main >/dev/null 2>&1
  set +e
  out9=$("$CHECK_MUTATION" 20 "$f9" 2>&1)
  rc9=$?
  set -e
  if [ "$rc9" -eq 0 ]; then
    echo "FAIL: MB9 expected failure on wrong subject" >&2
    exit 1
  fi
  if [[ "$out9" != *"does not match required subject"* ]]; then
    echo "FAIL: MB9 unexpected error: $out9" >&2
    exit 1
  fi
)

# MB10 the id in the subject not matching the branch fails.
repo10="$TMP_DIR/repo10"
setup_repo "$repo10"
f10="$TMP_DIR/list10.txt"
(
  cd "$repo10"
  git checkout -b "mutation/test-xyz" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "MUTATION — do not merge: abc" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-xyz" > "$f10"
  git checkout main >/dev/null 2>&1
  set +e
  out10=$("$CHECK_MUTATION" 20 "$f10" 2>&1)
  rc10=$?
  set -e
  if [ "$rc10" -eq 0 ]; then
    echo "FAIL: MB10 expected failure on mismatched id in subject" >&2
    exit 1
  fi
  if [[ "$out10" != *"MUTATION — do not merge: xyz"* ]]; then
    echo "FAIL: MB10 output did not name required prefix: $out10" >&2
    exit 1
  fi
)

# MB11 two commits fail.
repo11="$TMP_DIR/repo11"
setup_repo "$repo11"
f11="$TMP_DIR/list11.txt"
(
  cd "$repo11"
  git checkout -b "mutation/test-two" main >/dev/null 2>&1
  echo "change 1" > test1.txt && git add test1.txt && git commit -s -m "MUTATION — do not merge: two" >/dev/null 2>&1
  echo "change 2" > test2.txt && git add test2.txt && git commit -s -m "MUTATION — do not merge: two part 2" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-two" > "$f11"
  git checkout main >/dev/null 2>&1
  set +e
  out11=$("$CHECK_MUTATION" 20 "$f11" 2>&1)
  rc11=$?
  set -e
  if [ "$rc11" -eq 0 ]; then
    echo "FAIL: MB11 expected failure on two commits" >&2
    exit 1
  fi
  if [[ "$out11" != *"expected exactly 1"* ]]; then
    echo "FAIL: MB11 unexpected error: $out11" >&2
    exit 1
  fi
)

# MB12 a missing sign-off fails.
repo12="$TMP_DIR/repo12"
setup_repo "$repo12"
f12="$TMP_DIR/list12.txt"
(
  cd "$repo12"
  git checkout -b "mutation/test-unsigned" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit --no-gpg-sign -m "MUTATION — do not merge: unsigned" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-unsigned" > "$f12"
  git checkout main >/dev/null 2>&1
  set +e
  out12=$("$CHECK_MUTATION" 20 "$f12" 2>&1)
  rc12=$?
  set -e
  if [ "$rc12" -eq 0 ]; then
    echo "FAIL: MB12 expected failure on missing Signed-off-by" >&2
    exit 1
  fi
  if [[ "$out12" != *"Signed-off-by"* ]]; then
    echo "FAIL: MB12 unexpected error: $out12" >&2
    exit 1
  fi
)

# MB13 fetch failure fails closed.
repo13="$TMP_DIR/repo13"
setup_repo "$repo13"
(
  cd "$repo13"
  git remote add origin /path/does/not/exist
  set +e
  out13=$("$CHECK_MUTATION" 20 2>&1)
  rc13=$?
  set -e
  if [ "$rc13" -eq 0 ]; then
    echo "FAIL: MB13 expected failure when fetch fails" >&2
    exit 1
  fi
  if [[ "$out13" != *"Failed to fetch remote mutation branches"* ]]; then
    echo "FAIL: MB13 unexpected error: $out13" >&2
    exit 1
  fi
)

# MB14 excused branch passes.
repo14="$TMP_DIR/repo14"
setup_repo "$repo14"
f14="$TMP_DIR/list14.txt"
(
  cd "$repo14"
  git checkout -b "mutation/test-excused" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "Wrong subject that is excused" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-excused" > "$f14"
  echo -e "mutation/test-excused\t$sha\t2027-02-01\tWrong subject excused" > mutation_subject_exceptions.tsv
  git checkout main >/dev/null 2>&1
  "$CHECK_MUTATION" 20 "$f14" >/dev/null
)

# MB15 same branch at another SHA fails.
repo15="$TMP_DIR/repo15"
setup_repo "$repo15"
f15="$TMP_DIR/list15.txt"
(
  cd "$repo15"
  git checkout -b "mutation/test-badsha" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "Wrong subject excused with different sha" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-badsha" > "$f15"
  echo -e "mutation/test-badsha\t0123456789abcdef0123456789abcdef01234567\t2027-02-01\tWrong sha exception" > mutation_subject_exceptions.tsv
  git checkout main >/dev/null 2>&1
  set +e
  out15=$("$CHECK_MUTATION" 20 "$f15" 2>&1)
  rc15=$?
  set -e
  if [ "$rc15" -eq 0 ]; then
    echo "FAIL: MB15 expected failure on different SHA" >&2
    exit 1
  fi
  if [[ "$out15" != *"does not match required subject"* ]] && [[ "$out15" != *"Stale mutation subject exception"* ]]; then
    echo "FAIL: MB15 unexpected error: $out15" >&2
    exit 1
  fi
)

# MB16 stale row fails.
repo16="$TMP_DIR/repo16"
setup_repo "$repo16"
f16="$TMP_DIR/list16.txt"
(
  cd "$repo16"
  git checkout -b "mutation/test-real" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "MUTATION — do not merge: real" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-real" > "$f16"
  echo -e "mutation/test-nonexistent\t$sha\t2027-02-01\tStale row" > mutation_subject_exceptions.tsv
  git checkout main >/dev/null 2>&1
  set +e
  out16=$("$CHECK_MUTATION" 20 "$f16" 2>&1)
  rc16=$?
  set -e
  if [ "$rc16" -eq 0 ]; then
    echo "FAIL: MB16 expected failure on stale row" >&2
    exit 1
  fi
  if [[ "$out16" != *"Stale mutation subject exception"* ]]; then
    echo "FAIL: MB16 unexpected error: $out16" >&2
    exit 1
  fi
)

# MB17 past review_by fails.
repo17="$TMP_DIR/repo17"
setup_repo "$repo17"
f17="$TMP_DIR/list17.txt"
(
  cd "$repo17"
  git checkout -b "mutation/test-expired" main >/dev/null 2>&1
  echo "change" > test.txt && git add test.txt
  git commit -s -m "MUTATION — do not merge: expired" >/dev/null 2>&1
  sha=$(git rev-parse HEAD)
  echo -e "$sha\trefs/heads/mutation/test-expired" > "$f17"
  echo -e "mutation/test-expired\t$sha\t2020-01-01\tExpired row" > mutation_subject_exceptions.tsv
  git checkout main >/dev/null 2>&1
  set +e
  out17=$("$CHECK_MUTATION" 20 "$f17" 2>&1)
  rc17=$?
  set -e
  if [ "$rc17" -eq 0 ]; then
    echo "FAIL: MB17 expected failure on past review_by" >&2
    exit 1
  fi
  if [[ "$out17" != *"is in the past"* ]]; then
    echo "FAIL: MB17 unexpected error: $out17" >&2
    exit 1
  fi
)

echo "All mutation branch check self-tests passed (MB1 - MB17)."
