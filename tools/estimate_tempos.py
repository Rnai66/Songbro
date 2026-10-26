#!/usr/bin/env python3
"""Fill in a BeatBuddy beat + BPM for songs that have none, marked as estimated.

Usage:
  python3 tools/estimate_tempos.py songs.json review.csv

- Only songs without a beat are touched; anything set by hand is left alone.
- International songs use their commonly published tempo (confidence high/medium).
- Songs not in the table get a starting value from the folder they are filed in
  (เพลงช้า, สตริง_เร็ว, …) — confidence "guess"; check these by ear.
- Every filled song gets "estimated": true, shown as "≈" in SongBro until edited.
"""
import csv
import json
import sys

# BeatBuddy beats in the rnai2026 project: (folder, beat)
BALLAD2, BALLAD3 = (1, 1), (1, 2)
BLUES1, BLUES_68 = (2, 1), (2, 3)
BOSSA = (3, 1)
COUNTRY_STR8 = (5, 6)
FUNK1 = (7, 1)
HIPHOP1 = (9, 1)
CHACHA, MAMBO, SON_MONTUNO = (11, 4), (11, 10), (11, 16)
OLDIE1 = (15, 1)
POP1, POP6, POP8, POP10 = (16, 1), (16, 6), (16, 8), (16, 10)
RNB1, RNB3 = (18, 1), (18, 3)
ROCK1, ROCK7 = (19, 1), (19, 7)
REGGAE1, REGGAE2 = (20, 1), (20, 2)
TH_3CHA, TH_MORLUM, TH_POP, TH_POP2 = (28, 1), (28, 2), (28, 7), (28, 8)

# title(s) in the app -> (beat, bpm, confidence)
KNOWN = {
    ("7-it's my life", "it's my life"): (ROCK1, 120, "high"),
    ("All about the bass",): (OLDIE1, 134, "high"),
    ("Cheap Thrills",): (POP1, 90, "high"),
    ("Close to you", "close to you"): (BALLAD3, 92, "medium"),
    ("Havana",): (RNB1, 105, "high"),
    ("How do i live",): (BALLAD2, 66, "medium"),
    ("I Shot the sherriff",): (REGGAE2, 95, "medium"),
    ("I Stat the joke",): (BALLAD2, 66, "low"),
    ("Let it be", "let-it-be-the-beatles"): (BALLAD3, 72, "high"),
    ("Love me like you do",): (POP1, 95, "high"),
    ("Love will keep us ",): (BALLAD2, 70, "low"),
    ("Love yourself", "love yoursalf"): (POP6, 100, "high"),
    ("Lucky",): (POP6, 130, "low"),
    ("Saving all my love",): (BALLAD2, 82, "low"),
    ("Something jus like this", "Something just like this"): (POP10, 103, "high"),
    ("Stay with me",): (BALLAD3, 84, "high"),
    ("Still got the blue",): (POP8, 98, "low"),
    ("SuseiQ",): (ROCK1, 130, "medium"),
    ("Sway",): (CHACHA, 120, "medium"),
    ("The Game of love",): (POP1, 98, "medium"),
    ("Until i found you",): (BLUES_68, 101, "medium"),
    ("Wake me up",): (POP10, 124, "high"),
    ("What's Up",): (ROCK1, 135, "medium"),
    ("Wild Wolrd",): (POP8, 98, "medium"),
    ("Wind of chang", "wind of chang"): (POP8, 76, "high"),
    ("With you were here", "wish you were here"): (POP8, 62, "medium"),
    ("Yesterday Ones More",): (POP6, 92, "medium"),
    ("angles_ robbie",): (BALLAD3, 76, "medium"),
    ("beliver_imagin dragon",): (ROCK1, 125, "high"),
    ("bkack magic",): (MAMBO, 123, "low"),
    ("by-the-way-–-red-hot-chili-peppers",): (ROCK1, 122, "high"),
    ("can take my eyes",): (OLDIE1, 124, "medium"),
    ("chang the wold",): (RNB1, 96, "medium"),
    ("counting star",): (POP10, 122, "high"),
    ("creep",): (ROCK7, 92, "high"),
    ("despacito",): (HIPHOP1, 89, "high"),
    ("don'look back in angle",): (POP8, 82, "high"),
    ("don't-cry-gun-n",): (POP8, 64, "low"),
    ("dust in the wind-1",): (BALLAD2, 98, "low"),
    ("girls like you",): (POP10, 125, "high"),
    ("have i told you",): (BALLAD2, 63, "medium"),
    ("have-you-ever-seen-the-rain",): (ROCK1, 116, "high"),
    ("home", "home 01"): (BALLAD2, 60, "low"),
    ("how deep", "how deep 01"): (RNB1, 105, "high"),
    ("i can tell you why.",): (RNB3, 72, "medium"),
    ("i don won to miss",): (BALLAD2, 60, "high"),
    ("i swear",): (BALLAD2, 64, "medium"),
    ("i want it that way",): (POP1, 99, "high"),
    ("i'm not the only one",): (POP8, 82, "high"),
    ("just the way you are",): (POP1, 109, "medium"),
    ("just the way you r _billy jo",): (BOSSA, 138, "low"),
    ("knockin on havens door",): (POP8, 69, "high"),
    ("loss star",): (POP8, 82, "medium"),
    ("love story",): (POP10, 119, "high"),
    ("lyala",): (POP6, 95, "low"),
    ("marry you(2)",): (POP10, 145, "high"),
    ("memories",): (POP6, 91, "high"),
    ("moer then i can say",): (BALLAD3, 72, "low"),
    ("more then words",): (BALLAD3, 92, "high"),
    ("my love", "my love 01"): (BALLAD3, 72, "medium"),
    ("now& forever",): (BALLAD2, 65, "medium"),
    ("one call away",): (POP6, 77, "high"),
    ("oya-santana",): (CHACHA, 126, "high"),
    ("photograph(3",): (POP8, 108, "medium"),
    ("play that funcky music",): (FUNK1, 109, "high"),
    ("rude-magic",): (REGGAE1, 144, "medium"),
    ("shape of you",): (POP1, 96, "high"),
    ("she the one",): (BALLAD3, 60, "low"),
    ("slow danc", "slow danc 01"): (RNB3, 67, "medium"),
    ("smoke on the water",): (ROCK1, 114, "high"),
    ("smooth",): (SON_MONTUNO, 116, "medium"),
    ("suger",): (POP10, 120, "high"),
    ("sunday moning",): (POP1, 88, "high"),
    ("superman",): (POP8, 98, "medium"),
    ("swat _ala la la long", "swat ala la la lonng"): (REGGAE1, 94, "medium"),
    ("sweet chile oh my",): (ROCK1, 125, "high"),
    ("sweet home",): (ROCK1, 98, "high"),
    ("take it'easy",): (COUNTRY_STR8, 139, "medium"),
    ("take me to your h",): (BALLAD3, 70, "medium"),
    ("tears in haven",): (BALLAD3, 80, "high"),
    ("the lazy song",): (REGGAE1, 88, "medium"),
    ("to be with you-mr.big",): (POP1, 94, "medium"),
    ("unstoppable",): (POP10, 87, "medium"),
    ("when you say nothing at all",): (POP8, 88, "medium"),
    ("words beegee",): (BALLAD2, 70, "low"),
    ("you may be rithg",): (ROCK1, 140, "medium"),
    ("2-Made in Thailand",): (ROCK1, 136, "medium"),
    ("4-Gao Bai Qi Qio",): (POP1, 92, "low"),
    ("5-Hoi Fu Tin Kong",): (POP8, 76, "low"),
    ("7-Ke Xi Mei Ru Gao",): (BALLAD2, 76, "low"),
    # Thai: style from what the song is known as; tempo still a guess
    ("บักแตงโม",): (TH_MORLUM, 140, "low"),
    ("ห่อหมกฮวกไปฝากป้า-657x1024",): (TH_MORLUM, 140, "low"),
    ("เต่างอย",): (TH_MORLUM, 140, "low"),
    ("สุรินทร์เหลา", "คนสุรินทร์เหลา"): (TH_MORLUM, 135, "low"),
    ("หนุ่มบาว-สาวปาน", "9-หนุ่มบาว-สาวปาน"): (TH_3CHA, 130, "low"),
    ("มนต์เพลงคาราบาว", "ลุงขี้เมา", "ลงขี้เมา"): (ROCK1, 136, "low"),
    ("8-I just want na เป็นแฟน ยู ได้บ่", "I just want na เป็นแฟน ยู ได้บ่"): ((28, 5), 128, "low"),
}

