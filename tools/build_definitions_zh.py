#!/usr/bin/env python3
"""Build assets/data/definitions_zh.json (single-char Chinese definitions).

Source: pwxcoo/chinese-xinhua (MIT License), data/word.json — 16142 汉字
entries scraped from the Xinhua dictionary. Downloaded automatically to
tools/cache/xinhua_word.json when missing.

Output format:
    { "字": "中文释义文本", ... }
"""

import json
import pathlib
import re
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHARS_ASSET = ROOT / "assets" / "data" / "chars_index.json"
OUTPUT = ROOT / "assets" / "data" / "definitions_zh.json"
CACHE = ROOT / "tools" / "cache" / "xinhua_word.json"
DICT_URL = (
    "https://raw.githubusercontent.com/pwxcoo/chinese-xinhua/master/"
    "data/word.json"
)
MAX_TEXT = 360


def load_source() -> list:
    if not CACHE.exists() or CACHE.stat().st_size < 1000:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        print(f"downloading {DICT_URL}")
        urllib.request.urlretrieve(DICT_URL, CACHE)
    with CACHE.open(encoding="utf-8") as fh:
        return json.load(fh)


def clean(text: str, char: str) -> str:
    """Normalise whitespace and trim the header noise + long tail."""
    text = text.replace("\r", "")
    # Entries often open with the character itself followed by separators.
    text = re.sub(rf"^\s*{re.escape(char)}\s*", "", text)
    text = re.sub(r"\n{2,}", "\n", text)
    text = re.sub(r"[ \t]{2,}", " ", text).strip()
    if len(text) > MAX_TEXT:
        cut = text[:MAX_TEXT]
        # Prefer ending at a sentence-ish boundary.
        for sep in ("\n", "；", "。", "，"):
            idx = cut.rfind(sep)
            if idx > MAX_TEXT // 2:
                cut = cut[:idx + len(sep)]
                break
        text = cut.rstrip()
    return text


def main() -> None:
    with CHARS_ASSET.open(encoding="utf-8") as fh:
        index_chars = {e["c"] for e in json.load(fh)["chars"]}

    entries = load_source()
    result: dict[str, str] = {}
    for entry in entries:
        char = entry.get("word", "").strip()
        if char not in index_chars or char in result:
            continue
        explanation = entry.get("explanation", "") or ""
        cleaned = clean(explanation, char)
        if len(cleaned) >= 8:
            result[char] = cleaned

    OUTPUT.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    size_kb = OUTPUT.stat().st_size / 1024
    print(f"chars covered : {len(result)}")
    print(f"wrote {OUTPUT} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
