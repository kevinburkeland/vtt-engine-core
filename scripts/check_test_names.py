#!/usr/bin/env python3
import sys
import subprocess
import os
from collections import Counter


def is_test_file(path):
    parts = path.split('/')
    return len(parts) >= 2 and parts[0] == 'test' and path.endswith('_test.dart')


def extract_test_names(text, path=''):
    n = len(text)
    names = []

    def skip_whitespace_and_comments(idx):
        while idx < n:
            if text[idx:idx+2] == '//':
                nl = text.find('\n', idx)
                if nl == -1:
                    idx = n
                else:
                    idx = nl + 1
            elif text[idx:idx+2] == '/*':
                depth = 1
                idx += 2
                while idx < n and depth > 0:
                    if text[idx:idx+2] == '/*':
                        depth += 1
                        idx += 2
                    elif text[idx:idx+2] == '*/':
                        depth -= 1
                        idx += 2
                    else:
                        idx += 1
            elif text[idx].isspace():
                idx += 1
            else:
                break
        return idx

    def parse_string_literal(idx):
        if idx >= n:
            return None, idx
        is_raw = False
        start_idx = idx
        if text[idx] == 'r':
            if idx + 1 < n and text[idx+1] in ('\"', "'"):
                is_raw = True
                idx += 1
            else:
                return None, start_idx
        if idx >= n or text[idx] not in ('\"', "'"):
            return None, start_idx
        quote = text[idx]
        if text[idx:idx+3] == quote * 3:
            delim = quote * 3
            idx += 3
        else:
            delim = quote
            idx += 1

        chars = []
        delim_len = len(delim)
        while idx < n:
            if text[idx:idx+delim_len] == delim:
                idx += delim_len
                return ''.join(chars), idx
            if not is_raw and text[idx] == '\\':
                if idx + 1 < n:
                    c = text[idx+1]
                    if c == quote:
                        chars.append(quote)
                    elif c == '\\':
                        chars.append('\\')
                    elif c == 'n':
                        chars.append('\n')
                    elif c == 'r':
                        chars.append('\r')
                    elif c == 't':
                        chars.append('\t')
                    elif c == '$':
                        chars.append('$')
                    else:
                        chars.append('\\')
                        chars.append(c)
                    idx += 2
                else:
                    chars.append('\\')
                    idx += 1
            elif not is_raw and text[idx:idx+2] == '${':
                # interpolation - keep verbatim
                start_interp = idx
                idx += 2
                depth = 1
                while idx < n and depth > 0:
                    if text[idx] == '{':
                        depth += 1
                        idx += 1
                    elif text[idx] == '}':
                        depth -= 1
                        idx += 1
                    elif text[idx] in ('\"', "'"):
                        sub_q = text[idx]
                        if text[idx:idx+3] == sub_q * 3:
                            sub_delim = sub_q * 3
                        else:
                            sub_delim = sub_q
                        idx += len(sub_delim)
                        while idx < n:
                            if text[idx:idx+len(sub_delim)] == sub_delim:
                                idx += len(sub_delim)
                                break
                            if text[idx] == '\\' and idx + 1 < n:
                                idx += 2
                            else:
                                idx += 1
                    else:
                        idx += 1
                chars.append(text[start_interp:idx])
            else:
                chars.append(text[idx])
                idx += 1
        return None, start_idx

    i = 0
    prev_token_dot = False
    while i < n:
        i = skip_whitespace_and_comments(i)
        if i >= n:
            break

        c = text[i]
        if c.isalpha() or c in ('_', '$'):
            start_id = i
            while i < n and (text[i].isalnum() or text[i] in ('_', '$')):
                i += 1
            ident = text[start_id:i]

            if ident in ('test', 'testWidgets', 'group') and not prev_token_dot:
                next_i = skip_whitespace_and_comments(i)
                if next_i < n and text[next_i] == '(':
                    arg_i = skip_whitespace_and_comments(next_i + 1)
                    first_str, after_str_i = parse_string_literal(arg_i)
                    if first_str is not None:
                        full_name = first_str
                        curr_i = after_str_i
                        while True:
                            next_token_i = skip_whitespace_and_comments(curr_i)
                            adj_str, adj_after_i = parse_string_literal(next_token_i)
                            if adj_str is not None:
                                full_name += adj_str
                                curr_i = adj_after_i
                            else:
                                break
                        names.append(full_name)
                    else:
                        names.append(f'<non-literal at {path}>')
            prev_token_dot = False
        elif c == '.':
            prev_token_dot = True
            i += 1
        else:
            prev_token_dot = False
            str_val, new_i = parse_string_literal(i)
            if str_val is not None:
                i = new_i
            else:
                i += 1
    return names


