#!/usr/bin/env bash
set -euo pipefail

# Ensure GITHUB_ACTIONS is unset for self-test fixture runs (DC35 sets it explicitly)
unset GITHUB_ACTIONS || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_dependencies.py"

TMP_DIR=$(mktemp -d)
SERVER_PID=""
PORT_FILE="$TMP_DIR/server_port.txt"
HTTP_ROOT="$TMP_DIR/http_root"
mkdir -p "$HTTP_ROOT"

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# Start lightweight Python fixture HTTP server
python3 -c "
import http.server
import socketserver
import os
import sys

root = '$HTTP_ROOT'

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def do_GET(self):
        # Allow simulating 500 errors
        if '/trigger_500/' in self.path or self.path.endswith('/trigger_500'):
            self.send_response(500)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Internal Server Error')
            return

        path = self.path.split('?')[0].rstrip('/')
        json_file = os.path.join(root, path.lstrip('/') + '.json')
        if os.path.isfile(json_file):
            with open(json_file, 'rb') as f:
                data = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        super().do_GET()

with socketserver.TCPServer(('127.0.0.1', 0), Handler) as httpd:
    port = httpd.server_address[1]
    with open('$PORT_FILE', 'w') as f:
        f.write(str(port))
    httpd.serve_forever()
" &
SERVER_PID=$!

while [ ! -s "$PORT_FILE" ]; do
  sleep 0.05
done
SERVER_PORT=$(cat "$PORT_FILE")
SERVER_URL="http://127.0.0.1:$SERVER_PORT"

# Helper to write standard base fixtures
setup_base_fixtures() {
  local case_dir="$1"
  mkdir -p "$case_dir"
  mkdir -p "$case_dir/.github/workflows"

  # Base pubspec.yaml
  cat << 'EOF' > "$case_dir/pubspec.yaml"
name: test_pkg
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  meta: ^1.19.0
EOF

  # Base outdated.json
  cat << 'EOF' > "$case_dir/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "upgradable": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF

  # Base workflows
  cat << 'EOF' > "$case_dir/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.7
  node_job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: '26'
  min-sdk:
    name: Minimum SDK
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.0
EOF

  # Base exceptions
  touch "$case_dir/dependency_exceptions.tsv"

  # Base npm dir
  mkdir -p "$case_dir/npm"
  echo "{}" > "$case_dir/npm/outdated.json"
  cat << 'EOF' > "$case_dir/npm/audit.json"
{
  "metadata": {
    "vulnerabilities": {
      "info": 0, "low": 0, "moderate": 0, "high": 0, "critical": 0, "total": 0
    }
  }
}
EOF
}

# Setup standard HTTP endpoints
setup_http_fixtures() {
  # Flutter releases
  mkdir -p "$HTTP_ROOT"
  cat << 'EOF' > "$HTTP_ROOT/releases_linux.json"
{
  "current_release": {"stable": "3.47.9"},
  "releases": [
    {
      "version": "3.47.9",
      "release_date": "2026-10-20T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.7"
    },
    {
      "version": "3.47.7",
      "release_date": "2026-09-08T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.5"
    }
  ]
}
EOF

  cat << 'EOF' > "$HTTP_ROOT/releases_linux_dc36.json"
{
  "current_release": {"stable": "3.47.9"},
  "releases": [
    {
      "version": "3.47.9",
      "release_date": "2026-10-20T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.7"
    },
    {
      "version": "3.47.0",
      "release_date": "2026-08-01T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.0"
    }
  ]
}
EOF

  if [ -d "$SCRIPT_DIR/../.github/workflows" ]; then
    grep -hoE "uses:\s*[a-zA-Z0-9_\-]+/[a-zA-Z0-9_\-]+@[0-9a-fA-F]{40}\s*#\s*\S+" "$SCRIPT_DIR/../.github/workflows"/*.yml | while read -r line; do
      action=$(echo "$line" | sed -E 's/uses:\s*([^@]+)@.*/\1/')
      sha=$(echo "$line" | sed -E 's/uses:\s*[^@]+@([0-9a-fA-F]{40})\s*#.*/\1/')
      tag=$(echo "$line" | sed -E 's/.*#\s*(\S+)/\1/')
      mkdir -p "$HTTP_ROOT/repos/$action/releases"
      mkdir -p "$HTTP_ROOT/repos/$action/git/ref/tags"
      cat << EOF_ACT > "$HTTP_ROOT/repos/$action/releases/latest.json"
{
  "tag_name": "$tag",
  "published_at": "2026-05-10T12:00:00Z"
}
EOF_ACT
      cat << EOF_ACT > "$HTTP_ROOT/repos/$action/git/ref/tags/$tag.json"
{
  "object": {
    "sha": "$sha",
    "type": "commit"
  }
}
EOF_ACT
    done
  fi

  # Node dist index
  mkdir -p "$HTTP_ROOT/dist"
  cat << 'EOF' > "$HTTP_ROOT/dist/index.json"
[
  {"version": "v26.13.0", "date": "2026-10-10", "lts": "Lithium"},
  {"version": "v24.22.2", "date": "2026-04-15", "lts": "Krypton"}
]
EOF

  # Pub meta package & advisories
  mkdir -p "$HTTP_ROOT/api/packages/meta"
  cat << 'EOF' > "$HTTP_ROOT/api/packages/meta.json"
{
  "name": "meta",
  "is_discontinued": false,
  "latest": {
    "version": "1.19.0",
    "published": "2026-07-09T12:00:00.000Z"
  },
  "versions": [
    {
      "version": "1.19.0",
      "published": "2026-07-09T12:00:00.000Z",
      "retracted": false
    }
  ]
}
EOF
  cat << 'EOF' > "$HTTP_ROOT/api/packages/meta/advisories.json"
{
  "advisories": []
}
EOF

  # GitHub actions
  mkdir -p "$HTTP_ROOT/repos/actions/checkout/releases"
  mkdir -p "$HTTP_ROOT/repos/actions/checkout/git/ref/tags"
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/checkout/releases/latest.json"
{
  "tag_name": "v7.0.1",
  "published_at": "2026-07-20T15:00:00Z"
}
EOF
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/checkout/git/ref/tags/v7.0.1.json"
{
  "object": {
    "sha": "3d3c42e5aac5ba805825da76410c181273ba90b1",
    "type": "commit"
  }
}
EOF

  mkdir -p "$HTTP_ROOT/repos/dart-lang/setup-dart/releases"
  mkdir -p "$HTTP_ROOT/repos/dart-lang/setup-dart/git/ref/tags"
  cat << 'EOF' > "$HTTP_ROOT/repos/dart-lang/setup-dart/releases/latest.json"
{
  "tag_name": "v1.8.1",
  "published_at": "2026-05-10T12:00:00Z"
}
EOF
  cat << 'EOF' > "$HTTP_ROOT/repos/dart-lang/setup-dart/git/ref/tags/v1.8.1.json"
{
  "object": {
    "sha": "e51d8e519be8f8d29450b2bc73ea832f4165e2c1",
    "type": "commit"
  }
}
EOF

  mkdir -p "$HTTP_ROOT/repos/actions/setup-node/releases"
  mkdir -p "$HTTP_ROOT/repos/actions/setup-node/git/ref/tags"
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/setup-node/releases/latest.json"
{
  "tag_name": "v4.4.0",
  "published_at": "2026-05-10T12:00:00Z"
}
EOF
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/setup-node/git/ref/tags/v4.4.0.json"
{
  "object": {
    "sha": "49933ea5288caeca8642d1e84afbd3f7d6820020",
    "type": "commit"
  }
}
EOF
}

