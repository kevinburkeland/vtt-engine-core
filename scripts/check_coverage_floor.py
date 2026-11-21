#!/usr/bin/env python3
"""Verify Dart test line coverage against monotonic per-file floors."""

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Callable, Dict, List, Optional, Tuple


def read_package_name(repo_root: str) -> str:
    pubspec_path = os.path.join(repo_root, "pubspec.yaml")
    if not os.path.isfile(pubspec_path):
        raise ValueError(f"Missing pubspec.yaml at {pubspec_path}")
    with open(pubspec_path, "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*name\s*:\s*([A-Za-z0-9_]+)\s*$", line)
            if m:
                return m.group(1)
    raise ValueError(f"Could not find package name in {pubspec_path}")


def collect_json_files(coverage_dir: str) -> List[str]:
    if not os.path.isdir(coverage_dir):
        raise ValueError(f"Coverage directory does not exist: {coverage_dir}")
    json_files: List[str] = []
    for root, _, filenames in os.walk(coverage_dir):
        for fn in filenames:
            if fn.endswith(".json"):
                json_files.append(os.path.join(root, fn))
    json_files.sort()
    if not json_files:
        raise ValueError(f"Coverage directory contains no JSON files: {coverage_dir}")
    return json_files


def merge_coverage(json_files: List[str], package_name: str) -> Dict[str, Dict[int, int]]:
    pkg_prefix = f"package:{package_name}/"
    merged: Dict[str, Dict[int, int]] = {}
    for jf in json_files:
        try:
            with open(jf, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as exc:
            raise ValueError(f"Failed to parse coverage JSON file {jf}: {exc}") from exc

        if not isinstance(data, dict) or not isinstance(data.get("coverage"), list):
            raise ValueError(f"Invalid coverage JSON structure in {jf}: missing 'coverage' list")

        for entry in data["coverage"]:
            if not isinstance(entry, dict):
                raise ValueError(f"Invalid coverage entry in {jf}: expected dict")
            src = entry.get("source")
            if not isinstance(src, str):
                continue
            if not src.startswith(pkg_prefix):
                continue
            rel_path = "lib/" + src[len(pkg_prefix) :]
            hits = entry.get("hits")
            if not isinstance(hits, list) or len(hits) % 2 != 0:
                raise ValueError(f"Invalid hits array for {src} in {jf}")
            file_hits = merged.setdefault(rel_path, {})
            for i in range(0, len(hits), 2):
                line_no = hits[i]
                count = hits[i + 1]
                if not isinstance(line_no, int) or not isinstance(count, int):
                    raise ValueError(f"Non-integer hit entry for {src} in {jf}")
                if line_no not in file_hits or count > file_hits[line_no]:
                    file_hits[line_no] = count
    return merged


def list_lib_dart_files(repo_root: str) -> List[str]:
    lib_dir = os.path.join(repo_root, "lib")
    if not os.path.isdir(lib_dir):
        raise ValueError(f"Missing lib/ directory at {lib_dir}")
    result: List[str] = []
    for root, _, filenames in os.walk(lib_dir):
        for fn in filenames:
            if fn.endswith(".dart"):
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, repo_root).replace(os.sep, "/")
                result.append(rel)
    result.sort()
    return result


def parse_floors_tsv(content: str, source_label: str) -> Dict[str, float]:
    floors: Dict[str, float] = {}
    lines = content.splitlines()
    if not lines:
        raise ValueError(f"Empty floors file: {source_label}")
    header = lines[0].strip().split("\t")
    if header != ["path", "floor"]:
        raise ValueError(f"Invalid header in {source_label}: expected 'path\\tfloor', got {lines[0]!r}")
    for idx, raw in enumerate(lines[1:], start=2):
        stripped = raw.strip()
        if not stripped:
            continue
        parts = stripped.split("\t")
        if len(parts) != 2:
            raise ValueError(f"Invalid row at line {idx} in {source_label}: {raw!r}")
        path, val_str = parts[0].strip(), parts[1].strip()
        if not re.match(r"^\d+\.\d$", val_str):
            raise ValueError(
                f"Floor must have exactly one decimal place at line {idx} in {source_label}: {val_str!r}"
            )
        if path in floors:
            raise ValueError(f"Duplicate path {path!r} at line {idx} in {source_label}")
        floors[path] = float(val_str)
    return floors


def _run_git(repo_root: str, git_args: List[str]) -> str:
    cmd = ["git", "-C", repo_root, *git_args]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        cmd_str = " ".join(cmd)
        detail = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(f"git command failed ({cmd_str}): {detail}")
    return proc.stdout


