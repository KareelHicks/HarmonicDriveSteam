#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_GODOT_CUSTOM_ROOT = Path(
    "/Users/kareel/Library/Application Support/Godot/app_userdata/HarmonicDrive/custom_songs"
)
DEFAULT_IOS_MAPPED_DIR = Path(
    "/Users/kareel/Desktop/KareelGames/HarmonicDrive/HarmonicDrive Shared/stem_charts_mapped"
)

TARGET_SUFFIX = " - Professional [Mapped]"
COPY_FIELDS = ("title", "artist", "charter", "difficulty", "lane_count", "bpm", "nps", "notes")


@dataclass(frozen=True)
class SourceChart:
    key: str
    title: str
    project_dir: Path
    chart_path: Path
    fields: dict[str, Any]


@dataclass(frozen=True)
class TargetChart:
    key: str
    title: str
    path: Path
    data: dict[str, Any]


def normalize_title(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON: {exc}") from exc


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")


def source_title(project_dir: Path, manifest: dict[str, Any]) -> str:
    title = str(manifest.get("title", "")).strip()
    if title:
        return title
    song_id = str(manifest.get("song_id", "")).strip()
    if song_id:
        return song_id.replace("_", " ")
    return project_dir.name.replace("_", " ")


def calculate_nps(notes: list[Any]) -> float:
    duration = 0.0
    note_count = 0
    for note in notes:
        if not isinstance(note, dict):
            continue
        note_count += 1
        try:
            time_value = float(note.get("time", 0.0))
            length_value = float(note.get("length", note.get("duration", 0.0)))
        except (TypeError, ValueError):
            continue
        duration = max(duration, time_value + length_value)
    if duration <= 0.0:
        return 0.0
    return note_count / duration


def source_fields(
    chart: dict[str, Any],
    manifest: dict[str, Any],
    project_dir: Path,
    notes: list[Any],
) -> dict[str, Any]:
    title = str(chart.get("title", manifest.get("title", source_title(project_dir, manifest)))).strip()
    artist = str(chart.get("artist", manifest.get("artist", "Unknown Artist"))).strip()
    charter = str(chart.get("charter", manifest.get("charter", "Unknown Charter"))).strip()
    difficulty = str(chart.get("difficulty", "professional")).strip().lower() or "professional"
    fields: dict[str, Any] = {
        "title": title or source_title(project_dir, manifest),
        "artist": artist or "Unknown Artist",
        "charter": charter or "Unknown Charter",
        "difficulty": difficulty,
        "lane_count": chart.get("lane_count", manifest.get("lane_count", 5)),
        "bpm": chart.get("bpm", manifest.get("bpm", 120.0)),
        "nps": chart.get("nps", calculate_nps(notes)),
        "notes": notes,
    }
    return fields


def collect_sources(root: Path) -> tuple[dict[str, SourceChart], list[str]]:
    sources: dict[str, SourceChart] = {}
    warnings: list[str] = []
    for chart_path in sorted(root.glob("*/professional.json")):
        project_dir = chart_path.parent
        manifest_path = project_dir / "manifest.json"
        manifest: dict[str, Any] = {}
        if manifest_path.exists():
            loaded_manifest = read_json(manifest_path)
            if isinstance(loaded_manifest, dict):
                manifest = loaded_manifest
            else:
                warnings.append(f"Skipping non-object manifest: {manifest_path}")
                continue
        loaded_chart = read_json(chart_path)
        if not isinstance(loaded_chart, dict):
            warnings.append(f"Skipping non-object chart: {chart_path}")
            continue
        notes = loaded_chart.get("notes", None)
        if not isinstance(notes, list):
            warnings.append(f"Skipping chart without notes array: {chart_path}")
            continue
        fields = source_fields(loaded_chart, manifest, project_dir, notes)
        title = str(fields["title"])
        keys = {
            normalize_title(title),
            normalize_title(project_dir.name.replace("_", " ")),
            normalize_title(str(manifest.get("song_id", "")).replace("_", " ")),
        }
        keys.discard("")
        for key in keys:
            if key in sources:
                warnings.append(
                    f"Duplicate source title key {key}: {sources[key].chart_path} and {chart_path}"
                )
                continue
            sources[key] = SourceChart(
                key=key,
                title=title,
                project_dir=project_dir,
                chart_path=chart_path,
                fields=fields,
            )
    return sources, warnings


def collect_targets(target_dir: Path) -> tuple[dict[str, TargetChart], list[str]]:
    targets: dict[str, TargetChart] = {}
    warnings: list[str] = []
    for path in sorted(target_dir.glob("*.json")):
        if not path.stem.endswith(TARGET_SUFFIX):
            continue
        title = path.stem[: -len(TARGET_SUFFIX)]
        key = normalize_title(title)
        loaded = read_json(path)
        if not isinstance(loaded, dict):
            warnings.append(f"Skipping non-object target chart: {path}")
            continue
        if key in targets:
            warnings.append(f"Duplicate target title key {key}: {targets[key].path} and {path}")
            continue
        targets[key] = TargetChart(key=key, title=title, path=path, data=loaded)
    return targets, warnings


def backup_path_for(target_path: Path, backup_root: Path) -> Path:
    relative_name = target_path.name
    return backup_root / relative_name


def differing_fields(target_data: dict[str, Any], source_fields_value: dict[str, Any]) -> list[str]:
    changed: list[str] = []
    for field in COPY_FIELDS:
        if target_data.get(field, None) != source_fields_value.get(field, None):
            changed.append(field)
    return changed


def replace_chart_fields(
    sources: dict[str, SourceChart],
    targets: dict[str, TargetChart],
    apply: bool,
    backup_root: Path | None,
) -> tuple[int, int, list[str], list[str]]:
    matched = 0
    changed = 0
    missing_targets: list[str] = []
    unchanged: list[str] = []

    for source_key in sorted({source.key for source in sources.values()}):
        source = sources[source_key]
        target = targets.get(source.key)
        if target is None:
            missing_targets.append(f"{source.title}: {source.chart_path}")
            continue
        matched += 1
        changed_fields = differing_fields(target.data, source.fields)
        if not changed_fields:
            unchanged.append(source.title)
            continue
        changed += 1
        previous_notes = target.data.get("notes", None)
        source_notes = source.fields.get("notes", [])
        print(
            f"{'UPDATE' if apply else 'WOULD UPDATE'}: {target.path.name} "
            f"fields {', '.join(changed_fields)}; "
            f"notes {len(previous_notes) if isinstance(previous_notes, list) else 'missing'} -> {len(source_notes) if isinstance(source_notes, list) else 'missing'} "
            f"from {source.chart_path}"
        )
        if not apply:
            continue
        if backup_root is not None:
            backup_root.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target.path, backup_path_for(target.path, backup_root))
        updated = target.data.copy()
        for field in COPY_FIELDS:
            updated[field] = source.fields[field]
        write_json(target.path, updated)

    return matched, changed, missing_targets, unchanged


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Copy the notes array from each Godot custom_songs professional.json "
            "plus chart metadata into the equivalent iOS/macOS stem_charts_mapped "
            "Professional [Mapped] chart."
        )
    )
    parser.add_argument("--godot-custom-root", type=Path, default=DEFAULT_GODOT_CUSTOM_ROOT)
    parser.add_argument("--ios-mapped-dir", type=Path, default=DEFAULT_IOS_MAPPED_DIR)
    parser.add_argument("--apply", action="store_true", help="Write target files. Default is dry-run.")
    parser.add_argument("--no-backup", action="store_true", help="Do not create backups when using --apply.")
    parser.add_argument("--limit-missing", type=int, default=40)
    args = parser.parse_args()

    if not args.godot_custom_root.is_dir():
        print(f"ERROR: missing Godot custom songs root: {args.godot_custom_root}", file=sys.stderr)
        return 2
    if not args.ios_mapped_dir.is_dir():
        print(f"ERROR: missing iOS mapped chart directory: {args.ios_mapped_dir}", file=sys.stderr)
        return 2

    sources, source_warnings = collect_sources(args.godot_custom_root)
    targets, target_warnings = collect_targets(args.ios_mapped_dir)
    backup_root = None
    if args.apply and not args.no_backup:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_root = args.ios_mapped_dir / f"_professional_notes_backup_{stamp}"

    matched, changed, missing_targets, unchanged = replace_chart_fields(
        sources,
        targets,
        args.apply,
        backup_root,
    )

    print()
    print(f"Copied fields: {', '.join(COPY_FIELDS)}")
    print(f"Godot professional sources: {len({source.chart_path for source in sources.values()})}")
    print(f"iOS/macOS professional mapped targets: {len(targets)}")
    print(f"Matched source projects: {matched}")
    print(f"{'Updated' if args.apply else 'Would update'}: {changed}")
    print(f"Already identical: {len(unchanged)}")
    print(f"Missing targets: {len(missing_targets)}")
    if backup_root is not None and changed > 0:
        print(f"Backups written to: {backup_root}")

    warnings = source_warnings + target_warnings
    if warnings:
        print(f"\nWarnings ({len(warnings)}):")
        for warning in warnings[: args.limit_missing]:
            print(f"  {warning}")
        if len(warnings) > args.limit_missing:
            print(f"  ... {len(warnings) - args.limit_missing} more")

    if missing_targets:
        print(f"\nMissing iOS/macOS Professional [Mapped] targets ({len(missing_targets)}):")
        for missing in missing_targets[: args.limit_missing]:
            print(f"  {missing}")
        if len(missing_targets) > args.limit_missing:
            print(f"  ... {len(missing_targets) - args.limit_missing} more")

    if not args.apply:
        print("\nDry run only. Re-run with --apply to write files.")
    return 1 if missing_targets else 0


if __name__ == "__main__":
    raise SystemExit(main())