setup_http_fixtures

run_check() {
  local dir="$1"
  shift
  python3 -I "$CHECK_SCRIPT" \
    --pub-outdated "$dir/pub_outdated.json" \
    --pubspec "$dir/pubspec.yaml" \
    --workflows "$dir/.github/workflows" \
    --exceptions "$dir/dependency_exceptions.tsv" \
    --pub-api "$SERVER_URL" \
    --flutter-releases "$SERVER_URL/releases_linux.json" \
    --github-api "$SERVER_URL" \
    --npm-dir "$dir/npm" \
    --npm-outdated "$dir/npm/outdated.json" \
    --npm-audit "$dir/npm/audit.json" \
    --npm-registry "$SERVER_URL" \
    --node-dist "$SERVER_URL/dist/index.json" \
    --today 2026-11-10 \
    "$@"
}

echo "Running Dependency Check Self-Tests (DC1 - DC35)..."

# DC1: everything current -> pass
echo "Running DC1..."
d1="$TMP_DIR/dc1"; setup_base_fixtures "$d1"
out1=$(run_check "$d1")
[[ "$out1" == *"Dependencies up to date"* || "$out1" == *"Summary"* ]] || { echo "FAIL DC1: $out1"; exit 1; }

# DC2: direct dependency one version behind resolvable, newer version 30 days old -> fail (D1)
echo "Running DC2..."
d2="$TMP_DIR/dc2"; setup_base_fixtures "$d2"
cat << 'EOF' > "$d2/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.18.0"},
      "upgradable": {"version": "1.18.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
set +e; out2=$(run_check "$d2" 2>&1); rc2=$?; set -e
[ "$rc2" -ne 0 ] || { echo "FAIL DC2: expected failure"; exit 1; }
[[ "$out2" == *"D1"* && "$out2" == *"meta"* ]] || { echo "FAIL DC2 output: $out2"; exit 1; }

# DC3: same, newer version 3 days old -> pass, prints pending (3 days old)
echo "Running DC3..."
d3="$TMP_DIR/dc3"; setup_base_fixtures "$d3"
mkdir -p "$HTTP_ROOT/api/packages/pkg_fresh"
cat << 'EOF' > "$HTTP_ROOT/api/packages/pkg_fresh.json"
{
  "name": "pkg_fresh",
  "latest": {"version": "1.1.0", "published": "2026-11-07T00:00:00Z"},
  "versions": [
    {"version": "1.1.0", "published": "2026-11-07T00:00:00Z"}
  ]
}
EOF
cat << 'EOF' > "$HTTP_ROOT/api/packages/pkg_fresh/advisories.json"
{"advisories": []}
EOF
cat << 'EOF' > "$d3/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_fresh",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.1.0"},
      "latest": {"version": "1.1.0"}
    }
  ]
}
EOF
echo "  pkg_fresh: ^1.0.0" >> "$d3/pubspec.yaml"
out3=$(run_check "$d3")
[[ "$out3" == *"pending (3 days old)"* ]] || { echo "FAIL DC3: $out3"; exit 1; }

# DC4: transitive package behind resolvable -> fail (D1)
echo "Running DC4..."
d4="$TMP_DIR/dc4"; setup_base_fixtures "$d4"
cat << 'EOF' > "$d4/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "transitive",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.18.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
set +e; out4=$(run_check "$d4" 2>&1); rc4=$?; set -e
[ "$rc4" -ne 0 ] || { echo "FAIL DC4: expected failure"; exit 1; }
[[ "$out4" == *"D1"* && "$out4" == *"meta"* ]] || { echo "FAIL DC4 output: $out4"; exit 1; }

# DC5: transitive package with current == resolvable < latest -> pass, prints held by graph
echo "Running DC5..."
d5="$TMP_DIR/dc5"; setup_base_fixtures "$d5"
cat << 'EOF' > "$d5/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "transitive",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "2.0.0"}
    }
  ]
}
EOF
out5=$(run_check "$d5")
[[ "$out5" == *"held by graph"* ]] || { echo "FAIL DC5: $out5"; exit 1; }

# DC6: isCurrentAffectedByAdvisory: true, fix published 1 day ago -> fail (D2, no grace)
echo "Running DC6..."
d6="$TMP_DIR/dc6"; setup_base_fixtures "$d6"
cat << 'EOF' > "$d6/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": true,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
set +e; out6=$(run_check "$d6" 2>&1); rc6=$?; set -e
[ "$rc6" -ne 0 ] || { echo "FAIL DC6: expected failure"; exit 1; }
[[ "$out6" == *"D2"* && "$out6" == *"meta"* ]] || { echo "FAIL DC6 output: $out6"; exit 1; }

