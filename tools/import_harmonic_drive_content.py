#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT.parent / "HarmonicDrive" / "HarmonicDrive Shared"
CHART_SOURCES = {
    "stems_mapped": SOURCE_ROOT / "stem_charts_mapped",
    "stems_random": SOURCE_ROOT / "stem_charts_randomized",
    "synthesized": SOURCE_ROOT / "charts",
}
MUSIC_DIRS = [SOURCE_ROOT / "music", SOURCE_ROOT / "premium_music"]

DEST_CHARTS_DIR = ROOT / "content" / "charts"
DEST_AUDIO_DIR = ROOT / "content" / "audio"
DEST_MANIFEST = ROOT / "content" / "manifests" / "song_manifest.json"
DEST_PROGRESSION_MANIFEST = ROOT / "content" / "manifests" / "progression_manifest.json"
DIFFICULTIES = ["Easy", "Medium", "Hard", "Expert", "Professional"]
MODE_DEFS = {
    "stems_mapped": {
        "display_name": "Classic",
        "short_label": "Classic",
    },
    "stems_random": {
        "display_name": "Lane Shuffle",
        "short_label": "Shuffle",
    },
    "synthesized": {
        "display_name": "Remix Difficulty",
        "short_label": "Remix",
    },
}
def chart_base_name(stem: str) -> str | None:
    for difficulty in DIFFICULTIES:
        for suffix in [f" - {difficulty} [Mapped]", f" - {difficulty} [Random]", f" - {difficulty} [Synth]", f" - {difficulty}"]:
            if stem.endswith(suffix):
                return stem[: -len(suffix)]
    return None


def chart_priority(stem: str, difficulty: str) -> int:
    ordered_suffixes = [
        f" - {difficulty} [Mapped]",
        f" - {difficulty} [Random]",
        f" - {difficulty} [Synth]",
        f" - {difficulty}",
    ]
    for index, suffix in enumerate(ordered_suffixes):
        if stem.endswith(suffix):
            return index
    return 999


def collect_audio_files() -> dict[str, Path]:
    result: dict[str, Path] = {}
    for music_dir in MUSIC_DIRS:
        for path in music_dir.iterdir():
            if path.suffix.lower() not in {".m4a", ".wav", ".mp3"}:
                continue
            result[path.stem] = path
    return result


def find_audio_for_base(base_name: str, audio_files: dict[str, Path]) -> tuple[str, Path] | None:
    for stem, path in audio_files.items():
        if stem == base_name or stem.startswith(base_name + " - "):
            return stem, path
    return None


def is_premium_audio(path: Path) -> bool:
    return path.parent.name == "premium_music"


