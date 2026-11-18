#!/usr/bin/env python3
"""Verify Dart test line coverage against monotonic per-file floors."""

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Tuple


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


def read_previous_floors(repo_root: str, floors_path: str) -> Optional[Dict[str, float]]:
    rel_floors = os.path.relpath(os.path.abspath(floors_path), os.path.abspath(repo_root)).replace(
        os.sep, "/"
    )
    has_head1 = subprocess.run(
        ["git", "-C", repo_root, "rev-parse", "--verify", "HEAD~1"],
        capture_output=True,
        text=True,
    )
    if has_head1.returncode != 0:
        return None
    prev = subprocess.run(
        ["git", "-C", repo_root, "show", f"HEAD~1:{rel_floors}"],
        capture_output=True,
        text=True,
    )
    if prev.returncode != 0:
        # Missing in HEAD~1 is allowed only for the commit that introduces it.
        return None
    return parse_floors_tsv(prev.stdout, f"HEAD~1:{rel_floors}")


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

    prev_floors = read_previous_floors(repo_root, floors_path)
    if prev_floors is not None:
        for path, prev_val in sorted(prev_floors.items()):
            if path in floors and floors[path] < prev_val:
                errors.append(
                    f"Lowered floor for {path}: {floors[path]:.1f}% < previous commit floor {prev_val:.1f}%"
                )

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