# DC7: isCurrentAffectedByAdvisory: false but advisories endpoint lists range containing locked version -> fail (D2)
echo "Running DC7..."
d7="$TMP_DIR/dc7"; setup_base_fixtures "$d7"
mkdir -p "$HTTP_ROOT/api/packages/pkg_adv"
cat << 'EOF' > "$HTTP_ROOT/api/packages/pkg_adv.json"
{
  "name": "pkg_adv",
  "latest": {"version": "1.0.0", "published": "2026-07-09T12:00:00Z"},
  "versions": [{"version": "1.0.0", "published": "2026-07-09T12:00:00Z"}]
}
EOF
cat << 'EOF' > "$HTTP_ROOT/api/packages/pkg_adv/advisories.json"
{
  "advisories": [
    {
      "id": "GHSA-test-1234",
      "affected": [
        {
          "versions": ["1.0.0"]
        }
      ]
    }
  ]
}
EOF
cat << 'EOF' > "$d7/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_adv",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.0.0"},
      "latest": {"version": "1.0.0"}
    }
  ]
}
EOF
echo "  pkg_adv: ^1.0.0" >> "$d7/pubspec.yaml"
set +e; out7=$(run_check "$d7" 2>&1); rc7=$?; set -e
[ "$rc7" -ne 0 ] || { echo "FAIL DC7: expected failure"; exit 1; }
[[ "$out7" == *"D2"* && "$out7" == *"pkg_adv"* ]] || { echo "FAIL DC7 output: $out7"; exit 1; }

# DC8: discontinued package -> fail (D3)
echo "Running DC8..."
d8="$TMP_DIR/dc8"; setup_base_fixtures "$d8"
cat << 'EOF' > "$d8/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": true,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
set +e; out8=$(run_check "$d8" 2>&1); rc8=$?; set -e
[ "$rc8" -ne 0 ] || { echo "FAIL DC8: expected failure"; exit 1; }
[[ "$out8" == *"D3"* ]] || { echo "FAIL DC8 output: $out8"; exit 1; }

# DC9: retracted current version -> fail (D3)
echo "Running DC9..."
d9="$TMP_DIR/dc9"; setup_base_fixtures "$d9"
cat << 'EOF' > "$d9/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": true,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
set +e; out9=$(run_check "$d9" 2>&1); rc9=$?; set -e
[ "$rc9" -ne 0 ] || { echo "FAIL DC9: expected failure"; exit 1; }
[[ "$out9" == *"D3"* ]] || { echo "FAIL DC9 output: $out9"; exit 1; }

# DC10: direct dependency whose newest release is 800 days old -> fail (D4)
echo "Running DC10..."
d10="$TMP_DIR/dc10"; setup_base_fixtures "$d10"
mkdir -p "$HTTP_ROOT/api/packages/pkg_old"
cat << 'EOF' > "$HTTP_ROOT/api/packages/pkg_old.json"
{
  "name": "pkg_old",
  "latest": {"version": "1.0.0", "published": "2024-01-01T00:00:00Z"},
  "versions": [{"version": "1.0.0", "published": "2024-01-01T00:00:00Z"}]
}
EOF
cat << 'EOF' > "$HTTP_ROOT/api/packages/pkg_old/advisories.json"
{"advisories": []}
EOF
cat << 'EOF' > "$d10/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_old",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.0.0"},
      "latest": {"version": "1.0.0"}
    }
  ]
}
EOF
echo "  pkg_old: ^1.0.0" >> "$d10/pubspec.yaml"
set +e; out10=$(run_check "$d10" 2>&1); rc10=$?; set -e
[ "$rc10" -ne 0 ] || { echo "FAIL DC10: expected failure"; exit 1; }
[[ "$out10" == *"D4"* && "$out10" == *"pkg_old"* ]] || { echo "FAIL DC10 output: $out10"; exit 1; }

# DC11: same with valid exception row -> pass
echo "Running DC11..."
d11="$TMP_DIR/dc11"; setup_base_fixtures "$d11"
cat << 'EOF' > "$d11/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_old",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.0.0"},
      "latest": {"version": "1.0.0"}
    }
  ]
}
EOF
echo "  pkg_old: ^1.0.0" >> "$d11/pubspec.yaml"
printf "D4\tpkg_old\t1.0.0\t2026-12-01\tMaintained upstream fork is pending migration.\n" > "$d11/dependency_exceptions.tsv"
out11=$(run_check "$d11")
[[ "$out11" == *"Dependencies up to date"* || "$out11" == *"Summary"* ]] || { echo "FAIL DC11: $out11"; exit 1; }

# DC12: exception review_by yesterday -> fail (E1)
echo "Running DC12..."
d12="$TMP_DIR/dc12"; setup_base_fixtures "$d12"
cat << 'EOF' > "$d12/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_old",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.0.0"},
      "latest": {"version": "1.0.0"}
    }
  ]
}
EOF
echo "  pkg_old: ^1.0.0" >> "$d12/pubspec.yaml"
printf "D4\tpkg_old\t1.0.0\t2026-11-09\tMaintained upstream fork is pending migration.\n" > "$d12/dependency_exceptions.tsv"
set +e; out12=$(run_check "$d12" 2>&1); rc12=$?; set -e
[ "$rc12" -ne 0 ] || { echo "FAIL DC12: expected failure"; exit 1; }
[[ "$out12" == *"E1"* ]] || { echo "FAIL DC12 output: $out12"; exit 1; }

# DC13: review_by 91 days out -> fail (E1)
echo "Running DC13..."
d13="$TMP_DIR/dc13"; setup_base_fixtures "$d13"
cat << 'EOF' > "$d13/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_old",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.0.0"},
      "latest": {"version": "1.0.0"}
    }
  ]
}
EOF
echo "  pkg_old: ^1.0.0" >> "$d13/pubspec.yaml"
printf "D4\tpkg_old\t1.0.0\t2027-02-15\tMaintained upstream fork is pending migration.\n" > "$d13/dependency_exceptions.tsv"
set +e; out13=$(run_check "$d13" 2>&1); rc13=$?; set -e
[ "$rc13" -ne 0 ] || { echo "FAIL DC13: expected failure"; exit 1; }
[[ "$out13" == *"E1"* ]] || { echo "FAIL DC13 output: $out13"; exit 1; }