def ensure_ogg(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if (
        destination.exists()
        and destination.stat().st_size > 0
        and destination.stat().st_mtime >= source.stat().st_mtime
    ):
        return
    if destination.exists() and destination.stat().st_size == 0:
        destination.unlink()
    if source.suffix.lower() == ".ogg":
        shutil.copy2(source, destination)
        return
    subprocess.run(
        [
            "/opt/homebrew/bin/ffmpeg",
            "-y",
            "-i",
            str(source),
            "-vn",
            "-strict",
            "-2",
            "-c:a",
            "vorbis",
            "-q:a",
            "5",
            str(destination),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> None:
    DEST_CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    DEST_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    DEST_MANIFEST.parent.mkdir(parents=True, exist_ok=True)

    audio_files = collect_audio_files()

    charts_by_base: dict[str, dict[str, dict[str, Path]]] = {}
    bpm_by_base: dict[str, float] = {}
    professional_note_count_by_base: dict[str, int] = {}
    for mode_id, source_dir in CHART_SOURCES.items():
        for chart_path in sorted(source_dir.glob("*.json")):
            base_name = chart_base_name(chart_path.stem)
            if base_name is None:
                continue

            difficulty = next(d for d in DIFFICULTIES if f" - {d}" in chart_path.stem)
            charts_by_base.setdefault(base_name, {})
            charts_by_base[base_name].setdefault(mode_id, {})
            current = charts_by_base[base_name][mode_id].get(difficulty)
            if current is None or chart_priority(chart_path.stem, difficulty) < chart_priority(current.stem, difficulty):
                charts_by_base[base_name][mode_id][difficulty] = chart_path

            data = json.loads(chart_path.read_text(encoding="utf-8"))
            if base_name not in bpm_by_base:
                bpm_by_base[base_name] = float(data.get("bpm", 120.0))
            note_count = len(data.get("notes", []))
            if difficulty == "Professional":
                existing_count = professional_note_count_by_base.get(base_name)
                if mode_id == "synthesized" or existing_count is None:
                    professional_note_count_by_base[base_name] = note_count

    manifest: list[dict] = []
    progression_rows: list[dict] = []
    for base_name, chart_map_by_mode in sorted(charts_by_base.items()):
        audio_match = find_audio_for_base(base_name, audio_files)
        if audio_match is None:
            continue

        audio_stem, audio_source = audio_match
        song_id = "".join(c if c.isalnum() else "_" for c in base_name.lower()).strip("_")
        while "__" in song_id:
            song_id = song_id.replace("__", "_")
        audio_destination = DEST_AUDIO_DIR / f"{song_id}.ogg"
        ensure_ogg(audio_source, audio_destination)

        modes_payload = {}
        synthesized_difficulties: list[str] = []
        for mode_id, mode_charts in chart_map_by_mode.items():
            mode_dir = DEST_CHARTS_DIR / mode_id
            mode_dir.mkdir(parents=True, exist_ok=True)
            charts_payload = {}
            for difficulty, source_chart in mode_charts.items():
                chart_name = f"{song_id}_{difficulty.lower()}.json"
                chart_destination = mode_dir / chart_name
                shutil.copy2(source_chart, chart_destination)
                charts_payload[difficulty] = f"res://content/charts/{mode_id}/{chart_name}"
            if not charts_payload:
                continue
            modes_payload[mode_id] = {
                "id": mode_id,
                "display_name": MODE_DEFS[mode_id]["display_name"],
                "short_label": MODE_DEFS[mode_id]["short_label"],
                "charts": charts_payload,
            }
            if mode_id == "synthesized":
                synthesized_difficulties = list(charts_payload.keys())

        artist = audio_stem[len(base_name) + 3 :] if audio_stem.startswith(base_name + " - ") else "Unknown Artist"

        manifest.append(
            {
                "id": song_id,
                "display_name": base_name,
                "artist": artist,
                "audio_path": f"res://content/audio/{song_id}.ogg",
                "chart_base_name": base_name,
                "difficulties": synthesized_difficulties,
                "modes": modes_payload,
                "preview_start": 0.0,
                "bpm": bpm_by_base.get(base_name, 120.0),
                "is_premium": is_premium_audio(audio_source),
            }
        )
        progression_rows.append(
            {
                "id": song_id,
                "display_name": base_name,
                "professional_note_count": int(professional_note_count_by_base.get(base_name, 0)),
                "is_premium": is_premium_audio(audio_source),
            }
        )

    manifest.sort(key=lambda entry: entry["display_name"])
    progression_rows.sort(key=lambda entry: (int(entry["professional_note_count"]), str(entry["display_name"])))
    DEST_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    DEST_PROGRESSION_MANIFEST.write_text(json.dumps(build_progression_manifest(progression_rows), indent=2), encoding="utf-8")
    print(f"Imported {len(manifest)} songs into {DEST_MANIFEST}")


def build_progression_manifest(progress_rows: list[dict]) -> dict:
    total = len(progress_rows)
    if total == 0:
        return {"sections": [], "songs": {}}
    group_count = max(1, -(-total // 4))
    extra_groups = total - group_count * 3
    group_sizes = [4 if index < extra_groups else 3 for index in range(group_count)]

    section_rows: list[list[dict]] = []
    sections: list[dict] = []
    songs: dict[str, dict] = {}
    cursor = 0
    for index, group_size in enumerate(group_sizes):
        rows = progress_rows[cursor : cursor + group_size]
        cursor += group_size
        section_rows.append(list(rows))

    _rebalance_sections_for_standard_songs(section_rows)

    for index, rows in enumerate(section_rows):
        rows.sort(key=lambda row: (int(row["professional_note_count"]), str(row["display_name"])))
        section_id = index + 1
        section_song_ids = [str(row["id"]) for row in rows]
        sections.append(
            {
                "id": section_id,
                "songs": section_song_ids,
                "unlock_requirement": 2,
                "min_note_count": int(rows[0]["professional_note_count"]) if rows else 0,
                "max_note_count": int(rows[-1]["professional_note_count"]) if rows else 0,
            }
        )
        for row in rows:
            songs[str(row["id"])] = {
                "section_id": section_id,
                "professional_note_count": int(row["professional_note_count"]),
                "display_name": str(row["display_name"]),
                "is_premium": bool(row.get("is_premium", False)),
            }
    return {"sections": sections, "songs": songs}


def _standard_song_count(rows: list[dict]) -> int:
    return sum(1 for row in rows if not bool(row.get("is_premium", False)))


def _rebalance_sections_for_standard_songs(section_rows: list[list[dict]]) -> None:
    for index, rows in enumerate(section_rows):
        while _standard_song_count(rows) < 2:
            premium_index = next((i for i, row in enumerate(rows) if bool(row.get("is_premium", False))), None)
            if premium_index is None:
                break

            donor_section_index: int | None = None
            donor_row_index: int | None = None
            search_order = list(range(index + 1, len(section_rows))) + list(range(index - 1, -1, -1))
            for donor_index in search_order:
                donor_rows = section_rows[donor_index]
                if _standard_song_count(donor_rows) <= 2:
                    continue
                donor_row_index = next((i for i, row in enumerate(donor_rows) if not bool(row.get("is_premium", False))), None)
                if donor_row_index is not None:
                    donor_section_index = donor_index
                    break

            if donor_section_index is None or donor_row_index is None:
                break

            donor_rows = section_rows[donor_section_index]
            rows[premium_index], donor_rows[donor_row_index] = donor_rows[donor_row_index], rows[premium_index]


if __name__ == "__main__":
    main()
