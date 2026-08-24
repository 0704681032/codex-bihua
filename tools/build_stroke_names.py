#!/usr/bin/env python3
"""Build assets/data/stroke_names.json from cnchar-order's dictionary.

Source data: https://github.com/theajack/cnchar (MIT License)
File: src/cnchar/plugin/order/dict/stroke-order-jian.json  ({char: letters})

Letters map to standard stroke names (《现代汉语通用字笔顺规范》 naming,
as documented by cnchar's stroke-table). Repeated-stroke variants such as
"点2" collapse to the base name ("点"); ambiguous pairs sharing one letter
(横撇/横钩, 斜钩/卧钩, ...) are kept as slash-joined candidates here and
disambiguated at runtime from the median geometry.

Usage:
    python3 tools/build_stroke_names.py [path/to/stroke-order-jian.json]

The dict file is fetched automatically when missing.
"""

import json
import pathlib
import sys
import urllib.request

DICT_URL = (
    "https://raw.githubusercontent.com/theajack/cnchar/master/"
    "src/cnchar/plugin/order/dict/stroke-order-jian.json"
)

# cnchar letter -> canonical stroke name(s). Slash pairs share a letter
# in cnchar and need runtime disambiguation.
LETTER_TO_NAMES = {
    "j": "横",
    "f": "竖",
    "s": "撇",
    "k": "点",
    "l": "捺",
    "i": "提",
    "t": "弯钩",
    "g": "竖钩",
    "u": "竖弯钩",
    "b": "竖弯",
    "h": "竖提",
    "c": "横折",
    "r": "横折钩",
    "e": "横撇/横钩",
    "o": "横斜钩",
    "v": "横折折/横折弯",
    "a": "横折折撇",
    "q": "横折折折",
    "w": "横折折折钩/横撇弯钩",
    "p": "横折提",
    "n": "撇折",
    "m": "撇点",
    "x": "竖折折/竖折撇",
    "z": "竖折折钩",
    "y": "斜钩/卧钩",
    # Repeated-stroke variants collapse to the base name.
    "d": "点",  # 点2
}

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DICT_CACHE = ROOT / "tools" / "cache" / "stroke-order-jian.json"
CHARS_ASSET = ROOT / "assets" / "data" / "chars_3500.json"
OUTPUT = ROOT / "assets" / "data" / "stroke_names.json"


def load_order_dict(path: str) -> dict:
    source = pathlib.Path(path)
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        print(f"downloading {DICT_URL}")
        urllib.request.urlretrieve(DICT_URL, source)
    with source.open(encoding="utf-8") as fh:
        return json.load(fh)


def decode(letters: str) -> list[str]:
    names = []
    for letter in letters:
        name = LETTER_TO_NAMES.get(letter)
        if name is None:
            print(f"  ! unknown letter {letter!r} in {letters!r}")
            return []
        names.append(name)
    return names


def main() -> None:
    dict_path = sys.argv[1] if len(sys.argv) > 1 else str(DEFAULT_DICT_CACHE)
    order_dict = load_order_dict(dict_path)

    with CHARS_ASSET.open(encoding="utf-8") as fh:
        entries = json.load(fh)

    result = {}
    mismatch = []
    missing = 0
    for entry in entries:
        char = entry["char"]
        expected_count = len(entry["strokes"])
        letters = order_dict.get(char)
        if letters is None:
            missing += 1
            continue
        names = decode(letters)
        if not names:
            continue
        if len(names) != expected_count:
            mismatch.append(f"{char}: data={len(names)} strokes={expected_count}")
            continue
        result[char] = names

    OUTPUT.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"chars_3500 entries : {len(entries)}")
    print(f"covered            : {len(result)}")
    print(f"missing from dict  : {missing}")
    print(f"count mismatches   : {len(mismatch)}")
    for line in mismatch[:20]:
        print(" ", line)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
