#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_MUTATION="$SCRIPT_DIR/check_mutation_branches.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# MB1 an empty list with limit 20: pass, prints count 0.
empty_file="$TMP_DIR/empty.txt"
touch "$empty_file"
out1=$("$CHECK_MUTATION" 20 "$empty_file")
if [[ "$out1" != *"Mutation branches count: 0"* ]]; then
  echo "FAIL: MB1 expected count 0, got: $out1" >&2
  exit 1
fi

# MB2 exactly 20 mutation/ refs with limit 20: pass.
f20="$TMP_DIR/20.txt"
for i in $(seq 1 20); do
  echo -e "0123456789abcdef0123456789abcdef01234567\trefs/heads/mutation/branch-$i" >> "$f20"
done
"$CHECK_MUTATION" 20 "$f20" >/dev/null

# MB3 21 mutation/ refs with limit 20: fail, and the output lists all 21 names.
f21="$TMP_DIR/21.txt"
for i in $(seq 1 21); do
  echo -e "0123456789abcdef0123456789abcdef01234567\trefs/heads/mutation/branch-$i" >> "$f21"
done
set +e
out3=$("$CHECK_MUTATION" 20 "$f21" 2>&1)
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

# MB4 a list with refs/heads/main, refs/heads/mutations/a, refs/heads/feature/mutation/b and 2 real mutation/ refs, limit 1: fail with count 2
f4="$TMP_DIR/mixed.txt"
cat << 'EOF2' > "$f4"
0123456789abcdef0123456789abcdef01234567	refs/heads/main
0123456789abcdef0123456789abcdef01234567	refs/heads/mutations/a
0123456789abcdef0123456789abcdef01234567	refs/heads/feature/mutation/b
0123456789abcdef0123456789abcdef01234567	refs/heads/mutation/real-1
0123456789abcdef0123456789abcdef01234567	refs/heads/mutation/real-2
EOF2
set +e
out4=$("$CHECK_MUTATION" 1 "$f4" 2>&1)
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
out5=$("$CHECK_MUTATION" 20 "$TMP_DIR/does_not_exist.txt" 2>&1)
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
out6a=$("$CHECK_MUTATION" abc "$empty_file" 2>&1)
rc6a=$?
out6b=$("$CHECK_MUTATION" 2>&1)
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
  if [[ "$out7" != *"failed to query origin"* && "$out7" != *"Fatal"* && "$out7" != *"fatal"* ]]; then
    echo "FAIL: MB7 output did not indicate remote query error: $out7" >&2
    exit 1
  fi
)

echo "All mutation branch check self-tests passed (MB1 - MB7)."