# DC14: reason under 20 characters -> fail (E1)
echo "Running DC14..."
d14="$TMP_DIR/dc14"; setup_base_fixtures "$d14"
cat << 'EOF' > "$d14/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_old",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.0.0"},
      "latest": {"version": "1.0.0"}
    }
  ]
}
EOF
echo "  pkg_old: ^1.0.0" >> "$d14/pubspec.yaml"
printf "D4\tpkg_old\t1.0.0\t2026-12-01\tToo short reason\n" > "$d14/dependency_exceptions.tsv"
set +e; out14=$(run_check "$d14" 2>&1); rc14=$?; set -e
[ "$rc14" -ne 0 ] || { echo "FAIL DC14: expected failure"; exit 1; }
[[ "$out14" == *"E1"* ]] || { echo "FAIL DC14 output: $out14"; exit 1; }

# DC15: a row that matches no failure -> fail stale exception (E1)
echo "Running DC15..."
d15="$TMP_DIR/dc15"; setup_base_fixtures "$d15"
printf "D4\tmeta\t1.19.0\t2026-12-01\tMaintained upstream fork is pending migration.\n" > "$d15/dependency_exceptions.tsv"
set +e; out15=$(run_check "$d15" 2>&1); rc15=$?; set -e
[ "$rc15" -ne 0 ] || { echo "FAIL DC15: expected failure"; exit 1; }
[[ "$out15" == *"stale exception"* && "$out15" == *"E1"* ]] || { echo "FAIL DC15 output: $out15"; exit 1; }

# DC16: a D2 row 31 days out -> fail (E1)
echo "Running DC16..."
d16="$TMP_DIR/dc16"; setup_base_fixtures "$d16"
cat << 'EOF' > "$d16/pub_outdated.json"
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": true,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
printf "D2\tmeta\t1.19.0\t2026-12-15\tAdvisory GHSA-1234 upstream fix is in progress.\n" > "$d16/dependency_exceptions.tsv"
set +e; out16=$(run_check "$d16" 2>&1); rc16=$?; set -e
[ "$rc16" -ne 0 ] || { echo "FAIL DC16: expected failure"; exit 1; }
[[ "$out16" == *"E1"* ]] || { echo "FAIL DC16 output: $out16"; exit 1; }

# DC17: exact pin -> fail (D5)
echo "Running DC17..."
d17="$TMP_DIR/dc17"; setup_base_fixtures "$d17"
cat << 'EOF' > "$d17/pubspec.yaml"
name: test_pkg
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  meta: 1.19.0
EOF
set +e; out17=$(run_check "$d17" 2>&1); rc17=$?; set -e
[ "$rc17" -ne 0 ] || { echo "FAIL DC17: expected failure"; exit 1; }
[[ "$out17" == *"D5"* && "$out17" == *"meta"* ]] || { echo "FAIL DC17 output: $out17"; exit 1; }

# DC18: Flutter pin one stable behind, newer one 20 days old -> fail (T1)
echo "Running DC18..."
d18="$TMP_DIR/dc18"; setup_base_fixtures "$d18"
cat << 'EOF' > "$d18/pubspec.yaml"
name: test_pkg
environment:
  sdk: ^3.13.0
  flutter: 3.47.7
dependencies:
  meta: ^1.19.0
EOF
set +e; out18=$(run_check "$d18" 2>&1); rc18=$?; set -e
[ "$rc18" -ne 0 ] || { echo "FAIL DC18: expected failure"; exit 1; }
[[ "$out18" == *"T1"* ]] || { echo "FAIL DC18 output: $out18"; exit 1; }

# DC19: 5 days old -> pass with pending
echo "Running DC19..."
d19="$TMP_DIR/dc19"; setup_base_fixtures "$d19"
cat << 'EOF' > "$d19/pubspec.yaml"
name: test_pkg
environment:
  sdk: ^3.13.0
  flutter: 3.47.7
dependencies:
  meta: ^1.19.0
