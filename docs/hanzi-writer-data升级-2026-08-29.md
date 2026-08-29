# 字形数据源升级：Make Me a Hanzi → hanzi-writer-data（2026-08-29）

## 结论

笔画/中线数据源从 makemeahanzi `graphics.txt` 升级为
[hanzi-writer-data](https://github.com/chanind/hanzi-writer-data) 2.0.1
（npm 同名包，Arphic Public License，与原数据同血缘、同坐标系、同 schema）。
**现有 9574 字的字符集、顺序、拼音/部首/例句元数据、笔画数全部保持不变**，
仅 6 个字的笔画数据被社区修复更新，运行时索引与参考分片字节级不变。

## 为什么升级

- 上游 makemeahanzi 本体已多年停滞；hanzi-writer-data 是其**活跃维护的
  派生数据集**，社区持续以 PR 修正笔顺/字形错误，本次升级即吸收这些修复。
- 格式逐字段同构（`strokes` SVG 轮廓数组 + `medians` 中线折线数组，
  y-up 坐标系），可直接替换，无需改任何 Flutter 侧解析代码。

## 本次实测差异（全量对拍 9574 字）

| 类别 | 数量 | 明细 |
|------|------|------|
| 几何完全一致 | 9568 | 字节级相同 |
| SVG 轮廓修复 | 5 | 瑤 袤 謠 遙 颻 |
| 仅中线修复 | 1 | 黧 |
| 笔画数变化 | 0 | strokeNames 合并（6807 字）不受影响 |
| 字符集缺失 | 0 | 现有全部字在新源中存在 |
| 新源多出的字 | 1 | 本次刻意不扩容（涉及字体子集重建） |

验证锚点：`十` 竖笔中线仍为 y-up（起点 y > 终点 y）；`阳` 仍为 6 笔，
金样矩阵零变化。

## 升级方式（已固化进脚本）

`tools/build_chars_dictionary.py` 新增升级模式：`--hanzi-writer-data`
提供每字 JSON 目录，`--upgrade-from` 指向现有 `chars_3500.json` 以锁定
字符集/顺序并继承拼音、部首、examples 元数据；新源缺字即硬失败，
并打印 identical/svg/median/count 差异报告。

```bash
# 数据源（npmmirror 直连即可，无需代理）：
curl -sL -o tools/cache/hwdata.tgz \
  "https://registry.npmmirror.com/hanzi-writer-data/-/hanzi-writer-data-2.0.1.tgz"
mkdir -p tools/cache/hwdata && tar -xzf tools/cache/hwdata.tgz -C tools/cache/hwdata

# 升级 + 重拆（顺序固定）：
py tools/build_chars_dictionary.py \
  --hanzi-writer-data tools/cache/hwdata/package \
  --upgrade-from assets/data/chars_3500.json
py tools/split_chars_data.py --shard-size 64
py tools/split_reference_data.py
```

> 传统模式（`--graphics` + `--dictionary`）保持不变，两种模式互斥。
> Windows 上 python 走 `py` 启动器；`tools/cache/` 已在 .gitignore。

## 后续维护

- hanzi-writer-data 发版后重跑上面三步即可增量吸收新修复；升级模式的
  差异报告会先告诉你这次会动哪些字，`stroke count changed` 非空时需人工
  复核（笔数变化会导致该字 strokeNames 不再合并，回退几何分类器）。
- 若要扩字符集（吸收新源多出的字或 8105 全表），需同步重跑
  `tools/build_font_subset.py`（新字符进 Noto Sans SC 子集，否则 tofu）
  并重拆参考分片，单独立项。
