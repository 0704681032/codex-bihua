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

Usage: python3 tools/split_chars_data.py [--shard-size 64]
       python3 tools/split_chars_data.py --candidates 64,96,128,256
                                          ^ stats only, writes nothing
"""

import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHARS_ASSET = ROOT / "assets" / "data" / "chars_3500.json"
NAMES_ASSET = ROOT / "assets" / "data" / "stroke_names.json"
INDEX_OUT = ROOT / "assets" / "data" / "chars_index.json"
SHARDS_OUT = ROOT / "assets" / "data" / "shards"


def load_entries() -> tuple[list, int]:
    """Load source entries, merge stroke names, sort by code point."""
    with CHARS_ASSET.open(encoding="utf-8") as fh:
        entries = json.load(fh)
    names = {}
    if NAMES_ASSET.exists():
        with NAMES_ASSET.open(encoding="utf-8") as fh:
            names = json.load(fh)

    # Deterministic order: unicode code point.
    entries.sort(key=lambda e: ord(e["char"]))

    names_merged = 0
    for entry in entries:
        stroke_names = names.get(entry["char"])
        if stroke_names and len(stroke_names) == len(entry["strokes"]):
            entry["strokeNames"] = stroke_names
            names_merged += 1
    return entries, names_merged


def candidate_stats(entries: list, sizes: list[int]) -> None:
    """Measure serialized shard sizes per candidate size without writing."""
    print(f"entries: {len(entries)}")
    print(f"{'size':>5} {'shards':>7} {'total MB':>9} {'min KB':>8} "
          f"{'median KB':>10} {'P95 KB':>8} {'max KB':>8}")
    for size in sizes:
        buckets: dict[int, list] = {}
        for position, entry in enumerate(entries):
            buckets.setdefault(position // size, []).append(entry)
        shard_bytes = sorted(
            len(json.dumps(payload, ensure_ascii=False,
                           separators=(",", ":")).encode("utf-8"))
            for payload in buckets.values()
        )
        count = len(shard_bytes)
        print(f"{size:>5} {count:>7} {sum(shard_bytes) / 1024 / 1024:>9.1f} "
              f"{shard_bytes[0] / 1024:>8.1f} "
              f"{shard_bytes[count // 2] / 1024:>10.1f} "
              f"{shard_bytes[min(count - 1, int(count * 0.95))] / 1024:>8.1f} "
              f"{shard_bytes[-1] / 1024:>8.1f}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shard-size", type=int, default=256)
    parser.add_argument(
        "--candidates",
        type=str,
        default="",
        help="comma-separated shard sizes to measure and print, then exit",
    )
    args = parser.parse_args()

    entries, names_merged = load_entries()

    if args.candidates:
        sizes = [int(s) for s in args.candidates.split(",") if s.strip()]
        candidate_stats(entries, sizes)
        return

    INDEX_OUT.parent.mkdir(parents=True, exist_ok=True)
    SHARDS_OUT.mkdir(parents=True, exist_ok=True)
    for stale in SHARDS_OUT.glob("shard_*.json"):
        stale.unlink()

    index_chars = []
    shards: dict[int, list] = {}
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
        shards.setdefault(shard_id, []).append(entry)

    for shard_id, payload in shards.items():
        (SHARDS_OUT / f"shard_{shard_id:03d}.json").write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )

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
    print(f"shards           : {len(shards)} (size={args.shard_size})")
    print(f"strokeNames merged: {names_merged}")
    print(f"index size       : {index_size / 1024:.0f} KB")
    print(f"shard bytes total: {shard_bytes / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
