# Data License Notes

## 字形与笔顺（chars_3500.json → chars_index.json + shards/）

- 由 [Make Me a Hanzi](https://github.com/skishore/makemeahanzi) 的 `graphics.txt` 与 `dictionary.txt` 生成，包含真实笔画路径与笔顺中线数据。
- 原始数据仓库采用 `CC BY-SA 4.0`，请在分发时保留来源与许可证说明。

## 笔画名称（stroke_names.json / shards 内 strokeNames 字段）

- 由 [cnchar](https://github.com/theajack/cnchar) 的 `cnchar-order` 字典（`stroke-order-jian.json`，MIT License）生成。
- 共用字母的歧义笔画对（如 横撇/横钩）在运行时由 `StrokeClassifier.refineName` 依据中轴几何消解。

## 组词（words.json）

- 由 [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict) 生成（`CC BY-SA 4.0`），仅保留简体 2~4 字词并做儿童内容过滤。
- 拼音由带调数字格式转换为声调符号。

## 中文释义（definitions_zh.json）

- 来自 [pwxcoo/chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua)（MIT License）的 `data/word.json`（新华字典抓取整理数据）。
