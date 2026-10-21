#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ACTION_PINS="$SCRIPT_DIR/check_action_pins.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

WORKFLOWS_DIR="$TMP_DIR/workflows"
mkdir -p "$WORKFLOWS_DIR"

# Case 1: Valid pinned actions with sha and comment: pass
cat << 'EOF' > "$WORKFLOWS_DIR/valid.yml"
name: Valid Workflow
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Setup Java
        uses: actions/setup-java@3a4f6e1af504cf6a31855fa899c6aa5355ba6c12 # v4.7.0
EOF

"$CHECK_ACTION_PINS" "$WORKFLOWS_DIR" >/dev/null

# Case 2: Local action starting with ./: pass
cat << 'EOF' >> "$WORKFLOWS_DIR/valid.yml"
      - name: Local Action
        uses: ./.github/actions/my-local-action
EOF

"$CHECK_ACTION_PINS" "$WORKFLOWS_DIR" >/dev/null

# Case 3: Action pinned to version tag: fail, output names action and line
cat << 'EOF' > "$WORKFLOWS_DIR/invalid_tag.yml"
name: Invalid Tag Workflow
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF

set +e
out3=$("$CHECK_ACTION_PINS" "$WORKFLOWS_DIR" 2>&1)
rc3=$?
set -e
if [ "$rc3" -eq 0 ]; then
  echo "FAIL: Case 3 expected non-zero exit code" >&2
  exit 1
fi
if [[ "$out3" != *"actions/checkout@v4"* ]]; then
  echo "FAIL: Case 3 output did not name unpinned action: $out3" >&2
  exit 1
fi

rm "$WORKFLOWS_DIR/invalid_tag.yml"

# Case 4: Action pinned to branch: fail
cat << 'EOF' > "$WORKFLOWS_DIR/invalid_branch.yml"
name: Invalid Branch Workflow
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@main
EOF

set +e
out4=$("$CHECK_ACTION_PINS" "$WORKFLOWS_DIR" 2>&1)
rc4=$?
set -e
if [ "$rc4" -eq 0 ] || [[ "$out4" != *"actions/setup-node@main"* ]]; then
  echo "FAIL: Case 4 expected failure naming actions/setup-node@main" >&2
  exit 1
fi

rm "$WORKFLOWS_DIR/invalid_branch.yml"

# Case 5: 39-character hex (too short) or non-hex chars: fail
cat << 'EOF' > "$WORKFLOWS_DIR/invalid_hex.yml"
name: Invalid Hex Workflow
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af68 # 39 chars
EOF

set +e
out5=$("$CHECK_ACTION_PINS" "$WORKFLOWS_DIR" 2>&1)
rc5=$?
set -e
if [ "$rc5" -eq 0 ]; then
  echo "FAIL: Case 5 expected failure for 39-char SHA" >&2
  exit 1
fi

rm "$WORKFLOWS_DIR/invalid_hex.yml"

# Case 6: Non-existent directory: fail
set +e
out6=$("$CHECK_ACTION_PINS" "$TMP_DIR/non_existent_dir" 2>&1)
rc6=$?
set -e
if [ "$rc6" -eq 0 ]; then
  echo "FAIL: Case 6 expected non-zero exit code for missing directory" >&2
  exit 1
fi

# Case 7: Directory with no workflow files: pass
EMPTY_DIR="$TMP_DIR/empty"
mkdir -p "$EMPTY_DIR"
"$CHECK_ACTION_PINS" "$EMPTY_DIR" >/dev/null

echo "All action pinning test cases passed successfully."
