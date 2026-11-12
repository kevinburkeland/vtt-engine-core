#!/usr/bin/env python3
import sys
import os
import re
import argparse
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone, date, timedelta
import time

def parse_date(date_str):
    if not date_str:
        return None
    # Strip trailing Z or +00:00 or parse YYYY-MM-DD
    cleaned = date_str.strip()
    if len(cleaned) == 10 and cleaned.count('-') == 2:
        try:
            return datetime.strptime(cleaned, '%Y-%m-%d').date()
        except Exception:
            pass
    if cleaned.endswith('Z'):
        cleaned = cleaned[:-1] + '+00:00'
    try:
        dt = datetime.fromisoformat(cleaned)
        return dt.date()
    except Exception:
        return None

def fetch_json(url, headers=None, retries=3):
    req_headers = {
        'User-Agent': 'check_dependencies/1.0',
        'Accept': 'application/json',
    }
    if headers:
        req_headers.update(headers)

    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers=req_headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.getcode() != 200:
                    raise urllib.error.HTTPError(url, resp.getcode(), 'HTTP non-200', resp.headers, None)
                body = resp.read().decode('utf-8')
                return json.loads(body)
        except Exception as e:
            last_err = e
            if attempt < retries - 1:
                time.sleep(0.2 * (attempt + 1))
    print(f"Error: Network failure fetching URL '{url}': {last_err}", file=sys.stderr)
    sys.exit(1)

def parse_semver(v_str):
    cleaned = re.sub(r'^[v\^~>=<]+', '', str(v_str).strip())
    without_build = cleaned.split('+', 1)[0]
    parts = without_build.split('-', 1)
    core = parts[0]
    prerelease = parts[1] if len(parts) > 1 else None

    core_parts = []
    for p in core.split('.'):
        try:
            core_parts.append(int(p))
        except ValueError:
            core_parts.append(0)
    while len(core_parts) < 3:
        core_parts.append(0)
    return tuple(core_parts[:3]), prerelease

def semver_tuple(v_str):
    c, _ = parse_semver(v_str)
    return c

def semver_cmp(v1_str, v2_str):
    c1, pre1 = parse_semver(v1_str)
    c2, pre2 = parse_semver(v2_str)
    if c1 < c2:
        return -1
    elif c1 > c2:
        return 1

    if pre1 is not None and pre2 is None:
        return -1
    if pre1 is None and pre2 is not None:
        return 1
    if pre1 is None and pre2 is None:
        return 0

    p1_parts = pre1.split('.')
    p2_parts = pre2.split('.')
    for i in range(max(len(p1_parts), len(p2_parts))):
        if i >= len(p1_parts):
            return -1
        if i >= len(p2_parts):
            return 1
        id1, id2 = p1_parts[i], p2_parts[i]
        id1_is_num, id2_is_num = id1.isdigit(), id2.isdigit()
        if id1_is_num and id2_is_num:
            n1, n2 = int(id1), int(id2)
            if n1 < n2: return -1
            if n1 > n2: return 1
        elif id1_is_num and not id2_is_num:
            return -1
        elif not id1_is_num and id2_is_num:
            return 1
        else:
            if id1 < id2: return -1
            if id1 > id2: return 1
    return 0

def is_version_in_ranges(v_str, ranges):
    for r in ranges:
        events = r.get('events', [])
        introduced = None
        fixed = None
        for ev in events:
            if 'introduced' in ev and ev['introduced']:
                introduced = ev['introduced']
            if 'fixed' in ev and ev['fixed']:
                fixed = ev['fixed']
        
        matches = True
        if introduced:
            if semver_cmp(v_str, introduced) < 0:
                matches = False
        if fixed:
            if semver_cmp(v_str, fixed) >= 0:
                matches = False
        if matches and (introduced or fixed):
            return True
    return False

def parse_workflow_file(wf_path, wf_file):
    with open(wf_path, 'r', encoding='utf-8') as f:
        wf_lines = f.readlines()

    jobs = []
    in_jobs_section = False
    current_job = None
    current_step = None

    for line_idx, raw_line in enumerate(wf_lines, 1):
        line = raw_line.rstrip('\r\n')
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        indent = len(line) - len(line.lstrip(' '))

        if indent == 0:
            if stripped.startswith('jobs:'):
                in_jobs_section = True
            else:
                in_jobs_section = False
            current_job = None
            current_step = None
            continue

        if not in_jobs_section:
            continue

        # Top-level jobs are indented exactly 2 spaces
        if indent == 2:
            m_job = re.match(r'^  ([a-zA-Z0-9_\-]+):\s*(?:#.*)?$', line)
            if m_job:
                job_id = m_job.group(1)
                current_job = {
                    'id': job_id,
                    'name': None,
                    'file': wf_file,
                    'line': line_idx,
                    'steps': []
                }
                jobs.append(current_job)
                current_step = None
            continue

        if current_job is None:
            continue

        # Job attributes are indented 4 spaces
        if indent == 4:
            m_name = re.match(r'^    name:\s*(.*)$', line)
            if m_name:
                name_val = m_name.group(1).split('#')[0].strip().strip("'\"")
                current_job['name'] = name_val
            continue

        # Step item starts with 6 spaces: "      - "
        m_step = re.match(r'^\s{6}-\s*(.*)$', line)
        if m_step:
            current_step = {
                'job_id': current_job['id'],
                'file': wf_file,
                'start_line': line_idx,
                'uses': None,
                'uses_line': None,
                'with_active': False,
                'with_indent': 0,
                'sdk': None,
                'sdk_line': None,
                'node_version': None,
                'node_version_line': None,
            }
            current_job['steps'].append(current_step)
            rest = m_step.group(1).strip()
            if rest.startswith('uses:'):
                current_step['uses_line'] = line_idx
                current_step['uses'] = rest.split('uses:', 1)[1].strip()
            continue

        if current_step is not None:
            # Check if line sets with:
            if re.match(r'^\s+with:\s*(?:#.*)?$', line):
                current_step['with_active'] = True
                current_step['with_indent'] = indent
                continue

            if current_step['with_active']:
                if indent <= current_step['with_indent']:
                    current_step['with_active'] = False
                else:
                    m_sdk = re.match(r'^\s+sdk:\s*(.*)$', line)
                    if m_sdk:
                        current_step['sdk'] = m_sdk.group(1).split('#')[0].strip().strip("'\"")
                        current_step['sdk_line'] = line_idx
                    m_node = re.match(r'^\s+node-version:\s*(.*)$', line)
                    if m_node:
                        current_step['node_version'] = m_node.group(1).split('#')[0].strip().strip("'\"")
                        current_step['node_version_line'] = line_idx
                    continue

            # Check uses inside step (e.g. 8 spaces)
            m_uses = re.match(r'^\s+uses:\s*(.*)$', line)
            if m_uses:
                current_step['uses_line'] = line_idx
                current_step['uses'] = m_uses.group(1).strip()

    return jobs

