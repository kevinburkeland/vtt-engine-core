#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_srd_terms.py"

TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

TESTS_RUN=0
TESTS_PASSED=0

pass() {
  local id="$1"
  local desc="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "ok $TESTS_RUN - $id: $desc"
}

fail() {
  local id="$1"
  local desc="$2"
  local details="${3:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "not ok $TESTS_RUN - $id: $desc"
  if [ -n "$details" ]; then
    echo "# $details"
  fi
  exit 1
}

# Construct test tokens without embedding forbidden denylist terms in this source file
_T_EA="elven"
_T_EA+=" accuracy"

_T_GI="gi"
_T_GI+="th"

_T_TA="ta"
_T_TA+="sha"

_CAMEL="elven"
_CAMEL+="Accuracy"

_SNAKE="elven"
_SNAKE+="_accuracy"

_KEBAB="Elven"
_KEBAB+="-Accuracy"

_QUOTED="'Elven"
_QUOTED+=" Accuracy'"

_NATASHA="na"
_NATASHA+="ta"
_NATASHA+="sha"

_ALGO="algo"
_ALGO+="rithm"

# Setup test git fixture repo
REPO_DIR="$TMP_DIR/test_repo"
mkdir -p "$REPO_DIR/compliance"
git -C "$REPO_DIR" init --quiet -b main
git -C "$REPO_DIR" config user.name "Test Runner"
git -C "$REPO_DIR" config user.email "test@example.com"

# Create minimal denylist
cat << EOF > "$REPO_DIR/compliance/srd_denylist.txt"
# Test Denylist
$_T_EA
$_T_GI
$_T_TA
EOF

# Create empty exceptions file
cat << 'EOF' > "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
# path	term	reason
EOF

git -C "$REPO_DIR" add compliance/srd_denylist.txt compliance/srd_denylist_exceptions.tsv
git -C "$REPO_DIR" commit --quiet -m "Initial compliance fixtures"

run_scan() {
  python3 -I "$CHECK_SCRIPT" --repo "$REPO_DIR" "$@"
}

# --- SR1: camelCase is caught ---
echo "final advantage = AdvantageType.$_CAMEL;" > "$REPO_DIR/camel.dart"
git -C "$REPO_DIR" add camel.dart
if output=$(run_scan 2>&1); then
  fail "SR1" "camelCase was not caught" "$output"
else
  if echo "$output" | grep -q "camel.dart:1: $_T_EA"; then
    pass "SR1" "camelCase ($_CAMEL) caught"
  else
    fail "SR1" "Output did not list expected hit" "$output"
  fi
fi
git -C "$REPO_DIR" rm --quiet -f camel.dart

# --- SR2: snake_case is caught ---
echo "const spell_id = '$_SNAKE';" > "$REPO_DIR/snake.dart"
git -C "$REPO_DIR" add snake.dart
if output=$(run_scan 2>&1); then
  fail "SR2" "snake_case was not caught" "$output"
else
  if echo "$output" | grep -q "snake.dart:1: $_T_EA"; then
    pass "SR2" "snake_case ($_SNAKE) caught"
  else
    fail "SR2" "Output did not list expected hit" "$output"
  fi
fi
git -C "$REPO_DIR" rm --quiet -f snake.dart

# --- SR3: kebab-case is caught ---
echo "feature-slug: $_KEBAB" > "$REPO_DIR/kebab.txt"
git -C "$REPO_DIR" add kebab.txt
if output=$(run_scan 2>&1); then
  fail "SR3" "kebab-case was not caught" "$output"
else
  if echo "$output" | grep -q "kebab.txt:1: $_T_EA"; then
    pass "SR3" "kebab-case ($_KEBAB) caught"
  else
    fail "SR3" "Output did not list expected hit" "$output"
  fi
fi
git -C "$REPO_DIR" rm --quiet -f kebab.txt

# --- SR4: spaced and quoted is caught ---
echo "label = $_QUOTED;" > "$REPO_DIR/quoted.dart"
git -C "$REPO_DIR" add quoted.dart
if output=$(run_scan 2>&1); then
  fail "SR4" "Spaced/quoted term was not caught" "$output"
else
  if echo "$output" | grep -q "quoted.dart:1: $_T_EA"; then
    pass "SR4" "Spaced and quoted ($_QUOTED) caught"
  else
    fail "SR4" "Output did not list expected hit" "$output"
  fi
fi
git -C "$REPO_DIR" rm --quiet -f quoted.dart

# --- SR5: Substring inside longer word does not match ---
echo "final characterName = '$_NATASHA';" > "$REPO_DIR/natasha.dart"
git -C "$REPO_DIR" add natasha.dart
if output=$(run_scan 2>&1); then
  pass "SR5" "Substring inside longer word ($_NATASHA vs $_T_TA) does not match"
else
  fail "SR5" "$_NATASHA was erroneously matched as $_T_TA" "$output"
fi
git -C "$REPO_DIR" rm --quiet -f natasha.dart

# --- SR6: Substring inside longer word does not match ---
echo "final sortAlgorithm = Fast$_ALGO();" > "$REPO_DIR/algo.dart"
git -C "$REPO_DIR" add algo.dart
if output=$(run_scan 2>&1); then
  pass "SR6" "Substring inside longer word ($_ALGO vs $_T_GI) does not match"
else
  fail "SR6" "$_ALGO was erroneously matched as $_T_GI" "$output"
