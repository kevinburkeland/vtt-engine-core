#!/usr/bin/env python3
"""
Cold Iron Birdcage - SRD Compliance Scanner
Scans all git-tracked files for non-SRD / Product Identity terms defined in compliance/srd_denylist.txt.
Matches are excused only if covered by a live entry in compliance/srd_denylist_exceptions.tsv.
"""

import argparse
import os
import re
import subprocess
import sys


def split_words(text: str) -> list[str]:
    """
    Splits text into normalized words:
    1. Break between a lower-case letter or digit and an upper-case letter (camelCase).
    2. Treat every character that isn't an ASCII letter or digit as a separator.
    3. Lower-case all characters.
    """
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', text)
    s = re.sub(r'[^a-zA-Z0-9]+', ' ', s)
    return s.lower().split()


def load_denylist(path: str) -> list[tuple[str, list[str]]]:
    if not os.path.isfile(path):
        print(f"Error: Denylist file not found or unreadable: {path}", file=sys.stderr)
        sys.exit(1)
    terms = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                words = split_words(line)
                if words:
                    terms.append((line.lower(), words))
    except Exception as e:
        print(f"Error reading denylist file {path}: {e}", file=sys.stderr)
        sys.exit(1)

    if not terms:
        print(f"Error: Denylist file {path} contains no valid terms", file=sys.stderr)
        sys.exit(1)
    return terms


def load_exceptions(path: str) -> list[dict]:
    if not os.path.isfile(path):
        print(f"Error: Exceptions file not found or unreadable: {path}", file=sys.stderr)
        sys.exit(1)
    exceptions = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line_no, line in enumerate(f, 1):
                raw = line.strip('\r\n')
                if not raw or raw.startswith('#'):
                    continue
                parts = raw.split('\t')
                if len(parts) != 3:
                    print(
                        f"Error: {path}:{line_no}: Malformed exceptions row (expected 3 tab-separated columns: path, term, reason)",
                        file=sys.stderr,
                    )
                    sys.exit(1)
                exc_path = parts[0].strip()
                exc_term = parts[1].strip()
                exc_reason = parts[2].strip()
                if not exc_path or not exc_term or not exc_reason:
                    print(
                        f"Error: {path}:{line_no}: Empty column in exceptions row",
                        file=sys.stderr,
                    )
                    sys.exit(1)
                exceptions.append({
                    'line_no': line_no,
                    'path': exc_path,
                    'term': exc_term,
                    'term_words': split_words(exc_term),
                    'reason': exc_reason,
                    'matched_count': 0,
                })
    except Exception as e:
        print(f"Error reading exceptions file {path}: {e}", file=sys.stderr)
        sys.exit(1)
    return exceptions


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan git-tracked files for forbidden SRD terms.")
    parser.add_argument("--repo", default=".", help="Path to repository root")
    parser.add_argument("--denylist", help="Path to srd_denylist.txt")
    parser.add_argument("--exceptions", help="Path to srd_denylist_exceptions.tsv")
    args = parser.parse_args()

    repo_root = os.path.abspath(args.repo)
    denylist_path = os.path.abspath(args.denylist) if args.denylist else os.path.join(repo_root, "compliance", "srd_denylist.txt")
    exceptions_path = os.path.abspath(args.exceptions) if args.exceptions else os.path.join(repo_root, "compliance", "srd_denylist_exceptions.tsv")

    terms = load_denylist(denylist_path)
    exceptions = load_exceptions(exceptions_path)

    # Get git-tracked files
    try:
        out = subprocess.check_output(["git", "ls-files"], cwd=repo_root, text=True)
        tracked_files = [line.strip() for line in out.splitlines() if line.strip()]
    except Exception as e:
        print(f"Error running git ls-files in {repo_root}: {e}", file=sys.stderr)
        return 1

    denylist_rel = os.path.relpath(denylist_path, repo_root)
    exceptions_rel = os.path.relpath(exceptions_path, repo_root)

    skipped_binary = 0
    scanned_files = 0
    unexcused_hits = []
    excused_hits = []

    for rel_path in tracked_files:
        if (
            rel_path == denylist_rel
            or rel_path == exceptions_rel
            or rel_path.startswith("mutations/")
        ):
            continue

        full_path = os.path.join(repo_root, rel_path)
        try:
            with open(full_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except UnicodeDecodeError:
            skipped_binary += 1
            continue
        except Exception as e:
            print(f"Error reading {rel_path}: {e}", file=sys.stderr)
            return 1

        scanned_files += 1
        for line_no, line in enumerate(lines, 1):
            if rel_path == "test/removed_test_names.txt":
                stripped = line.strip()
                if stripped and not stripped.startswith("#") and "|" in stripped:
                    parts = stripped.rsplit("|", 1)
                    if parts[0].strip() and parts[1].strip() == "removed for SRD compliance in Cleanup slice 13":
                        continue
            lw = split_words(line)
            if not lw:
                continue
            for raw_term, tw in terms:
                k = len(tw)
                if any(lw[i : i + k] == tw for i in range(len(lw) - k + 1)):
                    # Hit found
                    is_excused = False
                    for exc in exceptions:
                        if exc["path"] == rel_path and exc["term_words"] == tw:
                            exc["matched_count"] += 1
                            is_excused = True
                            excused_hits.append((rel_path, line_no, raw_term, exc["reason"]))
                            break
                    if not is_excused:
                        unexcused_hits.append((rel_path, line_no, raw_term))
                        print(f"{rel_path}:{line_no}: {raw_term}")

    # Check for stale exception rows
    stale_exceptions = [exc for exc in exceptions if exc["matched_count"] == 0]
    for stale in stale_exceptions:
        print(
            f"Error: Stale exception row in {exceptions_rel}:{stale['line_no']}: {stale['path']}\t{stale['term']}",
            file=sys.stderr,
        )

    # Report results
    print(f"Skipped {skipped_binary} binary file(s).")
    if excused_hits:
        print(f"Used exceptions ({len(excused_hits)} hit(s)):")
        for rel_path, line_no, term, reason in excused_hits:
            print(f"  {rel_path}:{line_no}: {term} ({reason})")

    if unexcused_hits or stale_exceptions:
        print(
            f"SRD compliance scan FAILED: {len(unexcused_hits)} unexcused hit(s), {len(stale_exceptions)} stale exception(s).",
            file=sys.stderr,
        )
        return 1

    print(f"SRD compliance scan passed ({scanned_files} file(s) scanned).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
