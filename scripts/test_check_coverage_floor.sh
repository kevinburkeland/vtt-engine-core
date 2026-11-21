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

# 10. Lowered in commit 1 then an unrelated commit 2 fails (two-commit push hole)
REPO_TWO="$TMPDIR/lowered_two_commits"
make_fixture_repo "$REPO_TWO"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t79.9\nlib/b.dart\t40.0\n" > "$REPO_TWO/coverage_floors.tsv"
git -C "$REPO_TWO" add coverage_floors.tsv && git -C "$REPO_TWO" commit -q -m "commit 1: lower a"
echo "// unrelated" >> "$REPO_TWO/lib/a.dart"
git -C "$REPO_TWO" add lib/a.dart && git -C "$REPO_TWO" commit -q -m "commit 2: unrelated"
assert_fail "10. lowered in commit 1 then unrelated commit 2 fails" "lib/a\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_TWO/coverage" "$REPO_TWO/coverage_floors.tsv" --repo-root "$REPO_TWO"

# 11. Lowered in the middle of three commits fails
REPO_MID="$TMPDIR/lowered_middle_three"
make_fixture_repo "$REPO_MID"
echo "// c1" >> "$REPO_MID/lib/a.dart"
git -C "$REPO_MID" add lib/a.dart && git -C "$REPO_MID" commit -q -m "c1"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t79.5\nlib/b.dart\t40.0\n" > "$REPO_MID/coverage_floors.tsv"
git -C "$REPO_MID" add coverage_floors.tsv && git -C "$REPO_MID" commit -q -m "c2: lower a"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\nlib/b.dart\t40.0\n" > "$REPO_MID/coverage_floors.tsv"
git -C "$REPO_MID" add coverage_floors.tsv && git -C "$REPO_MID" commit -q -m "c3: restore a"
assert_fail "11. lowered in middle of three commits fails" "lib/a\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_MID/coverage" "$REPO_MID/coverage_floors.tsv" --repo-root "$REPO_MID"

# 12. TOTAL lowered two commits back fails
REPO_TOT2="$TMPDIR/total_lowered_two_back"
make_fixture_repo "$REPO_TOT2"
printf "path\tfloor\nTOTAL\t59.9\nlib/a.dart\t80.0\nlib/b.dart\t40.0\n" > "$REPO_TOT2/coverage_floors.tsv"
git -C "$REPO_TOT2" add coverage_floors.tsv && git -C "$REPO_TOT2" commit -q -m "lower total"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\nlib/b.dart\t40.0\n" > "$REPO_TOT2/coverage_floors.tsv"
git -C "$REPO_TOT2" add coverage_floors.tsv && git -C "$REPO_TOT2" commit -q -m "restore total"
echo "// extra" >> "$REPO_TOT2/lib/b.dart"
git -C "$REPO_TOT2" add lib/b.dart && git -C "$REPO_TOT2" commit -q -m "unrelated"
assert_fail "12. TOTAL lowered two commits back fails" "TOTAL" \
  python3 -I "$CHECK_SCRIPT" "$REPO_TOT2/coverage" "$REPO_TOT2/coverage_floors.tsv" --repo-root "$REPO_TOT2"

# 13. Row removed while its file still exists fails (even if re-added later)
REPO_REM="$TMPDIR/row_removed_file_exists"
make_fixture_repo "$REPO_REM"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\n" > "$REPO_REM/coverage_floors.tsv"
git -C "$REPO_REM" add coverage_floors.tsv && git -C "$REPO_REM" commit -q -m "drop b row while lib/b.dart exists"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t80.0\nlib/b.dart\t40.0\n" > "$REPO_REM/coverage_floors.tsv"
git -C "$REPO_REM" add coverage_floors.tsv && git -C "$REPO_REM" commit -q -m "re-add b row"
assert_fail "13. row removed while its file still exists fails" "lib/b\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_REM/coverage" "$REPO_REM/coverage_floors.tsv" --repo-root "$REPO_REM"

