#!/usr/bin/env python3
"""Build BBSongbook/Resources/known_beats.json from the user's beat tables.

  python3 tools/build_known_beats.py

Sources (later ones win when a song is in both):
  tools/drummer_song.tsv  title, folder, beat, bpm
  tools/drumesong2.tsv    title, beat code ("Blues-2", "Pop-1", "Polka"…), bpm
Songs listed twice with different beats inside one table are left out until
the user picks one.
"""
import json
import pathlib
import re
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOLDER = {"blues": 2, "blue": 2, "funk": 7, "pop": 16, "rock": 19, "country": 5, "oldie": 15}
WORLD = {"polka": (23, 3), "waltz": (23, 6)}


def beat_code(code):
    c = code.strip().lower()
    if c in WORLD:
        return WORLD[c]
    m = re.fullmatch(r"([a-z]+)[-0]*(\d+)", c)
    return FOLDER[m.group(1)], int(m.group(2))


def rows(path, parse):
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            yield parse(line.split("\t"))


def main():
    tables = [
        ("Drummer Song", rows(ROOT / "tools/drummer_song.tsv",
                              lambda c: (c[0], int(c[1]), int(c[2]), int(c[3])))),
        ("Drumesong2", rows(ROOT / "tools/drumesong2.tsv",
                            lambda c: (c[0], *beat_code(c[1]), int(c[2])))),
    ]
    merged = {}
    for source, entries in tables:
        seen = defaultdict(set)
        entries = list(entries)
        for title, folder, beat, bpm in entries:
            seen[title].add((folder, beat))
        for title, folder, beat, bpm in entries:
            if len(seen[title]) > 1:
                continue  # conflicting rows in this table: user hasn't chosen yet
            merged[title] = {"title": title, "folder": folder, "beat": beat,
                             "bpm": bpm if bpm > 0 else None, "source": source}
    out = ROOT / "BBSongbook/Resources/known_beats.json"
    out.write_text(json.dumps(sorted(merged.values(), key=lambda e: e["title"]),
                              ensure_ascii=False, indent=1), encoding="utf-8")
    print(len(merged), "songs ->", out)


if __name__ == "__main__":
    main()