def read_pubspec(pubspec_path):
    sdk_constraint = None
    flutter_constraint = None
    direct_exact_pins = []
    dev_exact_pins = []
    direct_deps = set()
    dev_deps = set()
    non_hosted_deps = set()
    declared_floors = {}

    current_section = None
    current_dep_name = None

    if not os.path.exists(pubspec_path):
        print(f"Error: Pubspec file '{pubspec_path}' not found.", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(pubspec_path):
        print(f"Error: Pubspec path '{pubspec_path}' is not a file.", file=sys.stderr)
        sys.exit(1)

    # Read pubspec.lock if present
    lock_path = os.path.join(os.path.dirname(pubspec_path), 'pubspec.lock')
    if os.path.exists(lock_path):
        current_pkg = None
        with open(lock_path, 'r', encoding='utf-8') as f:
            for line in f:
                m = re.match(r'^  ([a-zA-Z0-9_]+):', line)
                if m:
                    current_pkg = m.group(1)
                elif current_pkg and 'source:' in line:
                    source = line.split('source:', 1)[1].strip().strip('"\'')
                    if source != 'hosted':
                        non_hosted_deps.add(current_pkg)

    with open(pubspec_path, 'r', encoding='utf-8') as f:
        for raw_line in f:
            line = raw_line.rstrip()
            if not line or line.strip().startswith('#'):
                continue
            
            # Top level sections
            if not line.startswith(' ') and not line.startswith('\t'):
                if line.startswith('environment:'):
                    current_section = 'environment'
                elif line.startswith('dependencies:'):
                    current_section = 'dependencies'
                elif line.startswith('dev_dependencies:'):
                    current_section = 'dev_dependencies'
                else:
                    current_section = None
                current_dep_name = None
                continue

            # Inside section
            indent_line = line.strip()
            if current_section == 'environment':
                if indent_line.startswith('sdk:'):
                    sdk_constraint = indent_line.split(':', 1)[1].strip().strip("'\"")
                elif indent_line.startswith('flutter:'):
                    flutter_constraint = indent_line.split(':', 1)[1].strip().strip("'\"")
            elif current_section in ('dependencies', 'dev_dependencies'):
                if line.startswith('  ') and not line.startswith('    ') and ':' in indent_line:
                    pkg_name, rest = indent_line.split(':', 1)
                    pkg_name = pkg_name.strip()
                    current_dep_name = pkg_name
                    val = rest.strip()
                    if current_section == 'dependencies':
                        direct_deps.add(pkg_name)
                    else:
                        dev_deps.add(pkg_name)

                    if val and not val.startswith('{') and not val.startswith('#'):
                        val_clean = val.split('#')[0].strip().strip("'\"")
                        if re.match(r'^\d+\.\d+\.\d+.*$', val_clean):
                            # It's an exact pin!
                            if current_section == 'dependencies':
                                direct_exact_pins.append((pkg_name, val_clean))
                            else:
                                dev_exact_pins.append((pkg_name, val_clean))
                            declared_floors[pkg_name] = val_clean
                        elif val_clean.startswith('^'):
                            declared_floors[pkg_name] = val_clean[1:].strip()
                        elif val_clean.startswith('>='):
                            m_floor = re.search(r'>=\s*([0-9a-zA-Z\.\+\-]+)', val_clean)
                            if m_floor:
                                declared_floors[pkg_name] = m_floor.group(1).strip()
                    elif val.startswith('{'):
                        if 'git:' in val or 'sdk:' in val or 'path:' in val:
                            non_hosted_deps.add(pkg_name)
                elif current_dep_name and ('git:' in indent_line or 'sdk:' in indent_line or 'path:' in indent_line):
                    non_hosted_deps.add(current_dep_name)

    return sdk_constraint, flutter_constraint, direct_exact_pins, dev_exact_pins, direct_deps, dev_deps, non_hosted_deps, declared_floors

def get_ghsa_ids(pkg_name, all_vulns, visited=None):
    if visited is None:
        visited = set()
    if pkg_name in visited:
        return set()
    visited.add(pkg_name)
    ghsas = set()
    pkg_info = all_vulns.get(pkg_name, {})
    if not isinstance(pkg_info, dict):
        return set()
    vias = pkg_info.get('via', [])
    for v in vias:
        if isinstance(v, dict):
            for field in [v.get('url', ''), v.get('title', ''), str(v)]:
                for m in re.findall(r'GHSA-[a-zA-Z0-9\-]+', field, re.IGNORECASE):
                    ghsas.add(m.upper())
        elif isinstance(v, str):
            ghsas.update(get_ghsa_ids(v, all_vulns, visited))
    return ghsas

def main():
    parser = argparse.ArgumentParser(description='Enforce dependency currency and security invariances.')
    parser.add_argument('--pub-outdated', required=True, help='Path to pub outdated JSON file')
    parser.add_argument('--pubspec', required=True, help='Path to pubspec.yaml')
    parser.add_argument('--workflows', required=True, help='Path to .github/workflows directory')
    parser.add_argument('--exceptions', required=True, help='Path to dependency_exceptions.tsv')
    parser.add_argument('--pub-api', default='https://pub.dev', help='Base URL for Pub API')
    parser.add_argument('--flutter-releases', default='https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json', help='URL for Flutter releases')
    parser.add_argument('--github-api', default='https://api.github.com', help='Base URL for GitHub API')
    parser.add_argument('--npm-dir', default=None, help='Directory containing npm package.json/lock')
    parser.add_argument('--npm-outdated', default=None, help='Path to npm outdated JSON')
    parser.add_argument('--npm-audit', default=None, help='Path to npm audit JSON')
    parser.add_argument('--npm-registry', default='https://registry.npmjs.org', help='Base URL for npm registry')
    parser.add_argument('--node-dist', default='https://nodejs.org/dist/index.json', help='URL for Node LTS releases')
    parser.add_argument('--today', default=None, help='Override date YYYY-MM-DD for testing only')

    args = parser.parse_args()

    # Refuse --today in GitHub Actions (DC35)
    if args.today is not None and os.environ.get('GITHUB_ACTIONS') == 'true':
        print("Error: --today parameter is forbidden when running inside GitHub Actions.", file=sys.stderr)
        sys.exit(1)

    today = parse_date(args.today) if args.today else datetime.now(timezone.utc).date()
    print(f"Checking dependencies against date: {today}")

    github_headers = {}
    github_token = os.environ.get('GITHUB_TOKEN')
    if github_token:
        github_headers['Authorization'] = f'Bearer {github_token}'

    # Validate inputs exist and are readable (Fix 2.1)
    if not os.path.exists(args.pub_outdated) or not os.path.isfile(args.pub_outdated):
        print(f"Error: Outdated file '{args.pub_outdated}' not found or unreadable.", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(args.pubspec) or not os.path.isfile(args.pubspec):
        print(f"Error: Pubspec file '{args.pubspec}' not found or unreadable.", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(args.workflows) or not os.path.isdir(args.workflows):
        print(f"Error: Workflows directory '{args.workflows}' not found or not a directory.", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(args.exceptions) or not os.path.isfile(args.exceptions):
        print(f"Error: Exceptions file '{args.exceptions}' not found or unreadable.", file=sys.stderr)
        sys.exit(1)

    has_npm = any([args.npm_dir, args.npm_outdated, args.npm_audit])
    if has_npm:
        if not args.npm_dir or not os.path.exists(args.npm_dir) or not os.path.isdir(args.npm_dir):
            print(f"Error: npm directory '{args.npm_dir}' not found or not a directory.", file=sys.stderr)
            sys.exit(1)
        if not args.npm_outdated or not os.path.exists(args.npm_outdated) or not os.path.isfile(args.npm_outdated):
            print(f"Error: npm outdated file '{args.npm_outdated}' not found or unreadable.", file=sys.stderr)
            sys.exit(1)
        if not args.npm_audit or not os.path.exists(args.npm_audit) or not os.path.isfile(args.npm_audit):
            print(f"Error: npm audit file '{args.npm_audit}' not found or unreadable.", file=sys.stderr)
            sys.exit(1)

    # Parse exceptions
    exceptions = []
    exception_failures = []
    if os.path.exists(args.exceptions):
        with open(args.exceptions, 'r', encoding='utf-8') as f:
            for line_no, raw_line in enumerate(f, 1):
                line = raw_line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split('\t')
                if len(parts) != 5:
                    exception_failures.append(f"E1: {args.exceptions}:{line_no}: Malformed exception row: expected 5 tab-separated fields, got {len(parts)}")
                    continue
                rule_id, name, held_at, review_by_str, reason = parts
                rule_id = rule_id.strip()
                name = name.strip()
                held_at = held_at.strip()
                review_by = parse_date(review_by_str.strip())
                reason = reason.strip()

                if not review_by:
                    exception_failures.append(f"E1: {args.exceptions}:{line_no}: Invalid date format in review_by: '{review_by_str}'")
                    continue
                if len(reason) < 20:
                    exception_failures.append(f"E1: {args.exceptions}:{line_no}: Exception reason too short (under 20 characters): '{reason}'")
                if review_by < today:
                    exception_failures.append(f"E1: {args.exceptions}:{line_no}: Exception review_by date {review_by} is in the past (today is {today})")
                max_days = 30 if rule_id in ('D2', 'N2', 'N4') else 90
                if review_by > today + timedelta(days=max_days):
                    exception_failures.append(f"E1: {args.exceptions}:{line_no}: Exception review_by date {review_by} is more than {max_days} days in future")
                if rule_id in ('D2', 'N2', 'N4'):
                    if not re.search(r'GHSA-[a-z0-9\-]+', reason, re.IGNORECASE):
                        exception_failures.append(f"E1: {args.exceptions}:{line_no}: {rule_id} exception reason must include advisory ID: '{reason}'")

                exceptions.append({
                    'line_no': line_no,
                    'rule': rule_id,
                    'name': name,
                    'held_at': held_at,
                    'review_by': review_by,
                    'reason': reason,
                    'used': False
                })

    matched_exceptions = set()

    def check_exception(rule_id, name, version):
        for idx, exc in enumerate(exceptions):
            if exc['rule'] == rule_id and exc['name'] == name and exc['held_at'] == version:
                exc['used'] = True
                matched_exceptions.add(idx)
                return True
        return False

    failures = list(exception_failures)
    pending_notes = []
    held_notes = []

    # Read pubspec
    sdk_constraint, flutter_constraint, direct_exact_pins, dev_exact_pins, direct_deps, dev_deps, non_hosted_deps, declared_floors = read_pubspec(args.pubspec)

    # D5: exact pins
    for pkg, v in direct_exact_pins + dev_exact_pins:
        if not check_exception('D5', pkg, v):
            failures.append(f"D5: Package '{pkg}' has exact version pin '{v}' in {args.pubspec}")

    # Read pub outdated JSON
    if not os.path.exists(args.pub_outdated):
        print(f"Error: Outdated file '{args.pub_outdated}' not found.", file=sys.stderr)
        sys.exit(1)

    with open(args.pub_outdated, 'r', encoding='utf-8') as f:
        content = f.read()
    
    first_brace = content.find('{')
    if first_brace == -1:
        print(f"Error: Malformed pub outdated JSON in '{args.pub_outdated}': no JSON object found.", file=sys.stderr)
        sys.exit(1)

    try:
        outdated_data = json.loads(content[first_brace:])
    except Exception as e:
        print(f"Error: Failed to parse pub outdated JSON in '{args.pub_outdated}': {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(outdated_data, dict):
        print(f"Error: Malformed pub outdated JSON in '{args.pub_outdated}': root must be a dict.", file=sys.stderr)
        sys.exit(1)
    if 'packages' not in outdated_data or not isinstance(outdated_data['packages'], list):
        print(f"Error: Malformed pub outdated JSON in '{args.pub_outdated}': 'packages' key must be a list.", file=sys.stderr)
        sys.exit(1)
    pub_packages = outdated_data['packages']
    package_api_cache = {}

    def get_pub_package_info(pkg_name):
        if pkg_name in package_api_cache:
            return package_api_cache[pkg_name]
        url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}"
        data = fetch_json(url)
        package_api_cache[pkg_name] = data
        return data

    for pkg_item in pub_packages:
        pkg_name = pkg_item.get('package')
        kind = pkg_item.get('kind', 'transitive')
        is_disc = pkg_item.get('isDiscontinued', False)
        is_ret = pkg_item.get('isCurrentRetracted', False)
        is_adv = pkg_item.get('isCurrentAffectedByAdvisory', False)

        curr_obj = pkg_item.get('current') or {}
        res_obj = pkg_item.get('resolvable') or {}
        lat_obj = pkg_item.get('latest') or {}

        curr_v = curr_obj.get('version')
        res_v = res_obj.get('version')
        lat_v = lat_obj.get('version')

        if not curr_v:
            continue

        if pkg_name in non_hosted_deps:
            # Skip pub.dev API queries for local git or sdk dependencies
            continue

        # D3: retracted or discontinued
        if is_disc:
            if not check_exception('D3', pkg_name, curr_v):
                failures.append(f"D3: Package '{pkg_name}' is discontinued")
        if is_ret:
            if not check_exception('D3', pkg_name, curr_v):
                failures.append(f"D3: Package '{pkg_name}' version {curr_v} is retracted")

        # D2: advisory
        has_advisory = is_adv
        advisory_id = None
        if not has_advisory:
            # Query advisories endpoint
            adv_url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}/advisories"
            try:
                adv_data = fetch_json(adv_url)
                for adv in adv_data.get('advisories', []):
                    for aff in adv.get('affected', []):
                        aff_versions = aff.get('versions', [])
                        if curr_v in aff_versions:
                            has_advisory = True
                            advisory_id = adv.get('id', 'unknown')
                            break
                        if is_version_in_ranges(curr_v, aff.get('ranges', [])):
                            has_advisory = True
                            advisory_id = adv.get('id', 'unknown')
                            break
                    if has_advisory:
                        break
            except Exception:
                pass

        if has_advisory:
            if not check_exception('D2', pkg_name, curr_v):
                failures.append(f"D2: Package '{pkg_name}' at version {curr_v} is affected by security advisory ({advisory_id or 'reported by pub outdated'})")

        # D1: graph current
        if res_v and curr_v != res_v:
            # Current is behind resolvable
            pkg_info = get_pub_package_info(pkg_name)
            # Find publish date of FIRST newer version > curr_v (Fix 3.1)
            first_newer_date = None
            first_newer_ver = None
            for v_entry in pkg_info.get('versions', []):
                v_str = v_entry.get('version')
                if v_str and semver_cmp(v_str, curr_v) > 0 and semver_cmp(v_str, res_v) <= 0:
                    d = parse_date(v_entry.get('published'))
                    if d:
                        if first_newer_date is None or d < first_newer_date:
                            first_newer_date = d
                            first_newer_ver = v_str
            
            if first_newer_date:
                age_days = (today - first_newer_date).days
                if age_days < 14:
                    pending_notes.append(f"Package '{pkg_name}' resolvable {res_v} pending ({age_days} days old)")
                else:
                    if not check_exception('D1', pkg_name, curr_v):
                        failures.append(f"D1: Package '{pkg_name}' current {curr_v} is behind resolvable {res_v} (first newer release {first_newer_ver} published {first_newer_date}, {age_days} days old)")
            else:
                if not check_exception('D1', pkg_name, curr_v):
                    failures.append(f"D1: Package '{pkg_name}' current {curr_v} is behind resolvable {res_v}")

        elif lat_v and curr_v == res_v and semver_cmp(curr_v, lat_v) < 0:
            held_notes.append(f"Package '{pkg_name}' held by graph at {curr_v} (latest is {lat_v})")

        # D6: declared floor current (Fix 3.3)
        if (kind == 'direct' or pkg_name in direct_deps or pkg_name in dev_deps) and pkg_name in declared_floors:
            if pkg_name not in non_hosted_deps:
                floor_v = declared_floors[pkg_name]
                if curr_v and floor_v and curr_v != floor_v:
                    pkg_info = get_pub_package_info(pkg_name)
                    first_newer_floor_date = None
                    first_newer_floor_ver = None
                    for v_entry in pkg_info.get('versions', []):
                        v_str = v_entry.get('version')
                        if v_str and semver_cmp(v_str, floor_v) > 0:
                            if '-' in v_str and '-' not in floor_v:
                                continue
                            d = parse_date(v_entry.get('published'))
                            if d:
                                if first_newer_floor_date is None or d < first_newer_floor_date:
                                    first_newer_floor_date = d
                                    first_newer_floor_ver = v_str

                    age_days = (today - first_newer_floor_date).days if first_newer_floor_date else 999
                    if age_days < 14:
                        pending_notes.append(f"Package '{pkg_name}' declared floor '{floor_v}' pending current '{curr_v}' ({age_days} days old)")
                    else:
                        if not check_exception('D6', pkg_name, floor_v):
                            failures.append(f"D6: Package '{pkg_name}' declared floor '{floor_v}' is behind current '{curr_v}' (published {age_days} days ago)")

        # D4: not maintained (direct dependencies only)
        if kind == 'direct' or pkg_name in direct_deps:
            pkg_info = get_pub_package_info(pkg_name)
            latest_obj = pkg_info.get('latest', {})
            lat_pub_date = parse_date(latest_obj.get('published'))
            if lat_pub_date:
                days_since = (today - lat_pub_date).days
                if days_since > 730:
                    if not check_exception('D4', pkg_name, curr_v):
                        failures.append(f"D4: Direct dependency '{pkg_name}' is not maintained (newest release {latest_obj.get('version')} was published {days_since} days ago on {lat_pub_date})")

    # Target Flutter and Target Dart (T1, T2, T3)
    flutter_data = fetch_json(args.flutter_releases)
    stable_releases = [r for r in flutter_data.get('releases', []) if r.get('channel') == 'stable']
    newest_flutter = stable_releases[0] if stable_releases else None
    
    if newest_flutter:
        newest_flutter_ver = newest_flutter.get('version')
        newest_flutter_date = parse_date(newest_flutter.get('release_date'))
        target_dart = newest_flutter.get('dart_sdk_version')
        target_dart_minor_floor = f"3.{semver_tuple(target_dart)[1]}.0"

        # Previous stable target Dart and minor floor (for 14-day grace window validation)
        prev_target_dart = None
        for rel in stable_releases:
            d_ver = rel.get('dart_sdk_version')
            if d_ver and semver_cmp(d_ver, target_dart) < 0:
                prev_target_dart = d_ver
                break
        prev_floor = f"3.{semver_tuple(prev_target_dart)[1]}.0" if prev_target_dart else None

        # T1: Flutter version in pubspec (if specified)
        if flutter_constraint:
            if flutter_constraint != newest_flutter_ver:
                age_days = (today - newest_flutter_date).days if newest_flutter_date else 999
                if age_days < 14:
                    pending_notes.append(f"Flutter SDK pin '{flutter_constraint}' pending newest stable {newest_flutter_ver} ({age_days} days old)")
                else:
                    if not check_exception('T1', 'flutter', flutter_constraint):
                        failures.append(f"T1: Flutter constraint '{flutter_constraint}' is behind newest stable '{newest_flutter_ver}' (released {newest_flutter_date}, {age_days} days old)")

        # T3: SDK floor in pubspec
        if sdk_constraint:
            # Expected floor is ^3.<minor>.0 or >=3.<minor>.0
            expected_floor = f"3.{semver_tuple(target_dart)[1]}.0"
            actual_floor = re.search(r'3\.\d+\.0', sdk_constraint)
            actual_floor_ver = actual_floor.group(0) if actual_floor else None
            if not actual_floor_ver or semver_cmp(actual_floor_ver, expected_floor) < 0:
                # Find date of first stable release that shipped this dart minor
                first_release_date = None
                for rel in reversed(stable_releases):
                    d_ver = rel.get('dart_sdk_version', '')
                    if semver_tuple(d_ver)[:2] == semver_tuple(target_dart)[:2]:
                        first_release_date = parse_date(rel.get('release_date'))
                        break
                age_days = (today - first_release_date).days if first_release_date else (today - newest_flutter_date).days if newest_flutter_date else 999
                if age_days < 14 and actual_floor_ver and prev_floor and semver_cmp(actual_floor_ver, prev_floor) >= 0:
                    pending_notes.append(f"SDK constraint floor '{sdk_constraint}' pending target floor ^{expected_floor} ({age_days} days old)")
                else:
                    if not check_exception('T3', 'dart', sdk_constraint):
                        failures.append(f"T3: pubspec environment sdk '{sdk_constraint}' floor is behind target floor ^{expected_floor}")

        # Check workflows
        all_workflow_jobs = []
        all_setup_dart_steps = []

        if os.path.exists(args.workflows):
            for wf_file in sorted(os.listdir(args.workflows)):
                if not (wf_file.endswith('.yml') or wf_file.endswith('.yaml')):
                    continue
                wf_path = os.path.join(args.workflows, wf_file)
                wf_jobs = parse_workflow_file(wf_path, wf_file)
                all_workflow_jobs.extend(wf_jobs)

                for job in wf_jobs:
                    for step in job['steps']:
                        # Check setup-dart
                        if step['uses'] and 'dart-lang/setup-dart' in step['uses']:
                            all_setup_dart_steps.append(step)

                            if not step['sdk']:
                                line_no = step['uses_line'] or step['start_line']
                                failures.append(f"T2: {wf_file}:{line_no}: setup-dart step has no sdk: in with: block")
                            elif job['id'] == 'min-sdk':
                                line_no = step['sdk_line'] or step['uses_line'] or step['start_line']
                                if step['sdk'] != target_dart_minor_floor:
                                    first_release_date = None
                                    for rel in reversed(stable_releases):
                                        d_ver = rel.get('dart_sdk_version', '')
                                        if semver_tuple(d_ver)[:2] == semver_tuple(target_dart)[:2]:
                                            first_release_date = parse_date(rel.get('release_date'))
                                            break
                                    age_days = (today - first_release_date).days if first_release_date else (today - newest_flutter_date).days if newest_flutter_date else 999
                                    if age_days < 14 and prev_floor and semver_cmp(step['sdk'], prev_floor) >= 0:
                                        pending_notes.append(f"{wf_file}:{line_no}: Minimum SDK job sdk '{step['sdk']}' pending target floor '{target_dart_minor_floor}' ({age_days} days old)")
                                    else:
                                        if not check_exception('T3', 'dart', step['sdk']):
                                            failures.append(f"T3: {wf_file}:{line_no}: Minimum SDK job runs '{step['sdk']}', expected exact floor '{target_dart_minor_floor}'")
                            else:
                                line_no = step['sdk_line'] or step['uses_line'] or step['start_line']
                                if step['sdk'] != target_dart:
                                    # Find release date of first Flutter stable that shipped target_dart (Fix 3.1)
                                    first_target_dart_date = None
                                    for rel in reversed(stable_releases):
                                        if rel.get('dart_sdk_version') == target_dart:
                                            first_target_dart_date = parse_date(rel.get('release_date'))
                                            break
                                    age_days = (today - first_target_dart_date).days if first_target_dart_date else (today - newest_flutter_date).days if newest_flutter_date else 999
                                    if age_days < 14 and prev_target_dart and semver_cmp(step['sdk'], prev_target_dart) >= 0:
                                        pending_notes.append(f"{wf_file}:{line_no}: setup-dart sdk '{step['sdk']}' pending target Dart '{target_dart}' ({age_days} days old)")
                                    else:
                                        if not check_exception('T2', 'dart', step['sdk']):
                                            failures.append(f"T2: {wf_file}:{line_no}: setup-dart sdk '{step['sdk']}' is behind target Dart '{target_dart}' (shipped in Flutter {age_days} days ago)")

                        # A1: uses: owner/repo@sha # vX.Y.Z
                        if step['uses']:
                            uses_match = re.search(r'([a-zA-Z0-9_\-]+/[a-zA-Z0-9_\-]+)@([0-9a-fA-F]{40})\s*#\s*(\S+)', step['uses'])
                            if uses_match:
                                action_name = uses_match.group(1)
                                action_sha = uses_match.group(2)
                                action_comment = uses_match.group(3)
                                line_no = step['uses_line'] or step['start_line']

                                # Query GitHub release
                                gh_rel_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/releases/latest"
                                gh_rel_data = fetch_json(gh_rel_url, headers=github_headers)
                                latest_tag = gh_rel_data.get('tag_name')
                                rel_date = parse_date(gh_rel_data.get('published_at'))

                                # Follow tag to commit SHA
                                gh_ref_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/git/ref/tags/{latest_tag}"
                                gh_ref_data = fetch_json(gh_ref_url, headers=github_headers)
                                ref_obj = gh_ref_data.get('object', {})
                                commit_sha = ref_obj.get('sha')
                                if ref_obj.get('type') == 'tag':
                                    tag_obj_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/git/tags/{commit_sha}"
                                    tag_data = fetch_json(tag_obj_url, headers=github_headers)
                                    commit_sha = tag_data.get('object', {}).get('sha', commit_sha)

                                if action_sha != commit_sha or action_comment != latest_tag:
                                    # Query releases list to find date of first newer release tag (Fix 3.1)
                                    first_newer_rel_date = rel_date
                                    gh_all_rels_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/releases"
                                    gh_all_rels = fetch_json(gh_all_rels_url, headers=github_headers)
                                    if isinstance(gh_all_rels, list):
                                        newer_dates = []
                                        for r in gh_all_rels:
                                            if r.get('draft') or r.get('prerelease'):
                                                continue
                                            tag = r.get('tag_name')
                                            p_date = parse_date(r.get('published_at'))
                                            if tag and p_date and semver_cmp(tag, action_comment) > 0:
                                                newer_dates.append(p_date)
                                        if newer_dates:
                                            first_newer_rel_date = min(newer_dates)

                                    age_days = (today - first_newer_rel_date).days if first_newer_rel_date else 999
                                    if age_days < 14:
                                        pending_notes.append(f"{wf_file}:{line_no}: Action '{action_name}' pending latest release {latest_tag} ({age_days} days old)")
                                    else:
                                        if not check_exception('A1', action_name, action_sha):
                                            failures.append(f"A1: {wf_file}:{line_no}: Action '{action_name}' pinned to {action_sha} #{action_comment}, newest is {commit_sha} #{latest_tag}")

                        # N3: Node LTS in actions/setup-node
                        if step['node_version']:
                            node_val = step['node_version']
                            line_no = step['node_version_line'] or step['start_line']
                            node_dist_data = fetch_json(args.node_dist)
                            lts_releases = [x for x in node_dist_data if x.get('lts')]
                            if lts_releases:
                                newest_lts = lts_releases[0]
                                lts_ver = newest_lts.get('version', '').lstrip('v')
                                lts_major = lts_ver.split('.')[0]
                                # Find date the major first became LTS (oldest release with this lts_major) (Fix 3.1)
                                first_lts_date = None
                                for rel in reversed(lts_releases):
                                    v = rel.get('version', '').lstrip('v')
                                    if v.split('.')[0] == lts_major:
                                        first_lts_date = parse_date(rel.get('date'))
                                        break
                                lts_date = first_lts_date or parse_date(newest_lts.get('date'))
                                if node_val != lts_major:
                                    age_days = (today - lts_date).days if lts_date else 999
                                    if age_days < 14:
                                        pending_notes.append(f"{wf_file}:{line_no}: Node version '{node_val}' pending newest LTS '{lts_major}' ({age_days} days old)")
                                    else:
                                        if not check_exception('N3', 'node', node_val):
                                            failures.append(f"N3: {wf_file}:{line_no}: node-version '{node_val}' is behind newest Node LTS major '{lts_major}' (became LTS {lts_date}, {age_days} days old)")

            # T3 validation for pure Dart packages
            is_pure_dart = (flutter_constraint is None)
            min_sdk_jobs = [j for j in all_workflow_jobs if j['id'] == 'min-sdk']
            if is_pure_dart:
                if len(min_sdk_jobs) != 1:
                    failures.append(f"T3: Pure Dart package requires exactly one 'min-sdk' job, found {len(min_sdk_jobs)}")
                else:
                    min_sdk_job = min_sdk_jobs[0]
                    sd_steps = [s for s in min_sdk_job['steps'] if s['uses'] and 'dart-lang/setup-dart' in s['uses']]
                    if len(sd_steps) != 1:
                        failures.append(f"T3: 'min-sdk' job in pure Dart package must contain exactly one setup-dart step, found {len(sd_steps)}")

            # Print setup-dart summary lines (Fix 1.3)
            for s in all_setup_dart_steps:
                role = 'floor' if s['job_id'] == 'min-sdk' else 'target'
                line_no = s['uses_line'] or s['start_line']
                sdk_disp = s['sdk'] if s['sdk'] is not None else ''
                print(f"setup-dart: {s['file']}:{line_no} job {s['job_id']} sdk {sdk_disp} ({role})")

    # N1 & N2: npm dependencies
    if args.npm_dir:
        try:
            with open(args.npm_outdated, 'r', encoding='utf-8') as f:
                npm_outdated_content = f.read().strip()
            if npm_outdated_content:
                npm_outdated_data = json.loads(npm_outdated_content)
                if not isinstance(npm_outdated_data, dict):
                    failures.append(f"N1: npm outdated JSON in '{args.npm_outdated}' must be an object")
                elif 'error' in npm_outdated_data:
                    failures.append(f"N1: npm outdated reported error: {npm_outdated_data['error']}")
                else:
                    for npm_pkg, details in npm_outdated_data.items():
                        if not isinstance(details, dict):
                            failures.append(f"N1: npm outdated details for '{npm_pkg}' must be an object")
                            continue
                        curr_npm_v = details.get('current')
                        lat_npm_v = details.get('latest')
                        if curr_npm_v and lat_npm_v and curr_npm_v != lat_npm_v:
                            if semver_cmp(curr_npm_v, lat_npm_v) > 0:
                                print(f"npm package '{npm_pkg}' version {curr_npm_v} ahead of latest tag {lat_npm_v}")
                                continue
                            # Query npm registry
                            npm_pkg_url = f"{args.npm_registry.rstrip('/')}/{npm_pkg}"
                            npm_pkg_data = fetch_json(npm_pkg_url)
                            # Find publish date of FIRST newer version > curr_npm_v (Fix 3.1)
                            time_dict = npm_pkg_data.get('time', {})
                            first_newer_date = None
                            first_newer_ver = None
                            for v_str, time_str in time_dict.items():
                                if v_str not in ('created', 'modified'):
                                    try:
                                        if semver_cmp(v_str, curr_npm_v) > 0 and semver_cmp(v_str, lat_npm_v) <= 0:
                                            d = parse_date(time_str)
                                            if d and (first_newer_date is None or d < first_newer_date):
                                                first_newer_date = d
                                                first_newer_ver = v_str
                                    except Exception:
                                        pass
                            if not first_newer_date:
                                pub_time = time_dict.get(lat_npm_v)
                                first_newer_date = parse_date(pub_time) if pub_time else None
                                first_newer_ver = lat_npm_v

                            age_days = (today - first_newer_date).days if first_newer_date else 999
                            if age_days < 14:
                                pending_notes.append(f"npm package '{npm_pkg}' pending {lat_npm_v} ({age_days} days old)")
                            else:
                                if not check_exception('N1', npm_pkg, curr_npm_v):
                                    failures.append(f"N1: npm package '{npm_pkg}' current {curr_npm_v} is behind latest {lat_npm_v} (first newer release {first_newer_ver} published {first_newer_date}, {age_days} days old)")
        except Exception as e:
            failures.append(f"N1: Failed to read or parse npm outdated JSON in '{args.npm_outdated}': {e}")

        try:
            with open(args.npm_audit, 'r', encoding='utf-8') as f:
                npm_audit_content = f.read().strip()
            if npm_audit_content:
                npm_audit_data = json.loads(npm_audit_content)
                if not isinstance(npm_audit_data, dict):
                    failures.append(f"N2: npm audit JSON in '{args.npm_audit}' must be an object")
                elif 'error' in npm_audit_data:
                    failures.append(f"N2: npm audit reported error: {npm_audit_data['error']}")
                else:
                    vulns = npm_audit_data.get('vulnerabilities', {})
                    if not isinstance(vulns, dict):
                        failures.append(f"N2: npm audit JSON in '{args.npm_audit}' missing vulnerabilities object")
                    elif vulns:
                        for pkg_name, info in sorted(vulns.items()):
                            if not isinstance(info, dict):
                                continue
                            sev = info.get('severity', 'unknown')
                            if sev in ('info', 'low'):
                                continue

                            ghsas = get_ghsa_ids(pkg_name, vulns)
                            ghsa_str = ', '.join(sorted(ghsas)) if ghsas else 'no advisory ID'

                            installed_version = info.get('version')
                            if not installed_version and args.npm_dir:
                                lock_path = os.path.join(args.npm_dir, 'package-lock.json')
                                if os.path.exists(lock_path):
                                    try:
                                        with open(lock_path, 'r', encoding='utf-8') as lf:
                                            lock_data = json.load(lf)
                                        packages = lock_data.get('packages', {})
                                        for node in info.get('nodes', []):
                                            if node in packages and 'version' in packages[node]:
                                                installed_version = packages[node]['version']
                                                break
                                        if not installed_version:
                                            k = f"node_modules/{pkg_name}"
                                            if k in packages and 'version' in packages[k]:
                                                installed_version = packages[k]['version']
                                    except Exception:
                                        pass

                            exc_matched = False
                            for idx, exc in enumerate(exceptions):
                                if exc['rule'] == 'N2' and exc['name'] == pkg_name:
                                    if installed_version and exc['held_at'] != '*' and exc['held_at'] != installed_version:
                                        continue
                                    missing_ghsa = [g for g in ghsas if g.lower() not in exc['reason'].lower()]
                                    if not missing_ghsa:
                                        exc['used'] = True
                                        matched_exceptions.add(idx)
                                        exc_matched = True
                                        break
                            if not exc_matched:
                                failures.append(f"N2: npm package '{pkg_name}' has {sev} vulnerability: {ghsa_str}")
                    else:
                        metadata = npm_audit_data.get('metadata', {})
                        if not isinstance(metadata, dict):
                            failures.append(f"N2: npm audit JSON in '{args.npm_audit}' missing metadata object")
                        else:
                            meta_vulns = metadata.get('vulnerabilities', {})
                            if not isinstance(meta_vulns, dict):
                                failures.append(f"N2: npm audit metadata missing vulnerabilities object")
                            else:
                                mod_count = meta_vulns.get('moderate', 0)
                                high_count = meta_vulns.get('high', 0)
                                crit_count = meta_vulns.get('critical', 0)
                                if mod_count > 0 or high_count > 0 or crit_count > 0:
                                    failures.append(f"N2: npm audit reports {mod_count} moderate, {high_count} high, {crit_count} critical vulnerabilities")
        except Exception as e:
            failures.append(f"N2: Failed to read or parse npm audit JSON in '{args.npm_audit}': {e}")

        # N4: npm overrides declared
        pkg_json_path = os.path.join(args.npm_dir, 'package.json')
        if os.path.exists(pkg_json_path):
            try:
                with open(pkg_json_path, 'r', encoding='utf-8') as f:
                    pkg_json_data = json.load(f)
                if not isinstance(pkg_json_data, dict):
                    failures.append(f"N4: {pkg_json_path} must be a JSON object")
                elif 'overrides' in pkg_json_data:
                    overrides = pkg_json_data['overrides']
                    if not isinstance(overrides, dict):
                        failures.append(f"N4: 'overrides' in {pkg_json_path} must be an object")
                    else:
                        for override_pkg, override_val in sorted(overrides.items()):
                            if not isinstance(override_val, str) or not re.match(r'^\d+\.\d+\.\d+$', override_val):
                                failures.append(f"N4: npm override '{override_pkg}' value must be a plain exact version string, got '{override_val}'")
                                continue

                            # Freshness check within its major
                            major = override_val.split('.')[0]
                            npm_pkg_url = f"{args.npm_registry.rstrip('/')}/{override_pkg}"
                            npm_pkg_data = fetch_json(npm_pkg_url)
                            time_dict = npm_pkg_data.get('time', {}) if isinstance(npm_pkg_data, dict) else {}
                            same_major_newer = []
                            for v, ptime in time_dict.items():
                                if '-' in v or v in ('modified', 'created'):
                                    continue
                                if v.split('.')[0] == major and semver_cmp(v, override_val) > 0:
                                    same_major_newer.append((v, parse_date(ptime)))

                            if same_major_newer:
                                same_major_newer.sort(key=lambda x: [int(p) if p.isdigit() else 0 for p in x[0].split('.')])
                                first_newer_ver, first_newer_date = same_major_newer[0]
                                newest_in_major = same_major_newer[-1][0]
                                age_days = (today - first_newer_date).days if first_newer_date else 999
                                if age_days < 14:
                                    pending_notes.append(f"npm override '{override_pkg}' pending {newest_in_major} ({age_days} days old)")
                                else:
                                    failures.append(f"N4: npm override '{override_pkg}' version '{override_val}' is behind newest in major {major} '{newest_in_major}' (first newer release {first_newer_ver} published {first_newer_date}, {age_days} days old)")

                            # Check exception row
                            exc_found = False
                            for idx, exc in enumerate(exceptions):
                                if exc['rule'] == 'N4' and exc['name'] == override_pkg and exc['held_at'] == override_val:
                                    exc['used'] = True
                                    matched_exceptions.add(idx)
                                    exc_found = True
                                    break
                            if not exc_found:
                                failures.append(f"N4: npm override '{override_pkg}' version '{override_val}' is undeclared in exceptions")
            except Exception as e:
                failures.append(f"N4: Failed to read or parse '{pkg_json_path}': {e}")

    # E1: Check for stale exceptions
    for idx, exc in enumerate(exceptions):
        if idx not in matched_exceptions:
            failures.append(f"E1: {args.exceptions}:{exc['line_no']}: stale exception: rule {exc['rule']} for '{exc['name']}' at version '{exc['held_at']}' matched no failure")

    # Output results
    if held_notes:
        for note in held_notes:
            print(f"  [HELD] {note}")
    if pending_notes:
        for note in pending_notes:
            print(f"  [PENDING] {note}")

    if failures:
        print("\nDependency Check FAILURES found:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(f"\nSummary: {len(failures)} problem(s) found.", file=sys.stderr)
        sys.exit(1)

    print("\nSummary: All dependencies up to date!")
    sys.exit(0)

if __name__ == '__main__':
    main()
