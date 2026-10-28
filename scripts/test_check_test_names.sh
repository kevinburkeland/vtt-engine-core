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

echo "All test name ratchet self-tests passed (TN1 - TN8)."
