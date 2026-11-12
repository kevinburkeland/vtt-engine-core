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

        # Always check for .json file first before super().do_GET() redirects directories
        req_path = self.path.split('?')[0].rstrip('/')
        json_file = os.path.join(root, req_path.lstrip('/') + '.json')
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
  echo "{}" > "$case_dir/npm/package.json"
  echo "{}" > "$case_dir/npm/outdated.json"
  echo "0" > "$case_dir/npm/outdated_status.json"
  echo "0" > "$case_dir/npm/audit_status.json"
  touch "$case_dir/npm/outdated.stderr"
  touch "$case_dir/npm/audit.stderr"
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
      cat << EOF_ACT > "$HTTP_ROOT/repos/$action/releases.json"
[
  {
    "tag_name": "$tag",
    "published_at": "2026-05-10T12:00:00Z"
  }
]
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
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/checkout/releases.json"
[
  {
    "tag_name": "v7.0.1",
    "published_at": "2026-07-20T15:00:00Z"
  }
]
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
  cat << 'EOF' > "$HTTP_ROOT/repos/dart-lang/setup-dart/releases.json"
[
  {
    "tag_name": "v1.8.1",
    "published_at": "2026-05-10T12:00:00Z"
  }
]
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
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/setup-node/releases.json"
[
  {
    "tag_name": "v4.4.0",
    "published_at": "2026-05-10T12:00:00Z"
  }
]
EOF
  cat << 'EOF' > "$HTTP_ROOT/repos/actions/setup-node/git/ref/tags/v4.4.0.json"
{
  "object": {
    "sha": "49933ea5288caeca8642d1e84afbd3f7d6820020",
    "type": "commit"
  }
}
EOF

  # Mock npm registry endpoints for overrides
  cat << 'EOF' > "$HTTP_ROOT/pkg_override.json"
{
  "name": "pkg_override",
  "time": {
    "1.0.0": "2026-11-01T00:00:00Z"
  }
}
EOF

  cat << 'EOF' > "$HTTP_ROOT/pkg_lag.json"
{
  "name": "pkg_lag",
  "time": {
    "1.0.0": "2026-10-01T00:00:00Z",
    "1.0.1": "2026-10-21T00:00:00Z"
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
    --npm-outdated-status "$dir/npm/outdated_status.json" \
    --npm-audit-status "$dir/npm/audit_status.json" \
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
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    },
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
      "package": "meta",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.19.0"},
      "resolvable": {"version": "1.19.0"},
      "latest": {"version": "1.19.0"}
    },
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
sed -i 's/meta: \^1.19.0/pkg_old: ^1.0.0/' "$d10/pubspec.yaml"
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
sed -i 's/meta: \^1.19.0/pkg_old: ^1.0.0/' "$d11/pubspec.yaml"
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
sed -i 's/meta: \^1.19.0/pkg_old: ^1.0.0/' "$d12/pubspec.yaml"
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
sed -i 's/meta: \^1.19.0/pkg_old: ^1.0.0/' "$d13/pubspec.yaml"
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
sed -i 's/meta: \^1.19.0/pkg_old: ^1.0.0/' "$d14/pubspec.yaml"
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
  --npm-outdated-status "$d34/npm/outdated_status.json" \
  --npm-audit-status "$d34/npm/audit_status.json" \
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

# Flutter releases fixture built dynamically from repo workflows/pubspec
mkdir -p "$TMP_DIR/http_dc36"
today_dc36=$(python3 -I - "$SCRIPT_DIR/.." "$HTTP_ROOT" "$TMP_DIR/http_dc36/releases_linux.json" << 'PYEOF'
import os, sys, re, json
from datetime import datetime, timezone, timedelta

repo_root = sys.argv[1]
http_root = sys.argv[2]
out_fixture = sys.argv[3]

ci_path = os.path.join(repo_root, '.github/workflows/ci.yml')
pubspec_path = os.path.join(repo_root, 'pubspec.yaml')

target_dart = None
if os.path.exists(ci_path):
    with open(ci_path) as f:
        content = f.read()
    m = re.search(r'^\s*test:\s*[\s\S]*?uses:\s*dart-lang/setup-dart[^\n]*\s*with:\s*sdk:\s*[\x27\"]?([0-9]+\.[0-9]+\.[0-9]+)[\x27\"]?', content, re.MULTILINE)
    if m:
        target_dart = m.group(1)

flutter_ver = None
if os.path.exists(pubspec_path):
    with open(pubspec_path) as f:
        p_content = f.read()
    fm = re.search(r'^\s*flutter:\s*[\x27\"]?([0-9]+\.[0-9]+\.[0-9]+)[\x27\"]?', p_content, re.MULTILINE)
    if fm:
        flutter_ver = fm.group(1)

# Known Flutter releases fixture mapping
known_releases = {
    '3.50.0': '3.14.0',
}
rel_json_path = os.path.join(http_root, 'releases_linux.json')
if os.path.exists(rel_json_path):
    with open(rel_json_path) as f:
        base_data = json.load(f)
        for r in base_data.get('releases', []):
            if 'version' in r and 'dart_sdk_version' in r:
                known_releases[r['version']] = r['dart_sdk_version']

if not target_dart and flutter_ver:
    target_dart = known_releases.get(flutter_ver)

if not target_dart:
    target_dart = '3.14.0'

major, minor, patch = target_dart.split('.')
floor_dart = f"{major}.{minor}.0"

if flutter_ver:
    newest_flutter_ver = flutter_ver
else:
    newest_flutter_ver = '3.50.0' if target_dart == '3.14.0' else f"{major}.{minor}.0"

floor_flutter_ver = None
for f_v, d_v in known_releases.items():
    if d_v == floor_dart:
        floor_flutter_ver = f_v
        break
if not floor_flutter_ver:
    floor_flutter_ver = newest_flutter_ver

newest_date = datetime(2026, 10, 20, 0, 0, 0, tzinfo=timezone.utc)
today_calc = (newest_date + timedelta(days=60)).strftime('%Y-%m-%d')

releases = [
    {
        'version': newest_flutter_ver,
        'release_date': newest_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'channel': 'stable',
        'dart_sdk_version': target_dart,
    }
]
if floor_dart != target_dart:
    floor_date = newest_date - timedelta(days=60)
    releases.append({
        'version': floor_flutter_ver,
        'release_date': floor_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'channel': 'stable',
        'dart_sdk_version': floor_dart,
    })

data = {
    'current_release': {'stable': newest_flutter_ver},
    'releases': releases,
}
with open(out_fixture, 'w') as f:
    json.dump(data, f, indent=2)

print(today_calc)
PYEOF
)
cp "$TMP_DIR/http_dc36/releases_linux.json" "$HTTP_ROOT/releases_linux_dc36.json"

# Populate pub_outdated.json with all dependencies from repo pubspec matching declared floors
python3 -c "
import json, re, os
with open('$SCRIPT_DIR/../pubspec.yaml') as f:
    lines = f.readlines()
pkgs = {}
sec = None
for l in lines:
    if l.startswith('dependencies:'): sec = 'dep'
    elif l.startswith('dev_dependencies:'): sec = 'dev'
    elif not l.startswith(' ') and not l.startswith('\t'): sec = None
    elif sec:
        m = re.match(r'^\s+([a-zA-Z0-9_\-]+):\s*[\^]?([0-9]+\.[0-9]+\.[0-9]+)', l)
        if m and m.group(1) not in ('flutter', 'vtt_engine_core', 'vtt_ruleset_dnd5e'):
            pkgs[m.group(1)] = m.group(2)
        else:
            m2 = re.match(r'^\s+([a-zA-Z0-9_\-]+):', l)
            if m2 and m2.group(1) not in ('flutter', 'vtt_engine_core', 'vtt_ruleset_dnd5e'):
                pkgs[m2.group(1)] = '1.0.0'
outdated = {'packages': [{'package': p, 'kind': 'direct', 'isDiscontinued': False, 'isCurrentRetracted': False, 'isCurrentAffectedByAdvisory': False, 'current': {'version': v}, 'resolvable': {'version': v}, 'latest': {'version': v}} for p, v in pkgs.items()]}
for p, v in pkgs.items():
    os.makedirs('$HTTP_ROOT/api/packages/' + p, exist_ok=True)
    with open('$HTTP_ROOT/api/packages/' + p + '.json', 'w') as f:
        json.dump({'name': p, 'latest': {'version': v, 'published': '2026-10-01T00:00:00Z'}, 'versions': [{'version': v, 'published': '2026-10-01T00:00:00Z'}]}, f)
    with open('$HTTP_ROOT/api/packages/' + p + '/advisories.json', 'w') as f:
        json.dump({'advisories': []}, f)
with open('$d36/pub_outdated.json', 'w') as f:
    json.dump(outdated, f, indent=2)
"

# Header-only exceptions file
echo -e "# rule_id\tname\theld_at\treview_by\treason" > "$d36/dependency_exceptions.tsv"

# Run check against real workflows and real pubspec
npm_args=()
if [ -d "$SCRIPT_DIR/../firestore_rules_test" ]; then
  npm_args=(--npm-dir "$d36/npm" --npm-outdated "$d36/npm/outdated.json" --npm-audit "$d36/npm/audit.json" --npm-outdated-status "$d36/npm/outdated_status.json" --npm-audit-status "$d36/npm/audit_status.json" --npm-registry "$SERVER_URL" --node-dist "$SERVER_URL/dist/index.json")
fi