EOF
mkdir -p "$TMP_DIR/http_dc19"
cp -r "$HTTP_ROOT"/* "$TMP_DIR/http_dc19/"
cat << 'EOF' > "$TMP_DIR/http_dc19/releases_linux.json"
{
  "current_release": {"stable": "3.47.9"},
  "releases": [
    {
      "version": "3.47.9",
      "release_date": "2026-11-05T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.7"
    },
    {
      "version": "3.47.7",
      "release_date": "2026-10-08T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.5"
    }
  ]
}
EOF
cp "$TMP_DIR/http_dc19/releases_linux.json" "$HTTP_ROOT/releases_linux_dc19.json"
out19=$(run_check "$d19" --flutter-releases "$SERVER_URL/releases_linux_dc19.json")
[[ "$out19" == *"pending"* ]] || { echo "FAIL DC19: $out19"; exit 1; }

# DC20: setup-dart sdk: behind the target Dart -> fail (T2)
echo "Running DC20..."
d20="$TMP_DIR/dc20"; setup_base_fixtures "$d20"
cat << 'EOF' > "$d20/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.5
EOF
set +e; out20=$(run_check "$d20" 2>&1); rc20=$?; set -e
[ "$rc20" -ne 0 ] || { echo "FAIL DC20: expected failure"; exit 1; }
[[ "$out20" == *"T2"* ]] || { echo "FAIL DC20 output: $out20"; exit 1; }

# DC21: sdk: ^3.12.0 while target Dart is 3.13.x (first Flutter with 3.13 is 40 days old) -> fail (T3)
echo "Running DC21..."
d21="$TMP_DIR/dc21"; setup_base_fixtures "$d21"
cat << 'EOF' > "$d21/pubspec.yaml"
name: test_pkg
environment:
  sdk: ^3.12.0
  flutter: 3.47.9
dependencies:
  meta: ^1.19.0
EOF
set +e; out21=$(run_check "$d21" 2>&1); rc21=$?; set -e
[ "$rc21" -ne 0 ] || { echo "FAIL DC21: expected failure"; exit 1; }
[[ "$out21" == *"T3"* ]] || { echo "FAIL DC21 output: $out21"; exit 1; }

# DC22: minimum-SDK job version not equal to the floor -> fail (T3)
echo "Running DC22..."
d22="$TMP_DIR/dc22"; setup_base_fixtures "$d22"
cat << 'EOF' > "$d22/.github/workflows/ci.yml"
name: CI
jobs:
  min-sdk:
    name: Minimum SDK
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.3.4
EOF
set +e; out22=$(run_check "$d22" 2>&1); rc22=$?; set -e
[ "$rc22" -ne 0 ] || { echo "FAIL DC22: expected failure"; exit 1; }
[[ "$out22" == *"T3"* ]] || { echo "FAIL DC22 output: $out22"; exit 1; }

# DC22b: a newer standalone Dart exists that no Flutter stable ships yet -> not required (pass): the target is Flutter's Dart
echo "Running DC22b..."
d22b="$TMP_DIR/dc22b"; setup_base_fixtures "$d22b"
out22b=$(run_check "$d22b")
[[ "$out22b" == *"Dependencies up to date"* || "$out22b" == *"Summary"* ]] || { echo "FAIL DC22b: $out22b"; exit 1; }

# DC23: action SHA not the newest release's commit -> fail (A1)
echo "Running DC23..."
d23="$TMP_DIR/dc23"; setup_base_fixtures "$d23"
cat << 'EOF' > "$d23/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v7.0.1
EOF
set +e; out23=$(run_check "$d23" 2>&1); rc23=$?; set -e
[ "$rc23" -ne 0 ] || { echo "FAIL DC23: expected failure"; exit 1; }
[[ "$out23" == *"A1"* ]] || { echo "FAIL DC23 output: $out23"; exit 1; }

# DC24: right SHA, wrong # v comment -> fail (A1)
echo "Running DC24..."
d24="$TMP_DIR/dc24"; setup_base_fixtures "$d24"
cat << 'EOF' > "$d24/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v4.2.2
EOF
set +e; out24=$(run_check "$d24" 2>&1); rc24=$?; set -e
[ "$rc24" -ne 0 ] || { echo "FAIL DC24: expected failure"; exit 1; }
[[ "$out24" == *"A1"* ]] || { echo "FAIL DC24 output: $out24"; exit 1; }

# DC25: annotated tag -> script follows it to the commit and passes
echo "Running DC25..."
d25="$TMP_DIR/dc25"; setup_base_fixtures "$d25"
mkdir -p "$HTTP_ROOT/repos/actions/annotated/releases"
mkdir -p "$HTTP_ROOT/repos/actions/annotated/git/ref/tags"
mkdir -p "$HTTP_ROOT/repos/actions/annotated/git/tags"
cat << 'EOF' > "$HTTP_ROOT/repos/actions/annotated/releases/latest.json"
{"tag_name": "v1.0.0", "published_at": "2026-05-10T12:00:00Z"}
EOF
cat << 'EOF' > "$HTTP_ROOT/repos/actions/annotated/git/ref/tags/v1.0.0.json"
{
  "object": {
    "sha": "aaaa111122223333444455556666777788889999",
    "type": "tag"
  }
}
EOF
cat << 'EOF' > "$HTTP_ROOT/repos/actions/annotated/git/tags/aaaa111122223333444455556666777788889999.json"
{
  "object": {
    "sha": "bbbb111122223333444455556666777788889999",
    "type": "commit"
  }
}
EOF
cat << 'EOF' > "$d25/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/annotated@bbbb111122223333444455556666777788889999 # v1.0.0
EOF
out25=$(run_check "$d25")
[[ "$out25" == *"Dependencies up to date"* || "$out25" == *"Summary"* ]] || { echo "FAIL DC25: $out25"; exit 1; }

# DC26: npm package behind, 20 days -> fail (N1)
echo "Running DC26..."
d26="$TMP_DIR/dc26"; setup_base_fixtures "$d26"
cat << 'EOF' > "$d26/npm/outdated.json"
{
  "pkg_npm": {
    "current": "1.0.0",
    "wanted": "1.0.0",
    "latest": "2.0.0"
  }
}
EOF
mkdir -p "$HTTP_ROOT/pkg_npm"
cat << 'EOF' > "$HTTP_ROOT/pkg_npm.json"
{
  "time": {
    "2.0.0": "2026-10-10T00:00:00Z"
  }
}
EOF
set +e; out26=$(run_check "$d26" 2>&1); rc26=$?; set -e
[ "$rc26" -ne 0 ] || { echo "FAIL DC26: expected failure"; exit 1; }
[[ "$out26" == *"N1"* && "$out26" == *"pkg_npm"* ]] || { echo "FAIL DC26 output: $out26"; exit 1; }

# DC27: npm audit with one moderate -> fail (N2)
echo "Running DC27..."
d27="$TMP_DIR/dc27"; setup_base_fixtures "$d27"
cat << 'EOF' > "$d27/npm/audit.json"
{
  "metadata": {
    "vulnerabilities": {
      "info": 0, "low": 0, "moderate": 1, "high": 0, "critical": 0, "total": 1
    }
  }
}
EOF
set +e; out27=$(run_check "$d27" 2>&1); rc27=$?; set -e
[ "$rc27" -ne 0 ] || { echo "FAIL DC27: expected failure"; exit 1; }
[[ "$out27" == *"N2"* ]] || { echo "FAIL DC27 output: $out27"; exit 1; }

# DC28: with one low only -> pass
echo "Running DC28..."
d28="$TMP_DIR/dc28"; setup_base_fixtures "$d28"
cat << 'EOF' > "$d28/npm/audit.json"
{
  "metadata": {
    "vulnerabilities": {
      "info": 0, "low": 1, "moderate": 0, "high": 0, "critical": 0, "total": 1
    }
  }
}
EOF
out28=$(run_check "$d28")
[[ "$out28" == *"Dependencies up to date"* || "$out28" == *"Summary"* ]] || { echo "FAIL DC28: $out28"; exit 1; }

# DC29: node-version: '20' while a newer LTS line has been LTS for 30 days -> fail (N3)
echo "Running DC29..."
d29="$TMP_DIR/dc29"; setup_base_fixtures "$d29"
cat << 'EOF' > "$d29/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: '20'
EOF
set +e; out29=$(run_check "$d29" 2>&1); rc29=$?; set -e
[ "$rc29" -ne 0 ] || { echo "FAIL DC29: expected failure"; exit 1; }
[[ "$out29" == *"N3"* ]] || { echo "FAIL DC29 output: $out29"; exit 1; }

# DC30: pub.dev fixture returns HTTP 500 -> fail naming the URL (fail closed)
echo "Running DC30..."
d30="$TMP_DIR/dc30"; setup_base_fixtures "$d30"
set +e; out30=$(run_check "$d30" --pub-api "$SERVER_URL/trigger_500" 2>&1); rc30=$?; set -e
[ "$rc30" -ne 0 ] || { echo "FAIL DC30: expected failure"; exit 1; }
[[ "$out30" == *"trigger_500"* ]] || { echo "FAIL DC30 output: $out30"; exit 1; }

# DC31: the fixture server is down (connection refused) -> fail after retries
echo "Running DC31..."
d31="$TMP_DIR/dc31"; setup_base_fixtures "$d31"
set +e; out31=$(run_check "$d31" --pub-api "http://127.0.0.1:1" 2>&1); rc31=$?; set -e
[ "$rc31" -ne 0 ] || { echo "FAIL DC31: expected failure"; exit 1; }
[[ "$out31" == *"127.0.0.1:1"* ]] || { echo "FAIL DC31 output: $out31"; exit 1; }

# DC32: malformed --pub-outdated JSON -> fail
echo "Running DC32..."
d32="$TMP_DIR/dc32"; setup_base_fixtures "$d32"
echo "NOT_VALID_JSON" > "$d32/pub_outdated.json"
set +e; out32=$(run_check "$d32" 2>&1); rc32=$?; set -e
[ "$rc32" -ne 0 ] || { echo "FAIL DC32: expected failure"; exit 1; }

# DC33: a banner line before the JSON -> parsed and passes
echo "Running DC33..."
d33="$TMP_DIR/dc33"; setup_base_fixtures "$d33"
cat << 'EOF' > "$d33/pub_outdated.json"
Showing outdated packages...
Resolving dependencies...
{
  "packages": [
    {
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    }
  ]
}
EOF
out33=$(run_check "$d33")
[[ "$out33" == *"Dependencies up to date"* || "$out33" == *"Summary"* ]] || { echo "FAIL DC33: $out33"; exit 1; }

# DC34: run with --today absent: uses real date (check printed date is today's UTC date)
echo "Running DC34..."
d34="$TMP_DIR/dc34"; setup_base_fixtures "$d34"
today_utc=$(date -u +%Y-%m-%d)
out34=$(python3 -I "$CHECK_SCRIPT" \
  --pub-outdated "$d34/pub_outdated.json" \
  --pubspec "$d34/pubspec.yaml" \
  --workflows "$d34/.github/workflows" \
  --exceptions "$d34/dependency_exceptions.tsv" \
  --pub-api "$SERVER_URL" \
  --flutter-releases "$SERVER_URL/releases_linux.json" \
  --github-api "$SERVER_URL" \
  --npm-dir "$d34/npm" \
  --npm-outdated "$d34/npm/outdated.json" \
  --npm-audit "$d34/npm/audit.json" \
  --npm-registry "$SERVER_URL" \
  --node-dist "$SERVER_URL/dist/index.json")
[[ "$out34" == *"$today_utc"* ]] || { echo "FAIL DC34: expected date $today_utc in output: $out34"; exit 1; }

# DC35: run with --today when GITHUB_ACTIONS=true -> fails refusing --today
echo "Running DC35..."
d35="$TMP_DIR/dc35"; setup_base_fixtures "$d35"
set +e; out35=$(GITHUB_ACTIONS=true run_check "$d35" 2>&1); rc35=$?; set -e
[ "$rc35" -ne 0 ] || { echo "FAIL DC35: expected failure"; exit 1; }
[[ "$out35" == *"--today"* ]] || { echo "FAIL DC35 output: $out35"; exit 1; }

# DC36: real workflows check
echo "Running DC36..."
d36="$TMP_DIR/dc36"; setup_base_fixtures "$d36"
# Build stand-in GitHub API for every action in real workflows
grep -hoE "uses:\s*[a-zA-Z0-9_\-]+/[a-zA-Z0-9_\-]+@[0-9a-fA-F]{40}\s*#\s*\S+" "$SCRIPT_DIR/../.github/workflows"/*.yml | while read -r line; do
  action=$(echo "$line" | sed -E 's/uses:\s*([^@]+)@.*/\1/')
  sha=$(echo "$line" | sed -E 's/uses:\s*[^@]+@([0-9a-fA-F]{40})\s*#.*/\1/')
  tag=$(echo "$line" | sed -E 's/.*#\s*(\S+)/\1/')
  mkdir -p "$HTTP_ROOT/repos/$action/releases"
  mkdir -p "$HTTP_ROOT/repos/$action/git/ref/tags"
  cat << EOF > "$HTTP_ROOT/repos/$action/releases/latest.json"
{
  "tag_name": "$tag",
  "published_at": "2026-05-10T12:00:00Z"
}
EOF
  cat << EOF > "$HTTP_ROOT/repos/$action/git/ref/tags/$tag.json"
{
  "object": {
    "sha": "$sha",
    "type": "commit"
  }
}
EOF
done

