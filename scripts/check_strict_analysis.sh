#!/usr/bin/env bash
set -euo pipefail

CANARY="lib/zz_strict_canary.dart"

cleanup() {
  rm -f "$CANARY"
}
trap cleanup EXIT INT TERM

if [ ! -f "analysis_options.yaml" ]; then
  echo "FAIL: analysis_options.yaml not found" >&2
  exit 1
fi

if grep -qE '^[[:space:]]*errors[[:space:]]*:' analysis_options.yaml; then
  echo "FAIL: analysis_options.yaml contains an 'errors:' key" >&2
  exit 1
fi

ALLOWLIST=(
  "lib/crdt/crdt_lww_register.dart:avoid_dynamic_calls"
  "test/models/campaign_profile_map_tokens_test.dart:avoid_print"
)

is_allowed_ignore() {
  local candidate="$1"
  for allowed in "${ALLOWLIST[@]}"; do
    if [ "$candidate" = "$allowed" ]; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r match; do
  [ -z "$match" ] && continue
  file_path="${match%%:*}"
  comment_part="${match#*:}"
  codes_raw="$(printf '%s\n' "$comment_part" | sed -E 's/.*\/\/[[:space:]]*ignore(_for_file)?:[[:space:]]*//')"
  IFS=',' read -ra codes <<< "$codes_raw"
  if [ "${#codes[@]}" -eq 0 ]; then
    echo "FAIL: disallowed empty ignore comment in ${file_path}" >&2
    exit 1
  fi
  for raw_code in "${codes[@]}"; do
    code="$(printf '%s' "$raw_code" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//;s/[[:space:]].*$//')"
    entry="${file_path}:${code}"
    if ! is_allowed_ignore "$entry"; then
      echo "FAIL: disallowed ignore comment: ${entry}" >&2
      exit 1
    fi
  done
done < <(grep -rnE '//[[:space:]]*ignore(_for_file)?:' lib test 2>/dev/null || true)

cat > "$CANARY" <<'EOF'
int canaryCast(dynamic x) => x;
List canaryRaw() => <int>[];
final canaryInf = [];
EOF

set +e
ANALYZE_OUTPUT="$(dart analyze 2>&1)"
ANALYZE_EXIT=$?
set -e

echo "$ANALYZE_OUTPUT"

if [ "$ANALYZE_EXIT" -eq 0 ]; then
  echo "FAIL: dart analyze succeeded on canary file ${CANARY}" >&2
  exit 1
fi

UNWRAPPED="$(printf '%s\n' "$ANALYZE_OUTPUT" | sed ':a;N;$!ba;s/\n[[:space:]]\+/ /g')"

for expected_code in return_of_invalid_type strict_raw_type inference_failure_on_collection_literal; do
  if ! printf '%s\n' "$UNWRAPPED" | grep -F "$CANARY" | grep -Eq "(^|[^a-z0-9_])${expected_code}($|[^a-z0-9_])"; then
    echo "FAIL: dart analyze did not report ${expected_code} at ${CANARY}" >&2
    exit 1
  fi
done

cleanup
echo "OK: strict analysis canary verified (return_of_invalid_type, strict_raw_type, inference_failure_on_collection_literal)."

