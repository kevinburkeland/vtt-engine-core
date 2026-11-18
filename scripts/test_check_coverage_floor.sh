#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_coverage_floor.py"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

assert_fail() {
  local name="$1"
  local pattern="$2"
  shift 2
  set +e
  local out
  out=$("$@" 2>&1)
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL [$name]: expected non-zero exit, got 0. Output: $out"
    FAIL=$((FAIL + 1))
    return
  fi
  if [ -n "$pattern" ] && ! echo "$out" | grep -qE "$pattern"; then
    echo "FAIL [$name]: output did not match '$pattern'. Output: $out"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS [$name]"
  PASS=$((PASS + 1))
}

assert_pass() {
  local name="$1"
  shift
  set +e
  local out
  out=$("$@" 2>&1)
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL [$name]: expected exit 0, got $rc. Output: $out"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS [$name]"
  PASS=$((PASS + 1))
}

# Helper to create a clean synthetic git repo with package + coverage JSON + floors
make_fixture_repo() {
  local dir="$1"
  mkdir -p "$dir/lib" "$dir/coverage"
  cat > "$dir/pubspec.yaml" <<'EOF'
name: sample_pkg
version: 1.0.0
EOF
  echo "void a() {}" > "$dir/lib/a.dart"
  echo "void b() {}" > "$dir/lib/b.dart"

  # a.dart: 8/10 = 80.0%, b.dart: 4/10 = 40.0%, TOTAL: 12/20 = 60.0%
  cat > "$dir/coverage/test_1.vm.json" <<'EOF'
{
  "type": "CodeCoverage",
  "coverage": [
    {"source": "package:sample_pkg/a.dart", "hits": [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,0,10,0]},
    {"source": "package:sample_pkg/b.dart", "hits": [1,1,2,1,3,1,4,1,5,0,6,0,7,0,8,0,9,0,10,0]}
  ]
}
EOF

  printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\nlib/b.dart\t40.0\n" > "$dir/coverage_floors.tsv"

  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" add pubspec.yaml lib/a.dart lib/b.dart coverage_floors.tsv
  git -C "$dir" commit -q -m "initial"
}

# 1. Control passes
REPO_CTRL="$TMPDIR/ctrl"
make_fixture_repo "$REPO_CTRL"
assert_pass "1. control passes" \
  python3 -I "$CHECK_SCRIPT" "$REPO_CTRL/coverage" "$REPO_CTRL/coverage_floors.tsv" --repo-root "$REPO_CTRL"

# 2. Below total floor fails
REPO_TOT="$TMPDIR/below_total"
make_fixture_repo "$REPO_TOT"
printf "path\tfloor\nTOTAL\t60.1\nlib/a.dart\t80.0\nlib/b.dart\t40.0\n" > "$REPO_TOT/coverage_floors.tsv"
git -C "$REPO_TOT" add coverage_floors.tsv && git -C "$REPO_TOT" commit -q -m "raise total"
assert_fail "2. below total floor fails" "TOTAL" \
  python3 -I "$CHECK_SCRIPT" "$REPO_TOT/coverage" "$REPO_TOT/coverage_floors.tsv" --repo-root "$REPO_TOT"

# 3. One file below its floor fails
REPO_FILE="$TMPDIR/below_file"
make_fixture_repo "$REPO_FILE"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\nlib/b.dart\t40.1\n" > "$REPO_FILE/coverage_floors.tsv"
git -C "$REPO_FILE" add coverage_floors.tsv && git -C "$REPO_FILE" commit -q -m "raise b"
assert_fail "3. one file below its floor fails" "lib/b\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_FILE/coverage" "$REPO_FILE/coverage_floors.tsv" --repo-root "$REPO_FILE"

# 4. Missing row for existing lib/ file fails
REPO_MISS="$TMPDIR/missing_row"
make_fixture_repo "$REPO_MISS"
echo "void c() {}" > "$REPO_MISS/lib/c.dart"
assert_fail "4. missing row fails" "lib/c\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_MISS/coverage" "$REPO_MISS/coverage_floors.tsv" --repo-root "$REPO_MISS"

# 5. Stale row for deleted/non-existent file fails
REPO_STALE="$TMPDIR/stale_row"
make_fixture_repo "$REPO_STALE"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\nlib/b.dart\t40.0\nlib/ghost.dart\t50.0\n" > "$REPO_STALE/coverage_floors.tsv"
assert_fail "5. stale row fails" "lib/ghost\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_STALE/coverage" "$REPO_STALE/coverage_floors.tsv" --repo-root "$REPO_STALE"

# 6. Lowered floor versus previous commit fails
REPO_LOW="$TMPDIR/lowered_floor"
make_fixture_repo "$REPO_LOW"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t79.9\nlib/b.dart\t40.0\n" > "$REPO_LOW/coverage_floors.tsv"
git -C "$REPO_LOW" add coverage_floors.tsv && git -C "$REPO_LOW" commit -q -m "lower a"
assert_fail "6. lowered floor vs previous commit fails" "lib/a\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_LOW/coverage" "$REPO_LOW/coverage_floors.tsv" --repo-root "$REPO_LOW"

# 7. Empty coverage folder fails (and missing coverage folder fails)
REPO_EMPTY="$TMPDIR/empty_cov"
make_fixture_repo "$REPO_EMPTY"
rm -rf "$REPO_EMPTY/coverage"/*
assert_fail "7. empty coverage folder fails" "coverage|empty|JSON" \
  python3 -I "$CHECK_SCRIPT" "$REPO_EMPTY/coverage" "$REPO_EMPTY/coverage_floors.tsv" --repo-root "$REPO_EMPTY"

# 8. Broken JSON file fails
REPO_BADJSON="$TMPDIR/bad_json"
make_fixture_repo "$REPO_BADJSON"
echo "{not valid json" > "$REPO_BADJSON/coverage/broken.vm.json"
assert_fail "8. broken JSON file fails" "JSON|broken\.vm\.json" \
  python3 -I "$CHECK_SCRIPT" "$REPO_BADJSON/coverage" "$REPO_BADJSON/coverage_floors.tsv" --repo-root "$REPO_BADJSON"

# 9. Raised floor passes when coverage meets it
REPO_RAISE="$TMPDIR/raised_floor"
make_fixture_repo "$REPO_RAISE"
# Increase hits in a.dart to 9/10 = 90.0%, total 13/20 = 65.0%
cat > "$REPO_RAISE/coverage/test_1.vm.json" <<'EOF'
{
  "type": "CodeCoverage",
  "coverage": [
    {"source": "package:sample_pkg/a.dart", "hits": [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,0]},
    {"source": "package:sample_pkg/b.dart", "hits": [1,1,2,1,3,1,4,1,5,0,6,0,7,0,8,0,9,0,10,0]}
  ]
}
EOF
printf "path\tfloor\nTOTAL\t65.0\nlib/a.dart\t90.0\nlib/b.dart\t40.0\n" > "$REPO_RAISE/coverage_floors.tsv"
git -C "$REPO_RAISE" add coverage_floors.tsv && git -C "$REPO_RAISE" commit -q -m "raise floors"
assert_pass "9. raised floor passes" \
  python3 -I "$CHECK_SCRIPT" "$REPO_RAISE/coverage" "$REPO_RAISE/coverage_floors.tsv" --repo-root "$REPO_RAISE"

echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