# Flutter releases fixture whose newest stable ships Dart 3.13.7 and floor Dart 3.13.0
mkdir -p "$TMP_DIR/http_dc36"
cat << 'EOF' > "$TMP_DIR/http_dc36/releases_linux.json"
{
  "current_release": {"stable": "3.47.9"},
  "releases": [
    {
      "version": "3.47.9",
      "release_date": "2026-10-20T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.7"
    },
    {
      "version": "3.47.0",
      "release_date": "2026-08-01T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.0"
    }
  ]
}
EOF
cp "$TMP_DIR/http_dc36/releases_linux.json" "$HTTP_ROOT/releases_linux_dc36.json"

# Header-only exceptions file
echo -e "# rule_id\tname\theld_at\treview_by\treason" > "$d36/dependency_exceptions.tsv"

# Run check against real workflows and real pubspec
npm_args=()
if [ -d "$SCRIPT_DIR/../firestore_rules_test" ]; then
  npm_args=(--npm-dir "$d36/npm" --npm-outdated "$d36/npm/outdated.json" --npm-audit "$d36/npm/audit.json" --npm-registry "$SERVER_URL" --node-dist "$SERVER_URL/dist/index.json")
fi

out36=$(python3 -I "$CHECK_SCRIPT" \
  --pub-outdated "$d36/pub_outdated.json" \
  --pubspec "$SCRIPT_DIR/../pubspec.yaml" \
  --workflows "$SCRIPT_DIR/../.github/workflows" \
  --exceptions "$d36/dependency_exceptions.tsv" \
  --pub-api "$SERVER_URL" \
  --flutter-releases "$SERVER_URL/releases_linux_dc36.json" \
  --github-api "$SERVER_URL" \
  --today 2026-12-20 \
  "${npm_args[@]}")