out36=$(python3 -I "$CHECK_SCRIPT" \
  --pub-outdated "$d36/pub_outdated.json" \
  --pubspec "$SCRIPT_DIR/../pubspec.yaml" \
  --workflows "$SCRIPT_DIR/../.github/workflows" \
  --exceptions "$d36/dependency_exceptions.tsv" \
  --pub-api "$SERVER_URL" \
  --flutter-releases "$SERVER_URL/releases_linux_dc36.json" \
  --github-api "$SERVER_URL" \
  --today "$today_dc36" \
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
echo "0" > "$d46/npm_status.json"
set +e
out46=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d46/pub_outdated.json" --pubspec "$d46/pubspec.yaml" --workflows "$d46/.github/workflows" --exceptions "$d46/dependency_exceptions.tsv" --npm-dir "$d46/npm_dir" --npm-outdated "$d46/nonexistent.json" --npm-audit "$d46/npm_audit.json" --npm-outdated-status "$d46/npm_status.json" --npm-audit-status "$d46/npm_status.json" 2>&1)
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
echo "0" > "$d47/npm_status.json"
set +e
out47=$(python3 "$CHECK_SCRIPT" --pub-outdated "$d47/pub_outdated.json" --pubspec "$d47/pubspec.yaml" --workflows "$d47/.github/workflows" --exceptions "$d47/dependency_exceptions.tsv" --npm-dir "$d47/npm_dir" --npm-outdated "$d47/npm_outdated.json" --npm-audit "$d47/nonexistent.json" --npm-outdated-status "$d47/npm_status.json" --npm-audit-status "$d47/npm_status.json" 2>&1)
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


# DC50: pub package wait count measured from first newer release date (not newest)
echo "Running DC50..."
d50="$TMP_DIR/dc50"; setup_base_fixtures "$d50"
mkdir -p "$HTTP_ROOT/api/packages/pkg_multi_pub"
cat << 'EOF2' > "$HTTP_ROOT/api/packages/pkg_multi_pub.json"
{
  "name": "pkg_multi_pub",
  "latest": {"version": "1.2.0", "published": "2026-11-09T00:00:00Z"},
  "versions": [
    {"version": "1.0.0", "published": "2026-01-01T00:00:00Z"},
    {"version": "1.1.0", "published": "2026-10-01T00:00:00Z"},
    {"version": "1.2.0", "published": "2026-11-09T00:00:00Z"}
  ]
}
EOF2
cat << 'EOF2' > "$HTTP_ROOT/api/packages/pkg_multi_pub/advisories.json"
{"advisories": []}
EOF2
cat << 'EOF2' > "$d50/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_multi_pub",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.0.0"},
      "resolvable": {"version": "1.2.0"},
      "latest": {"version": "1.2.0"}
    }
  ]
}
EOF2
sed -i 's/meta: \^1.19.0/pkg_multi_pub: ^1.0.0/' "$d50/pubspec.yaml"
set +e
out50=$(run_check "$d50" --today 2026-11-10 2>&1)
rc50=$?
set -e
[ "$rc50" -ne 0 ] || { echo "FAIL DC50: expected failure for package behind older intermediate release"; exit 1; }
[[ "$out50" == *"D1:"* && "$out50" == *"pkg_multi_pub"* ]] || { echo "FAIL DC50 output: $out50"; exit 1; }

# DC51: Action wait count measured from first newer release date
echo "Running DC51..."
d51="$TMP_DIR/dc51"; setup_base_fixtures "$d51"
mkdir -p "$HTTP_ROOT/repos/actions/checkout/releases"
cat << 'EOF2' > "$HTTP_ROOT/repos/actions/checkout/releases/latest.json"
{
  "tag_name": "v7.0.1",
  "published_at": "2026-11-08T00:00:00Z"
}
EOF2
cat << 'EOF2' > "$HTTP_ROOT/repos/actions/checkout/releases.json"
[
  {"tag_name": "v7.0.1", "published_at": "2026-11-08T00:00:00Z"},
  {"tag_name": "v7.0.0", "published_at": "2026-10-01T00:00:00Z"},
  {"tag_name": "v6.0.0", "published_at": "2026-01-01T00:00:00Z"}
]
EOF2
cat << 'EOF2' > "$d51/.github/workflows/ci.yml"
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v6.0.0
EOF2
set +e
out51=$(run_check "$d51" --today 2026-11-10 2>&1)
rc51=$?
set -e
[ "$rc51" -ne 0 ] || { echo "FAIL DC51: expected failure for action behind older intermediate release"; exit 1; }
[[ "$out51" == *"A1:"* ]] || { echo "FAIL DC51 output: $out51"; exit 1; }

# DC52: npm package wait count measured from first newer release date
echo "Running DC52..."
d52="$TMP_DIR/dc52"; setup_base_fixtures "$d52"
mkdir -p "$d52/npm_dir" "$HTTP_ROOT/pkg_multi_npm"
echo '{"name": "test"}' > "$d52/npm_dir/package.json"
echo '{"name": "test", "lockfileVersion": 3}' > "$d52/npm_dir/package-lock.json"
echo '{"metadata":{"vulnerabilities":{"moderate":0,"high":0,"critical":0}}}' > "$d52/npm_audit.json"
cat << 'EOF2' > "$HTTP_ROOT/pkg_multi_npm.json"
{
  "name": "pkg_multi_npm",
  "time": {
    "1.0.0": "2026-01-01T00:00:00Z",
    "1.1.0": "2026-10-01T00:00:00Z",
    "1.2.0": "2026-11-09T00:00:00Z"
  }
}
EOF2
cat << 'EOF2' > "$d52/npm_outdated.json"
{
  "pkg_multi_npm": {
    "current": "1.0.0",
    "latest": "1.2.0"
  }
}
EOF2
set +e
out52=$(run_check "$d52" --npm-dir "$d52/npm_dir" --npm-outdated "$d52/npm_outdated.json" --npm-audit "$d52/npm_audit.json" --today 2026-11-10 2>&1)
rc52=$?
set -e
[ "$rc52" -ne 0 ] || { echo "FAIL DC52: expected failure for npm pkg behind older intermediate release"; exit 1; }
[[ "$out52" == *"N1:"* ]] || { echo "FAIL DC52 output: $out52"; exit 1; }

