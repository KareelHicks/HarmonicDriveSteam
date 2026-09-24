#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IOS_ROOT = ROOT.parent / "HarmonicDrive" / "HarmonicDrive Shared"
DEFAULT_GODOT_CHARTS_ROOT = ROOT / "content" / "charts"

DIFFICULTIES = ["Easy", "Medium", "Hard", "Expert", "Professional"]
MODE_CONFIG = {
    "synthesized": {
        "ios_dir": "charts",
        "godot_dir": "synthesized",
        "suffixes": ["Synth", ""],
    },
    "stems_random": {
        "ios_dir": "stem_charts_randomized",
        "godot_dir": "stems_random",
        "suffixes": ["Random"],
    },
    "stems_mapped": {
        "ios_dir": "stem_charts_mapped",
        "godot_dir": "stems_mapped",
        "suffixes": ["Mapped"],
    },
}


@dataclass(frozen=True)
class ChartRecord:
    key: str
    mode: str
    song_id: str
    display_name: str
    difficulty: str
    path: Path
    data: Any
    digest: str


def song_id_for_display_name(display_name: str) -> str:
    song_id = "".join(c if c.isalnum() else "_" for c in display_name.lower()).strip("_")
    while "__" in song_id:
        song_id = song_id.replace("__", "_")
    return song_id