# 14. Renamed file with a lower row fails
REPO_REN="$TMPDIR/renamed_lower_row"
make_fixture_repo "$REPO_REN"
git -C "$REPO_REN" mv lib/a.dart lib/a_renamed.dart
printf "path\tfloor\nTOTAL\t60.0\nlib/a_renamed.dart\t79.9\nlib/b.dart\t40.0\n" > "$REPO_REN/coverage_floors.tsv"
git -C "$REPO_REN" add coverage_floors.tsv && git -C "$REPO_REN" commit -q -m "rename a with lower floor"
sed -i 's/package:sample_pkg\/a.dart/package:sample_pkg\/a_renamed.dart/' "$REPO_REN/coverage/test_1.vm.json"
assert_fail "14. renamed file with lower row fails" "lib/a_renamed\.dart|lib/a\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_REN/coverage" "$REPO_REN/coverage_floors.tsv" --repo-root "$REPO_REN"

# 15. Shallow clone fails closed with "needs full history"
REPO_SHALLOW_SRC="$TMPDIR/shallow_src"
make_fixture_repo "$REPO_SHALLOW_SRC"
echo "// second" >> "$REPO_SHALLOW_SRC/lib/a.dart"
git -C "$REPO_SHALLOW_SRC" add lib/a.dart && git -C "$REPO_SHALLOW_SRC" commit -q -m "second"
REPO_SHALLOW="$TMPDIR/shallow_clone"
git clone -q --depth 1 "file://$REPO_SHALLOW_SRC" "$REPO_SHALLOW"
cp -r "$REPO_SHALLOW_SRC/coverage" "$REPO_SHALLOW/coverage"
assert_fail "15. shallow clone fails" "needs full history" \
  python3 -I "$CHECK_SCRIPT" "$REPO_SHALLOW/coverage" "$REPO_SHALLOW/coverage_floors.tsv" --repo-root "$REPO_SHALLOW"

# 16. Raised floor two commits back passes
REPO_RAISE2="$TMPDIR/raised_two_back"
make_fixture_repo "$REPO_RAISE2"
printf "path\tfloor\nTOTAL\t65.0\nlib/a.dart\t90.0\nlib/b.dart\t40.0\n" > "$REPO_RAISE2/coverage_floors.tsv"
git -C "$REPO_RAISE2" add coverage_floors.tsv && git -C "$REPO_RAISE2" commit -q -m "raise floors"
echo "// extra 1" >> "$REPO_RAISE2/lib/a.dart"
git -C "$REPO_RAISE2" add lib/a.dart && git -C "$REPO_RAISE2" commit -q -m "unrelated 1"
echo "// extra 2" >> "$REPO_RAISE2/lib/b.dart"
git -C "$REPO_RAISE2" add lib/b.dart && git -C "$REPO_RAISE2" commit -q -m "unrelated 2"
cat > "$REPO_RAISE2/coverage/test_1.vm.json" <<'EOF'
{
  "type": "CodeCoverage",
  "coverage": [
    {"source": "package:sample_pkg/a.dart", "hits": [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1,10,0]},
    {"source": "package:sample_pkg/b.dart", "hits": [1,1,2,1,3,1,4,1,5,0,6,0,7,0,8,0,9,0,10,0]}
  ]
}
EOF
assert_pass "16. raised floor two commits back passes" \
  python3 -I "$CHECK_SCRIPT" "$REPO_RAISE2/coverage" "$REPO_RAISE2/coverage_floors.tsv" --repo-root "$REPO_RAISE2"

