#!/usr/bin/env python3
"""Split words.json + definitions_zh.json into per-shard reference files.

The detail page used to read and jsonDecode both whole datasets (~4.9 MB)
on every first visit. This script buckets each char's {words, definition}
into the SAME shard numbering as the stroke shards, so opening a char
fetches one small reference file instead of two whole-file parses.

Outputs (consumed by lib at runtime):
  assets/data/references/reference_NNN.json
      { "<char>": {"w": [["词语","pīn yīn"], ...], "d": "中文释义"}, ... }

Inputs (build intermediates, NOT packaged at runtime):
  assets/data/chars_index.json    char -> shard mapping (`s` field)
  assets/data/words.json          CC-CEDICT derived per-char words
  assets/data/definitions_zh.json Xinhua derived per-char definitions

Run AFTER tools/split_chars_data.py — the shard ids come from the index.
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
INDEX_ASSET = ROOT / "assets" / "data" / "chars_index.json"
WORDS_ASSET = ROOT / "assets" / "data" / "words.json"
DEFS_ASSET = ROOT / "assets" / "data" / "definitions_zh.json"
OUT_DIR = ROOT / "assets" / "data" / "references"


def main() -> None:
    with INDEX_ASSET.open(encoding="utf-8") as fh:
        index_chars = json.load(fh)["chars"]
    with WORDS_ASSET.open(encoding="utf-8") as fh:
        words = json.load(fh)
    with DEFS_ASSET.open(encoding="utf-8") as fh:
        definitions = json.load(fh)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stale in OUT_DIR.glob("reference_*.json"):
        stale.unlink()

    buckets: dict[int, dict] = {}
    chars_with_words = 0
    chars_with_defs = 0
    for item in index_chars:
        char, shard = item["c"], item["s"]
        entry_words = words.get(char)
        entry_def = definitions.get(char)
        if not entry_words and not entry_def:
            continue
        payload = {}
        if entry_words:
            payload["w"] = entry_words
            chars_with_words += 1
        if entry_def:
            payload["d"] = entry_def
            chars_with_defs += 1
        buckets.setdefault(shard, {})[char] = payload

    shard_bytes = []
    for shard, payload in buckets.items():
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        (OUT_DIR / f"reference_{shard:03d}.json").write_text(
            text, encoding="utf-8"
        )
        shard_bytes.append(len(text.encode("utf-8")))

    shard_bytes.sort()
    count = len(shard_bytes)
    print(f"reference shards : {count}")
    print(f"chars with words : {chars_with_words}")
    print(f"chars with defs  : {chars_with_defs}")
    if count:
        print(f"bytes total      : {sum(shard_bytes) / 1024:.0f} KB")
        print(f"min/median/P95/max KB: "
              f"{shard_bytes[0] / 1024:.1f} / "
              f"{shard_bytes[count // 2] / 1024:.1f} / "
              f"{shard_bytes[min(count - 1, int(count * 0.95))] / 1024:.1f} / "
              f"{shard_bytes[-1] / 1024:.1f}")


if __name__ == "__main__":
    main()
