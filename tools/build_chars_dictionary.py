#!/usr/bin/env python3

"""Build the app dictionary JSON from Make Me a Hanzi source files.

The script accepts either local file paths or HTTPS URLs for `graphics.txt`
and `dictionary.txt`, merges them on the shared `character` key, and writes
the project-specific array schema used by the Flutter app.
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
        required=True,
        help="Path or HTTPS URL to graphics.txt",
    )
    parser.add_argument(
        "--dictionary",
        required=True,
        help="Path or HTTPS URL to dictionary.txt",
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
    return parser.parse_args()


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


def load_dictionary(source: str) -> dict[str, dict]:
    result: dict[str, dict] = {}
    raw_text = read_text(source)
    for item in iter_json_lines(raw_text, source):
        char = str(item.get("character", "")).strip()
        if len(char) != 1:
            continue
        result[char] = item
    return result


def load_graphics(source: str) -> tuple[list[str], dict[str, list[dict]]]:
    order: list[str] = []
    result: dict[str, list[dict]] = {}
    raw_text = read_text(source)
    for item in iter_json_lines(raw_text, source):
        char = str(item.get("character", "")).strip()
        if len(char) != 1:
            continue

        strokes_raw = item.get("strokes")
        medians_raw = item.get("medians")
        if not isinstance(strokes_raw, list):
            continue
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

        if not strokes:
            continue

        order.append(char)
        result[char] = strokes
    return order, result


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
