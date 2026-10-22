#!/usr/bin/env python3
"""Build BBSongbook/Resources/beats.json from a BBManager project folder.

Usage:
  python3 tools/make_beats.py "<path to BBManager project>/"

Reads SONGS/config.csv (folder order) and each folder's config.csv
(beat order) — the same order the BeatBuddy uses on its SD card.
"""
import json
import pathlib
import re
import sys

DEFAULT_PROJECT = pathlib.Path.home() / (
    "Library/Mobile Documents/com~apple~CloudDocs/Documents/Beatbuddy/rnai2026 - Project")
OUT = pathlib.Path(__file__).resolve().parent.parent / "BBSongbook/Resources/beats.json"


def read_config(folder: pathlib.Path):
    """Return [(file_id, number, name)] from a folder's config.csv (any case)."""
    for name in ("config.csv", "CONFIG.CSV", "Config.csv"):
        path = folder / name
        if path.exists():
            break
    else:
        return []
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "," not in line:
            continue
        file_id, label = line.split(",", 1)
        match = re.match(r"\s*(\d+)\.\s*(.*)", label)
        if not match:
            continue
        rows.append((file_id.strip(), int(match.group(1)), match.group(2).strip()))
    return rows


def main():
    project = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PROJECT
    songs_dir = project / "SONGS"
    folders = []
    for folder_id, number, name in read_config(songs_dir):
        beats = [{"number": n, "name": beat_name}
                 for _, n, beat_name in read_config(songs_dir / folder_id)]
        folders.append({"number": number, "name": name, "beats": beats})
    catalog = {"project": project.name.replace(" - Project", ""), "folders": folders}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(folders)} folders, {sum(len(f['beats']) for f in folders)} beats -> {OUT}")


if __name__ == "__main__":
    main()