def get_git_file_content(rev, path):
    res = subprocess.run(['git', 'show', f'{rev}:{path}'], capture_output=True, text=True)
    if res.returncode == 0:
        return res.stdout
    return None


def main():
    if len(sys.argv) < 3:
        print("Usage: check_test_names.py <baseline> <head>", file=sys.stderr)
        sys.exit(1)

    baseline = sys.argv[1]
    head = sys.argv[2]

    # Parse removed_test_names.txt at <head>
    allowed_removals = {}
    file_problems = []
    removed_content = get_git_file_content(head, 'test/removed_test_names.txt')
    if removed_content is None and os.path.exists('test/removed_test_names.txt'):
        try:
            with open('test/removed_test_names.txt', 'r', encoding='utf-8') as f:
                removed_content = f.read()
        except Exception:
            removed_content = None

    if removed_content is not None:
        for line_num, raw_line in enumerate(removed_content.splitlines(), start=1):
            line = raw_line.strip()
            if not line or line.startswith('#'):
                continue
            if '|' not in line:
                file_problems.append(
                    f"test/removed_test_names.txt:{line_num}: invalid entry (missing delimiter '|'): {line}"
                )
                continue
            name_part, reason_part = line.split('|', 1)
            name = name_part.strip()
            reason = reason_part.strip()
            if not reason:
                file_problems.append(
                    f"test/removed_test_names.txt:{line_num}: invalid entry for '{name}': empty reason"
                )
            elif not name:
                file_problems.append(
                    f"test/removed_test_names.txt:{line_num}: invalid entry: empty name"
                )
            else:
                allowed_removals[name] = reason

    # List commits
    rev_range = f"{baseline}..{head}"
    rev_list_res = subprocess.run(['git', 'rev-list', '--reverse', rev_range], capture_output=True, text=True)
    if rev_list_res.returncode != 0:
        print(f"Error running git rev-list {rev_range}: {rev_list_res.stderr}", file=sys.stderr)
        sys.exit(1)

    commits = [c.strip() for c in rev_list_res.stdout.splitlines() if c.strip()]
    total_commits = len(commits)

    problems = list(file_problems)

    for c in commits:
        short_c = c[:7]
        # Parent commit is first parent c^1
        p = f"{c}^1"
        diff_res = subprocess.run(['git', 'diff', '--name-only', p, c], capture_output=True, text=True)
        if diff_res.returncode != 0:
            problems.append(f"{short_c}: failed to diff against parent {p}")
            continue

        changed_test_files = [line.strip() for line in diff_res.stdout.splitlines() if is_test_file(line.strip())]
        if not changed_test_files:
            continue

        names_p = Counter()
        names_c = Counter()
        file_counts_p = {}
        file_counts_c = {}

        for path in changed_test_files:
            content_p = get_git_file_content(p, path)
            list_p = extract_test_names(content_p, path) if content_p is not None else []
            cnt_p = Counter(list_p)
            file_counts_p[path] = cnt_p
            names_p.update(cnt_p)

            content_c = get_git_file_content(c, path)
            list_c = extract_test_names(content_c, path) if content_c is not None else []
            cnt_c = Counter(list_c)
            file_counts_c[path] = cnt_c
            names_c.update(cnt_c)

        for name, count_p in names_p.items():
            count_c = names_c.get(name, 0)
            if count_p > count_c:
                drop_count = count_p - count_c
                # Find which file(s) it left
                left_files = []
                for path in changed_test_files:
                    fp = file_counts_p[path].get(name, 0)
                    fc = file_counts_c[path].get(name, 0)
                    if fp > fc:
                        left_files.append(path)
                left_file_str = ", ".join(left_files) if left_files else "unknown"

                if name not in allowed_removals:
                    problems.append(
                        f"{short_c}: test '{name}' removed from {left_file_str}"
                    )

    if problems:
        for prob in problems:
            print(prob)
        print(f"Checked {total_commits} commits: found {len(problems)} problem(s).")
        sys.exit(1)

    print(f"Checked {total_commits} commit(s). All test names preserved.")
    sys.exit(0)


if __name__ == '__main__':
    main()
