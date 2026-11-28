#!/usr/bin/env python3
import os
import sys
import json
import re
import argparse
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime, timezone, timedelta

# Guard record mode
_GUARD_RECORD_MODE = False
_GUARD_RECORD_ACCESSES = []
_GUARD_RECORD_VIOLATIONS = []

class _GuardedContainer:
    def __init__(self, raw, input_name):
        self._raw = raw
        self._input_name = input_name

    def _unwrap(self, caller_fn=None):
        frame = sys._getframe(1)
        caller = caller_fn or frame.f_code.co_name
        if _GUARD_RECORD_MODE:
            _GUARD_RECORD_ACCESSES.append((frame.f_code.co_filename, frame.f_lineno, caller, self._input_name))
            if caller not in ('need', 'opt', 'need_items', 'need_keys', 'need_child', 'opt_child', 'need_via_entry', 'guarded_to_text', 'wrap_guarded', '_unwrap'):
                _GUARD_RECORD_VIOLATIONS.append((frame.f_code.co_filename, frame.f_lineno, caller, self._input_name, 'unauthorized_unwrap'))
        return self._raw

    def _forbidden(self, op):
        frame = sys._getframe(2)
        filename = frame.f_code.co_filename
        lineno = frame.f_lineno
        caller = frame.f_code.co_name
        msg = f"Error: Direct access '{op}' forbidden on guarded container for '{self._input_name}' at {filename}:{lineno}. Use accessor instead."
        if _GUARD_RECORD_MODE:
            _GUARD_RECORD_VIOLATIONS.append((filename, lineno, caller, self._input_name, op))
        print(msg, file=sys.stderr)
        sys.exit(1)

    def __getitem__(self, key):
        self._forbidden(f"[{key!r}]")

    def __setitem__(self, key, value):
        self._forbidden(f"[{key!r}]=")

    def __delitem__(self, key):
        self._forbidden(f"del [{key!r}]")

    def __contains__(self, key):
        self._forbidden("in")

    def __len__(self):
        self._forbidden("len()")

    def __iter__(self):
        self._forbidden("iter()")

    def __bool__(self):
        self._forbidden("bool()")

    def __eq__(self, other):
        self._forbidden("==")

    def __ne__(self, other):
        self._forbidden("!=")

    def get(self, *args, **kwargs):
        self._forbidden(".get()")

    def keys(self, *args, **kwargs):
        self._forbidden(".keys()")

    def items(self, *args, **kwargs):
        self._forbidden(".items()")

    def values(self, *args, **kwargs):
        self._forbidden(".values()")

class _GuardedDict(_GuardedContainer):
    pass

class _GuardedList(_GuardedContainer):
    pass

def wrap_guarded(data, input_name):
    if isinstance(data, _GuardedContainer):
        return data
    if isinstance(data, dict):
        wrapped = {}
        for k, v in data.items():
            wrapped[k] = wrap_guarded(v, input_name)
        return _GuardedDict(wrapped, input_name)
    elif isinstance(data, list):
        wrapped = [wrap_guarded(item, input_name) for item in data]
        return _GuardedList(wrapped, input_name)
    return data