# Songs whose beat the user still has to choose (two different notes, etc.).
SKIP = {"santaria"}

# Starting point by the folder the song is filed in.
BY_FOLDER = [
    ("เพลงช้า", BALLAD2, 72),
    ("สากลแยก › ช้า", BALLAD3, 72),
    ("สากลแยก › เร็ว", POP10, 120),
    ("สตริง_เร็ว", TH_POP, 125),
    ("เพื่อชีวิต_เร็ว", ROCK1, 130),
    ("เพลงmedium", TH_POP2, 100),
    ("สวนป่า", TH_POP2, 100),
    ("ใหม่", TH_POP, 110),
    ("สากล", POP6, 100),
    ("food splash", POP6, 100),
]
DEFAULT = (TH_POP, 110)

known = {title: v for titles, v in KNOWN.items() for title in titles}


def main(path, review_path):
    songs = json.load(open(path, encoding="utf-8"))
    rows = []
    for s in songs:
        if s.get("beatFolder") or s["title"] in SKIP or s["title"].startswith("ตัวอย่าง"):
            continue
        if s["title"] in known:
            (folder, beat), bpm, confidence = known[s["title"]]
            source = "tempo ที่เผยแพร่ทั่วไป" if confidence != "low" else "ประมาณจากแนวเพลง"
        else:
            (folder, beat), bpm = next(((b, t) for name, b, t in BY_FOLDER if name in s["category"]), DEFAULT)
            confidence, source = "guess", f"ค่าเริ่มต้นของโฟลเดอร์ {s['category']}"
        s["beatFolder"], s["beatNumber"], s["estimated"] = folder, beat, True
        if not (s["title"] == "uptownfunky" and s.get("bpm")):  # keep the user's BPM
            s["bpm"] = bpm
        rows.append((s["title"], s["category"], folder, beat, s["bpm"], confidence, source))
    json.dump(songs, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)

    beats = json.load(open("BBSongbook/Resources/beats.json", encoding="utf-8"))
    name = {(f["number"], b["number"]): f"{f['name']} › {b['name']}" for f in beats["folders"] for b in f["beats"]}
    order = {"high": 0, "medium": 1, "low": 2, "guess": 3}
    with open(review_path, "w", encoding="utf-8-sig", newline="") as out:
        w = csv.writer(out)
        w.writerow(["เพลง", "โฟลเดอร์", "จังหวะ BeatBuddy", "BPM", "ความมั่นใจ", "ที่มา"])
        for t, cat, f, b, bpm, conf, src in sorted(rows, key=lambda r: (order[r[5]], r[1], r[0])):
            w.writerow([t, cat, name[(f, b)], bpm, conf, src])
    from collections import Counter
    print(len(rows), "songs filled;", dict(Counter(r[5] for r in rows)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