# DC53: Dart SDK wait count measured from first Flutter stable release shipping target Dart
echo "Running DC53..."
d53="$TMP_DIR/dc53"; setup_base_fixtures "$d53"
cat << 'EOF2' > "$HTTP_ROOT/releases_linux_dc53.json"
{
  "releases": [
    {
      "version": "3.47.9",
      "release_date": "2026-11-09T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.7"
    },
    {
      "version": "3.47.0",
      "release_date": "2026-10-01T00:00:00Z",
      "channel": "stable",
      "dart_sdk_version": "3.13.7"
    }
  ]
}
EOF2
if ls "$d53"/.github/workflows/*.yml 1> /dev/null 2>&1; then
  for f in "$d53"/.github/workflows/*.yml; do
    python3 -c "
with open('$f') as file:
    content = file.read()
import re
content = re.sub(r'sdk:\s*[\'\"]?3\.\d+\.\d+[\'\"]?', 'sdk: 3.12.0', content)
with open('$f', 'w') as file:
    file.write(content)
"
  done
fi
set +e
out53=$(run_check "$d53" --flutter-releases "$SERVER_URL/releases_linux_dc53.json" --today 2026-11-10 2>&1)
rc53=$?
set -e
[ "$rc53" -ne 0 ] || { echo "FAIL DC53: expected failure for setup-dart behind first release"; exit 1; }
[[ "$out53" == *"T2:"* || "$out53" == *"T3:"* ]] || { echo "FAIL DC53 output: $out53"; exit 1; }

# DC54: Node LTS wait count measured from date version became LTS
echo "Running DC54..."
d54="$TMP_DIR/dc54"; setup_base_fixtures "$d54"
cat << 'EOF2' > "$HTTP_ROOT/dist/index_dc54.json"
[
  {
    "version": "v26.1.0",
    "date": "2026-11-09",
    "lts": "Iron"
  },
  {
    "version": "v26.0.0",
    "date": "2026-10-01",
    "lts": "Iron"
  }
]
EOF2
cat << 'EOF2' > "$d54/.github/workflows/ci.yml"
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v4.4.0
        with:
          node-version: 24
EOF2
set +e
out54=$(run_check "$d54" --node-dist "$SERVER_URL/dist/index_dc54.json" --today 2026-11-10 2>&1)
rc54=$?
set -e
[ "$rc54" -ne 0 ] || { echo "FAIL DC54: expected failure for node-version behind first LTS release"; exit 1; }
[[ "$out54" == *"N3:"* ]] || { echo "FAIL DC54 output: $out54"; exit 1; }

# DC55: Version floors current in pubspec: exact floor matches target minor
echo "Running DC55..."
d55="$TMP_DIR/dc55"; setup_base_fixtures "$d55"
cat << 'EOF2' > "$d55/pubspec.yaml"
name: test_pkg
environment:
  sdk: '^3.12.0'
dependencies:
  meta: ^1.19.0
EOF2
set +e
out55=$(run_check "$d55" --today 2026-12-01 2>&1)
rc55=$?
set -e
[ "$rc55" -ne 0 ] || { echo "FAIL DC55: expected failure for outdated SDK floor"; exit 1; }
[[ "$out55" == *"T3:"* ]] || { echo "FAIL DC55 output: $out55"; exit 1; }

# DC56: N1: current ahead of latest tag -> pass with 'ahead of latest tag'
echo "Running DC56..."
d56="$TMP_DIR/dc56"; setup_base_fixtures "$d56"
mkdir -p "$d56/npm_dir"
echo '{"name": "test"}' > "$d56/npm_dir/package.json"
echo '{"name": "test", "lockfileVersion": 3}' > "$d56/npm_dir/package-lock.json"
echo '{"metadata":{"vulnerabilities":{"moderate":0,"high":0,"critical":0}}}' > "$d56/npm_audit.json"
cat << 'EOF2' > "$d56/npm_outdated.json"
{
  "pkg_ahead": {
    "current": "6.0.0",
    "latest": "5.0.2"
  }
}
EOF2
set +e
out56=$(run_check "$d56" --npm-dir "$d56/npm_dir" --npm-outdated "$d56/npm_outdated.json" --npm-audit "$d56/npm_audit.json" --today 2026-11-10 2>&1)
rc56=$?; set -e
[ "$rc56" -eq 0 ] || { echo "FAIL DC56: expected pass for current ahead of latest: $out56"; exit 1; }
[[ "$out56" == *"ahead of latest tag"* ]] || { echo "FAIL DC56 output missing 'ahead of latest tag': $out56"; exit 1; }

# DC57: Rule D6: declared floor behind current -> fail D6
echo "Running DC57..."
d57="$TMP_DIR/dc57"; setup_base_fixtures "$d57"
mkdir -p "$HTTP_ROOT/api/packages/pkg_d6"
echo '{"advisories": []}' > "$HTTP_ROOT/api/packages/pkg_d6/advisories.json"
cat << 'EOF2' > "$HTTP_ROOT/api/packages/pkg_d6.json"
{
  "name": "pkg_d6",
  "latest": {"version": "1.17.0", "published": "2026-01-01T00:00:00Z"},
  "versions": [
    {"version": "1.12.0", "published": "2025-01-01T00:00:00Z"},
    {"version": "1.13.0", "published": "2025-06-01T00:00:00Z"},
    {"version": "1.17.0", "published": "2026-01-01T00:00:00Z"}
  ]
}
EOF2
cat << 'EOF2' > "$d57/pubspec.yaml"
name: test_pkg
environment:
  sdk: '^3.13.0'
dependencies:
  pkg_d6: ^1.12.0
EOF2
cat << 'EOF2' > "$d57/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_d6",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.17.0"},
      "resolvable": {"version": "1.17.0"},
      "latest": {"version": "1.17.0"}
    }
  ]
}
EOF2
set +e
out57=$(run_check "$d57" --today 2026-11-10 2>&1)
rc57=$?; set -e
[ "$rc57" -ne 0 ] || { echo "FAIL DC57: expected failure for declared floor behind current"; exit 1; }
[[ "$out57" == *"D6:"* && "$out57" == *"pkg_d6"* ]] || { echo "FAIL DC57 output: $out57"; exit 1; }

# DC58: Rule D6: declared floor equal to current -> pass
echo "Running DC58..."
d58="$TMP_DIR/dc58"; setup_base_fixtures "$d58"
cat << 'EOF2' > "$d58/pubspec.yaml"
name: test_pkg
environment:
  sdk: '^3.13.0'
dependencies:
  pkg_d6: ^1.17.0
EOF2
cat << 'EOF2' > "$d58/pub_outdated.json"
{
  "packages": [
    {
      "package": "pkg_d6",
      "kind": "direct",
      "isDiscontinued": false,
      "isCurrentRetracted": false,
      "isCurrentAffectedByAdvisory": false,
      "current": {"version": "1.17.0"},
      "resolvable": {"version": "1.17.0"},
      "latest": {"version": "1.17.0"}
    }
  ]
}
EOF2
set +e
out58=$(run_check "$d58" --today 2026-11-10 2>&1)
rc58=$?; set -e
[ "$rc58" -eq 0 ] || { echo "FAIL DC58: expected pass when floor equals current: $out58"; exit 1; }

# DC59: Rule D6: Git and SDK dependencies skipped
echo "Running DC59..."
d59="$TMP_DIR/dc59"; setup_base_fixtures "$d59"
cat << 'EOF2' > "$d59/pubspec.yaml"
name: test_pkg
environment:
  sdk: '^3.13.0'
dependencies:
  vtt_engine_core:
    git:
      url: https://github.com/kevinburkeland/vtt-engine-core.git
      ref: main
  flutter:
    sdk: flutter
EOF2
cat << 'EOF2' > "$d59/pub_outdated.json"
{
  "packages": []
}
EOF2
set +e
out59=$(run_check "$d59" --today 2026-11-10 2>&1)
rc59=$?; set -e
[ "$rc59" -eq 0 ] || { echo "FAIL DC59: expected pass for git/sdk dependencies: $out59"; exit 1; }

# DC60: an undeclared override -> fails N4 naming it
echo "Running DC60..."
d60="$TMP_DIR/dc60"; setup_base_fixtures "$d60"
cat << 'EOF' > "$d60/npm/package.json"
{
  "overrides": {
    "pkg_override": "1.0.0"
  }
}
EOF
set +e
out60=$(run_check "$d60" --today 2026-11-10 2>&1)
rc60=$?; set -e
[ "$rc60" -ne 0 ] || { echo "FAIL DC60: expected failure for undeclared override"; exit 1; }
[[ "$out60" == *"N4"* && "$out60" == *"pkg_override"* ]] || { echo "FAIL DC60 output: $out60"; exit 1; }

# DC61: a declared override -> pass
echo "Running DC61..."
d61="$TMP_DIR/dc61"; setup_base_fixtures "$d61"
cat << 'EOF' > "$d61/npm/package.json"
{
  "overrides": {
    "pkg_override": "1.0.0"
  }
}
EOF
printf "N4\tpkg_override\t1.0.0\t2026-11-20\tRemoves GHSA-1111-2222-3333 in top-level parent\n" > "$d61/dependency_exceptions.tsv"
out61=$(run_check "$d61" --today 2026-11-10)
[[ "$out61" == *"Summary"* ]] || { echo "FAIL DC61: $out61"; exit 1; }

# DC62: an override one patch behind the newest in its major, newer release 20 days old -> fails
echo "Running DC62..."
d62="$TMP_DIR/dc62"; setup_base_fixtures "$d62"
cat << 'EOF' > "$d62/npm/package.json"
{
  "overrides": {
    "pkg_lag": "1.0.0"
  }
}
EOF
printf "N4\tpkg_lag\t1.0.0\t2026-11-20\tRemoves GHSA-1111-2222-3333 in top-level parent\n" > "$d62/dependency_exceptions.tsv"
set +e
out62=$(run_check "$d62" --today 2026-11-10 2>&1)
rc62=$?; set -e
[ "$rc62" -ne 0 ] || { echo "FAIL DC62: expected failure for lag override"; exit 1; }
[[ "$out62" == *"N4"* && "$out62" == *"pkg_lag"* ]] || { echo "FAIL DC62 output: $out62"; exit 1; }

# DC63: a range value (^11.0.0) -> fails
echo "Running DC63..."
d63="$TMP_DIR/dc63"; setup_base_fixtures "$d63"
cat << 'EOF' > "$d63/npm/package.json"
{
  "overrides": {
    "pkg_override": "^11.0.0"
  }
}
EOF
printf "N4\tpkg_override\t^11.0.0\t2026-11-20\tRemoves GHSA-1111-2222-3333 in top-level parent\n" > "$d63/dependency_exceptions.tsv"
set +e
out63=$(run_check "$d63" --today 2026-11-10 2>&1)
rc63=$?; set -e
[ "$rc63" -ne 0 ] || { echo "FAIL DC63: expected failure for range override"; exit 1; }
[[ "$out63" == *"N4"* ]] || { echo "FAIL DC63 output: $out63"; exit 1; }

# DC64: a nested object -> fails
echo "Running DC64..."
d64="$TMP_DIR/dc64"; setup_base_fixtures "$d64"
cat << 'EOF' > "$d64/npm/package.json"
{
  "overrides": {
    "parent_pkg": {
      "child_pkg": "1.0.0"
    }
  }
}
EOF
set +e
out64=$(run_check "$d64" --today 2026-11-10 2>&1)
rc64=$?; set -e
[ "$rc64" -ne 0 ] || { echo "FAIL DC64: expected failure for nested object override"; exit 1; }
[[ "$out64" == *"N4"* ]] || { echo "FAIL DC64 output: $out64"; exit 1; }

# DC65: an N4 row 31 days out -> fails E1
echo "Running DC65..."
d65="$TMP_DIR/dc65"; setup_base_fixtures "$d65"
cat << 'EOF' > "$d65/npm/package.json"
{
  "overrides": {
    "pkg_override": "1.0.0"
  }
}
EOF
# today is 2026-11-10; 31 days out is 2026-12-11
printf "N4\tpkg_override\t1.0.0\t2026-12-12\tRemoves GHSA-1111-2222-3333 in top-level parent\n" > "$d65/dependency_exceptions.tsv"
set +e
out65=$(run_check "$d65" --today 2026-11-10 2>&1)
rc65=$?; set -e
[ "$rc65" -ne 0 ] || { echo "FAIL DC65: expected failure for > 30 days review_by"; exit 1; }
[[ "$out65" == *"E1"* ]] || { echo "FAIL DC65 output: $out65"; exit 1; }

# DC66: a stale N4 row -> fails E1
echo "Running DC66..."
d66="$TMP_DIR/dc66"; setup_base_fixtures "$d66"
printf "N4\tpkg_override\t1.0.0\t2026-11-20\tRemoves GHSA-1111-2222-3333 in top-level parent\n" > "$d66/dependency_exceptions.tsv"
set +e
out66=$(run_check "$d66" --today 2026-11-10 2>&1)
rc66=$?; set -e
[ "$rc66" -ne 0 ] || { echo "FAIL DC66: expected failure for stale N4 row"; exit 1; }
[[ "$out66" == *"E1"* && "$out66" == *"stale exception"* ]] || { echo "FAIL DC66 output: $out66"; exit 1; }

# DC67: one moderate in npm audit -> fails naming package and GHSA
echo "Running DC67..."
d67="$TMP_DIR/dc67"; setup_base_fixtures "$d67"
cat << 'EOF' > "$d67/npm/audit.json"
{
  "vulnerabilities": {
    "vuln_pkg": {
      "name": "vuln_pkg",
      "severity": "moderate",
      "version": "1.0.0",
      "via": [
        {
          "source": 1001,
          "name": "vuln_pkg",
          "url": "https://github.com/advisories/GHSA-1234-5678-90ab",
          "severity": "moderate"
        }
      ]
    }
  }
}
EOF
set +e
out67=$(run_check "$d67" --today 2026-11-10 2>&1)
rc67=$?; set -e
[ "$rc67" -ne 0 ] || { echo "FAIL DC67: expected failure for moderate audit vuln"; exit 1; }
[[ "$out67" == *"N2"* && "$out67" == *"vuln_pkg"* && "$out67" == *"GHSA-1234-5678-90AB"* ]] || { echo "FAIL DC67 output: $out67"; exit 1; }

# DC68: same with a matching N2 row -> pass
echo "Running DC68..."
d68="$TMP_DIR/dc68"; setup_base_fixtures "$d68"
cp "$d67/npm/audit.json" "$d68/npm/audit.json"
printf "N2\tvuln_pkg\t1.0.0\t2026-11-20\tExcused for GHSA-1234-5678-90ab in vuln_pkg\n" > "$d68/dependency_exceptions.tsv"
out68=$(run_check "$d68" --today 2026-11-10)
[[ "$out68" == *"Summary"* ]] || { echo "FAIL DC68: $out68"; exit 1; }

# DC69: an N2 row missing one of two GHSA ids -> fails
echo "Running DC69..."
d69="$TMP_DIR/dc69"; setup_base_fixtures "$d69"
cat << 'EOF' > "$d69/npm/audit.json"
{
  "vulnerabilities": {
    "vuln_pkg": {
      "name": "vuln_pkg",
      "severity": "moderate",
      "version": "1.0.0",
      "via": [
        {
          "source": 1001,
          "name": "vuln_pkg",
          "url": "https://github.com/advisories/GHSA-1234-5678-90ab",
          "severity": "moderate"
        },
        {
          "source": 1002,
          "name": "vuln_pkg",
          "url": "https://github.com/advisories/GHSA-9999-8888-7777",
          "severity": "moderate"
        }
      ]
    }
  }
}
EOF
printf "N2\tvuln_pkg\t1.0.0\t2026-11-20\tExcused for GHSA-1234-5678-90ab only\n" > "$d69/dependency_exceptions.tsv"
set +e
out69=$(run_check "$d69" --today 2026-11-10 2>&1)
rc69=$?; set -e
[ "$rc69" -ne 0 ] || { echo "FAIL DC69: expected failure for missing GHSA ID"; exit 1; }
[[ "$out69" == *"N2"* ]] || { echo "FAIL DC69 output: $out69"; exit 1; }

# DC70: Flutter releases with no stable releases -> fails (Fix 2.2)
echo "Running DC70..."
d70="$TMP_DIR/dc70"; setup_base_fixtures "$d70"
cat << 'EOF2' > "$HTTP_ROOT/releases_linux_dc70.json"
{}
EOF2
set +e
out70=$(run_check "$d70" --flutter-releases "$SERVER_URL/releases_linux_dc70.json" --today 2026-11-10 2>&1)
rc70=$?; set -e
[ "$rc70" -ne 0 ] || { echo "FAIL DC70: expected failure for empty flutter releases"; exit 1; }
[[ "$out70" == *"T1:"* && "$out70" == *"releases"* ]] || { echo "FAIL DC70 output: $out70"; exit 1; }

# DC71: Fix 4.4 N2 exceptions name one exact version
echo "Running DC71 (Fix 4.4)..."
# Case 1: a '*' row fails as malformed (naming the line)
d71_star="$TMP_DIR/dc71_star"; setup_base_fixtures "$d71_star"
cp "$d67/npm/audit.json" "$d71_star/npm/audit.json"
printf "N2	vuln_pkg	*	2026-11-20	Excused for GHSA-1234-5678-90ab in vuln_pkg
" > "$d71_star/dependency_exceptions.tsv"
set +e; out71_star=$(run_check "$d71_star" --today 2026-11-10 2>&1); rc71_star=$?; set -e
[ "$rc71_star" -ne 0 ] || { echo "FAIL Fix 4.4 * case: expected failure for *"; exit 1; }
[[ "$out71_star" == *"dependency_exceptions.tsv:1"* && "$out71_star" == *"exact version string"* ]] || { echo "FAIL Fix 4.4 * case: unexpected output: $out71_star"; exit 1; }

# Case 2: a row for another version doesn't excuse the package
d71_diff="$TMP_DIR/dc71_diff"; setup_base_fixtures "$d71_diff"
cp "$d67/npm/audit.json" "$d71_diff/npm/audit.json"
printf "N2	vuln_pkg	2.0.0	2026-11-20	Excused for GHSA-1234-5678-90ab in vuln_pkg
" > "$d71_diff/dependency_exceptions.tsv"
set +e; out71_diff=$(run_check "$d71_diff" --today 2026-11-10 2>&1); rc71_diff=$?; set -e
[ "$rc71_diff" -ne 0 ] || { echo "FAIL Fix 4.4 diff version case: expected failure"; exit 1; }
[[ "$out71_diff" == *"N2"* ]] || { echo "FAIL Fix 4.4 diff version case: unexpected output: $out71_diff"; exit 1; }

# Case 3: an unknown installed version fails naming the package
d71_unk="$TMP_DIR/dc71_unk"; setup_base_fixtures "$d71_unk"
cat << 'EOF' > "$d71_unk/npm/audit.json"
{
  "vulnerabilities": {
    "vuln_pkg": {
      "name": "vuln_pkg",
      "severity": "moderate",
      "isDirect": true,
      "effects": [],
      "range": ">=1.0.0",
      "nodes": [ "node_modules/vuln_pkg" ],
      "fixAvailable": true,
      "via": [
        {
          "source": 1001,
          "name": "vuln_pkg",
          "dependency": "vuln_pkg",
          "title": "Vulnerability in vuln_pkg",
          "url": "https://github.com/advisories/GHSA-1234-5678-90ab",
          "severity": "moderate",
          "cwe": [],
          "cvss": {"score": 5.0, "vectorString": null},
          "range": ">=1.0.0"
        }
      ]
    }
  }
}
EOF
cat << 'EOF' > "$d71_unk/npm/package-lock.json"
{
  "name": "test-pkg",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "packages": {}
}
EOF
printf "N2	vuln_pkg	1.0.0	2026-11-20	Excused for GHSA-1234-5678-90ab in vuln_pkg
" > "$d71_unk/dependency_exceptions.tsv"
set +e; out71_unk=$(run_check "$d71_unk" --today 2026-11-10 2>&1); rc71_unk=$?; set -e
[ "$rc71_unk" -ne 0 ] || { echo "FAIL Fix 4.4 unknown installed version: expected failure"; exit 1; }
[[ "$out71_unk" == *"N2"* && "$out71_unk" == *"Unable to determine installed version for vulnerable package 'vuln_pkg'"* ]] || { echo "FAIL Fix 4.4 unknown installed version output: $out71_unk"; exit 1; }

# Case 4: exact matching row passes
d71_exact="$TMP_DIR/dc71_exact"; setup_base_fixtures "$d71_exact"
cp "$d67/npm/audit.json" "$d71_exact/npm/audit.json"
printf "N2	vuln_pkg	1.0.0	2026-11-20	Excused for GHSA-1234-5678-90ab in vuln_pkg
" > "$d71_exact/dependency_exceptions.tsv"
out71_exact=$(run_check "$d71_exact" --today 2026-11-10)
[[ "$out71_exact" == *"Summary"* ]] || { echo "FAIL Fix 4.4 exact matching row: $out71_exact"; exit 1; }

# DC72: Table-driven fail-closed law over all inputs (Fix 4.1)
echo "Running DC72: Table-driven fail-closed law over all inputs..."
CHECK_SCRIPT="$CHECK_SCRIPT" python3 - << 'EOF_DC71'
import os, sys, shutil, subprocess, json, tempfile, re
from http.server import SimpleHTTPRequestHandler
import socketserver
import threading

CHECK_SCRIPT = os.environ.get('CHECK_SCRIPT', os.path.abspath('scripts/check_dependencies.py'))

class LawTestRunner:
    def __init__(self):
        self.tmp_dir = tempfile.mkdtemp(prefix='fc_law_')
        self.http_root = os.path.join(self.tmp_dir, 'http_root')
        os.makedirs(self.http_root, exist_ok=True)
        self.setup_http_server()
        self.setup_base_fixtures()

    def setup_http_server(self):
        root = self.http_root
        class Handler(SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=root, **kwargs)
            def do_GET(self):
                req_path = self.path.split('?')[0].rstrip('/')
                json_file = os.path.join(root, req_path.lstrip('/') + '.json')
                if os.path.isfile(json_file):
                    with open(json_file, 'rb') as f:
                        data = f.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                parts = req_path.lstrip('/').split('/', 1)
                if '404' not in req_path and 'not_found' not in req_path and len(parts) > 1:
                    base_json_file = os.path.join(root, parts[1] + '.json')
                    if os.path.isfile(base_json_file):
                        with open(base_json_file, 'rb') as f:
                            data = f.read()
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.send_header('Content-Length', str(len(data)))
                        self.end_headers()
                        self.wfile.write(data)
                        return
                super().do_GET()

        self.server = socketserver.TCPServer(('127.0.0.1', 0), Handler)
        self.port = self.server.server_address[1]
        self.server_url = f"http://127.0.0.1:{self.port}"
        self.server_thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.server_thread.start()

    def setup_base_fixtures(self):
        def write_json(rel_path, obj_or_str):
            full_path = os.path.join(self.http_root, rel_path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, 'w', encoding='utf-8') as f:
                if isinstance(obj_or_str, str):
                    f.write(obj_or_str)
                else:
                    json.dump(obj_or_str, f, indent=2)

        write_json('releases_linux.json', {
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
        })
        write_json('api/packages/meta.json', {
            "name": "meta",
            "latest": {"version": "1.19.0", "published": "2026-10-01T00:00:00Z"},
            "versions": [{"version": "1.19.0", "published": "2026-10-01T00:00:00Z"}]
        })
        write_json('api/packages/meta/advisories.json', {"advisories": []})
        write_json('repos/actions/checkout/releases/latest.json', {"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"})
        write_json('repos/actions/checkout/releases.json', [{"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"}])
        write_json('repos/actions/checkout/git/ref/tags/v7.0.1.json', {"object": {"sha": "3d3c42e5aac5ba805825da76410c181273ba90b1", "type": "commit"}})
        write_json('repos/dart-lang/setup-dart/releases/latest.json', {"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"})
        write_json('repos/dart-lang/setup-dart/releases.json', [{"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"}])
        write_json('repos/dart-lang/setup-dart/git/ref/tags/v1.8.1.json', {"object": {"sha": "e51d8e519be8f8d29450b2bc73ea832f4165e2c1", "type": "commit"}})
        write_json('repos/actions/setup-node/releases/latest.json', {"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"})
        write_json('repos/actions/setup-node/releases.json', [{"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"}])
        write_json('repos/actions/setup-node/git/ref/tags/v4.4.0.json', {"object": {"sha": "49933ea5288caeca8642d1e84afbd3f7d6820020", "type": "commit"}})
        write_json('dist/index.json', [{"version": "v20.18.0", "date": "2026-10-01", "lts": "Iron"}])
        write_json('pkg_override.json', {"name": "pkg_override", "time": {"1.0.0": "2026-11-01T00:00:00Z"}})

    def create_case_dir(self, name):
        case_dir = os.path.join(self.tmp_dir, name)
        os.makedirs(case_dir, exist_ok=True)
        wf_dir = os.path.join(case_dir, '.github/workflows')
        os.makedirs(wf_dir, exist_ok=True)
        npm_dir = os.path.join(case_dir, 'npm')
        os.makedirs(npm_dir, exist_ok=True)

        with open(os.path.join(case_dir, 'pubspec.yaml'), 'w') as f:
            f.write("name: test_pkg\nenvironment:\n  sdk: ^3.13.0\n  flutter: 3.47.9\ndependencies:\n  meta: ^1.19.0\n")
        with open(os.path.join(case_dir, 'pubspec.lock'), 'w') as f:
            f.write("packages:\n  meta:\n    dependency: \"direct main\"\n    description:\n      name: meta\n      url: \"https://pub.dev\"\n    source: hosted\n    version: \"1.19.0\"\n")
        with open(os.path.join(case_dir, 'pub_outdated.json'), 'w') as f:
            json.dump({
                "packages": [{
                    "package": "meta",
                    "kind": "direct",
                    "isDiscontinued": False,
                    "isCurrentRetracted": False,
                    "isCurrentAffectedByAdvisory": False,
                    "current": {"version": "1.19.0"},
                    "upgradable": {"version": "1.19.0"},
                    "resolvable": {"version": "1.19.0"},
                    "latest": {"version": "1.19.0"}
                }]
            }, f)
        with open(os.path.join(wf_dir, 'ci.yml'), 'w') as f:
            f.write("""name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.7
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: '20'
""")
        with open(os.path.join(case_dir, 'dependency_exceptions.tsv'), 'w') as f:
            f.write("# rule\tname\theld_at\treview_by\treason\n")

        with open(os.path.join(npm_dir, 'package.json'), 'w') as f:
            f.write('{"name": "test_pkg", "version": "1.0.0"}\n')
        with open(os.path.join(npm_dir, 'package-lock.json'), 'w') as f:
            f.write('{"name": "test_pkg", "version": "1.0.0", "lockfileVersion": 3, "packages": {}}\n')
        with open(os.path.join(npm_dir, 'outdated.json'), 'w') as f:
            f.write("{}\n")
        with open(os.path.join(npm_dir, 'audit.json'), 'w') as f:
            json.dump({
                "auditReportVersion": 2,
                "vulnerabilities": {},
                "metadata": {
                    "vulnerabilities": {
                        "info": 0, "low": 0, "moderate": 0, "high": 0, "critical": 0, "total": 0
                    }
                }
            }, f)
        with open(os.path.join(npm_dir, 'outdated_status.json'), 'w') as f:
            f.write("0\n")
        with open(os.path.join(npm_dir, 'audit_status.json'), 'w') as f:
            f.write("0\n")
        open(os.path.join(npm_dir, 'outdated.stderr'), 'w').close()
        open(os.path.join(npm_dir, 'audit.stderr'), 'w').close()

        return case_dir

    def run_check(self, case_dir, extra_args=None):
        cmd = [
            sys.executable, '-I', CHECK_SCRIPT,
            '--pub-outdated', os.path.join(case_dir, 'pub_outdated.json'),
            '--pubspec', os.path.join(case_dir, 'pubspec.yaml'),
            '--workflows', os.path.join(case_dir, '.github/workflows'),
            '--exceptions', os.path.join(case_dir, 'dependency_exceptions.tsv'),
            '--pub-api', self.server_url,
            '--flutter-releases', f"{self.server_url}/releases_linux.json",
            '--github-api', self.server_url,
            '--npm-dir', os.path.join(case_dir, 'npm'),
            '--npm-outdated', os.path.join(case_dir, 'npm/outdated.json'),
            '--npm-audit', os.path.join(case_dir, 'npm/audit.json'),
            '--npm-outdated-status', os.path.join(case_dir, 'npm/outdated_status.json'),
            '--npm-audit-status', os.path.join(case_dir, 'npm/audit_status.json'),
            '--npm-registry', self.server_url,
            '--node-dist', f"{self.server_url}/dist/index.json",
            '--today', '2026-11-10'
        ]
        if extra_args:
            cmd.extend(extra_args)
        res = subprocess.run(cmd, capture_output=True, text=True)
        return res.returncode, res.stdout, res.stderr

    def cleanup(self):
        try:
            self.server.shutdown()
        except Exception:
            pass
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

def main():
    runner = LawTestRunner()
    failing_rows = []
    passing_rows = []

    # Verify baseline control
    base = runner.create_case_dir('base_control')
    rc, out, err = runner.run_check(base)
    if rc != 0:
        print(f"FATAL: Base control fixture failed! rc={rc}\nout={out}\nerr={err}")
        runner.cleanup()
        sys.exit(1)

    print("Baseline control passed clean.")

    tests = []

    # --- 1. FILES ---
    # pubspec.yaml
    tests.append(('pubspec_missing', 'pubspec.yaml', 'missing', lambda d: os.remove(os.path.join(d, 'pubspec.yaml')), 'pubspec.yaml'))
    tests.append(('pubspec_empty', 'pubspec.yaml', 'empty', lambda d: open(os.path.join(d, 'pubspec.yaml'), 'w').close(), 'pubspec.yaml'))
    tests.append(('pubspec_whitespace', 'pubspec.yaml', 'whitespace', lambda d: open(os.path.join(d, 'pubspec.yaml'), 'w').write("   \n\t\n"), 'pubspec.yaml'))
    tests.append(('pubspec_unparseable', 'pubspec.yaml', 'unparseable_yaml', lambda d: open(os.path.join(d, 'pubspec.yaml'), 'w').write(":\n  - : :\n"), 'pubspec.yaml'))
    tests.append(('pubspec_missing_sdk', 'pubspec.yaml', 'missing_sdk', lambda d: open(os.path.join(d, 'pubspec.yaml'), 'w').write("name: test_pkg\nenvironment:\n  flutter: 3.47.9\ndependencies:\n  meta: ^1.19.0\n"), 'pubspec.yaml'))

    # pubspec.lock (missed input found in code)
    tests.append(('pubspec_lock_empty', 'pubspec.lock', 'empty', lambda d: open(os.path.join(d, 'pubspec.lock'), 'w').close(), 'pubspec.lock'))
    tests.append(('pubspec_lock_whitespace', 'pubspec.lock', 'whitespace', lambda d: open(os.path.join(d, 'pubspec.lock'), 'w').write("   \n\t\n"), 'pubspec.lock'))

    # workflows directory & files
    tests.append(('workflows_missing_dir', 'workflows', 'missing_dir', lambda d: shutil.rmtree(os.path.join(d, '.github/workflows')), 'workflows'))
    tests.append(('workflows_empty_dir', 'workflows', 'empty_dir', lambda d: (shutil.rmtree(os.path.join(d, '.github/workflows')), os.makedirs(os.path.join(d, '.github/workflows'))), 'workflows'))
    tests.append(('workflows_file_empty', '.github/workflows/ci.yml', 'empty_file', lambda d: open(os.path.join(d, '.github/workflows/ci.yml'), 'w').close(), 'ci.yml'))
    tests.append(('workflows_file_whitespace', '.github/workflows/ci.yml', 'whitespace', lambda d: open(os.path.join(d, '.github/workflows/ci.yml'), 'w').write("  \n\t \n"), 'ci.yml'))
    tests.append(('workflows_file_unparseable', '.github/workflows/ci.yml', 'unparseable_yaml', lambda d: open(os.path.join(d, '.github/workflows/ci.yml'), 'w').write(":\n  - : :\n"), 'ci.yml'))
    tests.append(('workflows_file_no_jobs', '.github/workflows/ci.yml', 'missing_jobs', lambda d: open(os.path.join(d, '.github/workflows/ci.yml'), 'w').write("name: CI\non: [push]\n"), 'ci.yml'))

    # dependency_exceptions.tsv
    tests.append(('exceptions_missing', 'dependency_exceptions.tsv', 'missing', lambda d: os.remove(os.path.join(d, 'dependency_exceptions.tsv')), 'dependency_exceptions.tsv'))
    tests.append(('exceptions_malformed', 'dependency_exceptions.tsv', 'malformed_columns', lambda d: open(os.path.join(d, 'dependency_exceptions.tsv'), 'w').write("D1\tmeta\t1.0.0\n"), 'dependency_exceptions.tsv'))
    tests.append(('exceptions_invalid_date', 'dependency_exceptions.tsv', 'invalid_date', lambda d: open(os.path.join(d, 'dependency_exceptions.tsv'), 'w').write("D1\tmeta\t1.0.0\tinvalid-date\tReason that is more than twenty characters long\n"), 'dependency_exceptions.tsv'))
    tests.append(('exceptions_reason_short', 'dependency_exceptions.tsv', 'reason_too_short', lambda d: open(os.path.join(d, 'dependency_exceptions.tsv'), 'w').write("D1\tmeta\t1.0.0\t2026-11-20\tshort\n"), 'dependency_exceptions.tsv'))

    # pub_outdated.json
    tests.append(('pub_outdated_missing', 'pub_outdated.json', 'missing', lambda d: os.remove(os.path.join(d, 'pub_outdated.json')), 'pub_outdated.json'))
    tests.append(('pub_outdated_empty', 'pub_outdated.json', 'empty', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').close(), 'pub_outdated.json'))
    tests.append(('pub_outdated_whitespace', 'pub_outdated.json', 'whitespace', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write("   \n\t  \n"), 'pub_outdated.json'))
    tests.append(('pub_outdated_unparseable', 'pub_outdated.json', 'unparseable_json', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write("{ not valid json"), 'pub_outdated.json'))
    tests.append(('pub_outdated_null', 'pub_outdated.json', 'top_level_null', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write("null\n"), 'pub_outdated.json'))
    tests.append(('pub_outdated_array', 'pub_outdated.json', 'top_level_array', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write("[]\n"), 'pub_outdated.json'))
    tests.append(('pub_outdated_error', 'pub_outdated.json', 'error_payload', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write('{"error": "outdated failed"}\n'), 'pub_outdated.json'))
    tests.append(('pub_outdated_no_pkgs', 'pub_outdated.json', 'missing_packages_field', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write('{}\n'), 'pub_outdated.json'))
    tests.append(('pub_outdated_incomplete', 'pub_outdated.json', 'missing_dependency_entry', lambda d: open(os.path.join(d, 'pub_outdated.json'), 'w').write('{"packages": []}\n'), 'pub_outdated.json'))

    # npm package.json
    tests.append(('npm_pkg_missing', 'package.json', 'missing', lambda d: os.remove(os.path.join(d, 'npm/package.json')), 'package.json'))
    tests.append(('npm_pkg_empty', 'package.json', 'empty', lambda d: open(os.path.join(d, 'npm/package.json'), 'w').close(), 'package.json'))
    tests.append(('npm_pkg_ws', 'package.json', 'whitespace', lambda d: open(os.path.join(d, 'npm/package.json'), 'w').write("  \n\t \n"), 'package.json'))
    tests.append(('npm_pkg_unparseable', 'package.json', 'unparseable_json', lambda d: open(os.path.join(d, 'npm/package.json'), 'w').write("{ bad json"), 'package.json'))
    tests.append(('npm_pkg_null', 'package.json', 'top_level_null', lambda d: open(os.path.join(d, 'npm/package.json'), 'w').write("null\n"), 'package.json'))
    tests.append(('npm_pkg_array', 'package.json', 'top_level_array', lambda d: open(os.path.join(d, 'npm/package.json'), 'w').write("[]\n"), 'package.json'))

    # npm package-lock.json when vulnerable package present
    def setup_vuln_audit(d):
        open(os.path.join(d, 'npm/audit.json'), 'w').write(json.dumps({
            "auditReportVersion": 2,
            "vulnerabilities": {"vuln_pkg": {"severity": "moderate", "nodes": ["node_modules/vuln_pkg"], "via": [{"url": "https://github.com/advisories/GHSA-1234-5678-90ab"}]}}
        }))

    tests.append(('npm_lock_missing', 'package-lock.json', 'missing_when_vulnerable', lambda d: (setup_vuln_audit(d), os.remove(os.path.join(d, 'npm/package-lock.json'))), 'package-lock.json'))
    tests.append(('npm_lock_empty', 'package-lock.json', 'empty_when_vulnerable', lambda d: (setup_vuln_audit(d), open(os.path.join(d, 'npm/package-lock.json'), 'w').close()), 'package-lock.json'))
    tests.append(('npm_lock_ws', 'package-lock.json', 'whitespace_when_vulnerable', lambda d: (setup_vuln_audit(d), open(os.path.join(d, 'npm/package-lock.json'), 'w').write("  \n")), 'package-lock.json'))
    tests.append(('npm_lock_unparseable', 'package-lock.json', 'unparseable_when_vulnerable', lambda d: (setup_vuln_audit(d), open(os.path.join(d, 'npm/package-lock.json'), 'w').write("{ bad json")), 'package-lock.json'))
    tests.append(('npm_lock_null', 'package-lock.json', 'top_level_null_when_vulnerable', lambda d: (setup_vuln_audit(d), open(os.path.join(d, 'npm/package-lock.json'), 'w').write("null\n")), 'package-lock.json'))
    tests.append(('npm_lock_array', 'package-lock.json', 'top_level_array_when_vulnerable', lambda d: (setup_vuln_audit(d), open(os.path.join(d, 'npm/package-lock.json'), 'w').write("[]\n")), 'package-lock.json'))

    # npm outdated.json
    tests.append(('npm_outdated_missing', 'npm/outdated.json', 'missing', lambda d: os.remove(os.path.join(d, 'npm/outdated.json')), 'outdated.json'))
    tests.append(('npm_outdated_empty', 'npm/outdated.json', 'empty', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').close(), 'outdated.json'))
    tests.append(('npm_outdated_ws', 'npm/outdated.json', 'whitespace', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').write("  \n\t \n"), 'outdated.json'))
    tests.append(('npm_outdated_unparseable', 'npm/outdated.json', 'unparseable_json', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').write("{ not valid json"), 'outdated.json'))
    tests.append(('npm_outdated_null', 'npm/outdated.json', 'top_level_null', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').write("null\n"), 'outdated.json'))
    tests.append(('npm_outdated_array', 'npm/outdated.json', 'top_level_array', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').write("[]\n"), 'outdated.json'))
    tests.append(('npm_outdated_error', 'npm/outdated.json', 'error_payload', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').write('{"error": "E404"}\n'), 'outdated.json'))

    # npm audit.json
    tests.append(('npm_audit_missing', 'npm/audit.json', 'missing', lambda d: os.remove(os.path.join(d, 'npm/audit.json')), 'audit.json'))
    tests.append(('npm_audit_empty', 'npm/audit.json', 'empty', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').close(), 'audit.json'))
    tests.append(('npm_audit_ws', 'npm/audit.json', 'whitespace', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write("  \n\t \n"), 'audit.json'))
    tests.append(('npm_audit_unparseable', 'npm/audit.json', 'unparseable_json', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write("{ not json"), 'audit.json'))
    tests.append(('npm_audit_null', 'npm/audit.json', 'top_level_null', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write("null\n"), 'audit.json'))
    tests.append(('npm_audit_array', 'npm/audit.json', 'top_level_array', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write("[]\n"), 'audit.json'))
    tests.append(('npm_audit_error', 'npm/audit.json', 'error_payload', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write('{"error": "audit failed"}\n'), 'audit.json'))
    tests.append(('npm_audit_missing_meta', 'npm/audit.json', 'missing_metadata_and_vulns', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write('{}\n'), 'audit.json'))
    tests.append(('npm_audit_missing_mod', 'npm/audit.json', 'missing_moderate_field', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write('{"metadata": {"vulnerabilities": {}}}\n'), 'audit.json'))

    # npm outdated status
    tests.append(('npm_outdated_status_missing', 'npm/outdated_status.json', 'missing', lambda d: os.remove(os.path.join(d, 'npm/outdated_status.json')), 'outdated_status.json'))
    tests.append(('npm_outdated_status_empty', 'npm/outdated_status.json', 'empty', lambda d: open(os.path.join(d, 'npm/outdated_status.json'), 'w').close(), 'outdated_status.json'))
    tests.append(('npm_outdated_status_ws', 'npm/outdated_status.json', 'whitespace', lambda d: open(os.path.join(d, 'npm/outdated_status.json'), 'w').write("  \n"), 'outdated_status.json'))
    tests.append(('npm_outdated_status_non_int', 'npm/outdated_status.json', 'non_integer', lambda d: open(os.path.join(d, 'npm/outdated_status.json'), 'w').write("abc\n"), 'outdated_status.json'))
    tests.append(('npm_outdated_status_code2', 'npm/outdated_status.json', 'exit_code_2', lambda d: (open(os.path.join(d, 'npm/outdated_status.json'), 'w').write("2\n"), open(os.path.join(d, 'npm/outdated.stderr'), 'w').write("npm ERR! code E404\n")), 'outdated_status.json'))
    tests.append(('npm_outdated_status_code127', 'npm/outdated_status.json', 'exit_code_127', lambda d: (open(os.path.join(d, 'npm/outdated_status.json'), 'w').write("127\n"), open(os.path.join(d, 'npm/outdated.stderr'), 'w').write("npm: command not found\n")), 'outdated_status.json'))

    # npm audit status
    tests.append(('npm_audit_status_missing', 'npm/audit_status.json', 'missing', lambda d: os.remove(os.path.join(d, 'npm/audit_status.json')), 'audit_status.json'))
    tests.append(('npm_audit_status_empty', 'npm/audit_status.json', 'empty', lambda d: open(os.path.join(d, 'npm/audit_status.json'), 'w').close(), 'audit_status.json'))
    tests.append(('npm_audit_status_ws', 'npm/audit_status.json', 'whitespace', lambda d: open(os.path.join(d, 'npm/audit_status.json'), 'w').write("  \n"), 'audit_status.json'))
    tests.append(('npm_audit_status_non_int', 'npm/audit_status.json', 'non_integer', lambda d: open(os.path.join(d, 'npm/audit_status.json'), 'w').write("error\n"), 'audit_status.json'))
    tests.append(('npm_audit_status_code2', 'npm/audit_status.json', 'exit_code_2', lambda d: (open(os.path.join(d, 'npm/audit_status.json'), 'w').write("2\n"), open(os.path.join(d, 'npm/audit.stderr'), 'w').write("npm ERR! audit server error\n")), 'audit_status.json'))
    tests.append(('npm_audit_status_code127', 'npm/audit_status.json', 'exit_code_127', lambda d: (open(os.path.join(d, 'npm/audit_status.json'), 'w').write("127\n"), open(os.path.join(d, 'npm/audit.stderr'), 'w').write("npm: command not found\n")), 'audit_status.json'))

    # --- 2. URLS ---
    def setup_url_fixture(subpath, content):
        p = os.path.join(runner.http_root, subpath)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            if isinstance(content, str):
                f.write(content)
            else:
                json.dump(content, f)

    def test_url(test_id, input_name, damage_kind, arg_flag, subpath, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                rel_url = f"{runner.server_url}/not_found_{test_id}"
            else:
                setup_url_fixture(f"{test_id}/{subpath}", content_or_none)
                rel_url = f"{runner.server_url}/{test_id}"
            return [arg_flag, rel_url]
        return (test_id, input_name, damage_kind, setup_fn, input_name)

    # pub.dev package
    tests.append(test_url('url_pub_pkg_404', 'pub.dev package', 'http_404', '--pub-api', 'api/packages/meta.json', None))
    tests.append(test_url('url_pub_pkg_empty', 'pub.dev package', 'empty_body', '--pub-api', 'api/packages/meta.json', ''))
    tests.append(test_url('url_pub_pkg_ws', 'pub.dev package', 'whitespace', '--pub-api', 'api/packages/meta.json', '  \n\t '))
    tests.append(test_url('url_pub_pkg_bad_json', 'pub.dev package', 'unparseable_json', '--pub-api', 'api/packages/meta.json', '{ bad'))
    tests.append(test_url('url_pub_pkg_null', 'pub.dev package', 'top_level_null', '--pub-api', 'api/packages/meta.json', 'null\n'))
    tests.append(test_url('url_pub_pkg_array', 'pub.dev package', 'top_level_array', '--pub-api', 'api/packages/meta.json', '[]\n'))
    tests.append(test_url('url_pub_pkg_error', 'pub.dev package', 'error_payload', '--pub-api', 'api/packages/meta.json', '{"error": "pkg error"}'))
    tests.append(test_url('url_pub_pkg_missing_fields', 'pub.dev package', 'missing_versions_and_latest', '--pub-api', 'api/packages/meta.json', '{"name": "meta"}\n'))

    # pub.dev advisories
    tests.append(test_url('url_pub_adv_404', 'pub.dev advisories', 'http_404', '--pub-api', 'api/packages/meta/advisories.json', None))
    tests.append(test_url('url_pub_adv_empty', 'pub.dev advisories', 'empty_body', '--pub-api', 'api/packages/meta/advisories.json', ''))
    tests.append(test_url('url_pub_adv_ws', 'pub.dev advisories', 'whitespace', '--pub-api', 'api/packages/meta/advisories.json', '   \n'))
    tests.append(test_url('url_pub_adv_bad_json', 'pub.dev advisories', 'unparseable_json', '--pub-api', 'api/packages/meta/advisories.json', '{ bad'))
    tests.append(test_url('url_pub_adv_null', 'pub.dev advisories', 'top_level_null', '--pub-api', 'api/packages/meta/advisories.json', 'null\n'))
    tests.append(test_url('url_pub_adv_array', 'pub.dev advisories', 'top_level_array', '--pub-api', 'api/packages/meta/advisories.json', '[]\n'))
    tests.append(test_url('url_pub_adv_error', 'pub.dev advisories', 'error_payload', '--pub-api', 'api/packages/meta/advisories.json', '{"error": "adv error"}'))
    tests.append(test_url('url_pub_adv_missing_adv', 'pub.dev advisories', 'missing_advisories_field', '--pub-api', 'api/packages/meta/advisories.json', '{}\n'))

    # Flutter releases
    def test_fl(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                url = f"{runner.server_url}/fl_404_{test_id}.json"
            else:
                setup_url_fixture(f"{test_id}/releases.json", content_or_none)
                url = f"{runner.server_url}/{test_id}/releases.json"
            return ['--flutter-releases', url]
        return (test_id, 'Flutter releases', damage_kind, setup_fn, 'Flutter releases')

    tests.append(test_fl('url_fl_404', 'http_404', None))
    tests.append(test_fl('url_fl_empty', 'empty_body', ''))
    tests.append(test_fl('url_fl_ws', 'whitespace', '   \n'))
    tests.append(test_fl('url_fl_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_fl('url_fl_null', 'top_level_null', 'null\n'))
    tests.append(test_fl('url_fl_array', 'top_level_array', '[]\n'))
    tests.append(test_fl('url_fl_error', 'error_payload', '{"error": "fl error"}'))
    tests.append(test_fl('url_fl_missing_rel', 'missing_releases_field', '{}\n'))
    tests.append(test_fl('url_fl_empty_rel', 'empty_releases_list', '{"releases": []}\n'))

    # GitHub latest release
    def test_gh_latest(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                url = f"{runner.server_url}/gh_404_{test_id}"
            else:
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases/latest.json", content_or_none)
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases.json", [{"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/checkout/git/ref/tags/v7.0.1.json", {"object": {"sha": "3d3c42e5aac5ba805825da76410c181273ba90b1", "type": "commit"}})
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases/latest.json", {"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases.json", [{"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/git/ref/tags/v1.8.1.json", {"object": {"sha": "e51d8e519be8f8d29450b2bc73ea832f4165e2c1", "type": "commit"}})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases/latest.json", {"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases.json", [{"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/git/ref/tags/v4.4.0.json", {"object": {"sha": "49933ea5288caeca8642d1e84afbd3f7d6820020", "type": "commit"}})
                url = f"{runner.server_url}/{test_id}"
            return ['--github-api', url]
        return (test_id, 'GitHub latest release', damage_kind, setup_fn, 'GitHub release')

    tests.append(test_gh_latest('url_gh_latest_404', 'http_404', None))
    tests.append(test_gh_latest('url_gh_latest_empty', 'empty_body', ''))
    tests.append(test_gh_latest('url_gh_latest_ws', 'whitespace', '  \n\t '))
    tests.append(test_gh_latest('url_gh_latest_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_gh_latest('url_gh_latest_null', 'top_level_null', 'null\n'))
    tests.append(test_gh_latest('url_gh_latest_array', 'top_level_array', '[]\n'))
    tests.append(test_gh_latest('url_gh_latest_error', 'error_payload', '{"error": "gh error"}'))
    tests.append(test_gh_latest('url_gh_latest_missing_tag', 'missing_tag_name', '{"name": "v7.0.1"}\n'))

    # GitHub releases list
    def test_gh_rels(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                url = f"{runner.server_url}/gh_404_{test_id}"
            else:
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases/latest.json", {"tag_name": "v7.0.2", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases.json", content_or_none)
                setup_url_fixture(f"{test_id}/repos/actions/checkout/git/ref/tags/v7.0.2.json", {"object": {"sha": "999c42e5aac5ba805825da76410c181273ba90b1", "type": "commit"}})
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases/latest.json", {"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases.json", [{"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/git/ref/tags/v1.8.1.json", {"object": {"sha": "e51d8e519be8f8d29450b2bc73ea832f4165e2c1", "type": "commit"}})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases/latest.json", {"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases.json", [{"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/git/ref/tags/v4.4.0.json", {"object": {"sha": "49933ea5288caeca8642d1e84afbd3f7d6820020", "type": "commit"}})
                url = f"{runner.server_url}/{test_id}"
            return ['--github-api', url]
        return (test_id, 'GitHub releases list', damage_kind, setup_fn, 'GitHub releases list')

    tests.append(test_gh_rels('url_gh_rels_404', 'http_404', None))
    tests.append(test_gh_rels('url_gh_rels_empty', 'empty_body', ''))
    tests.append(test_gh_rels('url_gh_rels_ws', 'whitespace', '   \n'))
    tests.append(test_gh_rels('url_gh_rels_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_gh_rels('url_gh_rels_null', 'top_level_null', 'null\n'))
    tests.append(test_gh_rels('url_gh_rels_obj', 'top_level_object', '{}\n'))
    tests.append(test_gh_rels('url_gh_rels_error', 'error_payload', '{"error": "rels error"}'))

    # GitHub tag ref
    def test_gh_ref(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                url = f"{runner.server_url}/gh_404_{test_id}"
            else:
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases/latest.json", {"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases.json", [{"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/checkout/git/ref/tags/v7.0.1.json", content_or_none)
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases/latest.json", {"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases.json", [{"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/git/ref/tags/v1.8.1.json", {"object": {"sha": "e51d8e519be8f8d29450b2bc73ea832f4165e2c1", "type": "commit"}})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases/latest.json", {"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases.json", [{"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/git/ref/tags/v4.4.0.json", {"object": {"sha": "49933ea5288caeca8642d1e84afbd3f7d6820020", "type": "commit"}})
                url = f"{runner.server_url}/{test_id}"
            return ['--github-api', url]
        return (test_id, 'GitHub tag ref', damage_kind, setup_fn, 'GitHub tag ref')

    tests.append(test_gh_ref('url_gh_ref_404', 'http_404', None))
    tests.append(test_gh_ref('url_gh_ref_empty', 'empty_body', ''))
    tests.append(test_gh_ref('url_gh_ref_ws', 'whitespace', '   \n'))
    tests.append(test_gh_ref('url_gh_ref_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_gh_ref('url_gh_ref_null', 'top_level_null', 'null\n'))
    tests.append(test_gh_ref('url_gh_ref_array', 'top_level_array', '[]\n'))
    tests.append(test_gh_ref('url_gh_ref_error', 'error_payload', '{"error": "ref error"}'))

    # GitHub tag object
    def test_gh_tag(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                url = f"{runner.server_url}/gh_404_{test_id}"
            else:
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases/latest.json", {"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/checkout/releases.json", [{"tag_name": "v7.0.1", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/checkout/git/ref/tags/v7.0.1.json", {"object": {"sha": "tagsha1234567890abcdef1234567890abcdef12", "type": "tag"}})
                setup_url_fixture(f"{test_id}/repos/actions/checkout/git/tags/tagsha1234567890abcdef1234567890abcdef12.json", content_or_none)
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases/latest.json", {"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/releases.json", [{"tag_name": "v1.8.1", "published_at": "2026-05-10T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/dart-lang/setup-dart/git/ref/tags/v1.8.1.json", {"object": {"sha": "e51d8e519be8f8d29450b2bc73ea832f4165e2c1", "type": "commit"}})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases/latest.json", {"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"})
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/releases.json", [{"tag_name": "v4.4.0", "published_at": "2026-05-01T12:00:00Z"}])
                setup_url_fixture(f"{test_id}/repos/actions/setup-node/git/ref/tags/v4.4.0.json", {"object": {"sha": "49933ea5288caeca8642d1e84afbd3f7d6820020", "type": "commit"}})
                url = f"{runner.server_url}/{test_id}"
            return ['--github-api', url]
        return (test_id, 'GitHub tag object', damage_kind, setup_fn, 'GitHub tag object')

    tests.append(test_gh_tag('url_gh_tag_404', 'http_404', None))
    tests.append(test_gh_tag('url_gh_tag_empty', 'empty_body', ''))
    tests.append(test_gh_tag('url_gh_tag_ws', 'whitespace', '   \n'))
    tests.append(test_gh_tag('url_gh_tag_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_gh_tag('url_gh_tag_null', 'top_level_null', 'null\n'))
    tests.append(test_gh_tag('url_gh_tag_array', 'top_level_array', '[]\n'))
    tests.append(test_gh_tag('url_gh_tag_error', 'error_payload', '{"error": "tag error"}'))

    # Node index
    def test_node(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            if content_or_none is None:
                url = f"{runner.server_url}/node_404_{test_id}.json"
            else:
                setup_url_fixture(f"{test_id}/dist/index.json", content_or_none)
                url = f"{runner.server_url}/{test_id}/dist/index.json"
            return ['--node-dist', url]
        return (test_id, 'Node index', damage_kind, setup_fn, 'Node releases')

    tests.append(test_node('url_node_404', 'http_404', None))
    tests.append(test_node('url_node_empty', 'empty_body', ''))
    tests.append(test_node('url_node_ws', 'whitespace', '   \n'))
    tests.append(test_node('url_node_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_node('url_node_null', 'top_level_null', 'null\n'))
    tests.append(test_node('url_node_obj', 'top_level_object', '{}\n'))
    tests.append(test_node('url_node_error', 'error_payload', '{"error": "node error"}'))
    tests.append(test_node('url_node_empty_lts', 'no_lts_releases', '[{"version": "v21.0.0", "lts": false}]\n'))

    # npm registry package
    def test_npm_reg(test_id, damage_kind, content_or_none):
        def setup_fn(d):
            open(os.path.join(d, 'npm/package.json'), 'w').write(json.dumps({"name": "test_pkg", "overrides": {"pkg_override": "1.0.0"}}))
            open(os.path.join(d, 'dependency_exceptions.tsv'), 'w').write("N4\tpkg_override\t1.0.0\t2026-11-20\tExcused for test GHSA-1111-2222-3333\n")
            if content_or_none is None:
                url = f"{runner.server_url}/npm_404_{test_id}"
            else:
                setup_url_fixture(f"{test_id}/pkg_override.json", content_or_none)
                url = f"{runner.server_url}/{test_id}"
            return ['--npm-registry', url]
        return (test_id, 'npm registry package', damage_kind, setup_fn, 'npm registry')

    tests.append(test_npm_reg('url_npm_reg_404', 'http_404', None))
    tests.append(test_npm_reg('url_npm_reg_empty', 'empty_body', ''))
    tests.append(test_npm_reg('url_npm_reg_ws', 'whitespace', '   \n'))
    tests.append(test_npm_reg('url_npm_reg_bad_json', 'unparseable_json', '{ bad'))
    tests.append(test_npm_reg('url_npm_reg_null', 'top_level_null', 'null\n'))
    tests.append(test_npm_reg('url_npm_reg_array', 'top_level_array', '[]\n'))
    tests.append(test_npm_reg('url_npm_reg_error', 'error_payload', '{"error": "registry error"}'))
    tests.append(test_npm_reg('url_npm_reg_no_time', 'missing_time_field', '{"name": "pkg_override"}\n'))

    # Execute damage tests
    print(f"Running {len(tests)} damage tests...")
    for test_id, input_name, damage_kind, setup_fn, expected_identifier in tests:
        d = runner.create_case_dir(test_id)
        res_setup = setup_fn(d)
        extra_args = res_setup if isinstance(res_setup, list) else None
        rc, out, err = runner.run_check(d, extra_args)

        combined = (out + "\n" + err).strip()
        has_traceback = "Traceback (most recent call last)" in combined
        # Check that output names the damaged input (file path or URL)
        input_named = (
            expected_identifier.lower() in combined.lower() or
            input_name.lower() in combined.lower() or
            (extra_args and any(isinstance(a, str) and a.startswith('http') and a.lower() in combined.lower() for a in extra_args))
        )

        if rc == 0:
            failing_rows.append(f"FAIL_OPEN: {input_name} | {damage_kind} | exit code was 0 (expected non-zero failure)")
        elif has_traceback:
            failing_rows.append(f"UNHANDLED_EXCEPTION: {input_name} | {damage_kind} | traceback detected in output: {combined[:120]}...")
        elif not input_named:
            failing_rows.append(f"MISSING_INPUT_NAME: {input_name} | {damage_kind} | output did not mention '{expected_identifier}': {combined[:120]}...")
        else:
            passing_rows.append(f"PASS: {input_name} | {damage_kind}")

    # --- 3. ALLOWED-VALID TESTS ---
    valid_tests = []
    # 1. exceptions empty
    valid_tests.append(('exceptions_empty', 'dependency_exceptions.tsv', 'empty_file', lambda d: open(os.path.join(d, 'dependency_exceptions.tsv'), 'w').close(), '0 exceptions allowed'))
    # 2. exceptions comments only
    valid_tests.append(('exceptions_comments', 'dependency_exceptions.tsv', 'comments_only', lambda d: open(os.path.join(d, 'dependency_exceptions.tsv'), 'w').write("# comment 1\n# comment 2\n"), 'comments only allowed'))
    # 3. npm outdated empty object
    valid_tests.append(('npm_outdated_empty_obj', 'npm/outdated.json', 'empty_object', lambda d: open(os.path.join(d, 'npm/outdated.json'), 'w').write("{}\n"), 'npm outdated prints {} when current'))
    # 4. pub advisories empty list
    def setup_val_adv(d):
        setup_url_fixture('val_adv/api/packages/meta/advisories.json', '{"advisories": []}\n')
        return ['--pub-api', f"{runner.server_url}/val_adv"]
    valid_tests.append(('pub_adv_empty_list', 'pub.dev advisories', 'empty_advisories_list', setup_val_adv, 'pub.dev returns {"advisories": []} when clean'))
    # 5. npm audit zero vulnerabilities
    valid_tests.append(('npm_audit_zero_vulns', 'npm/audit.json', 'zero_vulnerabilities', lambda d: open(os.path.join(d, 'npm/audit.json'), 'w').write(json.dumps({
        "auditReportVersion": 2, "vulnerabilities": {}, "metadata": {"vulnerabilities": {"info": 0, "low": 0, "moderate": 0, "high": 0, "critical": 0, "total": 0}}
    })), 'npm audit reports 0 vulnerabilities when clean'))
    # 6. pubspec without flutter (pure Dart)
    def setup_pure_dart(d):
        open(os.path.join(d, 'pubspec.yaml'), 'w').write("name: test_pkg\nenvironment:\n  sdk: ^3.13.0\ndependencies:\n  meta: ^1.19.0\n")
        open(os.path.join(d, '.github/workflows/ci.yml'), 'w').write("""name: CI
on: [push]
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.7
  min-sdk:
    runs-on: ubuntu-latest
    steps:
      - uses: dart-lang/setup-dart@e51d8e519be8f8d29450b2bc73ea832f4165e2c1 # v1.8.1
        with:
          sdk: 3.13.0
""")
    valid_tests.append(('pubspec_pure_dart', 'pubspec.yaml', 'pure_dart_no_flutter', setup_pure_dart, 'pure Dart package has no flutter constraint'))

    print(f"Running {len(valid_tests)} allowed-valid tests...")
    for test_id, input_name, damage_kind, setup_fn, reason in valid_tests:
        d = runner.create_case_dir(test_id)
        res_setup = setup_fn(d)
        extra_args = res_setup if isinstance(res_setup, list) else None
        rc, out, err = runner.run_check(d, extra_args)
        if rc != 0:
            failing_rows.append(f"VALID_REJECTED: {input_name} | {damage_kind} | exited with code {rc} but should pass ({reason}): {(out + err).strip()[:100]}")
        else:
            passing_rows.append(f"PASS (allowed-valid): {input_name} | {damage_kind} ({reason})")

    runner.cleanup()

    print("\n--- RESULTS ---")
    print(f"Total tests: {len(tests) + len(valid_tests)}")
    print(f"Passing: {len(passing_rows)}")
    print(f"Failing: {len(failing_rows)}")
    if failing_rows:
        print("\nFailing rows:")
        for r in failing_rows:
            print("  ", r)
        sys.exit(1)
    else:
        print(f"\nFC law: {len(tests)} rows, {len(tests)} failed closed")
        print(f"FC law allowed-valid: {len(valid_tests)} rows passed")
        sys.exit(0)

if __name__ == '__main__':
    main()

EOF_DC71

# DC73: Source check - no swallowed exceptions
echo "Running DC73: Check for swallowed exceptions..."
if grep -n "except Exception: *pass" "$SCRIPT_DIR/check_dependencies.py"; then
  echo "FAIL DC73: Found swallowed exceptions in check_dependencies.py"
  exit 1
fi

echo "All 73 dependency check self-tests (DC1 - DC73) passed successfully!"