def fetch_json(url, headers=None, retries=3):
    req_headers = {
        'User-Agent': 'check_dependencies/1.0',
        'Accept': 'application/json'
    }
    if headers:
        req_headers.update(headers)

    for attempt in range(retries):
        req = urllib.request.Request(url, headers=req_headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                body = resp.read().decode('utf-8')
                if not body.strip():
                    raise ValueError(f"Empty response body received from '{url}'")
                data = json.loads(body)
                if data is None:
                    raise ValueError(f"Top-level JSON in '{url}' must not be null")
                return wrap_guarded(data, url)
        except urllib.error.HTTPError as e:
            if attempt == retries - 1:
                print(f"Error: Network failure fetching URL '{url}': HTTP Error {e.code}: {e.reason}", file=sys.stderr)
                sys.exit(1)
        except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as e:
            if attempt == retries - 1:
                print(f"Error: Network failure fetching URL '{url}': {e}", file=sys.stderr)
                sys.exit(1)
    print(f"Error: Failed to fetch '{url}' after {retries} retries.", file=sys.stderr)
    sys.exit(1)

SCHEMA = {
    # 1. Flutter releases
    'flutter_releases.releases': {'type': list, 'non_empty': True},
    'flutter_releases.releases[].channel': {'type': str, 'non_empty': True},
    'flutter_releases.releases[].version': {'type': str, 'non_empty': True},
    'flutter_releases.releases[].release_date': {'type': str, 'non_empty': True},
    'flutter_releases.releases[].dart_sdk_version': {'type': str, 'non_empty': True, 'optional': True, 'default': None, 'reason': "Flutter releases API: dart_sdk_version is omitted on legacy Flutter 1.x releases"},

    # 2. GitHub latest release
    'github_release.tag_name': {'type': str, 'non_empty': True},
    'github_release.published_at': {'type': str, 'non_empty': True},

    # 3. GitHub tag ref
    'github_tag_ref.object': {'type': dict, 'non_empty': True},
    'github_tag_ref.object.sha': {'type': str, 'non_empty': True},
    'github_tag_ref.object.type': {'type': str, 'non_empty': True},

    # 4. GitHub tag object
    'github_tag_object.object': {'type': dict, 'non_empty': True},
    'github_tag_object.object.sha': {'type': str, 'non_empty': True},

    # 5. GitHub releases list
    'github_releases_list.[]': {'type': list, 'non_empty': False},
    'github_releases_list.[].tag_name': {'type': str, 'non_empty': True},
    'github_releases_list.[].published_at': {'type': str, 'non_empty': True},
    'github_releases_list.[].draft': {'type': bool, 'non_empty': False, 'optional': True, 'default': False, 'reason': "GitHub releases API: 'draft' is omitted on non-draft releases"},
    'github_releases_list.[].prerelease': {'type': bool, 'non_empty': False, 'optional': True, 'default': False, 'reason': "GitHub releases API: 'prerelease' is omitted on non-prerelease releases"},

    # 6. Node dist
    'node_dist.[]': {'type': list, 'non_empty': True},
    'node_dist.[].version': {'type': str, 'non_empty': True},
    'node_dist.[].date': {'type': str, 'non_empty': True},
    'node_dist.[].lts': {'type': (str, bool), 'non_empty': False, 'optional': True, 'default': False, 'reason': "Node dist index: 'lts' is False or codename string for LTS releases"},

    # 7. npm package.json
    'npm_package.{}': {'type': dict, 'non_empty': False},
    'npm_package.overrides': {'type': dict, 'non_empty': False, 'optional': True, 'default': None, 'reason': "npm package.json: 'overrides' is omitted when no overrides are declared"},
    'npm_package.overrides.*': {'type': str, 'non_empty': True},

    # 8. npm package-lock.json
    'npm_package_lock.packages': {'type': dict, 'non_empty': False},
    'npm_package_lock.packages.*': {'type': dict, 'non_empty': False},
    'npm_package_lock.packages.*.version': {'type': str, 'non_empty': True},

    # 9. npm outdated
    'npm_outdated.{}': {'type': dict, 'non_empty': False},
    'npm_outdated.*': {'type': dict, 'non_empty': False},
    'npm_outdated.*.current': {'type': str, 'non_empty': True},
    'npm_outdated.*.latest': {'type': str, 'non_empty': True},

    # 10. npm registry
    'npm_registry.time': {'type': dict, 'non_empty': True},
    'npm_registry.time.*': {'type': str, 'non_empty': True},

    # 11. npm audit
    'npm_audit.{}': {'type': dict, 'non_empty': False},
    'npm_audit.metadata': {'type': dict, 'non_empty': False, 'optional': True, 'default': None, 'reason': "npm audit: 'metadata' is omitted in detail-only audit output"},
    'npm_audit.metadata.vulnerabilities': {'type': dict, 'non_empty': True},
    'npm_audit.metadata.vulnerabilities.moderate': {'type': int, 'non_empty': False},
    'npm_audit.metadata.vulnerabilities.high': {'type': int, 'non_empty': False},
    'npm_audit.metadata.vulnerabilities.critical': {'type': int, 'non_empty': False},
    'npm_audit.vulnerabilities': {'type': dict, 'non_empty': False, 'optional': True, 'default': None, 'reason': "npm audit: 'vulnerabilities' is omitted in summary-only audit output"},
    'npm_audit.vulnerabilities.*': {'type': dict, 'non_empty': False, 'optional': True, 'default': None, 'reason': "npm audit: a package name referenced in 'via' may not have an entry in 'vulnerabilities'"},
    'npm_audit.vulnerabilities.*.severity': {'type': str, 'non_empty': True},
    'npm_audit.vulnerabilities.*.version': {'type': str, 'non_empty': True, 'optional': True, 'default': None, 'reason': "npm audit: 'version' is omitted for top-level or unmet dependencies"},
    'npm_audit.vulnerabilities.*.nodes': {'type': list, 'non_empty': False, 'optional': True, 'default': [], 'reason': "npm audit: 'nodes' is omitted when package is not installed directly in node_modules"},
    'npm_audit.vulnerabilities.*.via': {'type': list, 'non_empty': False, 'optional': True, 'default': [], 'reason': "npm audit: 'via' is omitted or empty when no chained advisory"},
    'npm_audit.vulnerabilities.*.via[].url': {'type': str, 'non_empty': False, 'optional': True, 'default': '', 'reason': "npm audit: 'via' advisory object may omit 'url'"},
    'npm_audit.vulnerabilities.*.via[].title': {'type': str, 'non_empty': False, 'optional': True, 'default': '', 'reason': "npm audit: 'via' advisory object may omit 'title'"},

    # 12. pub outdated
    'pub_outdated.{}': {'type': dict, 'non_empty': False},
    'pub_outdated.packages': {'type': list, 'non_empty': False},
    'pub_outdated.packages[].package': {'type': str, 'non_empty': True},
    'pub_outdated.packages[].kind': {'type': str, 'non_empty': True, 'optional': True, 'default': 'transitive', 'reason': "dart pub outdated: 'kind' is omitted for transitive dependencies"},
    'pub_outdated.packages[].isDiscontinued': {'type': bool, 'non_empty': False, 'optional': True, 'default': False, 'reason': "dart pub outdated / pub.dev API: 'isDiscontinued' is omitted when false"},
    'pub_outdated.packages[].isCurrentRetracted': {'type': bool, 'non_empty': False, 'optional': True, 'default': False, 'reason': "dart pub outdated: 'isCurrentRetracted' is omitted when false"},
    'pub_outdated.packages[].isCurrentAffectedByAdvisory': {'type': bool, 'non_empty': False, 'optional': True, 'default': False, 'reason': "dart pub outdated: 'isCurrentAffectedByAdvisory' is omitted when false"},
    'pub_outdated.packages[].current.version': {'type': str, 'non_empty': True},
    'pub_outdated.packages[].resolvable.version': {'type': str, 'non_empty': True},
    'pub_outdated.packages[].latest.version': {'type': str, 'non_empty': True},

    # 13. pub.dev package
    'pub_package.name': {'type': str, 'non_empty': True},
    'pub_package.latest.version': {'type': str, 'non_empty': True},
    'pub_package.latest.published': {'type': str, 'non_empty': True},
    'pub_package.versions': {'type': list, 'non_empty': True},
    'pub_package.versions[].version': {'type': str, 'non_empty': True},
    'pub_package.versions[].published': {'type': str, 'non_empty': True},

    # 14. pub.dev advisories
    'pub_advisories.advisories': {'type': list, 'non_empty': False},
    'pub_advisories.advisories[].id': {'type': str, 'non_empty': True},
    'pub_advisories.advisories[].affected': {'type': list, 'non_empty': True},
    'pub_advisories.advisories[].affected[].versions': {'type': list, 'non_empty': False, 'optional': True, 'default': [], 'reason': "OSV/pub.dev advisory schema: 'versions' is omitted when advisory specifies range-only constraints"},
    'pub_advisories.advisories[].affected[].ranges': {'type': list, 'non_empty': False, 'optional': True, 'default': [], 'reason': "OSV/pub.dev advisory schema: 'ranges' is omitted when advisory specifies explicit version lists"},
    'pub_advisories.advisories[].affected[].ranges[].events': {'type': list, 'non_empty': True},
    # OSV Schema (https://ossf.github.io/osv-schema/#affectedranges-field):
    # "The events array contains objects, each of which MUST contain a single field, one of: introduced, fixed, last_affected, or limit."
    # Note: pub.dev's OSV JSON serializer (e.g. shared_preferences_android/advisories) emits all four keys
    # with the three inactive fields set to null and exactly one field set to a non-empty string.
    'pub_advisories.advisories[].affected[].ranges[].events[].introduced': {'type': str, 'non_empty': True, 'optional': True, 'nullable': True, 'default': None, 'reason': "OSV range event: each event holds exactly one non-null field of introduced, fixed, last_affected, or limit"},
    'pub_advisories.advisories[].affected[].ranges[].events[].fixed': {'type': str, 'non_empty': True, 'optional': True, 'nullable': True, 'default': None, 'reason': "OSV range event: each event holds exactly one non-null field of introduced, fixed, last_affected, or limit"},
    'pub_advisories.advisories[].affected[].ranges[].events[].last_affected': {'type': str, 'non_empty': True, 'optional': True, 'nullable': True, 'default': None, 'reason': "OSV range event: each event holds exactly one non-null field of introduced, fixed, last_affected, or limit"},
    'pub_advisories.advisories[].affected[].ranges[].events[].limit': {'type': str, 'non_empty': True, 'optional': True, 'nullable': True, 'default': None, 'reason': "OSV range event: each event holds exactly one non-null field of introduced, fixed, last_affected, or limit"},

    # 15. pubspec.yaml
    'pubspec.name': {'type': str, 'non_empty': True},
    'pubspec.environment.sdk': {'type': str, 'non_empty': True},

    # 16. pubspec.lock
    'pubspec_lock.packages': {'type': dict, 'non_empty': True},
    'pubspec_lock.packages.*': {'type': dict, 'non_empty': True},
    'pubspec_lock.packages.*.source': {'type': str, 'non_empty': True},
}

ACCESSED_PATHS = set()

def _check_type(val, expected_type):
    if isinstance(expected_type, tuple):
        for t in expected_type:
            if _check_type(val, t):
                return True
        return False
    if expected_type is list:
        return isinstance(val, (_GuardedList, list))
    if expected_type is dict:
        return isinstance(val, (_GuardedDict, dict))
    if expected_type is int:
        return isinstance(val, int) and not isinstance(val, bool)
    return isinstance(val, expected_type)

def _get_type_name(expected_type):
    if isinstance(expected_type, tuple):
        return '/'.join(t.__name__ for t in expected_type)
    return expected_type.__name__

def _access_path(obj, path, input_name, is_opt=False):
    ACCESSED_PATHS.add(path)
    if path not in SCHEMA:
        print(f"Error: Schema failure in '{input_name}': unknown schema path '{path}'.", file=sys.stderr)
        sys.exit(1)

    spec = SCHEMA[path]
    expected_type = spec['type']
    non_empty = spec.get('non_empty', False)
    default = spec.get('default', None)

    prefix_code = "T1: " if path.startswith('flutter_releases') else ""

    if obj is None:
        if is_opt:
            return default
        print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': target object is null.", file=sys.stderr)
        sys.exit(1)

    _, rest = path.split('.', 1)

    val = None
    key_found = False

    if rest in ('[]', '{}'):
        val = obj
        key_found = True
    elif '[].' in rest:
        tokens = []
        curr_rest = rest
        while '[].' in curr_rest:
            prefix, curr_rest = curr_rest.split('[].', 1)
            if prefix:
                tokens.append(('prefix', prefix))
            tokens.append(('index', 0))
        if curr_rest:
            tokens.append(('suffix', curr_rest))

        curr = obj
        key_found = True
        for kind, val_token in tokens:
            if kind == 'prefix':
                raw = curr._unwrap('opt' if is_opt else 'need') if isinstance(curr, _GuardedContainer) else curr
                if isinstance(raw, dict) and val_token in raw:
                    curr = raw[val_token]
            elif kind == 'index':
                raw = curr._unwrap('opt' if is_opt else 'need') if isinstance(curr, _GuardedContainer) else curr
                if isinstance(raw, list):
                    if len(raw) == 0:
                        key_found = False
                        break
                    curr = raw[0]
            elif kind == 'suffix':
                for seg in val_token.split('.'):
                    raw = curr._unwrap('opt' if is_opt else 'need') if isinstance(curr, _GuardedContainer) else curr
                    if not isinstance(raw, dict) or seg not in raw:
                        if is_opt:
                            return default
                        print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': missing '{seg}'.", file=sys.stderr)
                        sys.exit(1)
                    curr = raw[seg]
        val = curr
    elif rest.startswith('*.'):
        suffix = rest[2:]
        curr = obj
        for seg in suffix.split('.'):
            raw = curr._unwrap('opt' if is_opt else 'need') if isinstance(curr, _GuardedContainer) else curr
            if not isinstance(raw, dict) or seg not in raw:
                if is_opt:
                    return default
                print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': missing '{seg}'.", file=sys.stderr)
                sys.exit(1)
            curr = raw[seg]
        val = curr
        key_found = True
    else:
        segs = rest.split('.')
        curr = obj
        raw = curr._unwrap('opt' if is_opt else 'need') if isinstance(curr, _GuardedContainer) else curr
        start_idx = 0
        if isinstance(raw, dict):
            for i in range(len(segs)):
                if segs[i] in raw:
                    start_idx = i
                    break
        for seg in segs[start_idx:]:
            raw = curr._unwrap('opt' if is_opt else 'need') if isinstance(curr, _GuardedContainer) else curr
            if not isinstance(raw, dict) or seg not in raw:
                if is_opt:
                    return default
                print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': missing '{seg}'.", file=sys.stderr)
                sys.exit(1)
            curr = raw[seg]
        val = curr
        key_found = True

    if val is None:
        if is_opt and not key_found:
            return default
        print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': value is null.", file=sys.stderr)
        sys.exit(1)

    if not _check_type(val, expected_type):
        got_name = type(val._unwrap('need') if isinstance(val, _GuardedContainer) else val).__name__
        print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': expected {_get_type_name(expected_type)}, got {got_name}.", file=sys.stderr)
        sys.exit(1)

    if non_empty:
        raw_val = val._unwrap('need') if isinstance(val, _GuardedContainer) else val
        if isinstance(raw_val, (str, list, dict)) and len(raw_val) == 0:
            print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': empty value where non-empty required.", file=sys.stderr)
            sys.exit(1)

    return val

def need(obj, path, input_name):
    return _access_path(obj, path, input_name, is_opt=False)

def opt(obj, path, input_name):
    if path not in SCHEMA or not SCHEMA[path].get('optional', False):
        print(f"Error: Schema failure in '{input_name}': path '{path}' is not marked optional.", file=sys.stderr)
        sys.exit(1)
    return _access_path(obj, path, input_name, is_opt=True)

def need_items(obj, path, input_name):
    ACCESSED_PATHS.add(path)
    if path not in SCHEMA:
        print(f"Error: Schema failure in '{input_name}': unknown schema path '{path}'.", file=sys.stderr)
        sys.exit(1)
    if obj is None:
        print(f"Error: Schema failure in '{input_name}' at path '{path}': target object is null.", file=sys.stderr)
        sys.exit(1)
    if isinstance(obj, _GuardedList):
        raw_list = obj._unwrap('need_items')
    elif isinstance(obj, list):
        raw_list = obj
    else:
        print(f"Error: Schema failure in '{input_name}' at path '{path}': expected list, got {type(obj).__name__}.", file=sys.stderr)
        sys.exit(1)

    is_list_of_objects = (
        path != 'npm_audit.vulnerabilities.*.via'
        and any(k.startswith(f"{path}[].") or k.startswith(f"{path}.[].") for k in SCHEMA)
    )
    if is_list_of_objects:
        for item in raw_list:
            if item is None:
                print(f"Error: Schema failure in '{input_name}' at path '{path}[]': element is null.", file=sys.stderr)
                sys.exit(1)
            if isinstance(item, _GuardedDict):
                item_raw = item._unwrap('need_items')
            elif isinstance(item, dict):
                item_raw = item
            else:
                got_t = type(item._unwrap('need_items') if isinstance(item, _GuardedContainer) else item).__name__
                print(f"Error: Schema failure in '{input_name}' at path '{path}[]': expected dict, got {got_t}.", file=sys.stderr)
                sys.exit(1)
            if len(item_raw) == 0:
                if path == 'pub_advisories.advisories[].affected':
                    print(f"Error: Schema failure in '{input_name}' at path '{path}[]': entry must contain at least 'versions' or 'ranges'.", file=sys.stderr)
                    sys.exit(1)
                elif path == 'pub_advisories.advisories[].affected[].ranges[].events':
                    print(f"Error: Schema failure in '{input_name}' at path '{path}[]': OSV event must contain exactly one of introduced, fixed, last_affected, or limit.", file=sys.stderr)
                    sys.exit(1)
                else:
                    req_children = [k for k in SCHEMA if (k.startswith(f"{path}[].") or k.startswith(f"{path}.[].")) and not SCHEMA[k].get('optional', False)]
                    if req_children:
                        child = req_children[0]
                        seg = child.split('[].')[-1].split('.')[0] if '[].' in child else child.split('.[].')[-1].split('.')[0]
                        print(f"Error: Schema failure in '{input_name}' at path '{child}': missing '{seg}'.", file=sys.stderr)
                        sys.exit(1)

    return raw_list

def need_keys(obj, path, input_name):
    ACCESSED_PATHS.add(path)
    if path not in SCHEMA:
        print(f"Error: Schema failure in '{input_name}': unknown schema path '{path}'.", file=sys.stderr)
        sys.exit(1)
    if obj is None:
        print(f"Error: Schema failure in '{input_name}' at path '{path}': target object is null.", file=sys.stderr)
        sys.exit(1)
    if isinstance(obj, _GuardedDict):
        raw_dict = obj._unwrap('need_keys')
    elif isinstance(obj, dict):
        raw_dict = obj
    else:
        print(f"Error: Schema failure in '{input_name}' at path '{path}': expected dict, got {type(obj).__name__}.", file=sys.stderr)
        sys.exit(1)
    return list(raw_dict.keys())

def _validate_child_value(val, path, input_name, spec):
    prefix_code = "N4: " if path.startswith('npm_package.overrides') else ""
    if val is None:
        print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': value is null.", file=sys.stderr)
        sys.exit(1)
    expected_type = spec['type']
    if not _check_type(val, expected_type):
        got_name = type(val._unwrap('need_child') if isinstance(val, _GuardedContainer) else val).__name__
        print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': expected {_get_type_name(expected_type)}, got {got_name}.", file=sys.stderr)
        sys.exit(1)
    if spec.get('non_empty', False):
        raw_val = val._unwrap('need_child') if isinstance(val, _GuardedContainer) else val
        if isinstance(raw_val, (str, list, dict)) and len(raw_val) == 0:
            print(f"Error: {prefix_code}Schema failure in '{input_name}' at path '{path}': empty value where non-empty required.", file=sys.stderr)
            sys.exit(1)
    return val

def need_child(obj, path, key, input_name):
    ACCESSED_PATHS.add(path)
    if path not in SCHEMA:
        print(f"Error: Schema failure in '{input_name}': unknown schema path '{path}'.", file=sys.stderr)
        sys.exit(1)
    if isinstance(obj, _GuardedDict):
        raw_dict = obj._unwrap('need_child')
    elif isinstance(obj, dict):
        raw_dict = obj
    else:
        got_name = type(obj._unwrap('need_child') if isinstance(obj, _GuardedContainer) else obj).__name__
        print(f"Error: Schema failure in '{input_name}' at path '{path}': expected dict, got {got_name}.", file=sys.stderr)
        sys.exit(1)
    if key not in raw_dict:
        print(f"Error: Schema failure in '{input_name}' at path '{path}': missing '{key}'.", file=sys.stderr)
        sys.exit(1)
    return _validate_child_value(raw_dict[key], path, input_name, SCHEMA[path])

def opt_child(obj, path, key, input_name):
    ACCESSED_PATHS.add(path)
    if path not in SCHEMA:
        print(f"Error: Schema failure in '{input_name}': unknown schema path '{path}'.", file=sys.stderr)
        sys.exit(1)
    spec = SCHEMA[path]
    if not spec.get('optional', False):
        print(f"Error: Schema failure in '{input_name}': path '{path}' is not marked optional.", file=sys.stderr)
        sys.exit(1)
    if isinstance(obj, _GuardedDict):
        raw_dict = obj._unwrap('opt_child')
    elif isinstance(obj, dict):
        raw_dict = obj
    else:
        got_name = type(obj._unwrap('opt_child') if isinstance(obj, _GuardedContainer) else obj).__name__
        print(f"Error: Schema failure in '{input_name}' at path '{path}': expected dict, got {got_name}.", file=sys.stderr)
        sys.exit(1)
    if key not in raw_dict:
        return spec.get('default', None)
    val = raw_dict[key]
    if val is None and spec.get('nullable', False):
        return spec.get('default', None)
    return _validate_child_value(val, path, input_name, spec)

def need_via_entry(item, path, input_name):
    """Classify an npm audit 'via' element as ('dict', obj) or ('str', pkg_name), failing closed otherwise."""
    if isinstance(item, (_GuardedDict, dict)):
        return ('dict', item)
    if isinstance(item, str) and len(item) > 0:
        return ('str', item)
    got_t = type(item._unwrap('need_via_entry') if isinstance(item, _GuardedContainer) else item).__name__
    print(f"Error: Schema failure in '{input_name}' at path '{path}[]': expected dict or non-empty str, got {got_t}.", file=sys.stderr)
    sys.exit(1)

def guarded_to_text(obj):
    """Return string representation of a guarded container for advisory ID regex scanning."""
    if isinstance(obj, _GuardedContainer):
        return str(obj._unwrap('guarded_to_text'))
    return str(obj)

def parse_semver(
    v_str,
    *,
    source=None,
    field=None,
    allow_short=False,
    allow_zero_sentinel=False,
):
    """Parse a semantic version string into ((major, minor, patch), prerelease).

    Fails closed (exits 1 naming input, field, and value) when any core part is
    not a non-negative ASCII integer or when the core does not have 3 parts
    (unless `allow_short=True` for GitHub Action major/minor tags like `v4` or
    `v4.2`, or `allow_zero_sentinel=True` for OSV `introduced: "0"`).
    """
    def _fail():
        loc = f" in '{source}'" if source else ""
        where = f" at '{field}'" if field else ""
        print(
            f"Error: Malformed version {v_str!r}{loc}{where}: "
            "expected non-negative integer semver parts.",
            file=sys.stderr,
        )
        sys.exit(1)

    if v_str is None:
        _fail()
    raw = str(v_str).strip()
    if not raw:
        _fail()
    cleaned = re.sub(r'^(?:>=|<=|[v^~><])+', '', raw).strip()
    if not cleaned:
        _fail()
    without_build = cleaned.split('+', 1)[0]
    parts = without_build.split('-', 1)
    core = parts[0]
    prerelease = parts[1] if len(parts) > 1 else None

    if allow_zero_sentinel and core == '0' and prerelease is None:
        return (0, 0, 0), None

    raw_parts = core.split('.')
    if allow_short:
        if not (1 <= len(raw_parts) <= 3):
            _fail()
    else:
        if len(raw_parts) != 3:
            _fail()

    core_parts = []
    for p in raw_parts:
        if not re.fullmatch(r'[0-9]+', p):
            _fail()
        core_parts.append(int(p))
    while len(core_parts) < 3:
        core_parts.append(0)
    return tuple(core_parts), prerelease

def semver_tuple(v_str, *, source=None, field=None, allow_short=False):
    c, _ = parse_semver(v_str, source=source, field=field, allow_short=allow_short)
    return c

def semver_cmp(
    v1_str,
    v2_str,
    *,
    source=None,
    field1=None,
    field2=None,
    allow_short=False,
    allow_zero_sentinel_2=False,
):
    c1, pre1 = parse_semver(
        v1_str, source=source, field=field1, allow_short=allow_short
    )
    c2, pre2 = parse_semver(
        v2_str,
        source=source,
        field=field2,
        allow_short=allow_short,
        allow_zero_sentinel=allow_zero_sentinel_2,
    )
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

def is_version_in_ranges(v_str, ranges, input_name):
    # OSV Schema (https://ossf.github.io/osv-schema/#affectedranges-field):
    # "The events array contains objects, each of which MUST contain a single field,
    # one of: introduced, fixed, last_affected, or limit."
    for r in need_items(ranges, 'pub_advisories.advisories[].affected[].ranges', input_name):
        events = need(r, 'pub_advisories.advisories[].affected[].ranges[].events', input_name)
        introduced = None
        fixed = None
        last_affected = None
        for ev in need_items(events, 'pub_advisories.advisories[].affected[].ranges[].events', input_name):
            ev_keys = need_keys(ev, 'pub_advisories.advisories[].affected[].ranges[].events', input_name)
            unknown_keys = [k for k in ev_keys if k not in ('introduced', 'fixed', 'last_affected', 'limit')]
            if unknown_keys:
                print(
                    f"Error: Schema failure in '{input_name}' at path 'pub_advisories.advisories[].affected[].ranges[].events[]': "
                    f"unknown OSV event key(s) {unknown_keys}.",
                    file=sys.stderr,
                )
                sys.exit(1)
            intro = opt_child(ev, 'pub_advisories.advisories[].affected[].ranges[].events[].introduced', 'introduced', input_name)
            fix = opt_child(ev, 'pub_advisories.advisories[].affected[].ranges[].events[].fixed', 'fixed', input_name)
            last_aff = opt_child(ev, 'pub_advisories.advisories[].affected[].ranges[].events[].last_affected', 'last_affected', input_name)
            lim = opt_child(ev, 'pub_advisories.advisories[].affected[].ranges[].events[].limit', 'limit', input_name)
            present = [
                k for k, v in (
                    ('introduced', intro),
                    ('fixed', fix),
                    ('last_affected', last_aff),
                    ('limit', lim),
                ) if v is not None
            ]
            if len(present) != 1:
                print(
                    f"Error: Schema failure in '{input_name}' at path 'pub_advisories.advisories[].affected[].ranges[].events[]': "
                    f"OSV event must hold exactly one non-null field of introduced, fixed, last_affected, or limit, got {present}.",
                    file=sys.stderr,
                )
                sys.exit(1)
            if intro is not None:
                introduced = intro
            if fix is not None:
                fixed = fix
            if last_aff is not None:
                last_affected = last_aff
            if lim is not None:
                print(
                    f"Error: Schema failure in '{input_name}' at path 'pub_advisories.advisories[].affected[].ranges[].events[].limit': "
                    f"unsupported OSV event 'limit'.",
                    file=sys.stderr,
                )
                sys.exit(1)

        matches = True
        if introduced is not None:
            if semver_cmp(
                v_str,
                introduced,
                source=input_name,
                field1='installed_version',
                field2='pub_advisories.advisories[].affected[].ranges[].events[].introduced',
                allow_zero_sentinel_2=True,
            ) < 0:
                matches = False
        if fixed is not None:
            if semver_cmp(
                v_str,
                fixed,
                source=input_name,
                field1='installed_version',
                field2='pub_advisories.advisories[].affected[].ranges[].events[].fixed',
            ) >= 0:
                matches = False
        if last_affected is not None:
            if semver_cmp(
                v_str,
                last_affected,
                source=input_name,
                field1='installed_version',
                field2='pub_advisories.advisories[].affected[].ranges[].events[].last_affected',
            ) > 0:
                matches = False
        if matches and (introduced is not None or fixed is not None or last_affected is not None):
            return True
    return False

def get_ghsa_ids(pkg_name, all_vulns, input_name, visited=None):
    if visited is None:
        visited = set()
    if pkg_name in visited:
        return set()
    visited.add(pkg_name)
    ghsas = set()
    pkg_info = opt_child(all_vulns, 'npm_audit.vulnerabilities.*', pkg_name, input_name)
    if pkg_info is None:
        return set()
    vias = opt(pkg_info, 'npm_audit.vulnerabilities.*.via', input_name)
    for v in need_items(vias, 'npm_audit.vulnerabilities.*.via', input_name):
        entry_kind, entry_val = need_via_entry(v, 'npm_audit.vulnerabilities.*.via', input_name)
        if entry_kind == 'dict':
            url_str = opt_child(entry_val, 'npm_audit.vulnerabilities.*.via[].url', 'url', input_name)
            title_str = opt_child(entry_val, 'npm_audit.vulnerabilities.*.via[].title', 'title', input_name)
            for field in [url_str, title_str, guarded_to_text(entry_val)]:
                for m in re.findall(r'GHSA-[a-zA-Z0-9\-]+', field, re.IGNORECASE):
                    ghsas.add(m.upper())
        else:
            ghsas.update(get_ghsa_ids(entry_val, all_vulns, input_name, visited))
    return ghsas

def parse_workflow_file(wf_path, wf_file):
    with open(wf_path, 'r', encoding='utf-8') as f:
        wf_lines = f.readlines()

    if not wf_lines or not any(l.strip() and not l.strip().startswith('#') for l in wf_lines):
        print(f"Error: Workflow file '{wf_path}' is empty or whitespace.", file=sys.stderr)
        sys.exit(1)

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

        # Job-level properties (4 spaces)
        if indent == 4:
            if stripped.startswith('- ') and stripped.startswith('- uses:'):
                pass
            m_prop = re.match(r'^    ([a-zA-Z0-9_\-]+):\s*(.*)$', line)
            if m_prop:
                prop_key = m_prop.group(1)
                prop_val = m_prop.group(2).strip()
                if prop_key == 'name':
                    current_job['name'] = prop_val.strip('\'"')
            continue

        # Steps are indented 6+ spaces or start with - at indent 6
        if stripped.startswith('- '):
            current_step = {
                'job_id': current_job['id'],
                'file': wf_file,
                'name': None,
                'uses': None,
                'uses_line': None,
                'start_line': line_idx,
                'sdk': None,
                'sdk_line': None,
                'node_version': None,
                'node_version_line': None
            }
            current_job['steps'].append(current_step)

            m_inline = re.match(r'^\s*-\s+uses:\s*(.*)$', line)
            if m_inline:
                current_step['uses'] = m_inline.group(1).strip()
                current_step['uses_line'] = line_idx
            m_inline_name = re.match(r'^\s*-\s+name:\s*(.*)', line)
            if m_inline_name:
                current_step['name'] = m_inline_name.group(1).strip('\'"')
            continue

        if current_step is not None:
            m_step_prop = re.match(r'^\s*([a-zA-Z0-9_\-]+):\s*(.*)$', line)
            if m_step_prop:
                k = m_step_prop.group(1)
                v = m_step_prop.group(2).strip()
                if k == 'uses':
                    full_uses = stripped[len('uses:'):].strip()
                    current_step['uses'] = full_uses
                    current_step['uses_line'] = line_idx
                elif k == 'name':
                    current_step['name'] = v.strip('\'"')
                elif k == 'sdk':
                    current_step['sdk'] = v.strip('\'"')
                    current_step['sdk_line'] = line_idx
                elif k in ('node-version', 'node-version-file'):
                    if k == 'node-version':
                        current_step['node_version'] = v.strip('\'"')
                        current_step['node_version_line'] = line_idx

    if not jobs:
        print(f"Error: Workflow file '{wf_path}' contains no valid jobs.", file=sys.stderr)
        sys.exit(1)

    return jobs

def parse_date(date_str):
    if not date_str:
        return None
    cleaned = date_str.strip()
    if len(cleaned) == 10 and cleaned.count('-') == 2:
        try:
            return datetime.strptime(cleaned, '%Y-%m-%d').date()
        except ValueError:
            pass
    if cleaned.endswith('Z'):
        cleaned = cleaned[:-1] + '+00:00'
    try:
        dt = datetime.fromisoformat(cleaned)
        return dt.date()
    except (ValueError, TypeError):
        return None

def read_pubspec(pubspec_path):
    if not os.path.exists(pubspec_path):
        print(f"Error: Pubspec file '{pubspec_path}' not found.", file=sys.stderr)
        sys.exit(1)

    with open(pubspec_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    if not lines or not any(l.strip() and not l.strip().startswith('#') for l in lines):
        print(f"Error: Pubspec file '{pubspec_path}' is empty or whitespace.", file=sys.stderr)
        sys.exit(1)

    # Read lockfile if present
    lock_path = os.path.join(os.path.dirname(pubspec_path), 'pubspec.lock')
    lock_non_hosted = set()
    if os.path.exists(lock_path):
        lock_non_hosted = read_pubspec_lock(lock_path)

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
    pkg_name_from_pubspec = None

    for line_idx, raw_line in enumerate(lines, 1):
        line = raw_line.rstrip('\r\n')
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        indent = len(line) - len(line.lstrip(' '))

        if indent == 0:
            current_dep_name = None
            if stripped.startswith('name:'):
                raw_name = stripped.split(':', 1)[1].strip().strip('\'"')
                if raw_name.startswith('[') or raw_name.startswith('{'):
                    pkg_name_from_pubspec = ['invalid'] if raw_name.startswith('[') else {'invalid': 1}
                else:
                    pkg_name_from_pubspec = raw_name
                current_section = None
            elif stripped.startswith('environment:'):
                current_section = 'environment'
            elif stripped.startswith('dependencies:'):
                current_section = 'dependencies'
            elif stripped.startswith('dev_dependencies:'):
                current_section = 'dev_dependencies'
            else:
                current_section = None
            continue

        if current_section == 'environment':
            m = re.match(r'^\s*sdk:\s*(.*)$', stripped)
            if m:
                raw_sdk = m.group(1).split('#')[0].strip().strip('\'"')
                if raw_sdk.startswith('[') or raw_sdk.startswith('{'):
                    sdk_constraint = ['invalid'] if raw_sdk.startswith('[') else {'invalid': 1}
                else:
                    sdk_constraint = raw_sdk
            m_fl = re.match(r'^\s*flutter:\s*[\'"]?([^\'"#]+)[\'"]?', stripped)
            if m_fl:
                flutter_constraint = m_fl.group(1).strip()

        elif current_section in ('dependencies', 'dev_dependencies'):
            if indent == 2:
                m = re.match(r'^  ([a-zA-Z0-9_\-]+):\s*(.*)$', line)
                if m:
                    dep_name = m.group(1)
                    val = m.group(2).strip()
                    current_dep_name = dep_name
                    if current_section == 'dependencies':
                        direct_deps.add(dep_name)
                    else:
                        dev_deps.add(dep_name)

                    if val:
                        clean_val = val.split('#')[0].strip().strip('\'"')
                        if clean_val and re.match(r'^\d+\.\d+\.\d+(\+.*)?$', clean_val):
                            if current_section == 'dependencies':
                                direct_exact_pins.append((dep_name, clean_val))
                            else:
                                dev_exact_pins.append((dep_name, clean_val))
                        if clean_val and re.match(r'^\^[0-9]+', clean_val):
                            floor = clean_val.lstrip('^')
                            declared_floors[dep_name] = floor
                        elif clean_val and re.match(r'^>=([0-9]+\.[0-9]+\.[0-9]+)', clean_val):
                            floor = re.match(r'^>=([0-9]+\.[0-9]+\.[0-9]+)', clean_val).group(1)
                            declared_floors[dep_name] = floor
                        if 'git:' in val or 'sdk:' in val or 'path:' in val:
                            non_hosted_deps.add(dep_name)
            elif indent > 2:
                indent_line = stripped
                if current_dep_name and ('git:' in indent_line or 'sdk:' in indent_line or 'path:' in indent_line):
                    non_hosted_deps.add(current_dep_name)

    if not pkg_name_from_pubspec or not sdk_constraint:
        print(f"Error: Pubspec file '{pubspec_path}' is unparseable YAML or missing top-level keys.", file=sys.stderr)
        sys.exit(1)

    pubspec_dict = wrap_guarded({'name': pkg_name_from_pubspec, 'environment': {'sdk': sdk_constraint}}, pubspec_path)
    need(pubspec_dict, 'pubspec.name', pubspec_path)
    need(pubspec_dict, 'pubspec.environment.sdk', pubspec_path)

    non_hosted_deps.update(lock_non_hosted)
    return sdk_constraint, flutter_constraint, direct_exact_pins, dev_exact_pins, direct_deps, dev_deps, non_hosted_deps, declared_floors

def read_pubspec_lock(lock_path):
    with open(lock_path, 'r', encoding='utf-8') as f:
        lock_lines = f.readlines()
    if not lock_lines or not any(l.strip() and not l.strip().startswith('#') for l in lock_lines):
        print(f"Error: pubspec.lock '{lock_path}' is empty or whitespace.", file=sys.stderr)
        sys.exit(1)

    in_packages = False
    curr_pkg = None
    packages_dict = {}

    for line in lock_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        indent = len(line) - len(line.lstrip(' '))
        if indent == 0:
            if stripped.startswith('packages:'):
                in_packages = True
            else:
                in_packages = False
            curr_pkg = None
        elif in_packages and indent == 2:
            m = re.match(r'^  ([a-zA-Z0-9_\-]+):\s*$', line)
            if m:
                curr_pkg = m.group(1)
                packages_dict[curr_pkg] = {}
        elif in_packages and curr_pkg and indent == 4:
            m = re.match(r'^    ([a-zA-Z0-9_\-]+):\s*(.*)$', line)
            if m:
                k = m.group(1)
                raw_v = m.group(2).strip().strip('\'"')
                if raw_v.startswith('[') or raw_v.startswith('{'):
                    v = ['invalid'] if raw_v.startswith('[') else {'invalid': 1}
                else:
                    v = raw_v
                packages_dict[curr_pkg][k] = v

    packages_obj = wrap_guarded({'packages': packages_dict}, lock_path)
    packages = need(packages_obj, 'pubspec_lock.packages', lock_path)
    non_hosted = set()
    for p_name in need_keys(packages, 'pubspec_lock.packages', lock_path):
        p_info = need_child(packages, 'pubspec_lock.packages.*', p_name, lock_path)
        source = need(p_info, 'pubspec_lock.packages.*.source', lock_path)
        if source != 'hosted':
            non_hosted.add(p_name)
    return non_hosted

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
    parser.add_argument('--npm-outdated-status', default=None, help='Path to npm outdated status file')
    parser.add_argument('--npm-audit-status', default=None, help='Path to npm audit status file')
    parser.add_argument('--record-schema-access', default=None, help='Path to output accessed schema paths')
    parser.add_argument('--guard-record-mode', action='store_true', help='Enable guard record mode')
    parser.add_argument('--npm-registry', default='https://registry.npmjs.org', help='Base URL for npm registry')
    parser.add_argument('--node-dist', default='https://nodejs.org/dist/index.json', help='URL for Node.js release index')
    parser.add_argument('--today', default=None, help='Override evaluation date (YYYY-MM-DD)')

    args = parser.parse_args()

    global _GUARD_RECORD_MODE
    if args.guard_record_mode or os.environ.get('CHECK_DEPENDENCIES_GUARD_RECORD') == '1':
        _GUARD_RECORD_MODE = True

    if args.today is not None and os.environ.get('GITHUB_ACTIONS') == 'true':
        print("Error: --today flag is forbidden in GitHub Actions CI runs.", file=sys.stderr)
        sys.exit(1)

    today = parse_date(args.today) if args.today else datetime.now(timezone.utc).date()

    github_headers = {}
    github_token = os.environ.get('GITHUB_TOKEN')
    if github_token:
        github_headers['Authorization'] = f"token {github_token}"

    print(f"Checking dependencies against date: {today}")

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

    wf_files = [f for f in sorted(os.listdir(args.workflows)) if f.endswith('.yml') or f.endswith('.yaml')]
    if not wf_files:
        print(f"Error: Workflows directory '{args.workflows}' contains no .yml or .yaml files.", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(args.exceptions) or not os.path.isfile(args.exceptions):
        print(f"Error: Exceptions file '{args.exceptions}' not found or unreadable.", file=sys.stderr)
        sys.exit(1)

    if args.npm_dir:
        if not os.path.exists(args.npm_dir) or not os.path.isdir(args.npm_dir):
            print(f"Error: npm directory '{args.npm_dir}' not found or not a directory.", file=sys.stderr)
            sys.exit(1)
        if not args.npm_outdated or not os.path.exists(args.npm_outdated) or not os.path.isfile(args.npm_outdated):
            print(f"Error: npm outdated file '{args.npm_outdated}' not found or unreadable.", file=sys.stderr)
            sys.exit(1)
        if not args.npm_audit or not os.path.exists(args.npm_audit) or not os.path.isfile(args.npm_audit):
            print(f"Error: npm audit file '{args.npm_audit}' not found or unreadable.", file=sys.stderr)
            sys.exit(1)
        if not args.npm_outdated_status:
            print(f"Error: --npm-outdated-status is required when --npm-dir is specified.", file=sys.stderr)
            sys.exit(1)
        if not os.path.exists(args.npm_outdated_status) or not os.path.isfile(args.npm_outdated_status):
            print(f"Error: npm outdated status file '{args.npm_outdated_status}' not found or unreadable.", file=sys.stderr)
            sys.exit(1)
        if not args.npm_audit_status:
            print(f"Error: --npm-audit-status is required when --npm-dir is specified.", file=sys.stderr)
            sys.exit(1)
        if not os.path.exists(args.npm_audit_status) or not os.path.isfile(args.npm_audit_status):
            print(f"Error: npm audit status file '{args.npm_audit_status}' not found or unreadable.", file=sys.stderr)
            sys.exit(1)

        def parse_status_file(status_path):
            with open(status_path, 'r', encoding='utf-8') as sf:
                c = sf.read()
            s = c.strip()
            if not s:
                print(f"Error: Status file '{status_path}' is empty or whitespace.", file=sys.stderr)
                sys.exit(1)
            try:
                code = int(s)
            except ValueError:
                print(f"Error: Status file '{status_path}' contains non-integer value '{s}'.", file=sys.stderr)
                sys.exit(1)
            if code not in (0, 1):
                stderr_path = status_path.replace('_status.json', '.stderr').replace('.status', '.stderr')
                stderr_msg = ""
                if os.path.exists(stderr_path):
                    try:
                        with open(stderr_path, 'r', encoding='utf-8') as ef:
                            stderr_msg = ef.read().strip()
                    except (IOError, OSError):
                        pass
                print(f"Error: Status file '{status_path}' reported non-zero/one exit code {code}.\nStderr: {stderr_msg}", file=sys.stderr)
                sys.exit(1)
            return code

        npm_outdated_status_code = parse_status_file(args.npm_outdated_status)
        npm_audit_status_code = parse_status_file(args.npm_audit_status)

    # Read and parse exceptions TSV
    exceptions = []
    exception_failures = []

    try:
        with open(args.exceptions, 'r', encoding='utf-8') as f:
            for line_idx, line in enumerate(f, 1):
                clean_line = line.strip()
                if not clean_line or clean_line.startswith('#'):
                    continue
                parts = line.rstrip('\r\n').split('\t')
                if len(parts) != 5:
                    exception_failures.append(f"E1: {args.exceptions}:{line_idx}: Malformed exception row: expected 5 tab-separated fields, got {len(parts)}")
                    continue

                rule_id, name, held_at, review_by_str, reason = parts
                rule_id = rule_id.strip()
                name = name.strip()
                held_at = held_at.strip()
                review_by_str = review_by_str.strip()
                reason = reason.strip()

                review_by = parse_date(review_by_str)
                if not review_by:
                    exception_failures.append(f"E1: {args.exceptions}:{line_idx}: Invalid date format in review_by: '{review_by_str}'")
                    continue

                if len(reason) < 20:
                    exception_failures.append(f"E1: {args.exceptions}:{line_idx}: Exception reason too short (under 20 characters): '{reason}'")
                if review_by < today:
                    exception_failures.append(f"E1: {args.exceptions}:{line_idx}: Exception review_by date {review_by} is in the past (today is {today})")
                max_days = 30 if rule_id in ('D2', 'N2', 'N4') else 90
                if review_by > today + timedelta(days=max_days):
                    exception_failures.append(f"E1: {args.exceptions}:{line_idx}: Exception review_by date {review_by} is more than {max_days} days in future")
                if rule_id in ('D2', 'N2', 'N4'):
                    if not re.search(r'GHSA-[a-zA-Z0-9\-]+', reason, re.IGNORECASE):
                        exception_failures.append(f"E1: {args.exceptions}:{line_idx}: {rule_id} exception reason must include advisory ID: '{reason}'")
                if rule_id == 'N2':
                    if not re.match(r'^\d+\.\d+\.\d+$', held_at):
                        exception_failures.append(f"E1: {args.exceptions}:{line_idx}: N2 exception held_at must be an exact version string (e.g. 1.2.3), got '{held_at}'")

                exceptions.append({
                    'line': line_idx,
                    'rule': rule_id,
                    'name': name,
                    'held_at': held_at,
                    'review_by': review_by_str,
                    'reason': reason,
                    'used': False
                })
    except Exception as e:
        print(f"Error: Failed to read exceptions file '{args.exceptions}': {e}", file=sys.stderr)
        sys.exit(1)

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

    # D7: every declared dependency must be used
    def strip_dart_comments(text):
        out = []
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            # String literals (triple or single quoted, optional raw prefix)
            if ch in ("'", '"') or (ch == 'r' and i + 1 < n and text[i + 1] in ("'", '"')):
                is_raw = (ch == 'r')
                if is_raw:
                    out.append(ch)
                    i += 1
                q = text[i]
                if text[i:i + 3] == q * 3:
                    delim = q * 3
                    out.append(delim)
                    i += 3
                    while i < n:
                        if not is_raw and text[i] == '\\' and i + 1 < n:
                            out.append(text[i:i + 2])
                            i += 2
                            continue
                        if text[i:i + 3] == delim:
                            out.append(delim)
                            i += 3
                            break
                        out.append(text[i])
                        i += 1
                else:
                    out.append(q)
                    i += 1
                    while i < n:
                        if not is_raw and text[i] == '\\' and i + 1 < n:
                            out.append(text[i:i + 2])
                            i += 2
                            continue
                        if text[i] == q or text[i] == '\n':
                            out.append(text[i])
                            i += 1
                            break
                        out.append(text[i])
                        i += 1
                continue
            # Single-line comment
            if ch == '/' and i + 1 < n and text[i + 1] == '/':
                i += 2
                while i < n and text[i] != '\n':
                    i += 1
                continue
            # Block comment (supports nesting in Dart)
            if ch == '/' and i + 1 < n and text[i + 1] == '*':
                depth = 1
                i += 2
                while i < n and depth > 0:
                    if text[i:i + 2] == '/*':
                        depth += 1
                        i += 2
                    elif text[i:i + 2] == '*/':
                        depth -= 1
                        i += 2
                    else:
                        if text[i] == '\n':
                            out.append('\n')
                        i += 1
                out.append(' ')
                continue
            out.append(ch)
            i += 1
        return ''.join(out)

    def scan_dart_package_imports(root_dir, subdirs):
        used = set()
        for sub in subdirs:
            d = os.path.join(root_dir, sub)
            if not os.path.isdir(d):
                continue
            for r, _, files in os.walk(d):
                for fn in files:
                    if not fn.endswith('.dart'):
                        continue
                    fpath = os.path.join(r, fn)
                    with open(fpath, 'r', encoding='utf-8', errors='ignore') as df:
                        stripped = strip_dart_comments(df.read())
                    for stmt in re.finditer(r'(?:^|;)\s*(?:import|export)\s+([^;]+);', stripped, re.MULTILINE):
                        for m in re.finditer(r'''['"]package:([a-zA-Z0-9_]+)/[^'"]*['"]''', stmt.group(1)):
                            used.add(m.group(1))
        return used

    def scan_analysis_options_includes(root_dir):
        used = set()
        ao_path = os.path.join(root_dir, 'analysis_options.yaml')
        if not os.path.isfile(ao_path):
            return used
        with open(ao_path, 'r', encoding='utf-8', errors='ignore') as f:
            in_include_block = False
            for raw in f:
                clean = raw.split('#', 1)[0].rstrip()
                if not clean.strip():
                    continue
                if re.match(r'^\s*include\s*:', clean):
                    in_include_block = True
                    for m in re.finditer(r'package:([a-zA-Z0-9_]+)/', clean):
                        used.add(m.group(1))
                elif in_include_block:
                    if re.match(r'^\s*-\s+', clean):
                        for m in re.finditer(r'package:([a-zA-Z0-9_]+)/', clean):
                            used.add(m.group(1))
                    elif not clean.startswith(' '):
                        in_include_block = False
                    else:
                        in_include_block = False
        return used

    def scan_workflow_and_script_runs(wf_dir, root_dir):
        used = set()
        files_to_scan = []
        if os.path.isdir(wf_dir):
            for fn in sorted(os.listdir(wf_dir)):
                if fn.endswith('.yml') or fn.endswith('.yaml'):
                    files_to_scan.append(os.path.join(wf_dir, fn))
        scripts_dir = os.path.join(root_dir, 'scripts')
        if os.path.isdir(scripts_dir):
            for r, _, files in os.walk(scripts_dir):
                for fn in sorted(files):
                    if fn.endswith(('.sh', '.py', '.dart')):
                        files_to_scan.append(os.path.join(r, fn))
        for fpath in files_to_scan:
            with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                lines = []
                for idx, raw in enumerate(f):
                    if idx == 0 and raw.startswith('#!'):
                        continue
                    lines.append(raw.split('#', 1)[0])
            text = '\n'.join(lines)
            for m in re.finditer(r'\b(?:dart|flutter\s+pub|pub)\s+run\s+([a-zA-Z0-9_\-]+)', text):
                used.add(m.group(1))
            if re.search(r'\bdart\s+test\b', text):
                used.add('test')
            if re.search(r'\bflutter\s+test\b', text):
                used.add('flutter_test')
        return used

    repo_root = os.path.dirname(os.path.abspath(args.pubspec))
    main_used_pkgs = scan_dart_package_imports(repo_root, ['lib', 'bin'])
    dev_used_pkgs = (
        main_used_pkgs
        | scan_dart_package_imports(repo_root, ['test', 'integration_test', 'tool'])
        | scan_analysis_options_includes(repo_root)
        | scan_workflow_and_script_runs(args.workflows, repo_root)
    )
    for pkg in sorted(direct_deps):
        if pkg not in main_used_pkgs:
            if not check_exception('D7', pkg, '*'):
                failures.append(f"D7: Declared dependency '{pkg}' is unused in lib/ or bin/ in {args.pubspec}")
    for pkg in sorted(dev_deps):
        if pkg not in dev_used_pkgs:
            if not check_exception('D7', pkg, '*'):
                failures.append(f"D7: Declared dev_dependency '{pkg}' is unused in {args.pubspec}")

    # Read pub outdated JSON
    if not os.path.exists(args.pub_outdated):
        print(f"Error: Outdated file '{args.pub_outdated}' not found.", file=sys.stderr)
        sys.exit(1)

    with open(args.pub_outdated, 'r', encoding='utf-8') as f:
        content = f.read()
    if not content.strip():
        print(f"Error: Pub outdated file '{args.pub_outdated}' is empty or whitespace.", file=sys.stderr)
        sys.exit(1)

    first_brace = content.find('{')
    if first_brace == -1:
        print(f"Error: Pub outdated file '{args.pub_outdated}' contains no JSON object.", file=sys.stderr)
        sys.exit(1)

    try:
        outdated_data = wrap_guarded(json.loads(content[first_brace:]), args.pub_outdated)
    except Exception as e:
        print(f"Error: Failed to parse pub outdated JSON in '{args.pub_outdated}': {e}", file=sys.stderr)
        sys.exit(1)

    need(outdated_data, 'pub_outdated.{}', args.pub_outdated)
    pub_packages = need(outdated_data, 'pub_outdated.packages', args.pub_outdated)

    # Rule: pub outdated must list every direct and dev dependency declared in pubspec.yaml
    reported_pkgs = {need(p, 'pub_outdated.packages[].package', args.pub_outdated) for p in need_items(pub_packages, 'pub_outdated.packages', args.pub_outdated)}
    for dep_name in sorted(list(direct_deps) + list(dev_deps)):
        if dep_name not in non_hosted_deps:
            if dep_name not in reported_pkgs:
                failures.append(f"D1: pub outdated JSON in '{args.pub_outdated}' missing entry for declared dependency '{dep_name}'")

    package_api_cache = {}

    def get_pub_package_info(pkg_name):
        if pkg_name in package_api_cache:
            return package_api_cache[pkg_name]
        url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}"
        data = fetch_json(url)
        need(data, 'pub_package.name', url)
        need(data, 'pub_package.latest.version', url)
        need(data, 'pub_package.latest.published', url)
        versions = need(data, 'pub_package.versions', url)
        for v_entry in need_items(versions, 'pub_package.versions', url):
            need(v_entry, 'pub_package.versions[].version', url)
            need(v_entry, 'pub_package.versions[].published', url)
        package_api_cache[pkg_name] = data
        return data

    for pkg_item in need_items(pub_packages, 'pub_outdated.packages', args.pub_outdated):
        pkg_name = need(pkg_item, 'pub_outdated.packages[].package', args.pub_outdated)
        kind = opt(pkg_item, 'pub_outdated.packages[].kind', args.pub_outdated)
        is_disc = opt(pkg_item, 'pub_outdated.packages[].isDiscontinued', args.pub_outdated)
        is_ret = opt(pkg_item, 'pub_outdated.packages[].isCurrentRetracted', args.pub_outdated)
        is_adv = opt(pkg_item, 'pub_outdated.packages[].isCurrentAffectedByAdvisory', args.pub_outdated)

        curr_v = need(pkg_item, 'pub_outdated.packages[].current.version', args.pub_outdated)
        res_v = need(pkg_item, 'pub_outdated.packages[].resolvable.version', args.pub_outdated)
        lat_v = need(pkg_item, 'pub_outdated.packages[].latest.version', args.pub_outdated)

        if pkg_name in non_hosted_deps:
            # Skip pub.dev API queries for local git or sdk dependencies
            continue

        if is_disc:
            if not check_exception('D3', pkg_name, curr_v):
                failures.append(f"D3: Package '{pkg_name}' is discontinued")

        if is_ret:
            if not check_exception('D3', pkg_name, curr_v):
                failures.append(f"D3: Package '{pkg_name}' version {curr_v} is retracted")

        # D2: advisories
        has_advisory = is_adv
        advisory_id = None
        if not has_advisory:
            # Query advisories endpoint
            adv_url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}/advisories"
            adv_data = fetch_json(adv_url)
            advisories = need(adv_data, 'pub_advisories.advisories', adv_url)
            for adv in need_items(advisories, 'pub_advisories.advisories', adv_url):
                adv_id = need(adv, 'pub_advisories.advisories[].id', adv_url)
                affected = need(adv, 'pub_advisories.advisories[].affected', adv_url)
                for aff in need_items(affected, 'pub_advisories.advisories[].affected', adv_url):
                    aff_versions = opt(aff, 'pub_advisories.advisories[].affected[].versions', adv_url)
                    aff_ranges = opt(aff, 'pub_advisories.advisories[].affected[].ranges', adv_url)
                    vers_items = need_items(aff_versions, 'pub_advisories.advisories[].affected[].versions', adv_url)
                    ranges_items = need_items(aff_ranges, 'pub_advisories.advisories[].affected[].ranges', adv_url)
                    if not vers_items and not ranges_items:
                        print(f"Error: Schema failure in '{adv_url}' at path 'pub_advisories.advisories[].affected[]': entry must contain at least 'versions' or 'ranges'.", file=sys.stderr)
                        sys.exit(1)
                    in_ranges = is_version_in_ranges(curr_v, aff_ranges, adv_url)
                    if (curr_v in vers_items) or in_ranges:
                        has_advisory = True
                        advisory_id = adv_id
                        break
                if has_advisory:
                    break

        if has_advisory:
            if not check_exception('D2', pkg_name, curr_v):
                failures.append(f"D2: Package '{pkg_name}' at version {curr_v} is affected by security advisory ({advisory_id or 'reported by pub outdated'})")

        # D1: graph current
        if res_v and curr_v != res_v:
            pkg_info = get_pub_package_info(pkg_name)
            url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}"
            first_newer_date = None
            first_newer_ver = None
            for v_entry in need_items(need(pkg_info, 'pub_package.versions', url), 'pub_package.versions', url):
                v_str = need(v_entry, 'pub_package.versions[].version', url)
                if v_str and semver_cmp(v_str, curr_v) > 0 and semver_cmp(v_str, res_v) <= 0:
                    d = parse_date(need(v_entry, 'pub_package.versions[].published', url))
                    if d:
                        if first_newer_date is None or d < first_newer_date:
                            first_newer_date = d
                            first_newer_ver = v_str

            age_days = (today - first_newer_date).days if first_newer_date else 999
            if age_days < 14:
                pending_notes.append(f"Package '{pkg_name}' resolvable {res_v} pending ({age_days} days old)")
            else:
                if not check_exception('D1', pkg_name, curr_v):
                    failures.append(f"D1: Package '{pkg_name}' at version {curr_v} is behind resolvable {res_v} (first newer release {first_newer_ver} published {first_newer_date}, {age_days} days old)")
        elif lat_v and curr_v == res_v and semver_cmp(curr_v, lat_v) < 0:
            held_notes.append(f"Package '{pkg_name}' held by graph at {curr_v} (latest is {lat_v})")

        # D3: floor drift
        if (kind == 'direct' or pkg_name in direct_deps or pkg_name in dev_deps) and pkg_name in declared_floors:
            floor_v = declared_floors[pkg_name]
            if curr_v != floor_v:
                pkg_info = get_pub_package_info(pkg_name)
                url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}"
                first_newer_floor_date = None
                first_newer_floor_ver = None
                for v_entry in need_items(need(pkg_info, 'pub_package.versions', url), 'pub_package.versions', url):
                    v_str = need(v_entry, 'pub_package.versions[].version', url)
                    if '-' in v_str and '-' not in floor_v:
                        continue
                    if v_str and semver_cmp(v_str, floor_v) > 0 and semver_cmp(v_str, curr_v) <= 0:
                        d = parse_date(need(v_entry, 'pub_package.versions[].published', url))
                        if d:
                            if first_newer_floor_date is None or d < first_newer_floor_date:
                                first_newer_floor_date = d
                                first_newer_floor_ver = v_str

                age_days = (today - first_newer_floor_date).days if first_newer_floor_date else 999
                if age_days < 14:
                    pending_notes.append(f"Package '{pkg_name}' declared floor '{floor_v}' pending lockfile {curr_v} ({age_days} days old, first newer {first_newer_floor_ver})")
                else:
                    if not check_exception('D6', pkg_name, floor_v):
                        failures.append(f"D6: Package '{pkg_name}' declared floor '{floor_v}' is behind lockfile {curr_v} (first newer release {first_newer_floor_ver} published {first_newer_floor_date}, {age_days} days old)")

        # D4: package freshness
        if kind == 'direct' or pkg_name in direct_deps:
            pkg_info = get_pub_package_info(pkg_name)
            url = f"{args.pub_api.rstrip('/')}/api/packages/{pkg_name}"
            latest_v = need(pkg_info, 'pub_package.latest.version', url)
            lat_pub_date = parse_date(need(pkg_info, 'pub_package.latest.published', url))
            if lat_pub_date:
                days_since = (today - lat_pub_date).days
                if days_since > 730:
                    if not check_exception('D4', pkg_name, curr_v):
                        failures.append(f"D4: Direct dependency '{pkg_name}' is not maintained (newest release {latest_v} was published {days_since} days ago on {lat_pub_date})")

    # Target Flutter and Target Dart (T1, T2, T3)
    flutter_data = fetch_json(args.flutter_releases)
    releases = need(flutter_data, 'flutter_releases.releases', args.flutter_releases)
    stable_releases = []
    for rel in need_items(releases, 'flutter_releases.releases', args.flutter_releases):
        need(rel, 'flutter_releases.releases[].version', args.flutter_releases)
        need(rel, 'flutter_releases.releases[].release_date', args.flutter_releases)
        ch = need(rel, 'flutter_releases.releases[].channel', args.flutter_releases)
        if ch == 'stable':
            stable_releases.append(rel)
    if not stable_releases:
        failures.append(f"T1: Flutter releases from '{args.flutter_releases}' contains no stable releases")
    newest_flutter = stable_releases[0] if stable_releases else None

    if newest_flutter is not None:
        newest_flutter_ver = need(newest_flutter, 'flutter_releases.releases[].version', args.flutter_releases)
        newest_flutter_date = parse_date(need(newest_flutter, 'flutter_releases.releases[].release_date', args.flutter_releases))
        target_dart = None
        for rel in stable_releases:
            d_ver = opt(rel, 'flutter_releases.releases[].dart_sdk_version', args.flutter_releases)
            if d_ver:
                target_dart = d_ver
                break
        if not target_dart:
            target_dart = '3.0.0'
        target_dart_minor_floor = f"3.{semver_tuple(target_dart)[1]}.0"

        # Previous stable target Dart and minor floor (for 14-day grace window validation)
        prev_target_dart = None
        for rel in stable_releases:
            d_ver = opt(rel, 'flutter_releases.releases[].dart_sdk_version', args.flutter_releases)
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
            expected_floor = f"3.{semver_tuple(target_dart)[1]}.0"
            actual_floor = re.search(r'3\.\d+\.0', sdk_constraint)
            actual_floor_ver = actual_floor.group(0) if actual_floor else None
            if actual_floor_ver:
                if actual_floor_ver != expected_floor:
                    first_floor_release_date = None
                    for rel in reversed(stable_releases):
                        d_ver = opt(rel, 'flutter_releases.releases[].dart_sdk_version', args.flutter_releases)
                        if d_ver and semver_tuple(d_ver)[:2] == semver_tuple(target_dart)[:2]:
                            first_floor_release_date = parse_date(need(rel, 'flutter_releases.releases[].release_date', args.flutter_releases))
                            break
                    age_days = (today - first_floor_release_date).days if first_floor_release_date else (today - newest_flutter_date).days if newest_flutter_date else 999
                    if age_days < 14 and prev_floor and actual_floor_ver == prev_floor:
                        pending_notes.append(f"pubspec.yaml SDK floor '{actual_floor_ver}' pending target floor '{expected_floor}' ({age_days} days old)")
                    else:
                        if not check_exception('T3', 'dart', actual_floor_ver):
                            failures.append(f"T3: pubspec.yaml SDK floor '{actual_floor_ver}' is behind target Dart floor '{expected_floor}' (shipped in Flutter {age_days} days ago)")

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
                                        d_ver = opt(rel, 'flutter_releases.releases[].dart_sdk_version', args.flutter_releases)
                                        if d_ver and semver_tuple(d_ver)[:2] == semver_tuple(target_dart)[:2]:
                                            first_release_date = parse_date(need(rel, 'flutter_releases.releases[].release_date', args.flutter_releases))
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
                                    first_target_dart_date = None
                                    for rel in reversed(stable_releases):
                                        d_ver = opt(rel, 'flutter_releases.releases[].dart_sdk_version', args.flutter_releases)
                                        if d_ver == target_dart:
                                            first_target_dart_date = parse_date(need(rel, 'flutter_releases.releases[].release_date', args.flutter_releases))
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
                                latest_tag = need(gh_rel_data, 'github_release.tag_name', gh_rel_url)
                                rel_date_str = need(gh_rel_data, 'github_release.published_at', gh_rel_url)
                                rel_date = parse_date(rel_date_str)

                                # Follow tag to commit SHA
                                commit_sha = None
                                if latest_tag:
                                    gh_ref_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/git/ref/tags/{latest_tag}"
                                    gh_ref_data = fetch_json(gh_ref_url, headers=github_headers)
                                    need(gh_ref_data, 'github_tag_ref.object', gh_ref_url)
                                    commit_sha = need(gh_ref_data, 'github_tag_ref.object.sha', gh_ref_url)
                                    ref_type = need(gh_ref_data, 'github_tag_ref.object.type', gh_ref_url)
                                    if ref_type == 'tag':
                                        tag_obj_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/git/tags/{commit_sha}"
                                        tag_data = fetch_json(tag_obj_url, headers=github_headers)
                                        need(tag_data, 'github_tag_object.object', tag_obj_url)
                                        commit_sha = need(tag_data, 'github_tag_object.object.sha', tag_obj_url)

                                if action_sha != commit_sha or action_comment != latest_tag:
                                    first_newer_rel_date = rel_date
                                    gh_all_rels_url = f"{args.github_api.rstrip('/')}/repos/{action_name}/releases"
                                    gh_all_rels = fetch_json(gh_all_rels_url, headers=github_headers)
                                    need(gh_all_rels, 'github_releases_list.[]', gh_all_rels_url)
                                    newer_dates = []
                                    for r in need_items(gh_all_rels, 'github_releases_list.[]', gh_all_rels_url):
                                        tag = need(r, 'github_releases_list.[].tag_name', gh_all_rels_url)
                                        p_date_str = need(r, 'github_releases_list.[].published_at', gh_all_rels_url)
                                        is_draft = opt(r, 'github_releases_list.[].draft', gh_all_rels_url)
                                        is_prerelease = opt(r, 'github_releases_list.[].prerelease', gh_all_rels_url)
                                        if is_draft or is_prerelease:
                                            continue
                                        p_date = parse_date(p_date_str)
                                        if tag and p_date and semver_cmp(
                                            tag,
                                            action_comment,
                                            source=gh_all_rels_url,
                                            field1='github_releases_list.[].tag_name',
                                            field2=f'{wf_file}:{line_no}',
                                            allow_short=True,
                                        ) > 0:
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
                            need(node_dist_data, 'node_dist.[]', args.node_dist)
                            lts_releases = []
                            for rel in need_items(node_dist_data, 'node_dist.[]', args.node_dist):
                                need(rel, 'node_dist.[].version', args.node_dist)
                                need(rel, 'node_dist.[].date', args.node_dist)
                                lts_val = opt(rel, 'node_dist.[].lts', args.node_dist)
                                if lts_val:
                                    lts_releases.append(rel)
                            if not lts_releases:
                                failures.append(f"N3: Node releases from '{args.node_dist}' contains no LTS releases")
                            else:
                                newest_lts = lts_releases[0]
                                lts_ver = need(newest_lts, 'node_dist.[].version', args.node_dist).lstrip('v')
                                lts_major = lts_ver.split('.')[0]
                                first_lts_date = None
                                for rel in reversed(lts_releases):
                                    v = need(rel, 'node_dist.[].version', args.node_dist).lstrip('v')
                                    if v.split('.')[0] == lts_major:
                                        first_lts_date = parse_date(need(rel, 'node_dist.[].date', args.node_dist))
                                        break
                                lts_date = first_lts_date or parse_date(need(newest_lts, 'node_dist.[].date', args.node_dist))
                                if node_val != lts_major:
                                    age_days = (today - lts_date).days if lts_date else 999
                                    if age_days < 14:
                                        pending_notes.append(f"{wf_file}:{line_no}: Node version '{node_val}' pending newest LTS '{lts_major}' ({age_days} days old)")
                                    else:
                                        if not check_exception('N3', 'node', node_val):
                                            failures.append(f"N3: {wf_file}:{line_no}: Node version '{node_val}' is behind newest LTS '{lts_major}' (became LTS {age_days} days ago on {lts_date})")

        # T3: Package has pure Dart constraints vs Flutter constraints
        is_pure_dart = flutter_constraint is None
        min_sdk_jobs = [j for j in all_workflow_jobs if j['id'] == 'min-sdk']
        if is_pure_dart:
            if len(min_sdk_jobs) != 1:
                failures.append(f"T3: Pure Dart package requires exactly one 'min-sdk' job, found {len(min_sdk_jobs)}")
            else:
                min_sdk_job = min_sdk_jobs[0]
                sd_steps = [s for s in min_sdk_job['steps'] if s['uses'] and 'dart-lang/setup-dart' in s['uses']]
                if len(sd_steps) != 1:
                    failures.append(f"T3: 'min-sdk' job in {min_sdk_job['file']}:{min_sdk_job['line']} must have exactly one setup-dart step, found {len(sd_steps)}")

        # Print setup-dart summary lines (Fix 1.3)
        for s in all_setup_dart_steps:
            role = 'floor' if s['job_id'] == 'min-sdk' else 'target'
            line_no = s['uses_line'] or s['start_line']
            sdk_disp = s['sdk'] if s['sdk'] is not None else ''
            print(f"setup-dart: {s['file']}:{line_no} job {s['job_id']} sdk {sdk_disp} ({role})")

    # Check npm dependencies if npm_dir or npm_outdated provided
    pkg_json_data = None
    if args.npm_dir or args.npm_outdated or args.npm_audit:
        if args.npm_dir:
            pkg_json_path = os.path.join(args.npm_dir, 'package.json')
        else:
            pkg_json_path = os.path.join(os.path.dirname(args.npm_outdated or args.npm_audit), 'package.json')

        if not os.path.exists(pkg_json_path):
            failures.append(f"N1: npm package.json '{pkg_json_path}' not found")
        else:
            try:
                with open(pkg_json_path, 'r', encoding='utf-8') as f:
                    pkg_json_content = f.read()
                if not pkg_json_content.strip():
                    failures.append(f"N1: npm package.json '{pkg_json_path}' is empty or whitespace")
                else:
                    pkg_json_data = wrap_guarded(json.loads(pkg_json_content), pkg_json_path)
                    need(pkg_json_data, 'npm_package.{}', pkg_json_path)
            except Exception as e:
                failures.append(f"N1: Failed to read or parse npm package.json '{pkg_json_path}': {e}")

        try:
            with open(args.npm_outdated, 'r', encoding='utf-8') as f:
                npm_outdated_content = f.read()
            if not npm_outdated_content.strip():
                failures.append(f"N1: npm outdated file '{args.npm_outdated}' is empty or whitespace")
            else:
                npm_outdated_data = wrap_guarded(json.loads(npm_outdated_content), args.npm_outdated)
                outdated_keys = need_keys(npm_outdated_data, 'npm_outdated.{}', args.npm_outdated)
                if 'error' in outdated_keys:
                    failures.append(f"N1: npm outdated file '{args.npm_outdated}' reported an 'error' payload")
                else:
                    need(npm_outdated_data, 'npm_outdated.{}', args.npm_outdated)
                    for npm_pkg in sorted(outdated_keys):
                        details = need_child(npm_outdated_data, 'npm_outdated.*', npm_pkg, args.npm_outdated)
                        curr_npm_v = need(details, 'npm_outdated.*.current', args.npm_outdated)
                        lat_npm_v = need(details, 'npm_outdated.*.latest', args.npm_outdated)
                        if curr_npm_v and lat_npm_v and curr_npm_v != lat_npm_v:
                            if semver_cmp(curr_npm_v, lat_npm_v) > 0:
                                print(f"npm package '{npm_pkg}' version {curr_npm_v} ahead of latest tag {lat_npm_v}")
                                continue
                            npm_pkg_url = f"{args.npm_registry.rstrip('/')}/{npm_pkg}"
                            npm_pkg_data = fetch_json(npm_pkg_url)
                            time_dict = need(npm_pkg_data, 'npm_registry.time', npm_pkg_url)
                            time_keys = set(need_keys(time_dict, 'npm_registry.time', npm_pkg_url))
                            first_newer_date = None
                            first_newer_ver = None
                            for v_str in time_keys:
                                time_str = need_child(time_dict, 'npm_registry.time.*', v_str, npm_pkg_url)
                                if '-' in v_str or v_str in ('modified', 'created'):
                                    continue
                                if semver_cmp(v_str, curr_npm_v) > 0 and semver_cmp(v_str, lat_npm_v) <= 0:
                                    d = parse_date(time_str)
                                    if d:
                                        if first_newer_date is None or d < first_newer_date:
                                            first_newer_date = d
                                            first_newer_ver = v_str

                            pub_time = need_child(time_dict, 'npm_registry.time.*', lat_npm_v, npm_pkg_url) if lat_npm_v in time_keys else None
                            pub_date = parse_date(pub_time) if pub_time else None
                            ref_date = first_newer_date or pub_date
                            age_days = (today - ref_date).days if ref_date else 999
                            if age_days < 14:
                                pending_notes.append(f"npm package '{npm_pkg}' pending latest {lat_npm_v} ({age_days} days old)")
                            else:
                                if not check_exception('N1', npm_pkg, curr_npm_v):
                                    failures.append(f"N1: npm package '{npm_pkg}' at version {curr_npm_v} is behind latest {lat_npm_v} (first newer release {first_newer_ver or lat_npm_v} published {ref_date}, {age_days} days old)")
        except Exception as e:
            failures.append(f"N1: Failed to read or parse npm outdated JSON in '{args.npm_outdated}': {e}")

        try:
            with open(args.npm_audit, 'r', encoding='utf-8') as f:
                npm_audit_content = f.read()
            if not npm_audit_content.strip():
                failures.append(f"N2: npm audit file '{args.npm_audit}' is empty or whitespace")
            else:
                npm_audit_data = wrap_guarded(json.loads(npm_audit_content), args.npm_audit)
                need(npm_audit_data, 'npm_audit.{}', args.npm_audit)
                vulns = opt(npm_audit_data, 'npm_audit.vulnerabilities', args.npm_audit)
                metadata = opt(npm_audit_data, 'npm_audit.metadata', args.npm_audit)
                if vulns is None and metadata is None:
                    failures.append(f"N2: npm audit JSON in '{args.npm_audit}' missing metadata and vulnerabilities objects")
                elif vulns is not None:
                    vuln_keys = sorted(need_keys(vulns, 'npm_audit.vulnerabilities', args.npm_audit))
                    if vuln_keys:
                        need(npm_audit_data, 'npm_audit.vulnerabilities', args.npm_audit)
                        for pkg_name in vuln_keys:
                            info = need_child(vulns, 'npm_audit.vulnerabilities.*', pkg_name, args.npm_audit)
                            sev = need(info, 'npm_audit.vulnerabilities.*.severity', args.npm_audit)
                            if sev in ('info', 'low'):
                                continue

                            ghsas = get_ghsa_ids(pkg_name, vulns, args.npm_audit)
                            ghsa_str = ', '.join(sorted(ghsas)) if ghsas else 'no advisory ID'

                            installed_version = opt(info, 'npm_audit.vulnerabilities.*.version', args.npm_audit)
                            info_nodes = opt(info, 'npm_audit.vulnerabilities.*.nodes', args.npm_audit)
                            if not installed_version and args.npm_dir:
                                lock_path = os.path.join(args.npm_dir, 'package-lock.json')
                                if not os.path.exists(lock_path) or not os.path.isfile(lock_path):
                                    failures.append(f"N2: package-lock.json '{lock_path}' not found when resolving version for vulnerable package '{pkg_name}'")
                                else:
                                    try:
                                        with open(lock_path, 'r', encoding='utf-8') as lf:
                                            lock_content = lf.read()
                                        if not lock_content.strip():
                                            failures.append(f"N2: package-lock.json '{lock_path}' is empty or whitespace")
                                        else:
                                            lock_data = wrap_guarded(json.loads(lock_content), lock_path)
                                            packages = need(lock_data, 'npm_package_lock.packages', lock_path)
                                            pkg_lock_keys = set(need_keys(packages, 'npm_package_lock.packages', lock_path))
                                            if info_nodes is not None:
                                                for node in need_items(info_nodes, 'npm_audit.vulnerabilities.*.nodes', args.npm_audit):
                                                    if node in pkg_lock_keys:
                                                        node_entry = need_child(packages, 'npm_package_lock.packages.*', node, lock_path)
                                                        installed_version = need(node_entry, 'npm_package_lock.packages.*.version', lock_path)
                                                        break
                                            if not installed_version:
                                                k = f"node_modules/{pkg_name}"
                                                if k in pkg_lock_keys:
                                                    k_entry = need_child(packages, 'npm_package_lock.packages.*', k, lock_path)
                                                    installed_version = need(k_entry, 'npm_package_lock.packages.*.version', lock_path)
                                    except Exception as e:
                                        failures.append(f"N2: Failed to read or parse package-lock.json '{lock_path}': {e}")
                            if not installed_version:
                                failures.append(f"N2: Unable to determine installed version for vulnerable package '{pkg_name}'")

                            exc_matched = False
                            for idx, exc in enumerate(exceptions):
                                if exc['rule'] == 'N2' and exc['name'] == pkg_name:
                                    if not installed_version or exc['held_at'] != installed_version:
                                        continue
                                    missing_ghsa = [g for g in ghsas if g.lower() not in exc['reason'].lower()]
                                    if not missing_ghsa:
                                        exc['used'] = True
                                        matched_exceptions.add(idx)
                                        exc_matched = True
                                        break

                            if not exc_matched:
                                failures.append(f"N2: Vulnerability in npm package '{pkg_name}' severity '{sev}' ({ghsa_str}) at installed version {installed_version or 'unknown'}")

                if metadata is not None and (vulns is None or not need_keys(vulns, 'npm_audit.vulnerabilities', args.npm_audit)):
                    meta_vulns = need(metadata, 'npm_audit.metadata.vulnerabilities', args.npm_audit)
                    mod_count = need(meta_vulns, 'npm_audit.metadata.vulnerabilities.moderate', args.npm_audit)
                    high_count = need(meta_vulns, 'npm_audit.metadata.vulnerabilities.high', args.npm_audit)
                    crit_count = need(meta_vulns, 'npm_audit.metadata.vulnerabilities.critical', args.npm_audit)
                    if mod_count > 0 or high_count > 0 or crit_count > 0:
                        failures.append(f"N2: npm audit reports {mod_count} moderate, {high_count} high, {crit_count} critical vulnerabilities")
        except Exception as e:
            failures.append(f"N2: Failed to read or parse npm audit JSON in '{args.npm_audit}': {e}")

        # N4: npm overrides declared
        overrides = opt(pkg_json_data, 'npm_package.overrides', pkg_json_path) if pkg_json_data is not None else None
        if overrides is not None:
            for override_pkg in sorted(need_keys(overrides, 'npm_package.overrides', pkg_json_path)):
                override_val = need_child(overrides, 'npm_package.overrides.*', override_pkg, pkg_json_path)
                if not re.match(r'^\d+\.\d+\.\d+$', override_val):
                    failures.append(f"N4: npm override '{override_pkg}' value must be a plain exact version string, got '{override_val}'")
                    continue

                # Freshness check within its major
                major = override_val.split('.')[0]
                npm_pkg_url = f"{args.npm_registry.rstrip('/')}/{override_pkg}"
                npm_pkg_data = fetch_json(npm_pkg_url)
                time_dict = need(npm_pkg_data, 'npm_registry.time', npm_pkg_url)
                same_major_newer = []
                for v in need_keys(time_dict, 'npm_registry.time', npm_pkg_url):
                    ptime = need_child(time_dict, 'npm_registry.time.*', v, npm_pkg_url)
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
                    failures.append(f"N4: npm override '{override_pkg}' version '{override_val}' lacks valid N4 exception entry in dependency_exceptions.tsv")

    # E1: Check for stale exceptions
    for idx, exc in enumerate(exceptions):
        if not exc['used']:
            failures.append(f"E1: {args.exceptions}:{exc['line']}: stale exception: rule {exc['rule']} for '{exc['name']}' at version '{exc['held_at']}' matched no failure")

    if held_notes:
        for note in held_notes:
            print(f"  [HELD] {note}")

    if pending_notes:
        print("\nPending grace-period notes (14-day window):")
        for n in pending_notes:
            print(f"  - {n}")

    if failures:
        print("\nDependency Check FAILURES found:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(f"\nSummary: {len(failures)} problem(s) found.", file=sys.stderr)
        sys.exit(1)

    if _GUARD_RECORD_MODE and _GUARD_RECORD_VIOLATIONS:
        print(f"\nError: Guard violations recorded in record mode ({len(_GUARD_RECORD_VIOLATIONS)} violations):", file=sys.stderr)
        for v in _GUARD_RECORD_VIOLATIONS:
            print(f"  - in '{v[3]}': caller '{v[2]}' direct access '{v[4]}' at {v[0]}:{v[1]}", file=sys.stderr)
        sys.exit(1)

    if args.record_schema_access:
        with open(args.record_schema_access, 'w', encoding='utf-8') as f:
            for p in sorted(ACCESSED_PATHS):
                f.write(p + '\n')

    print("\nSummary: All dependencies up to date!")
    sys.exit(0)

if __name__ == '__main__':
    main()
