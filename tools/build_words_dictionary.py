#!/usr/bin/env python3
"""Build assets/data/words.json (per-character example words with pinyin).

Source: CC-CEDICT https://www.mdbg.net/chinese/dictionary?page=cc-cedict
(CC BY-SA 4.0). Downloaded to tools/cache/cedict.txt.gz by this script
when missing.

Output format (compact, offline):
    { "字": [["词语","pīn yīn"], ...], ... }

Only simplified words of length 2..4 are kept; up to --max per character,
two-character words first. Entries matching the kid-safety blocklist are
dropped.
"""

import argparse
import gzip
import json
import pathlib
import re
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHARS_ASSET = ROOT / "assets" / "data" / "chars_index.json"
OUTPUT = ROOT / "assets" / "data" / "words.json"
CACHE = ROOT / "tools" / "cache" / "cedict.txt.gz"
DICT_URL = (
    "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
)

LINE_RE = re.compile(
    r"^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/(.+)/$", re.UNICODE
)

# Kid-app safety: drop entries containing any of these (case-insensitive).
BLOCKLIST = (
    "fuck", "shit", "penis", "vagina", "nigg", "rape", "slut", "whore",
    "porn", "incest", "masturb", "prostitut", "sodom", "orgasm", "erotic",
    "sex",
)

TONE_MARKS = {
    ("a", 1): "ā", ("a", 2): "á", ("a", 3): "ǎ", ("a", 4): "à",
    ("e", 1): "ē", ("e", 2): "é", ("e", 3): "ě", ("e", 4): "è",
    ("o", 1): "ō", ("o", 2): "ó", ("o", 3): "ǒ", ("o", 4): "ò",
    ("i", 1): "ī", ("i", 2): "í", ("i", 3): "ǐ", ("i", 4): "ì",
    ("u", 1): "ū", ("u", 2): "ú", ("u", 3): "ǔ", ("u", 4): "ù",
    ("v", 1): "ǖ", ("v", 2): "ǘ", ("v", 3): "ǚ", ("v", 4): "ǜ",
}


def load_cedict() -> str:
    if not CACHE.exists():
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        print(f"downloading {DICT_URL}")
        urllib.request.urlretrieve(DICT_URL, CACHE)
    with gzip.open(CACHE, "rt", encoding="utf-8") as fh:
        return fh.read()


def tone_syllable(syllable: str) -> str:
    """Convert one numbered pinyin syllable (e.g. 'zhong1') to tone marks."""
    syllable = syllable.strip()
    match = re.match(r"^([A-Za-züv]+)([1-5])$", syllable)
    if not match:
        return syllable.lower()
    letters, tone = match.group(1), int(match.group(2))
    lowered = letters.replace("v", "ü").lower()
    if tone == 5 or tone == 0:
        return lowered

    placed = False

    def mark(text: str, vowel: str) -> str:
        nonlocal placed
        target = vowel
        for i, ch in enumerate(text):
            if ch == target or (target == "ü" and ch == "u" and
                                i + 1 < len(text) and text[i + 1] == "i"):
                continue
        # handled below via replace on first occurrence
        placed = True
        return text

    # Standard placement rules: a > e > o > (iu last vowel) > u/ü.
    order = ["a", "e", "o"]
    for vowel in order:
        idx = lowered.find(vowel)
        if idx >= 0:
            return (lowered[:idx] +
                    TONE_MARKS[(vowel, tone)] + lowered[idx + 1:])
    # 'iu'/'ui' families take the final vowel.
    for suffix_vowel in ("i", "u"):
        idx = lowered.rfind(suffix_vowel)
        if idx >= 0:
            key = suffix_vowel
            return (lowered[:idx] +
                    TONE_MARKS[(key, tone)] + lowered[idx + 1:])
    return lowered


def convert_pinyin(raw: str) -> str:
    parts = raw.split()
    converted = [tone_syllable(p) for p in parts]
    # Proper nouns keep their capitalisation hint on the first syllable.
    if parts and parts[0][:1].isupper():
        converted[0] = converted[0][:1].upper() + converted[0][1:]
    return " ".join(converted)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max", type=int, default=8)
    args = parser.parse_args()

    with CHARS_ASSET.open(encoding="utf-8") as fh:
        index_chars = {e["c"] for e in json.load(fh)["chars"]}

    text = load_cedict()
    per_char: dict[str, list[tuple[int, str, str]]] = {}
    skipped_blocklist = 0

    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = LINE_RE.match(line)
        if not match:
            continue
        _traditional, simplified, pinyin_raw, english = match.groups()

        if len(simplified) < 2 or len(simplified) > 4:
            continue
        lowered_english = english.lower()
        if any(bad in lowered_english for bad in BLOCKLIST):
            skipped_blocklist += 1
            continue
        if not all(ch in index_chars for ch in simplified):
            continue

        pinyin = convert_pinyin(pinyin_raw)
        for ch in set(simplified):
            per_char.setdefault(ch, []).append((simplified, pinyin))

    result: dict[str, list[list[str]]] = {}
    for ch, candidates in per_char.items():
        seen: set[str] = set()
        chosen: list[list[str]] = []
        # 组词直觉: 目标字打头的词(火车/火苗)最相关, 其次是包含该字的短词。
        ranked = sorted(
            candidates,
            key=lambda entry: (
                (0 if entry[0].startswith(ch) else 1) * 100 + len(entry[0]),
                entry[0],
            ),
        )
        for word, pinyin in ranked:
            if word in seen:
                continue
            seen.add(word)
            chosen.append([word, pinyin])
            if len(chosen) >= args.max:
                break
        if chosen:
            result[ch] = chosen

    OUTPUT.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    size_kb = OUTPUT.stat().st_size / 1024
    print(f"chars covered      : {len(result)}")
    print(f"blocklist skipped  : {skipped_blocklist}")
    print(f"wrote {OUTPUT} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
