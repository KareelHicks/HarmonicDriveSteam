#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
COMPARE_SCRIPT = ROOT / "tools" / "compare_harmonic_drive_charts.py"
DEFAULT_GODOT_CHARTS_ROOT = ROOT / "content" / "charts"
MODE_TO_GODOT_DIR = {
    "synthesized": "synthesized",
    "stems_random": "stems_random",
    "stems_mapped": "stems_mapped",
}


def load_report(report_path: Path | None) -> dict[str, Any]:
    if report_path is not None:
        return json.loads(report_path.read_text(encoding="utf-8"))

    completed = subprocess.run(
        [sys.executable, str(COMPARE_SCRIPT), "--json"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode not in {0, 1}:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip() or "chart comparison failed")
    return json.loads(completed.stdout)


def expected_godot_path(godot_charts_root: Path, key: str) -> Path:
    try:
        mode, chart_key = key.split("/", 1)
    except ValueError as exc:
        raise ValueError(f"Invalid chart key in report: {key}") from exc
    if mode not in MODE_TO_GODOT_DIR:
        raise ValueError(f"Unknown chart mode in report key: {key}")
    return godot_charts_root / MODE_TO_GODOT_DIR[mode] / f"{chart_key}.json"


def ensure_inside_root(path: Path, root: Path) -> None:
    resolved_path = path.resolve()
    resolved_root = root.resolve()
    try:
        resolved_path.relative_to(resolved_root)
    except ValueError as exc:
        raise ValueError(f"Refusing to write outside {resolved_root}: {resolved_path}") from exc


def copy_chart(source: Path, destination: Path, godot_charts_root: Path, dry_run: bool) -> None:
    ensure_inside_root(destination, godot_charts_root)
    if not source.is_file():
        raise FileNotFoundError(f"Source chart does not exist: {source}")
    if dry_run:
        print(f"DRY RUN: {source} -> {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    print(f"Copied {source} -> {destination}")


def verify(godot_charts_root: Path) -> int:
    completed = subprocess.run(
        [sys.executable, str(COMPARE_SCRIPT), "--quiet", "--godot-charts-root", str(godot_charts_root)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(completed.stdout.rstrip())
    return completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply chart updates reported by compare_harmonic_drive_charts.py to the Godot chart tree."
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Path to JSON output from compare_harmonic_drive_charts.py --json. If omitted, comparison is run first.",
    )
    parser.add_argument(
        "--godot-charts-root",
        type=Path,
        default=DEFAULT_GODOT_CHARTS_ROOT,
        help="Godot content/charts directory to update.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print planned copies without writing files.")
    parser.add_argument("--no-verify", action="store_true", help="Skip running the comparison after copying.")
    args = parser.parse_args()

    report = load_report(args.report)
    godot_charts_root = args.godot_charts_root

    missing = report.get("missing_in_godot", [])
    mismatches = report.get("content_mismatches", [])
    extras = report.get("extra_in_godot", [])
    if extras:
        print(f"NOTE: {len(extras)} extra Godot charts are present; this script does not delete files.")

    copied = 0
    for item in missing:
        key = str(item.get("key", ""))
        source = Path(str(item.get("ios_path", "")))
        destination = expected_godot_path(godot_charts_root, key)
        copy_chart(source, destination, godot_charts_root, args.dry_run)
        copied += 1

    for item in mismatches:
        source = Path(str(item.get("ios_path", "")))
        destination_value = item.get("godot_path")
        if destination_value:
            destination = Path(str(destination_value))
        else:
            destination = expected_godot_path(godot_charts_root, str(item.get("key", "")))
        copy_chart(source, destination, godot_charts_root, args.dry_run)
        copied += 1

    print(f"Applied {copied} chart update(s)." if not args.dry_run else f"Planned {copied} chart update(s).")

    if args.dry_run or args.no_verify:
        return 0

    verify_code = verify(godot_charts_root)
    if verify_code == 0:
        print("OK: Godot chart files now match the iOS chart sources.")
    return verify_code


if __name__ == "__main__":
    raise SystemExit(main())