def _is_export_only_barrel(source: Optional[str]) -> bool:
    if not source:
        return False
    cleaned = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    cleaned = re.sub(r"//[^\n]*", "", cleaned)
    stripped = cleaned.strip()
    if not stripped or not stripped.endswith(";"):
        return False
    statements = [s.strip() for s in stripped.split(";") if s.strip()]
    if not statements:
        return False
    return all(
        re.match(r"^(export|library)\b", stmt) is not None for stmt in statements
    ) and any(re.match(r"^export\b", stmt) is not None for stmt in statements)


def _compare_floor_maps(
    parent_floors: Dict[str, float],
    curr_floors: Dict[str, float],
    curr_lib_files: set,
    renames: Dict[str, str],
    context_label: str,
    read_file_fn: Optional[Callable[[str], Optional[str]]] = None,
) -> List[str]:
    errs: List[str] = []
    if "TOTAL" in parent_floors:
        if "TOTAL" not in curr_floors:
            errs.append(f"Removed TOTAL floor row in {context_label}")
        elif curr_floors["TOTAL"] + 1e-9 < parent_floors["TOTAL"]:
            errs.append(
                f"Lowered floor for TOTAL in {context_label}: "
                f"{curr_floors['TOTAL']:.1f}% < previous floor {parent_floors['TOTAL']:.1f}%"
            )

    for path, prev_val in sorted(parent_floors.items()):
        if path == "TOTAL":
            continue
        if path in curr_floors:
            if curr_floors[path] + 1e-9 < prev_val:
                if (
                    curr_floors[path] == 0.0
                    and read_file_fn is not None
                    and _is_export_only_barrel(read_file_fn(path))
                ):
                    continue
                errs.append(
                    f"Lowered floor for {path} in {context_label}: "
                    f"{curr_floors[path]:.1f}% < previous floor {prev_val:.1f}%"
                )
        elif path in renames:
            new_path = renames[path]
            if new_path not in curr_floors:
                errs.append(
                    f"Missing floor row for renamed file {path} -> {new_path} in {context_label}"
                )
            elif curr_floors[new_path] + 1e-9 < prev_val:
                errs.append(
                    f"Lowered floor for renamed file {path} -> {new_path} in {context_label}: "
                    f"{curr_floors[new_path]:.1f}% < previous floor {prev_val:.1f}%"
                )
        else:
            if path in curr_lib_files:
                errs.append(
                    f"Removed floor row for existing file {path} in {context_label}"
                )
    return errs


def _parse_renames(diff_output: str) -> Dict[str, str]:
    renames: Dict[str, str] = {}
    for line in diff_output.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[0].startswith("R"):
            renames[parts[1]] = parts[2]
    return renames


def check_floor_history(
    repo_root: str,
    floors_path: str,
    working_floors: Dict[str, float],
    working_lib_set: set,
) -> List[str]:
    rel_floors = os.path.relpath(os.path.abspath(floors_path), os.path.abspath(repo_root)).replace(
        os.sep, "/"
    )

    shallow = _run_git(repo_root, ["rev-parse", "--is-shallow-repository"]).strip()
    if shallow == "true":
        raise RuntimeError(
            "Coverage floor check needs full history (repository is a shallow clone; use fetch-depth: 0)."
        )

    commits_out = _run_git(repo_root, ["log", "--format=%H", "--", rel_floors])
    commits = [c.strip() for c in commits_out.splitlines() if c.strip()]

    errors: List[str] = []

    for commit_sha in commits:
        commit_tsv = _run_git(repo_root, ["show", f"{commit_sha}:{rel_floors}"])
        commit_floors = parse_floors_tsv(commit_tsv, f"{commit_sha}:{rel_floors}")

        rev_out = _run_git(repo_root, ["rev-list", "--parents", "-n", "1", commit_sha]).strip()
        parents = rev_out.split()[1:]
        if not parents:
            continue

        commit_lib_out = _run_git(repo_root, ["ls-tree", "-r", "--name-only", commit_sha, "--", "lib"])
        commit_lib_set = {l.strip() for l in commit_lib_out.splitlines() if l.strip()}

        for parent_sha in parents:
            parent_has = _run_git(
                repo_root, ["ls-tree", "-r", "--name-only", parent_sha, "--", rel_floors]
            ).strip()
            if not parent_has:
                # Commit first introduced coverage_floors.tsv relative to this parent.
                continue

            parent_tsv = _run_git(repo_root, ["show", f"{parent_sha}:{rel_floors}"])
            parent_floors = parse_floors_tsv(parent_tsv, f"{parent_sha}:{rel_floors}")
            diff_out = _run_git(repo_root, ["diff", "-M", "--name-status", parent_sha, commit_sha])
            renames = _parse_renames(diff_out)
            def _read_commit_file(p: str, sha: str = commit_sha) -> Optional[str]:
                try:
                    return _run_git(repo_root, ["show", f"{sha}:{p}"])
                except RuntimeError:
                    return None

            errors.extend(
                _compare_floor_maps(
                    parent_floors,
                    commit_floors,
                    commit_lib_set,
                    renames,
                    f"commit {commit_sha[:12]} (parent {parent_sha[:12]})",
                    read_file_fn=_read_commit_file,
                )
            )

    # Also compare working tree floors against HEAD
    head_has = _run_git(repo_root, ["ls-tree", "-r", "--name-only", "HEAD", "--", rel_floors]).strip()
    if head_has:
        head_tsv = _run_git(repo_root, ["show", f"HEAD:{rel_floors}"])
        head_floors = parse_floors_tsv(head_tsv, f"HEAD:{rel_floors}")
        wt_diff = _run_git(repo_root, ["diff", "-M", "--name-status", "HEAD"])
        wt_renames = _parse_renames(wt_diff)

        def _read_wt_file(p: str) -> Optional[str]:
            full = os.path.join(repo_root, p)
            if not os.path.isfile(full):
                return None
            with open(full, "r", encoding="utf-8") as fh:
                return fh.read()

        errors.extend(
            _compare_floor_maps(
                head_floors,
                working_floors,
                working_lib_set,
                wt_renames,
                "working tree vs HEAD",
                read_file_fn=_read_wt_file,
            )
        )

    return errors