def canonical_digest(data: Any) -> str:
    payload = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def read_chart(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON: {exc}") from exc


def parse_ios_chart(path: Path, mode: str) -> tuple[str, str] | None:
    suffixes = MODE_CONFIG[mode]["suffixes"]
    for difficulty in DIFFICULTIES:
        for suffix in suffixes:
            expected = f" - {difficulty}" + (f" [{suffix}]" if suffix else "")
            if path.stem.endswith(expected):
                return path.stem[: -len(expected)], difficulty
    return None


def parse_godot_chart(path: Path) -> tuple[str, str] | None:
    match = re.fullmatch(r"(.+)_(easy|medium|hard|expert|professional)", path.stem)
    if match is None:
        return None
    difficulty = next(d for d in DIFFICULTIES if d.lower() == match.group(2))
    return match.group(1), difficulty


def collect_ios_charts(ios_root: Path) -> tuple[dict[str, ChartRecord], list[str]]:
    records: dict[str, ChartRecord] = {}
    warnings: list[str] = []
    for mode in MODE_CONFIG:
        source_dir = ios_root / str(MODE_CONFIG[mode]["ios_dir"])
        if not source_dir.is_dir():
            warnings.append(f"Missing iOS source directory for {mode}: {source_dir}")
            continue
        for path in sorted(source_dir.glob("*.json")):
            parsed = parse_ios_chart(path, mode)
            if parsed is None:
                warnings.append(f"Skipped iOS chart with unknown name format: {path}")
                continue
            display_name, difficulty = parsed
            song_id = song_id_for_display_name(display_name)
            key = f"{mode}/{song_id}_{difficulty.lower()}"
            data = read_chart(path)
            if key in records:
                warnings.append(f"Duplicate iOS chart key {key}: {records[key].path} and {path}")
            records[key] = ChartRecord(
                key=key,
                mode=mode,
                song_id=song_id,
                display_name=display_name,
                difficulty=difficulty,
                path=path,
                data=data,
                digest=canonical_digest(data),
            )
    return records, warnings


def collect_godot_charts(godot_charts_root: Path) -> tuple[dict[str, ChartRecord], list[str]]:
    records: dict[str, ChartRecord] = {}
    warnings: list[str] = []
    for mode, config in MODE_CONFIG.items():
        source_dir = godot_charts_root / str(config["godot_dir"])
        if not source_dir.is_dir() and mode == "stems_random":
            legacy_dir = godot_charts_root / "stems_randomized"
            if legacy_dir.is_dir():
                source_dir = legacy_dir
        if not source_dir.is_dir():
            warnings.append(f"Missing Godot chart directory for {mode}: {source_dir}")
            continue
        for path in sorted(source_dir.glob("*.json")):
            parsed = parse_godot_chart(path)
            if parsed is None:
                warnings.append(f"Skipped Godot chart with unknown name format: {path}")
                continue
            song_id, difficulty = parsed
            key = f"{mode}/{song_id}_{difficulty.lower()}"
            data = read_chart(path)
            if key in records:
                warnings.append(f"Duplicate Godot chart key {key}: {records[key].path} and {path}")
            records[key] = ChartRecord(
                key=key,
                mode=mode,
                song_id=song_id,
                display_name=song_id,
                difficulty=difficulty,
                path=path,
                data=data,
                digest=canonical_digest(data),
            )
    return records, warnings


def chart_summary(record: ChartRecord) -> str:
    notes = record.data.get("notes", []) if isinstance(record.data, dict) else []
    bpm = record.data.get("bpm") if isinstance(record.data, dict) else None
    offset = record.data.get("audioOffset") if isinstance(record.data, dict) else None
    return f"notes={len(notes)} bpm={bpm} audioOffset={offset}"


def first_difference(left: Any, right: Any, path: str = "$") -> str | None:
    if type(left) is not type(right):
        return f"{path}: type differs ({type(left).__name__} != {type(right).__name__})"
    if isinstance(left, dict):
        left_keys = set(left)
        right_keys = set(right)
        missing = sorted(left_keys - right_keys)
        extra = sorted(right_keys - left_keys)
        if missing:
            return f"{path}: missing in Godot: {missing[0]}"
        if extra:
            return f"{path}: extra in Godot: {extra[0]}"
        for key in sorted(left_keys):
            diff = first_difference(left[key], right[key], f"{path}.{key}")
            if diff is not None:
                return diff
        return None
    if isinstance(left, list):
        if len(left) != len(right):
            return f"{path}: list length differs ({len(left)} != {len(right)})"
        for index, (left_item, right_item) in enumerate(zip(left, right)):
            diff = first_difference(left_item, right_item, f"{path}[{index}]")
            if diff is not None:
                return diff
        return None
    if left != right:
        return f"{path}: value differs ({left!r} != {right!r})"
    return None


def group_counts(records: dict[str, ChartRecord]) -> dict[str, int]:
    return {mode: sum(1 for record in records.values() if record.mode == mode) for mode in MODE_CONFIG}


def print_grouped(records: list[ChartRecord], label: str, limit: int) -> None:
    if not records:
        return
    print(f"\n{label} ({len(records)}):")
    for record in records[:limit]:
        print(f"  {record.key}")
        print(f"    path: {record.path}")
        print(f"    {chart_summary(record)}")
    if len(records) > limit:
        print(f"  ... {len(records) - limit} more")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare iOS Harmonic Drive chart JSON files against the Godot imported copies."
    )
    parser.add_argument("--ios-root", type=Path, default=DEFAULT_IOS_ROOT)
    parser.add_argument("--godot-charts-root", type=Path, default=DEFAULT_GODOT_CHARTS_ROOT)
    parser.add_argument("--limit", type=int, default=40, help="Maximum rows to print for each issue group.")
    parser.add_argument("--quiet", action="store_true", help="Only print the summary and mismatches.")
    parser.add_argument("--json", action="store_true", help="Emit a machine-readable JSON report.")
    args = parser.parse_args()

    try:
        ios_records, ios_warnings = collect_ios_charts(args.ios_root)
        godot_records, godot_warnings = collect_godot_charts(args.godot_charts_root)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    all_ios_keys = set(ios_records)
    all_godot_keys = set(godot_records)
    missing_keys = sorted(all_ios_keys - all_godot_keys)
    extra_keys = sorted(all_godot_keys - all_ios_keys)
    changed_keys = sorted(
        key for key in all_ios_keys & all_godot_keys if ios_records[key].digest != godot_records[key].digest
    )

    if args.json:
        report = {
            "ios_root": str(args.ios_root),
            "godot_charts_root": str(args.godot_charts_root),
            "ios_counts": group_counts(ios_records),
            "godot_counts": group_counts(godot_records),
            "missing_in_godot": [
                {
                    "key": key,
                    "ios_path": str(ios_records[key].path),
                    "summary": chart_summary(ios_records[key]),
                }
                for key in missing_keys
            ],
            "extra_in_godot": [
                {
                    "key": key,
                    "godot_path": str(godot_records[key].path),
                    "summary": chart_summary(godot_records[key]),
                }
                for key in extra_keys
            ],
            "content_mismatches": [
                {
                    "key": key,
                    "ios_path": str(ios_records[key].path),
                    "godot_path": str(godot_records[key].path),
                    "ios_summary": chart_summary(ios_records[key]),
                    "godot_summary": chart_summary(godot_records[key]),
                    "first_diff": first_difference(ios_records[key].data, godot_records[key].data),
                }
                for key in changed_keys
            ],
            "warnings": ios_warnings + godot_warnings,
        }
        print(json.dumps(report, indent=2))
        return 1 if missing_keys or extra_keys or changed_keys else 0

    print("Chart comparison")
    print(f"  iOS root: {args.ios_root}")
    print(f"  Godot charts root: {args.godot_charts_root}")
    print(f"  iOS chart counts: {group_counts(ios_records)} total={len(ios_records)}")
    print(f"  Godot chart counts: {group_counts(godot_records)} total={len(godot_records)}")
    print(f"  Missing in Godot: {len(missing_keys)}")
    print(f"  Extra in Godot: {len(extra_keys)}")
    print(f"  Content mismatches: {len(changed_keys)}")

    for warning in ios_warnings + godot_warnings:
        print(f"WARNING: {warning}")

    if not args.quiet:
        print_grouped([ios_records[key] for key in missing_keys], "Missing in Godot", args.limit)
        print_grouped([godot_records[key] for key in extra_keys], "Extra in Godot", args.limit)

    if changed_keys:
        print(f"\nContent mismatches ({len(changed_keys)}):")
        for key in changed_keys[: args.limit]:
            ios_record = ios_records[key]
            godot_record = godot_records[key]
            print(f"  {key}")
            print(f"    iOS:   {ios_record.path}")
            print(f"           {chart_summary(ios_record)}")
            print(f"    Godot: {godot_record.path}")
            print(f"           {chart_summary(godot_record)}")
            diff = first_difference(ios_record.data, godot_record.data)
            if diff is not None:
                print(f"    first diff: {diff}")
        if len(changed_keys) > args.limit:
            print(f"  ... {len(changed_keys) - args.limit} more")

    if missing_keys or extra_keys or changed_keys:
        return 1
    print("\nOK: Godot chart files match the iOS chart sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
