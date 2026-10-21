#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_DCO="$SCRIPT_DIR/check_dco.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -b main
git config user.name "Alice Smith"
git config user.email "alice@example.com"

# Case 1: a commit signed by its author: pass
git commit --allow-empty -m "Commit 1" -s
"$CHECK_DCO" "" HEAD >/dev/null

# Case 2: a commit with no sign-off: fail, and the output names it
git commit --allow-empty -m "Commit 2 unsigned"
bad2=$(git rev-parse --short HEAD)
base2=$(git rev-parse HEAD~1)
set +e
out2=$("$CHECK_DCO" "$base2" HEAD 2>&1)
rc2=$?
set -e
if [ "$rc2" -eq 0 ]; then
  echo "FAIL: Case 2 expected non-zero exit code" >&2
  exit 1
fi
if [[ "$out2" != *"$bad2"* ]]; then
  echo "FAIL: Case 2 output did not name $bad2: $out2" >&2
  exit 1
fi

# Case 3: a sign-off with a different email than the author: fail
git commit --allow-empty -m "Commit 3

Signed-off-by: Alice Smith <other@example.com>"
bad3=$(git rev-parse --short HEAD)
base3=$(git rev-parse HEAD~1)
set +e
out3=$("$CHECK_DCO" "$base3" HEAD 2>&1)
rc3=$?
set -e
if [ "$rc3" -eq 0 ] || [[ "$out3" != *"$bad3"* ]]; then
  echo "FAIL: Case 3 expected failure naming $bad3" >&2
  exit 1
fi

# Case 4: a sign-off with a different name than the author: fail
git commit --allow-empty -m "Commit 4

Signed-off-by: Bob Smith <alice@example.com>"
bad4=$(git rev-parse --short HEAD)
base4=$(git rev-parse HEAD~1)
set +e
out4=$("$CHECK_DCO" "$base4" HEAD 2>&1)
rc4=$?
set -e
if [ "$rc4" -eq 0 ] || [[ "$out4" != *"$bad4"* ]]; then
  echo "FAIL: Case 4 expected failure naming $bad4" >&2
  exit 1
fi

# Case 5: two sign-offs, one of them the author: pass
git commit --allow-empty -m "Commit 5

Signed-off-by: Collaborator <collab@example.com>
Signed-off-by: Alice Smith <alice@example.com>"
base5=$(git rev-parse HEAD~1)
"$CHECK_DCO" "$base5" HEAD >/dev/null

# Case 6: the words Signed-off-by: inside the body but not as a trailer (followed by more body text): fail
git commit --allow-empty -m "Commit 6

Here is body text containing
Signed-off-by: Alice Smith <alice@example.com>
followed by more body text in another paragraph.

Another body paragraph."
bad6=$(git rev-parse --short HEAD)
base6=$(git rev-parse HEAD~1)
set +e
out6=$("$CHECK_DCO" "$base6" HEAD 2>&1)
rc6=$?
set -e
if [ "$rc6" -eq 0 ] || [[ "$out6" != *"$bad6"* ]]; then
  echo "FAIL: Case 6 expected failure naming $bad6" >&2
  exit 1
fi

# Case 7: a range of three commits where only the middle one is bad: fail, and only the middle one is named
base7=$(git rev-parse HEAD)
git commit --allow-empty -m "Commit 7A" -s
sha7a=$(git rev-parse --short HEAD)
git commit --allow-empty -m "Commit 7B bad"
sha7b=$(git rev-parse --short HEAD)
git commit --allow-empty -m "Commit 7C" -s
sha7c=$(git rev-parse --short HEAD)

set +e
out7=$("$CHECK_DCO" "$base7" HEAD 2>&1)
rc7=$?
set -e
if [ "$rc7" -eq 0 ]; then
  echo "FAIL: Case 7 expected failure" >&2
  exit 1
fi
if [[ "$out7" != *"$sha7b"* ]]; then
  echo "FAIL: Case 7 did not name bad commit $sha7b" >&2
  exit 1
fi
if [[ "$out7" == *"$sha7a"* ]]; then
  echo "FAIL: Case 7 named good commit $sha7a" >&2
  exit 1
fi
if [[ "$out7" == *"$sha7c"* ]]; then
  echo "FAIL: Case 7 named good commit $sha7c" >&2
  exit 1
fi

# Case 8: empty baseline over a fully signed history of three commits passes
CLEAN_REPO="$TMP_DIR/clean_repo"
mkdir -p "$CLEAN_REPO"
cd "$CLEAN_REPO"
git init -b main
git config user.name "Alice Smith"
git config user.email "alice@example.com"
git commit --allow-empty -m "Root commit" -s
git commit --allow-empty -m "Second commit" -s
git commit --allow-empty -m "Third commit" -s
out8=$("$CHECK_DCO" "" HEAD)
if [[ "$out8" != *"Checked 3 commit(s); all carry valid DCO sign-off."* ]]; then
  echo "FAIL: Case 8 expected 3 checked commits: $out8" >&2
  exit 1
fi

# Case 9: an unsigned merge commit in range fails, and the output names the merge commit's short SHA
base9=$(git rev-parse HEAD)
git checkout -b feature-branch
git commit --allow-empty -m "Feature branch commit" -s
git checkout main
git commit --allow-empty -m "Main branch commit" -s
git merge --no-ff --no-edit feature-branch
merge9=$(git rev-parse --short HEAD)
set +e
out9=$("$CHECK_DCO" "$base9" HEAD 2>&1)
rc9=$?
set -e
if [ "$rc9" -eq 0 ]; then
  echo "FAIL: Case 9 expected failure for unsigned merge commit" >&2
  exit 1
fi
if [[ "$out9" != *"$merge9"* ]]; then
  echo "FAIL: Case 9 output did not name unsigned merge $merge9: $out9" >&2
  exit 1
fi

# Case 9b: a merge commit made with --signoff by its author passes
base9b=$(git rev-parse HEAD)
git checkout -b feature-branch-signed
git commit --allow-empty -m "Feature branch signed commit" -s
git checkout main
git commit --allow-empty -m "Main branch signed commit" -s
git merge --no-ff --no-edit --signoff feature-branch-signed
out9b=$("$CHECK_DCO" "$base9b" HEAD)
if [[ "$out9b" != *"Checked 3 commit(s); all carry valid DCO sign-off."* ]]; then
  echo "FAIL: Case 9b expected 3 commits including signed merge commit: $out9b" >&2
  exit 1
fi

# Case 10: empty baseline with an unsigned older commit and a signed newest commit fails
PUSH_REPO="$TMP_DIR/push_repo"
mkdir -p "$PUSH_REPO"
cd "$PUSH_REPO"
git init -b main
git config user.name "Alice Smith"
git config user.email "alice@example.com"
git commit --allow-empty -m "Old unsigned root commit"
bad10=$(git rev-parse --short HEAD)
git commit --allow-empty -m "Pushed commit" -s
set +e
out10=$("$CHECK_DCO" "" HEAD 2>&1)
rc10=$?
set -e
if [ "$rc10" -eq 0 ]; then
  echo "FAIL: Case 10 expected failure" >&2
  exit 1
fi
if [[ "$out10" != *"$bad10"* ]]; then
  echo "FAIL: Case 10 output did not name $bad10: $out10" >&2
  exit 1
fi

echo "All DCO test cases passed successfully."