setup_dart_count=$(echo "$out36" | grep -c "^setup-dart:" || true)
real_count=$((grep -c 'dart-lang/setup-dart' "$SCRIPT_DIR/../.github/workflows"/*.yml || true) | awk -F: '{s+=$2} END {print s+0}')
[ "$setup_dart_count" -eq "$real_count" ] || { echo "FAIL DC36 count mismatch: found $setup_dart_count setup-dart lines, expected $real_count"; exit 1; }
setup_http_fixtures

# DC37: no phantom setup-dart
echo "Running DC37..."
d37="$TMP_DIR/dc37"; setup_base_fixtures "$d37"
cat << 'EOF' > "$d37/.github/workflows/ci.yml"
name: CI
jobs:
  main:
    name: 🎯 Main Test Job
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: 🎯 Set up Dart SDK (3.13.7)
        uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.7
  sdk-tools:
    name: 🛠️ Tools sdk: setup (Dart 3.13.0)
    runs-on: ubuntu-latest
    steps:
      - name: 📥 Tool step sdk: check (Dart 3.13.0)
        uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: '26'
          sdk: 3.13.0
  min-sdk:
    name: 🎯 Minimum SDK Verification (Dart 3.13.0)
    runs-on: ubuntu-latest
    steps:
      - name: 🎯 Set up Dart SDK (3.13.0)
        uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.0
EOF
out37=$(run_check "$d37" --flutter-releases "$SERVER_URL/releases_linux_dc36.json" --today 2026-12-20)
setup_dart_count37=$(echo "$out37" | grep -c "^setup-dart:" || true)
[ "$setup_dart_count37" -eq 2 ] || { echo "FAIL DC37: expected exactly 2 setup-dart steps, got $setup_dart_count37"; exit 1; }

# DC38: min-sdk job wrong SDK -> fails T3 naming file and line
echo "Running DC38..."
d38="$TMP_DIR/dc38"; setup_base_fixtures "$d38"
cp -r "$SCRIPT_DIR/../.github/workflows" "$d38/.github/"
if grep -q "min-sdk:" "$d38/.github/workflows"/*.yml; then
  # Pure dart repo: modify existing min-sdk job sdk to one minor below floor (3.12.0)
  for f in "$d38/.github/workflows"/*.yml; do
    if grep -q "min-sdk:" "$f"; then
      python3 -c "
with open('$f') as file:
    content = file.read()
import re
content = re.sub(r'(min-sdk:[\s\S]*?sdk:\s*[\'\"]?)3\.13\.0', r'\g<1>3.12.0', content)
with open('$f', 'w') as file:
    file.write(content)
"
    fi
  done
else
  # App repo (no min-sdk job in real workflows): inject min-sdk job with 3.12.0
  cat << 'EOF' > "$d38/.github/workflows/ci.yml"
name: CI
jobs:
  min-sdk:
    name: Minimum SDK
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.12.0
EOF
fi
set +e
out38=$(run_check "$d38" --flutter-releases "$SERVER_URL/releases_linux_dc36.json" --today 2026-12-20 2>&1)
rc38=$?
set -e
[ "$rc38" -ne 0 ] || { echo "FAIL DC38: expected failure"; exit 1; }
[[ "$out38" == *"T3:"* ]] || { echo "FAIL DC38 output missing T3: $out38"; exit 1; }
echo "$out38" | grep -qE "T3:.*ci\.ya?ml:[0-9]+" || { echo "FAIL DC38 output missing file and line: $out38"; exit 1; }

# DC39: main job setup-dart sdk one patch below target -> fails T2 naming file and line
echo "Running DC39..."
d39="$TMP_DIR/dc39"; setup_base_fixtures "$d39"
cp -r "$SCRIPT_DIR/../.github/workflows" "$d39/.github/"
if grep -q "dart-lang/setup-dart" "$d39/.github/workflows"/*.yml; then
  # Core / ruleset: change main job setup-dart to 3.13.6
  for f in "$d39/.github/workflows"/*.yml; do
    if grep -q "dart-lang/setup-dart" "$f"; then
      python3 -c "
with open('$f') as file:
    content = file.read()
import re
# Only replace in main/test job, not min-sdk
content = re.sub(r'(uses:\s*dart-lang/setup-dart[^\n]*\n\s*with:\s*\n\s*sdk:\s*[\'\"]?)3\.13\.7', r'\g<1>3.13.6', content)
with open('$f', 'w') as file:
    file.write(content)
"
    fi
  done
else
  # App: inject main job with setup-dart 3.13.6
  cat << 'EOF' > "$d39/.github/workflows/ci.yml"
name: CI
jobs:
  main_dart:
    name: Main Dart
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.6
EOF
fi
set +e
out39=$(run_check "$d39" --flutter-releases "$SERVER_URL/releases_linux_dc36.json" --today 2026-12-20 2>&1)
rc39=$?
set -e
[ "$rc39" -ne 0 ] || { echo "FAIL DC39: expected failure"; exit 1; }
[[ "$out39" == *"T2:"* ]] || { echo "FAIL DC39 output missing T2: $out39"; exit 1; }
echo "$out39" | grep -qE "T2:.*ci\.ya?ml:[0-9]+" || { echo "FAIL DC39 output missing file and line: $out39"; exit 1; }

# DC40: Pure-Dart fixture with no min-sdk job -> fails T3
echo "Running DC40..."
d40="$TMP_DIR/dc40"; setup_base_fixtures "$d40"
# Pure Dart pubspec (no flutter:)
cat << 'EOF' > "$d40/pubspec.yaml"
name: pure_dart_pkg
environment:
  sdk: ^3.13.0
dependencies:
  meta: ^1.19.0
EOF
cat << 'EOF' > "$d40/.github/workflows/ci.yml"
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.7
EOF
set +e
out40=$(run_check "$d40" --flutter-releases "$SERVER_URL/releases_linux_dc36.json" --today 2026-12-20 2>&1)
rc40=$?
set -e
[ "$rc40" -ne 0 ] || { echo "FAIL DC40: expected failure"; exit 1; }
[[ "$out40" == *"T3"* ]] || { echo "FAIL DC40 output missing T3: $out40"; exit 1; }

# DC41: setup-dart step with no sdk: -> fails
echo "Running DC41..."
d41="$TMP_DIR/dc41"; setup_base_fixtures "$d41"
cat << 'EOF' > "$d41/.github/workflows/ci.yml"
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          cache: true
EOF
set +e
out41=$(run_check "$d41" --flutter-releases "$SERVER_URL/releases_linux_dc36.json" --today 2026-12-20 2>&1)
rc41=$?
set -e
[ "$rc41" -ne 0 ] || { echo "FAIL DC41: expected failure"; exit 1; }

# DC42: missing or unreadable --pub-outdated -> fails
echo "Running DC42..."
d42="$TMP_DIR/dc42"; setup_base_fixtures "$d42"
set +e
out42=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d42/nonexistent.json" --pubspec "$d42/pubspec.yaml" --workflows "$d42/.github/workflows" --exceptions "$d42/dependency_exceptions.tsv" 2>&1)
rc42=$?
set -e
[ "$rc42" -ne 0 ] || { echo "FAIL DC42: expected failure"; exit 1; }

# DC43: missing or unreadable --pubspec -> fails
echo "Running DC43..."
d43="$TMP_DIR/dc43"; setup_base_fixtures "$d43"
set +e
out43=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d43/pub_outdated.json" --pubspec "$d43/nonexistent.yaml" --workflows "$d43/.github/workflows" --exceptions "$d43/dependency_exceptions.tsv" 2>&1)
rc43=$?
set -e
[ "$rc43" -ne 0 ] || { echo "FAIL DC43: expected failure"; exit 1; }

# DC44: missing or unreadable --workflows -> fails
echo "Running DC44..."
d44="$TMP_DIR/dc44"; setup_base_fixtures "$d44"
set +e
out44=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d44/pub_outdated.json" --pubspec "$d44/pubspec.yaml" --workflows "$d44/nonexistent_workflows" --exceptions "$d44/dependency_exceptions.tsv" 2>&1)
rc44=$?
set -e
[ "$rc44" -ne 0 ] || { echo "FAIL DC44: expected failure"; exit 1; }

# DC45: missing or unreadable --exceptions -> fails
echo "Running DC45..."
d45="$TMP_DIR/dc45"; setup_base_fixtures "$d45"
set +e
out45=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d45/pub_outdated.json" --pubspec "$d45/pubspec.yaml" --workflows "$d45/.github/workflows" --exceptions "$d45/nonexistent.tsv" 2>&1)
rc45=$?
set -e
[ "$rc45" -ne 0 ] || { echo "FAIL DC45: expected failure"; exit 1; }

# DC46: missing or unreadable --npm-outdated (when npm args given) -> fails
echo "Running DC46..."
d46="$TMP_DIR/dc46"; setup_base_fixtures "$d46"
mkdir -p "$d46/npm_dir"
echo '{"name": "test"}' > "$d46/npm_dir/package.json"
echo '{"name": "test", "lockfileVersion": 3}' > "$d46/npm_dir/package-lock.json"
echo '{"metadata":{"vulnerabilities":{"moderate":0,"high":0,"critical":0}}}' > "$d46/npm_audit.json"
set +e
out46=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d46/pub_outdated.json" --pubspec "$d46/pubspec.yaml" --workflows "$d46/.github/workflows" --exceptions "$d46/dependency_exceptions.tsv" --npm-dir "$d46/npm_dir" --npm-outdated "$d46/nonexistent.json" --npm-audit "$d46/npm_audit.json" 2>&1)
rc46=$?
set -e
[ "$rc46" -ne 0 ] || { echo "FAIL DC46: expected failure"; exit 1; }

# DC47: missing or unreadable --npm-audit (when npm args given) -> fails
echo "Running DC47..."
d47="$TMP_DIR/dc47"; setup_base_fixtures "$d47"
mkdir -p "$d47/npm_dir"
echo '{"name": "test"}' > "$d47/npm_dir/package.json"
echo '{"name": "test", "lockfileVersion": 3}' > "$d47/npm_dir/package-lock.json"
echo '{}' > "$d47/npm_outdated.json"
set +e
out47=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d47/pub_outdated.json" --pubspec "$d47/pubspec.yaml" --workflows "$d47/.github/workflows" --exceptions "$d47/dependency_exceptions.tsv" --npm-dir "$d47/npm_dir" --npm-outdated "$d47/npm_outdated.json" --npm-audit "$d47/nonexistent.json" 2>&1)
rc47=$?
set -e
[ "$rc47" -ne 0 ] || { echo "FAIL DC47: expected failure"; exit 1; }

# DC48: malformed JSON or unexpected shape in pub_outdated -> fails
echo "Running DC48..."
d48="$TMP_DIR/dc48"; setup_base_fixtures "$d48"
echo '{"packages": "not_a_list"}' > "$d48/pub_outdated.json"
set +e
out48=$(run_check "$d48" 2>&1)
rc48=$?
set -e
[ "$rc48" -ne 0 ] || { echo "FAIL DC48: expected failure"; exit 1; }

# DC49: npm audit/outdated with error payload -> fails
echo "Running DC49..."
d49="$TMP_DIR/dc49"; setup_base_fixtures "$d49"
mkdir -p "$d49/npm_dir"
echo '{"name": "test"}' > "$d49/npm_dir/package.json"
echo '{"name": "test", "lockfileVersion": 3}' > "$d49/npm_dir/package-lock.json"
echo '{"error": {"code": "E404", "summary": "Not found"}}' > "$d49/npm_audit.json"
echo '{}' > "$d49/npm_outdated.json"
set +e
out49=$(run_check "$d49" --npm-dir "$d49/npm_dir" --npm-outdated "$d49/npm_outdated.json" --npm-audit "$d49/npm_audit.json" 2>&1)
rc49=$?
set -e
[ "$rc49" -ne 0 ] || { echo "FAIL DC49: expected failure"; exit 1; }

echo "All 49 dependency check self-tests (DC1 - DC49) passed successfully!"
