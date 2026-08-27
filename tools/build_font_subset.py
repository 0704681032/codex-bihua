#!/usr/bin/env python3
"""Build the bundled CJK web font (Noto Sans SC) for release builds.

Why: the Flutter web CanvasKit renderer normally fetches Noto fallback
fonts in unicode-range chunks from fonts.gstatic.com at runtime. Behind
the GFW / a flaky proxy some chunks fail silently and those characters
render as tofu (☒). Bundling a subset font into FontManifest removes the
CDN dependency entirely — deterministic on every network.

Source font (download via proxy if needed, ~18 MB variable TTF):
  https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf

Corpus = every character the app can ever show:
  * lib/**/*.dart            — UI string literals (comments ride along,
                                harmless)
  * packaged JSON data       — chars_index / radicals / stroke_names /
                                references shards / words (raw, decoded)
  * pinyin tone letters      — ā á ǎ à ē é ě è ō ó ǒ ò ū ú ǔ ù ǖ ǘ ǚ ǜ
  * full CJK punctuation and fullwidth forms blocks

Usage:
  python3 tools/build_font_subset.py <NotoSansSC[wght].ttf> <out_dir>

Output: NotoSansSC-Regular.ttf (wght 400) + NotoSansSC-Bold.ttf (wght 700),
static instances so Flutter's weight matching behaves predictably
(variable-font axes are not applied by ThemeData font weights).

After changing the font files, run `flutter build web --release` again.
New UI strings / data characters need a re-run of this script, or they
fall back to the CDN chunks again.
"""

import sys
from pathlib import Path

from fontTools import subset
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.ttLib import TTFont

REPO = Path(__file__).resolve().parent.parent

DATA_FILES = [
    "assets/data/chars_index.json",
    "assets/data/radicals.json",
    "assets/data/stroke_names.json",
    "assets/data/words.json",
]
REFERENCE_DIR = "assets/data/references"
EXTRA_TEXT = (
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "āáǎàēéěèōóǒòūúǔùǖǘǚǜü"
    "·—…''\"\"、。，：；！？（）《》〈〉【】〖〗〔〕"
    "～～￥％℃〇一二三四五六七八九十"
)


def collect_corpus() -> str:
    parts = [EXTRA_TEXT]
    for rel in DATA_FILES:
        path = REPO / rel
        if path.exists():
            parts.append(path.read_text(encoding="utf-8"))
    for path in sorted((REPO / REFERENCE_DIR).rglob("*.json")):
        parts.append(path.read_text(encoding="utf-8"))
    for path in sorted((REPO / "lib").rglob("*.dart")):
        parts.append(path.read_text(encoding="utf-8"))
    corpus = "".join(dict.fromkeys("".join(parts)))  # unique, order stable
    return corpus


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    variable_ttf = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    corpus = collect_corpus()
    print(f"corpus: {len(corpus)} unique chars")
    corpus_file = out_dir / "_corpus.txt"
    corpus_file.write_text(corpus, encoding="utf-8")

    for weight, name in ((400, "Regular"), (700, "Bold")):
        font = TTFont(variable_ttf)
        instantiateVariableFont(font, {"wght": weight}, inplace=True)
        static_path = out_dir / f"_instance_{name}.ttf"
        font.save(static_path)

        out_path = out_dir / f"NotoSansSC-{name}.ttf"
        subset.main(
            [
                str(static_path),
                f"--output-file={out_path}",
                f"--text-file={corpus_file}",
            ]
        )
        static_path.unlink()
        print(f"{out_path.name}: {out_path.stat().st_size / 1024:.0f} KB")
    corpus_file.unlink()


if __name__ == "__main__":
    main()