def check_coverage(
    coverage_dir: str,
    floors_path: str,
    repo_root: str,
) -> Tuple[List[str], List[str]]:
    package_name = read_package_name(repo_root)
    json_files = collect_json_files(coverage_dir)
    merged = merge_coverage(json_files, package_name)
    lib_files = list_lib_dart_files(repo_root)
    lib_set = set(lib_files)

    if not os.path.isfile(floors_path):
        raise ValueError(f"Floors file does not exist: {floors_path}")
    with open(floors_path, "r", encoding="utf-8") as f:
        floors = parse_floors_tsv(f.read(), floors_path)

    errors: List[str] = []
    report_lines: List[str] = []

    if "TOTAL" not in floors:
        errors.append("Missing required TOTAL row in coverage_floors.tsv")

    for lf in lib_files:
        if lf not in floors:
            errors.append(f"Missing row in coverage_floors.tsv for lib/ file: {lf}")

    for path in sorted(floors):
        if path == "TOTAL":
            continue
        if path not in lib_set:
            errors.append(f"Stale or invalid row in coverage_floors.tsv (file does not exist): {path}")

    errors.extend(check_floor_history(repo_root, floors_path, floors, lib_set))

    total_lines = 0
    total_hits = 0
    for lf in lib_files:
        file_hits = merged.get(lf, {})
        lines_count = len(file_hits)
        hits_count = sum(1 for c in file_hits.values() if c > 0)
        total_lines += lines_count
        total_hits += hits_count
        pct = (hits_count * 100.0 / lines_count) if lines_count > 0 else 0.0
        floor = floors.get(lf)
        if floor is not None:
            report_lines.append(
                f"{lf}: measured {pct:.1f}% ({hits_count}/{lines_count}) vs floor {floor:.1f}%"
            )
            if pct + 1e-9 < floor:
                errors.append(
                    f"Coverage below floor for {lf}: measured {pct:.1f}% ({hits_count}/{lines_count}) < floor {floor:.1f}%"
                )
            elif pct - floor > 0.5 + 1e-9:
                errors.append(
                    f"{lf}: measured {pct:.1f}, floor {floor:.1f}; raise the floor"
                )

    total_pct = (total_hits * 100.0 / total_lines) if total_lines > 0 else 0.0
    total_floor = floors.get("TOTAL")
    if total_floor is not None:
        report_lines.insert(
            0,
            f"TOTAL: measured {total_pct:.1f}% ({total_hits}/{total_lines}) vs floor {total_floor:.1f}%",
        )
        if total_pct + 1e-9 < total_floor:
            errors.append(
                f"Coverage below floor for TOTAL: measured {total_pct:.1f}% ({total_hits}/{total_lines}) < floor {total_floor:.1f}%"
            )
        elif total_pct - total_floor > 0.5 + 1e-9:
            errors.append(
                f"TOTAL: measured {total_pct:.1f}, floor {total_floor:.1f}; raise the floor"
            )

    return report_lines, errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Check Dart line coverage against monotonic floors.")
    parser.add_argument("coverage_dir", help="Path to dart test --coverage directory")
    parser.add_argument("floors_tsv", help="Path to coverage_floors.tsv")
    parser.add_argument("--repo-root", default=".", help="Repository root directory (default: .)")
    args = parser.parse_args()

    try:
        report_lines, errors = check_coverage(args.coverage_dir, args.floors_tsv, args.repo_root)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    for line in report_lines:
        print(line)

    if errors:
        print("\nCoverage floor check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("\nCoverage floor check PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
