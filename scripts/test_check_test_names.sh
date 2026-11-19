#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_test_names.py"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

setup_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -b main >/dev/null 2>&1
  git config user.name "Test Runner"
  git config user.email "test@example.com"
}

# TN1: deleting a test fails, naming it.
(
  repo="$TMP_DIR/repo_tn1"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/alpha_test.dart
void main() {
  test('alpha test', () {});
}
EOF
  git add test/alpha_test.dart
  git commit -m "add test" >/dev/null

  cat << 'EOF' > test/alpha_test.dart
void main() {}
EOF
  git add test/alpha_test.dart
  git commit -m "delete test" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN1 expected failure when deleting test" >&2
    exit 1
  fi
  if [[ "$out" != *"alpha test"* ]]; then
    echo "FAIL: TN1 expected output to name 'alpha test', got: $out" >&2
    exit 1
  fi
)

# TN2: moving a test to another file in the same commit passes.
(
  repo="$TMP_DIR/repo_tn2"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/first_test.dart
void main() {
  test('bravo test', () {});
}
EOF
  git add test/first_test.dart
  git commit -m "add test in first" >/dev/null

  cat << 'EOF' > test/first_test.dart
void main() {}
EOF
  cat << 'EOF' > test/second_test.dart
void main() {
  test('bravo test', () {});
}
EOF
  git add test/first_test.dart test/second_test.dart
  git commit -m "move test to second" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN2 expected pass when moving test between files, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN3: deleting a test with a reasoned list entry passes.
(
  repo="$TMP_DIR/repo_tn3"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/charlie_test.dart
void main() {
  test('charlie test', () {});
}
EOF
  git add test/charlie_test.dart
  git commit -m "add charlie test" >/dev/null

  cat << 'EOF' > test/charlie_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names list
# Rows below this line are append-only (Cleanup slice 14).
charlie test | deprecated feature removed
EOF
  git add test/charlie_test.dart test/removed_test_names.txt
  git commit -m "remove charlie test with reason" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN3 expected pass when removed test has reason, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN4: a list entry with an empty reason fails.
(
  repo="$TMP_DIR/repo_tn4"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/delta_test.dart
void main() {
  test('delta test', () {});
}
EOF
  git add test/delta_test.dart
  git commit -m "add delta test" >/dev/null

  cat << 'EOF' > test/delta_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names list
# Rows below this line are append-only (Cleanup slice 14).
delta test |
EOF
  git add test/delta_test.dart test/removed_test_names.txt
  git commit -m "remove delta test with empty reason" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN4 expected failure when list entry has empty reason" >&2
    exit 1
  fi
  if [[ "$out" != *"empty reason"* ]]; then
    echo "FAIL: TN4 expected output to mention empty reason, got: $out" >&2
    exit 1
  fi
)

# TN5: renaming a test fails, naming the old name.
(
  repo="$TMP_DIR/repo_tn5"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/echo_test.dart
void main() {
  test('echo old name', () {});
}
EOF
  git add test/echo_test.dart
  git commit -m "add test with old name" >/dev/null

  cat << 'EOF' > test/echo_test.dart
void main() {
  test('echo new name', () {});
}
EOF
  git add test/echo_test.dart
  git commit -m "rename test" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN5 expected failure when renaming test" >&2
    exit 1
  fi
  if [[ "$out" != *"echo old name"* ]]; then
    echo "FAIL: TN5 expected output to name old test 'echo old name', got: $out" >&2
    exit 1
  fi
)

# TN6: a name split as adjacent literals, a raw string, a triple-quoted string and a literal on the next line are each extracted (deleting each one fails, naming the joined text).
(
  repo="$TMP_DIR/repo_tn6"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/complex_test.dart
void main() {
  test('part one ' 'part two', () {});
  test(r'raw string test', () {});
  test('''triple quoted test''', () {});
  test(
      'next line literal test', () {});
}
EOF
  git add test/complex_test.dart
  git commit -m "add complex string tests" >/dev/null

  cat << 'EOF' > test/complex_test.dart
void main() {}
EOF
  git add test/complex_test.dart
  git commit -m "delete complex string tests" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN6 expected failure when deleting complex tests" >&2
    exit 1
  fi
  for name in "part one part two" "raw string test" "triple quoted test" "next line literal test"; do
    if [[ "$out" != *"$name"* ]]; then
      echo "FAIL: TN6 expected output to contain '$name', got: $out" >&2
      exit 1
    fi
  done
)

# TN7: deleting a test in an early commit, then re-adding a different test in a later commit, still fails (history is walked, not just the endpoints).
(
  repo="$TMP_DIR/repo_tn7"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/walk_test.dart
void main() {
  test('initial test', () {});
}
EOF
  git add test/walk_test.dart
  git commit -m "initial test" >/dev/null

  cat << 'EOF' > test/walk_test.dart
void main() {}
EOF
  git add test/walk_test.dart
  git commit -m "delete initial test" >/dev/null

  cat << 'EOF' > test/walk_test.dart
void main() {
  test('replacement test', () {});
}
EOF
  git add test/walk_test.dart
  git commit -m "add replacement test" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~2 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN7 expected failure when walking history with deleted test" >&2
    exit 1
  fi
  if [[ "$out" != *"initial test"* ]]; then
    echo "FAIL: TN7 expected output to name 'initial test', got: $out" >&2
    exit 1
  fi
)

# TN8: a commit that doesn't touch a test file is checked and passes.
(
  repo="$TMP_DIR/repo_tn8"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/untouched_test.dart
void main() {
  test('untouched test', () {});
}
EOF
  git add test/untouched_test.dart
  git commit -m "initial test" >/dev/null

  echo "non-test file change" > README.md
  git add README.md
  git commit -m "update doc" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN8 expected pass when no test files touched, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN9: a commit that renames test/a_test.dart to test/a_tst.dart fails, naming the test.
(
  repo="$TMP_DIR/repo_tn9"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/a_test.dart
void main() {
  test('rename to non-test', () {});
}
EOF
  git add test/a_test.dart
  git commit -m "add test" >/dev/null

  git mv test/a_test.dart test/a_tst.dart
  git commit -m "rename to non-test file" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN9 expected failure when renaming test file to non-test" >&2
    exit 1
  fi
  if [[ "$out" != *"rename to non-test"* ]]; then
    echo "FAIL: TN9 expected output to name 'rename to non-test', got: $out" >&2
    exit 1
  fi
)

# TN10: a commit that moves test/a_test.dart to old/a_test.dart fails, naming the test.
(
  repo="$TMP_DIR/repo_tn10"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/a_test.dart
void main() {
  test('move outside test dir', () {});
}
EOF
  git add test/a_test.dart
  git commit -m "add test" >/dev/null

  mkdir -p old
  git mv test/a_test.dart old/a_test.dart
  git commit -m "move to old dir" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN10 expected failure when moving test file outside test dir" >&2
    exit 1
  fi
  if [[ "$out" != *"move outside test dir"* ]]; then
    echo "FAIL: TN10 expected output to name 'move outside test dir', got: $out" >&2
    exit 1
  fi
)

# TN11: a rename from test/a_test.dart to test/sub/a_test.dart passes.
(
  repo="$TMP_DIR/repo_tn11"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/a_test.dart
void main() {
  test('rename within test dir', () {});
}
EOF
  git add test/a_test.dart
  git commit -m "add test" >/dev/null

  mkdir -p test/sub
  git mv test/a_test.dart test/sub/a_test.dart
  git commit -m "rename within test dir" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN11 expected pass when renaming within test dir, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN12: a row in test/removed_test_names.txt for a live test fails, naming the row as live.
(
  repo="$TMP_DIR/repo_tn12"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/live_test.dart
void main() {
  test('currently live test', () {});
}
EOF
  git add test/live_test.dart
  git commit -m "add live test" >/dev/null

  cat << 'EOF' > test/removed_test_names.txt
# Rows below this line are append-only (Cleanup slice 14).
currently live test | removed for test reasons
EOF
  git add test/removed_test_names.txt
  git commit -m "add whitelist row for live test" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN12 expected failure for row excusing a live test" >&2
    exit 1
  fi
  if [[ "$out" != *"row excuses a live test"* ]] || [[ "$out" != *"currently live test"* ]]; then
    echo "FAIL: TN12 expected error message mentioning 'row excuses a live test' and 'currently live test', got: $out" >&2
    exit 1
  fi
)

# TN13: a row in test/removed_test_names.txt for a name that never existed fails.
(
  repo="$TMP_DIR/repo_tn13"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/some_test.dart
void main() {
  test('real test', () {});
}
EOF
  git add test/some_test.dart
  git commit -m "add real test" >/dev/null

  cat << 'EOF' > test/removed_test_names.txt
# Rows below this line are append-only (Cleanup slice 14).
completely invented test name | removed for reasons
EOF
  git add test/removed_test_names.txt
  git commit -m "add bogus whitelist row" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN13 expected failure for row naming a test that never existed" >&2
    exit 1
  fi
  if [[ "$out" != *"row names a test that never existed"* ]] || [[ "$out" != *"completely invented test name"* ]]; then
    echo "FAIL: TN13 expected error message mentioning 'row names a test that never existed', got: $out" >&2
    exit 1
  fi
)

# TN14: a row in test/removed_test_names.txt for a really removed test passes.
(
  repo="$TMP_DIR/repo_tn14"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/remove_me_test.dart
void main() {
  test('truly removed test', () {});
}
EOF
  git add test/remove_me_test.dart
  git commit -m "add test" >/dev/null

  cat << 'EOF' > test/remove_me_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Rows below this line are append-only (Cleanup slice 14).
truly removed test | legitimately deleted
EOF
  git add test/remove_me_test.dart test/removed_test_names.txt
  git commit -m "delete test and whitelist it" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN14 expected pass for really removed test with row, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN15: a row in test/removed_test_names.txt for a renamed test (old name gone, new name present) passes.
(
  repo="$TMP_DIR/repo_tn15"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/rename_test.dart
void main() {
  test('old name test', () {});
}
EOF
  git add test/rename_test.dart
  git commit -m "add old test" >/dev/null

  cat << 'EOF' > test/rename_test.dart
void main() {
  test('new name test', () {});
}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Rows below this line are append-only (Cleanup slice 14).
old name test | renamed to new name test
EOF
  git add test/rename_test.dart test/removed_test_names.txt
  git commit -m "rename test and whitelist old name" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD~1 HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN15 expected pass for renamed test with row for old name, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN16: append a row after the marker commit passes.
(
  repo="$TMP_DIR/repo_tn16"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
  test('second test', () {});
}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "add marker" >/dev/null
  base_sha=$(git rev-parse HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {
  test('second test', () {});
}
EOF
  cat << 'EOF' >> test/removed_test_names.txt
first test | removed in step 1
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "append first test removal" >/dev/null

  cat << 'EOF' > test/app_test.dart
void main() {}
EOF
  cat << 'EOF' >> test/removed_test_names.txt
second test | removed in step 2
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "append second test removal" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" "$base_sha" HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TN16 expected pass when appending rows, got rc $rc: $out" >&2
    exit 1
  fi
)

# TN17: edit a row's reason after the marker commit fails, naming the commit, line number and old/new text.
(
  repo="$TMP_DIR/repo_tn17"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
}
EOF
  git add test/app_test.dart
  git commit -m "init" >/dev/null
  base_sha=$(git rev-parse HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | original reason text
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "remove with marker" >/dev/null

  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | rewritten reason text
EOF
  git add test/removed_test_names.txt
  git commit -m "rewrite reason" >/dev/null
  bad_sha=$(git rev-parse --short=7 HEAD)

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" "$base_sha" HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN17 expected failure when editing a row's reason" >&2
    exit 1
  fi
  if [[ "$out" != *"$bad_sha"* ]] || [[ "$out" != *":3:"* ]] || [[ "$out" != *"original reason text"* ]] || [[ "$out" != *"rewritten reason text"* ]]; then
    echo "FAIL: TN17 expected output to name commit $bad_sha, line 3, and old/new text, got: $out" >&2
    exit 1
  fi
)

# TN18: delete a row after the marker commit fails.
(
  repo="$TMP_DIR/repo_tn18"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
  test('second test', () {});
}
EOF
  git add test/app_test.dart
  git commit -m "init" >/dev/null
  base_sha=$(git rev-parse HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | reason 1
second test | reason 2
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "remove two with marker" >/dev/null

  cat << 'EOF' > test/app_test.dart
void main() {
  test('second test', () {});
}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | reason 1
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "delete second row" >/dev/null
  bad_sha=$(git rev-parse --short=7 HEAD)

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" "$base_sha" HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN18 expected failure when deleting a row" >&2
    exit 1
  fi
  if [[ "$out" != *"$bad_sha"* ]] || [[ "$out" != *":4:"* ]] || [[ "$out" != *"second test | reason 2"* ]]; then
    echo "FAIL: TN18 expected output to name commit $bad_sha, line 4, and deleted text, got: $out" >&2
    exit 1
  fi
)

# TN19: swap two rows after the marker commit fails.
(
  repo="$TMP_DIR/repo_tn19"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
  test('second test', () {});
}
EOF
  git add test/app_test.dart
  git commit -m "init" >/dev/null
  base_sha=$(git rev-parse HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | reason 1
second test | reason 2
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "remove two with marker" >/dev/null

  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
second test | reason 2
first test | reason 1
EOF
  git add test/removed_test_names.txt
  git commit -m "swap rows" >/dev/null
  bad_sha=$(git rev-parse --short=7 HEAD)

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" "$base_sha" HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN19 expected failure when swapping two rows" >&2
    exit 1
  fi
  if [[ "$out" != *"$bad_sha"* ]] || [[ "$out" != *":3:"* ]]; then
    echo "FAIL: TN19 expected output to name commit $bad_sha and line 3, got: $out" >&2
    exit 1
  fi
)

# TN20: edit a row in one commit and append in the next fails, naming the first commit.
(
  repo="$TMP_DIR/repo_tn20"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
  test('second test', () {});
}
EOF
  git add test/app_test.dart
  git commit -m "init" >/dev/null
  base_sha=$(git rev-parse HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {
  test('second test', () {});
}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | original reason
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "remove first with marker" >/dev/null

  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
# Rows below this line are append-only (Cleanup slice 14).
first test | edited reason
EOF
  git add test/removed_test_names.txt
  git commit -m "edit first reason" >/dev/null
  first_bad_sha=$(git rev-parse --short=7 HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {}
EOF
  cat << 'EOF' >> test/removed_test_names.txt
second test | appended reason
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "append second" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" "$base_sha" HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN20 expected failure when editing a row in one commit and appending in the next" >&2
    exit 1
  fi
  if [[ "$out" != *"$first_bad_sha"* ]] || [[ "$out" != *"original reason"* ]] || [[ "$out" != *"edited reason"* ]]; then
    echo "FAIL: TN20 expected output to name first commit $first_bad_sha and old/new text, got: $out" >&2
    exit 1
  fi
)

# TN21: remove the marker fails.
(
  repo="$TMP_DIR/repo_tn21"
  setup_repo "$repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
}
EOF
  git add test/app_test.dart
  git commit -m "init" >/dev/null
  base_sha=$(git rev-parse HEAD)

  cat << 'EOF' > test/app_test.dart
void main() {}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Removed test names ratchet whitelist.
first test | removed without marker
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "remove without marker" >/dev/null

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" "$base_sha" HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN21 expected failure when marker is missing at HEAD" >&2
    exit 1
  fi
  if [[ "$out" != *"append-only"* ]]; then
    echo "FAIL: TN21 expected output to mention missing append-only marker, got: $out" >&2
    exit 1
  fi
)

# TN22: a shallow clone fails closed.
(
  src_repo="$TMP_DIR/repo_tn22_src"
  setup_repo "$src_repo"
  mkdir -p test
  cat << 'EOF' > test/app_test.dart
void main() {
  test('first test', () {});
}
EOF
  cat << 'EOF' > test/removed_test_names.txt
# Rows below this line are append-only (Cleanup slice 14).
EOF
  git add test/app_test.dart test/removed_test_names.txt
  git commit -m "c1" >/dev/null
  c1=$(git rev-parse HEAD)

  echo "// comment" >> test/app_test.dart
  git add test/app_test.dart
  git commit -m "c2" >/dev/null

  shallow_repo="$TMP_DIR/repo_tn22_shallow"
  git clone --depth 1 "file://$src_repo" "$shallow_repo" >/dev/null 2>&1
  cd "$shallow_repo"

  set +e
  out=$(python3 -I "$CHECK_SCRIPT" HEAD HEAD 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: TN22 expected failure in a shallow clone" >&2
    exit 1
  fi
  if [[ "$out" != *"shallow"* ]]; then
    echo "FAIL: TN22 expected output to mention shallow clone, got: $out" >&2
    exit 1
  fi
)

echo "All test name ratchet self-tests passed (TN1 - TN22)."