# 17. Floor 0.6 below measured fails (Fix 5.3)
REPO_LAG_FAIL="$TMPDIR/lag_0_6_fail"
make_fixture_repo "$REPO_LAG_FAIL"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t79.4\nlib/b.dart\t40.0\n" > "$REPO_LAG_FAIL/coverage_floors.tsv"
git -C "$REPO_LAG_FAIL" add coverage_floors.tsv && git -C "$REPO_LAG_FAIL" commit --amend -q --no-edit
assert_fail "17. floor 0.6 below measured fails" "lib/a\.dart: measured 80\.0, floor 79\.4; raise the floor" \
  python3 -I "$CHECK_SCRIPT" "$REPO_LAG_FAIL/coverage" "$REPO_LAG_FAIL/coverage_floors.tsv" --repo-root "$REPO_LAG_FAIL"

# 18. Floor 0.5 below measured passes (Fix 5.3)
REPO_LAG_PASS="$TMPDIR/lag_0_5_pass"
make_fixture_repo "$REPO_LAG_PASS"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t79.5\nlib/b.dart\t40.0\n" > "$REPO_LAG_PASS/coverage_floors.tsv"
git -C "$REPO_LAG_PASS" add coverage_floors.tsv && git -C "$REPO_LAG_PASS" commit --amend -q --no-edit
assert_pass "18. floor 0.5 below measured passes" \
  python3 -I "$CHECK_SCRIPT" "$REPO_LAG_PASS/coverage" "$REPO_LAG_PASS/coverage_floors.tsv" --repo-root "$REPO_LAG_PASS"

# 19. File split into export-only barrel may lower its own floor to 0.0 while TOTAL stays >= previous
REPO_BARREL_PASS="$TMPDIR/barrel_split_pass"
make_fixture_repo "$REPO_BARREL_PASS"
cat > "$REPO_BARREL_PASS/lib/a_impl.dart" <<'EOF'
int f() => 1;
EOF
cat > "$REPO_BARREL_PASS/lib/a.dart" <<'EOF'
export 'a_impl.dart';
EOF
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t0.0\nlib/a_impl.dart\t80.0\nlib/b.dart\t40.0\n" > "$REPO_BARREL_PASS/coverage_floors.tsv"
git -C "$REPO_BARREL_PASS" add lib/a.dart lib/a_impl.dart coverage_floors.tsv && git -C "$REPO_BARREL_PASS" commit -q -m "split a into barrel"
cat > "$REPO_BARREL_PASS/coverage/test_1.vm.json" <<'EOF'
{
  "type": "CodeCoverage",
  "coverage": [
    {"source": "package:sample_pkg/a_impl.dart", "hits": [1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,0,10,0]},
    {"source": "package:sample_pkg/b.dart", "hits": [1,1,2,1,3,1,4,1,5,0,6,0,7,0,8,0,9,0,10,0]}
  ]
}
EOF
assert_pass "19. export-only barrel split lowering its own floor to 0.0 passes" \
  python3 -I "$CHECK_SCRIPT" "$REPO_BARREL_PASS/coverage" "$REPO_BARREL_PASS/coverage_floors.tsv" --repo-root "$REPO_BARREL_PASS"

# 20. Non-barrel file lowering its floor to 0.0 still fails
REPO_NONBARREL_FAIL="$TMPDIR/nonbarrel_zero_fail"
make_fixture_repo "$REPO_NONBARREL_FAIL"
printf "path\tfloor\nTOTAL\t60.0\nlib/a.dart\t0.0\nlib/b.dart\t40.0\n" > "$REPO_NONBARREL_FAIL/coverage_floors.tsv"
git -C "$REPO_NONBARREL_FAIL" add coverage_floors.tsv && git -C "$REPO_NONBARREL_FAIL" commit -q -m "lower non-barrel to zero"
assert_fail "20. non-barrel file lowering floor to 0.0 still fails" "Lowered floor for lib/a\.dart" \
  python3 -I "$CHECK_SCRIPT" "$REPO_NONBARREL_FAIL/coverage" "$REPO_NONBARREL_FAIL/coverage_floors.tsv" --repo-root "$REPO_NONBARREL_FAIL"

echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
