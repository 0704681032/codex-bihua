#!/usr/bin/env python3

"""Build the app dictionary JSON from Make Me a Hanzi source files.

Two modes:

* Legacy: pass ``--graphics`` and ``--dictionary`` (paths or HTTPS URLs).
  Merges both on the shared ``character`` key into the app schema.
* Upgrade: pass ``--hanzi-writer-data DIR`` and ``--upgrade-from FILE``.
  Takes strokes/medians from the hanzi-writer-data per-character JSON files
  (https://github.com/chanind/hanzi-writer-data — the actively maintained
  fork of Make Me a Hanzi graphics) and inherits pinyin/radical/examples
  from an existing app dictionary, pinning the character set and order.
  Hard-fails if any existing character is missing from the new source.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable
from urllib.request import urlopen


DEFAULT_PINYIN = "zi4"
DEFAULT_RADICAL = "一"
IDS_OPERATORS = {
    "⿰",
    "⿱",
    "⿲",
    "⿳",
    "⿴",
    "⿵",
    "⿶",
    "⿷",
    "⿸",
    "⿹",
    "⿺",
    "⿻",
    "？",
}


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Build assets/data/chars_3500.json from Make Me a Hanzi data.",
    )
    parser.add_argument(
        "--graphics",
        help="Path or HTTPS URL to graphics.txt (legacy mode)",
    )
    parser.add_argument(
        "--dictionary",
        help="Path or HTTPS URL to dictionary.txt (legacy mode)",
    )
    parser.add_argument(
        "--hanzi-writer-data",
        default=None,
        help="Directory of per-character JSON files extracted from the "
        "hanzi-writer-data npm package (upgrade mode)",
    )
    parser.add_argument(
        "--upgrade-from",
        default=None,
        help="Existing app dictionary JSON whose character set, order and "
        "pinyin/radical/examples metadata are kept (upgrade mode)",
    )
    parser.add_argument(
        "--output",
        default=str(repo_root / "assets" / "data" / "chars_3500.json"),
        help="Output JSON path. Defaults to the app dictionary asset.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Write indented JSON instead of compact JSON.",
    )
    args = parser.parse_args()

    legacy = bool(args.graphics or args.dictionary)
    upgrade = bool(args.hanzi_writer_data or args.upgrade_from)
    if legacy and upgrade:
        parser.error(
            "--graphics/--dictionary and --hanzi-writer-data/--upgrade-from "
            "are mutually exclusive modes"
        )
    if legacy and not (args.graphics and args.dictionary):
        parser.error("legacy mode needs both --graphics and --dictionary")
    if upgrade and not (args.hanzi_writer_data and args.upgrade_from):
        parser.error(
            "upgrade mode needs both --hanzi-writer-data and --upgrade-from"
        )
    return args


def read_text(path_or_url: str) -> str:
    if path_or_url.startswith(("http://", "https://")):
        with urlopen(path_or_url, timeout=60) as response:  # nosec: trusted CLI input
            return response.read().decode("utf-8")
    return Path(path_or_url).read_text(encoding="utf-8")


def iter_json_lines(raw_text: str, source_name: str) -> Iterable[dict]:
    for line_number, line in enumerate(raw_text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            decoded = json.loads(stripped)
        except json.JSONDecodeError as exc:
            raise ValueError(
                f"{source_name} line {line_number} is not valid JSON: {exc}"
            ) from exc
        if not isinstance(decoded, dict):
            continue
        yield decoded


def normalize_pinyin(value: object) -> str:
    if isinstance(value, list):
        for item in value:
            text = str(item).strip()
            if text:
                return text
        return ""
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return ""
        return text.split(",")[0].strip()
    return ""


def normalize_examples(definition: object) -> list[str]:
    if not isinstance(definition, str):
        return []
    text = definition.strip()
    return [text] if text else []


def derive_radical(entry: dict) -> str:
    radical = entry.get("radical")
    if isinstance(radical, str) and radical.strip():
        return radical.strip()

    decomposition = entry.get("decomposition")
    if not isinstance(decomposition, str):
        return ""

    for char in decomposition.strip():
        if char in IDS_OPERATORS or char.isspace():
            continue
        return char
    return ""


def normalize_points(points: object) -> list[list[float]]:
    if not isinstance(points, list):
        return []

    normalized: list[list[float]] = []
    for point in points:
        if not isinstance(point, list) or len(point) < 2:
            continue
        x = point[0]
        y = point[1]
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
            continue
        normalized.append([float(x), float(y)])
    return normalized


def validate_strokes(char: str, strokes: list[dict]) -> None:
    """Hard-fail on data that would break stroke order or animation.

    Make Me a Hanzi stores every stroke as a closed filled outline plus a
    median polyline in a flipped (y-up) 1024x1024 coordinate space; the app's
    animation clips the outline along the median, so both must be present and
    consistent for every stroke.
    """
    problems: list[str] = []
    seen_orders: list[int] = []

    for index, stroke in enumerate(strokes, start=1):
        if stroke.get("order") != index:
            problems.append(f"stroke {index} has order={stroke.get('order')}")
        seen_orders.append(int(stroke.get("order", -1)))
        if not str(stroke.get("svgPath", "")).strip():
            problems.append(f"stroke {index} has empty svgPath")
        medians = stroke.get("medianPoints") or []
        if len(medians) < 2:
            problems.append(f"stroke {index} has fewer than 2 median points")
        for point in medians:
            x, y = point[0], point[1]
            if not (-300 <= x <= 1400 and -300 <= y <= 1400):
                problems.append(
                    f"stroke {index} median point out of range: [{x}, {y}]"
                )
                break

    if seen_orders != list(range(1, len(strokes) + 1)):
        problems.append("orders are not a strict 1..n sequence")

    if problems:
        details = "; ".join(problems[:5])
        raise ValueError(f"invalid stroke data for '{char}': {details}")


def load_dictionary(source: str) -> dict[str, dict]:
    result: dict[str, dict] = {}
    raw_text = read_text(source)
    for item in iter_json_lines(raw_text, source):
        char = str(item.get("character", "")).strip()
        if len(char) != 1:
            continue
        result[char] = item
    return result


def strokes_from_raw(
    char: str, strokes_raw: object, medians_raw: object
) -> list[dict]:
    """Normalize raw stroke path strings + median polylines into app schema."""
    if not isinstance(strokes_raw, list):
        return []
    if not isinstance(medians_raw, list):
        medians_raw = []

    strokes: list[dict] = []
    for index, path in enumerate(strokes_raw, start=1):
        if not isinstance(path, str):
            continue
        svg_path = path.strip()
        if not svg_path:
            continue
        median_points = normalize_points(
            medians_raw[index - 1] if index - 1 < len(medians_raw) else []
        )
        strokes.append(
            {
                "order": len(strokes) + 1,
                "svgPath": svg_path,
                "medianPoints": median_points,
            }
        )
    return strokes


def load_graphics(source: str) -> tuple[list[str], dict[str, list[dict]]]:
    order: list[str] = []
    result: dict[str, list[dict]] = {}
    raw_text = read_text(source)
    for item in iter_json_lines(raw_text, source):
        char = str(item.get("character", "")).strip()
        if len(char) != 1:
            continue

        strokes = strokes_from_raw(
            char, item.get("strokes"), item.get("medians")
        )
        if not strokes:
            continue

        validate_strokes(char, strokes)

        order.append(char)
        result[char] = strokes
    return order, result


def load_hanzi_writer(source_dir: str) -> dict[str, list[dict]]:
    """Load per-character JSON files from the hanzi-writer-data package."""
    directory = Path(source_dir)
    if not directory.is_dir():
        raise ValueError(f"hanzi-writer-data directory not found: {directory}")

    result: dict[str, list[dict]] = {}
    for path in sorted(directory.glob("*.json")):
        char = path.stem
        if len(char) != 1:
            continue
        try:
            decoded = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path.name} is not valid JSON: {exc}") from exc

        strokes = strokes_from_raw(
            char, decoded.get("strokes"), decoded.get("medians")
        )
        if not strokes:
            continue

        validate_strokes(char, strokes)
        result[char] = strokes
    if not result:
        raise ValueError(f"no character JSON files found under {directory}")
    return result


def build_entries(
    ordered_chars: list[str],
    graphics: dict[str, list[dict]],
    dictionary: dict[str, dict],
) -> tuple[list[dict], dict[str, int]]:
    entries: list[dict] = []
    stats = {
        "missing_dictionary": 0,
        "default_pinyin": 0,
        "default_radical": 0,
        "with_medians": 0,
    }

    for char in ordered_chars:
        strokes = graphics.get(char, [])
        if not strokes:
            continue

        dict_entry = dictionary.get(char)
        if dict_entry is None:
            stats["missing_dictionary"] += 1
            dict_entry = {}

        raw_pinyin = normalize_pinyin(dict_entry.get("pinyin"))
        pinyin = raw_pinyin or DEFAULT_PINYIN
        if not raw_pinyin:
            stats["default_pinyin"] += 1

        raw_radical = derive_radical(dict_entry)
        radical = raw_radical or DEFAULT_RADICAL
        if not raw_radical:
            stats["default_radical"] += 1

        examples = normalize_examples(dict_entry.get("definition"))
        if any(stroke["medianPoints"] for stroke in strokes):
            stats["with_medians"] += 1

        entries.append(
            {
                "char": char,
                "pinyin": pinyin,
                "radical": radical,
                "strokeCount": len(strokes),
                "strokes": strokes,
                "examples": examples,
            }
        )
    return entries, stats


def build_entries_upgrade(
    old_entries: list[dict], hanzi_writer: dict[str, list[dict]]
) -> tuple[list[dict], dict]:
    """Swap strokes/medians in-place against an existing app dictionary.

    Keeps the character set, order and all metadata identical so that the
    index, reference shards and font subset stay byte-stable except for the
    characters whose geometry the hanzi-writer-data project fixed.
    """
    entries: list[dict] = []
    stats = {
        "identical": 0,
        "svg_changed": [],
        "median_changed": [],
        "count_changed": [],
        "skipped_extra": [],
        "missing": [],
    }

    for old in old_entries:
        char = old["char"]
        new_strokes = hanzi_writer.get(char)
        if new_strokes is None:
            stats["missing"].append(char)
            continue

        old_strokes = old["strokes"]
        if len(new_strokes) != len(old_strokes):
            stats["count_changed"].append(
                (char, len(old_strokes), len(new_strokes))
            )
        elif new_strokes != old_strokes:
            svg_differs = any(
                new["svgPath"] != old["svgPath"]
                for new, old in zip(new_strokes, old_strokes)
            )
            (stats["svg_changed"] if svg_differs else stats["median_changed"]).append(char)
        else:
            stats["identical"] += 1

        entries.append(
            {
                "char": char,
                "pinyin": old["pinyin"],
                "radical": old["radical"],
                "strokeCount": len(new_strokes),
                "strokes": new_strokes,
                "examples": old.get("examples", []),
            }
        )

    if stats["missing"]:
        preview = ", ".join(stats["missing"][:10])
        raise ValueError(
            f"hanzi-writer-data is missing {len(stats['missing'])} "
            f"characters present in --upgrade-from: {preview}"
        )

    old_chars = {old["char"] for old in old_entries}
    stats["skipped_extra"] = sorted(set(hanzi_writer) - old_chars)
    return entries, stats


def write_output(entries: list[dict], output_path: Path, pretty: bool) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_suffix(output_path.suffix + ".tmp")
    json_text = json.dumps(
        entries,
        ensure_ascii=False,
        indent=2 if pretty else None,
        separators=None if pretty else (",", ":"),
    )
    temp_path.write_text(json_text, encoding="utf-8")
    temp_path.replace(output_path)


def main() -> int:
    args = parse_args()

    if args.hanzi_writer_data:
        old_entries = json.loads(
            Path(args.upgrade_from).read_text(encoding="utf-8")
        )
        if not isinstance(old_entries, list) or not old_entries:
            raise ValueError(f"--upgrade-from has no entries: {args.upgrade_from}")
        hanzi_writer = load_hanzi_writer(args.hanzi_writer_data)
        entries, stats = build_entries_upgrade(old_entries, hanzi_writer)
        output_path = Path(args.output)
        write_output(entries, output_path, pretty=args.pretty)

        print(f"output: {output_path}")
        print(f"upgrade-from: {args.upgrade_from}")
        print(f"hanzi-writer-data chars: {len(hanzi_writer)}")
        print(f"written entries: {len(entries)}")
        print(f"identical geometry: {stats['identical']}")
        print(
            "svg changed: "
            f"{len(stats['svg_changed'])} -> {''.join(stats['svg_changed'])}"
        )
        print(
            "median changed: "
            f"{len(stats['median_changed'])} -> "
            f"{''.join(stats['median_changed'])}"
        )
        print(
            "stroke count changed: "
            f"{len(stats['count_changed'])} -> {stats['count_changed']}"
        )
        print(
            "skipped (not in old set): "
            f"{len(stats['skipped_extra'])} -> {''.join(stats['skipped_extra'])}"
        )
        return 0

    ordered_chars, graphics = load_graphics(args.graphics)
    dictionary = load_dictionary(args.dictionary)
    entries, stats = build_entries(ordered_chars, graphics, dictionary)
    output_path = Path(args.output)
    write_output(entries, output_path, pretty=args.pretty)

    print(f"output: {output_path}")
    print(f"graphics entries: {len(graphics)}")
    print(f"dictionary entries: {len(dictionary)}")
    print(f"written entries: {len(entries)}")
    print(f"entries with medians: {stats['with_medians']}")
    print(f"missing dictionary rows: {stats['missing_dictionary']}")
    print(f"default pinyin applied: {stats['default_pinyin']}")
    print(f"default radical applied: {stats['default_radical']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI surface
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
