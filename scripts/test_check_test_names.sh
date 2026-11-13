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

echo "All test name ratchet self-tests passed (TN1 - TN15)."

