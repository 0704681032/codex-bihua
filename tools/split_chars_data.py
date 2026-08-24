#!/usr/bin/env python3
"""Split the monolithic chars_3500.json into fast-loading assets.

Outputs (consumed by lib at runtime):
  assets/data/chars_index.json   light metadata for every char (~0.5 MB)
                                 -> powers home page, search and filters
  assets/data/shards/shard_NNN.json
                                 full stroke payloads grouped into fixed
                                 shards -> loaded on demand by the detail
                                 page and cached

Inputs (kept out of the app bundle):
  assets/data/chars_3500.json    Make Me a Hanzi derived full data
  assets/data/stroke_names.json  cnchar-order derived stroke names

Usage: python3 tools/split_chars_data.py [--shard-size 256]
"""

import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHARS_ASSET = ROOT / "assets" / "data" / "chars_3500.json"
NAMES_ASSET = ROOT / "assets" / "data" / "stroke_names.json"
INDEX_OUT = ROOT / "assets" / "data" / "chars_index.json"
SHARDS_OUT = ROOT / "assets" / "data" / "shards"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shard-size", type=int, default=256)
    args = parser.parse_args()

    with CHARS_ASSET.open(encoding="utf-8") as fh:
        entries = json.load(fh)
    names = {}
    if NAMES_ASSET.exists():
        with NAMES_ASSET.open(encoding="utf-8") as fh:
            names = json.load(fh)

    # Deterministic order: unicode code point.
    entries.sort(key=lambda e: ord(e["char"]))

    INDEX_OUT.parent.mkdir(parents=True, exist_ok=True)
    SHARDS_OUT.mkdir(parents=True, exist_ok=True)
    for stale in SHARDS_OUT.glob("shard_*.json"):
        stale.unlink()

    index_chars = []
    shard_count = 0
    names_merged = 0
    for position, entry in enumerate(entries):
        shard_id = position // args.shard_size
        index_chars.append(
            {
                "c": entry["char"],
                "p": entry["pinyin"],
                "r": entry["radical"],
                "n": entry["strokeCount"],
                "s": shard_id,
            }
        )

        stroke_names = names.get(entry["char"])
        if stroke_names and len(stroke_names) == len(entry["strokes"]):
            entry["strokeNames"] = stroke_names
            names_merged += 1

        shard_path = SHARDS_OUT / f"shard_{shard_id:03d}.json"
        payload = []
        if shard_path.exists():
            with shard_path.open(encoding="utf-8") as fh:
                payload = json.load(fh)
        payload.append(entry)
        shard_path.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        shard_count = max(shard_count, shard_id + 1)

    INDEX_OUT.write_text(
        json.dumps(
            {"shardSize": args.shard_size, "chars": index_chars},
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )

    index_size = INDEX_OUT.stat().st_size
    shard_bytes = sum(p.stat().st_size for p in SHARDS_OUT.glob("*.json"))
    print(f"entries          : {len(entries)}")
    print(f"shards           : {shard_count} (size={args.shard_size})")
    print(f"strokeNames merged: {names_merged}")
    print(f"index size       : {index_size / 1024:.0f} KB")
    print(f"shard bytes total: {shard_bytes / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