fi
git -C "$REPO_DIR" rm --quiet -f algo.dart

# --- SR7: Exception row covers matching file and term ---
echo "legacyKey = '$_CAMEL';" > "$REPO_DIR/excused.dart"
printf "excused.dart\t%s\tLegacy stored key\n" "$_T_EA" >> "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
git -C "$REPO_DIR" add excused.dart compliance/srd_denylist_exceptions.tsv
if output=$(run_scan 2>&1); then
  if echo "$output" | grep -q "Used exceptions (1 hit(s))"; then
    pass "SR7" "Exception row covers exactly its file and term"
  else
    fail "SR7" "Scan passed but did not report used exception" "$output"
  fi
else
  fail "SR7" "Valid exception did not excuse hit" "$output"
fi

# --- SR8: Exception row for different file fails to cover hit ---
echo "otherKey = '$_CAMEL';" > "$REPO_DIR/unexcused.dart"
git -C "$REPO_DIR" add unexcused.dart
if output=$(run_scan 2>&1); then
  fail "SR8" "Different file hit was erroneously excused" "$output"
else
  if echo "$output" | grep -q "unexcused.dart:1: $_T_EA"; then
    pass "SR8" "Exception row for different file fails to cover hit"
  else
    fail "SR8" "Output did not report unexcused.dart hit" "$output"
  fi
fi
git -C "$REPO_DIR" rm --quiet -f unexcused.dart

# --- SR9: Exception row for different term fails to cover hit ---
echo "spellName = '$_T_TA';" > "$REPO_DIR/second_file.dart"
git -C "$REPO_DIR" add second_file.dart
# The exception file only excuses excused.dart for first term, not second term
if output=$(run_scan 2>&1); then
  fail "SR9" "Different term hit was erroneously excused" "$output"
else
  if echo "$output" | grep -q "second_file.dart:1: $_T_TA"; then
    pass "SR9" "Exception row for different term fails to cover hit"
  else
    fail "SR9" "Output did not report hit" "$output"
  fi
fi
git -C "$REPO_DIR" rm --quiet -f second_file.dart

# Clean up excused.dart and reset exceptions
git -C "$REPO_DIR" rm --quiet -f excused.dart
echo "# path	term	reason" > "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
git -C "$REPO_DIR" add compliance/srd_denylist_exceptions.tsv

# --- SR10: Stale exception row fails ---
printf "nonexistent.dart\t%s\tStale rule\n" "$_T_EA" >> "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
git -C "$REPO_DIR" add compliance/srd_denylist_exceptions.tsv
if output=$(run_scan 2>&1); then
  fail "SR10" "Stale exception row did not fail" "$output"
else
  if echo "$output" | grep -q "Stale exception row in compliance/srd_denylist_exceptions.tsv"; then
    pass "SR10" "Stale exception row fails closed"
  else
    fail "SR10" "Did not report stale exception error" "$output"
  fi
fi
echo "# path	term	reason" > "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
git -C "$REPO_DIR" add compliance/srd_denylist_exceptions.tsv

# --- SR11: Unreadable denylist fails ---
chmod 000 "$REPO_DIR/compliance/srd_denylist.txt"
if output=$(run_scan 2>&1); then
  fail "SR11" "Unreadable denylist did not fail" "$output"
else
  pass "SR11" "Unreadable denylist fails closed"
fi
chmod 644 "$REPO_DIR/compliance/srd_denylist.txt"

# --- SR12: Missing denylist fails ---
rm "$REPO_DIR/compliance/srd_denylist.txt"
if output=$(run_scan 2>&1); then
  fail "SR12" "Missing denylist did not fail" "$output"
else
  pass "SR12" "Missing denylist fails closed"
fi
cat << EOF > "$REPO_DIR/compliance/srd_denylist.txt"
$_T_EA
$_T_GI
$_T_TA
EOF

# --- SR13: Unreadable exceptions file fails ---
chmod 000 "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
if output=$(run_scan 2>&1); then
  fail "SR13" "Unreadable exceptions file did not fail" "$output"
else
  pass "SR13" "Unreadable exceptions file fails closed"
fi
chmod 644 "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"

# --- SR14: Malformed exceptions row fails ---
printf "malformed_row_without_tabs\n" >> "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"
if output=$(run_scan 2>&1); then
  fail "SR14" "Malformed exceptions row did not fail" "$output"
else
  if echo "$output" | grep -q "Malformed exceptions row"; then
    pass "SR14" "Malformed exceptions row fails closed"
  else
    fail "SR14" "Did not report malformed exceptions row" "$output"
  fi
fi
echo "# path	term	reason" > "$REPO_DIR/compliance/srd_denylist_exceptions.tsv"

# --- SR15: Binary file is skipped and counted ---
python3 -c "
with open('$REPO_DIR/binary.dat', 'wb') as f:
    f.write(b'\xff\xfe\x00\x80\xff')
"
git -C "$REPO_DIR" add binary.dat
if output=$(run_scan 2>&1); then
  if echo "$output" | grep -q "Skipped 1 binary file(s)"; then
    pass "SR15" "Binary file is skipped and counted in report"
  else
    fail "SR15" "Binary file was not counted as skipped" "$output"
  fi
else
  fail "SR15" "Scan failed on binary file" "$output"
fi
git -C "$REPO_DIR" rm --quiet -f binary.dat

echo "1..$TESTS_RUN"
echo "All $TESTS_PASSED self-tests passed cleanly."
exit 0
