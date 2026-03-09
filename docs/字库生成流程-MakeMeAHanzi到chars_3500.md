# 字库生成流程：Make Me a Hanzi 到 `chars_3500.json`

## 1. 目的

这份文档说明当前项目里的汉字笔顺数据是怎么来的，以及原始数据如何整理成应用最终使用的 JSON 文件。

目标文件：

- `/Users/jyy/Documents/bihua/assets/data/chars_3500.json`

当前状态：

- 文件实际包含 `9565` 个汉字条目
- 文件名仍叫 `chars_3500.json`，这是历史命名，不代表当前只有 3500 字

---

## 2. 重要说明

仓库里**没有保留当时的数据转换脚本**，所以这份文档是根据以下信息反推整理出的可复现流程：

- 当前生成后的字库文件结构
- 应用内字库解析代码
- 数据来源说明文件
- Make Me a Hanzi 的公开数据格式

也就是说，这份文档描述的是**当前项目实际采用的数据结构与转换逻辑**，足够让后续重新写一份生成脚本。

---

## 3. 原始来源

上游数据来自 `Make Me a Hanzi`：

- 仓库：`https://github.com/skishore/makemeahanzi`
- 图形数据：`graphics.txt`
- 字典数据：`dictionary.txt`
- 许可证：`CC BY-SA 4.0`

当前仓库中的来源说明：

- `/Users/jyy/Documents/bihua/assets/data/LICENSE.md`

原始链接：

- `https://raw.githubusercontent.com/skishore/makemeahanzi/master/graphics.txt`
- `https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt`
- `https://raw.githubusercontent.com/skishore/makemeahanzi/master/LICENSE`

---

## 4. 原始数据里真正有用的部分

### 4.1 `graphics.txt`

这部分提供了“怎么画这个字”的核心信息，主要用于笔顺展示和播放：

- 汉字本身
- 每一笔的 SVG 路径
- 每一笔的中线点序列

在本项目中最终映射为：

- `strokes[].svgPath`
- `strokes[].medianPoints`

### 4.2 `dictionary.txt`

这部分提供“这个字的字典信息”，用于搜索和展示：

- 汉字本身
- 拼音等字典属性
- 可用于补充部首、释义或展示文案的信息

在本项目中最终映射为：

- `char`
- `pinyin`
- `radical`
- `examples`

注意：

- 当前项目最终写入的 `examples` 很多时候是空数组
- `radical` 和 `pinyin` 在最终 JSON 中必须有值；如果原始记录不足，转换阶段需要补默认值或做推导

---

## 5. 最终 JSON 结构

应用读取的字库顶层必须是一个数组，这一点在字库仓储里有显式校验：

- `/Users/jyy/Documents/bihua/lib/features/dictionary/data/asset_dictionary_repository.dart`

单个条目的目标结构如下：

```json
{
  "char": "字",
  "pinyin": "zi4",
  "radical": "子",
  "strokeCount": 6,
  "strokes": [
    {
      "order": 1,
      "svgPath": "M ...",
      "medianPoints": [[x1, y1], [x2, y2]]
    }
  ],
  "examples": []
}
```

说明：

- `char`：必须是单个汉字
- `strokeCount`：最终应和 `strokes.length` 一致
- `strokes`：不能为空，否则应用会退回到合成占位笔画
- `medianPoints`：不是强制字段，但如果有，播放器效果会明显更准确

---

## 6. 字段映射关系

### 6.1 从图形数据到项目字段

- 原始汉字 -> `char`
- 原始每笔 path -> `strokes[].svgPath`
- 原始每笔中线 -> `strokes[].medianPoints`
- 当前笔顺序号 -> `strokes[].order`

### 6.2 从字典数据到项目字段

- 原始拼音 -> `pinyin`
- 原始部首/可推导部件 -> `radical`
- 原始释义或示例信息 -> `examples`

### 6.3 在项目中额外计算的字段

- `strokeCount`：通常直接取 `strokes.length`
- `flipYAxis`：**当前 JSON 里一般不显式写入**，应用在运行时根据 `medianPoints` 自动推断

`flipYAxis` 的推断位置：

- `/Users/jyy/Documents/bihua/lib/features/dictionary/domain/character_entry.dart`

逻辑是：

- 如果 JSON 里显式给了 `flipYAxis`，就按文件值走
- 如果没给，但某个字存在 `medianPoints`，应用默认把它当作需要 Y 轴翻转的数据源

---

## 7. 一次完整的转换流程

可以把整个转换理解成 7 步：

1. 下载 `graphics.txt` 和 `dictionary.txt`
2. 分别解析成“按汉字索引”的内存结构
3. 以汉字为 key 合并两份数据
4. 为每个字生成项目目标结构
5. 过滤掉非法条目
6. 统一排序并输出成 JSON 数组
7. 保存为 `/Users/jyy/Documents/bihua/assets/data/chars_3500.json`

更细一点：

1. 读取 `graphics.txt`
- 对每个字抽取图形记录
- 获取每一笔的 `svgPath`
- 获取每一笔的 `medianPoints`

2. 读取 `dictionary.txt`
- 对每个字抽取字典记录
- 获取拼音
- 获取部首或可用于补充部首的字段
- 如果没有可用示例，`examples` 可以先置空

3. 合并规则
- 以汉字本身作为唯一 key
- 图形数据优先，因为没有图形就无法播放笔顺
- 字典数据用于补充 `pinyin`、`radical`、`examples`

4. 构造目标条目
- `char` = 当前汉字
- `strokeCount` = 笔画列表长度
- `strokes[i].order` = `i + 1`
- `strokes[i].svgPath` = 原始路径
- `strokes[i].medianPoints` = 原始中线点
- `examples` = 没有则写 `[]`

5. 数据清洗
- 仅保留单个汉字字符
- 去掉空路径
- 去掉空白拼音/部首时补默认值
- 保证 `strokeCount > 0`

6. 序列化
- 输出为 JSON 数组，不是对象字典
- 保持 UTF-8 编码
- 建议不压缩字段名，方便后续直接排查

7. 落盘
- 覆盖写入 `/Users/jyy/Documents/bihua/assets/data/chars_3500.json`

---

## 8. 当前应用是怎么读取它的

应用不是直接拿原始上游数据跑，而是只认项目自己的 JSON 结构。

读取入口：

- `/Users/jyy/Documents/bihua/lib/features/dictionary/data/asset_dictionary_repository.dart`

解析入口：

- `/Users/jyy/Documents/bihua/lib/features/dictionary/domain/character_entry.dart`
- `/Users/jyy/Documents/bihua/lib/features/dictionary/domain/stroke_path.dart`

当前读取逻辑有几个关键点：

1. 顶层必须是数组  
否则会抛出：

```text
chars_3500.json 必须是数组
```

2. `char` 必须是单个字符  
不是单字的记录会被跳过。

3. `strokeCount` 可以补  
如果文件里没填，会优先取 `strokes.length`。

4. `strokes` 不能为空  
如果为空，仓储会回退到 `_generateSyntheticStrokes(...)` 生成占位笔画。

5. `pinyin` 和 `radical` 可以补默认值  
当前默认值逻辑在仓储里是：

- 空拼音 -> `zi4`
- 空部首 -> `一`

这也是为什么最终正式数据里尽量要把这两个字段写全，避免运行时兜底污染真实字库质量。

---

## 9. 为什么这份数据能支持“笔顺播放”

关键不只是 SVG path，还有 `medianPoints`。

原因：

- `svgPath` 更适合画出笔画轮廓
- `medianPoints` 更适合做“当前笔按顺序播放”的轨迹估计

项目里的播放画布会优先使用 `medianPoints` 来提取当前笔的部分路径，这样比单纯截 SVG path 更稳定：

- `/Users/jyy/Documents/bihua/lib/features/detail/presentation/widgets/stroke_canvas.dart`

这也是本次修复后笔顺播放明显更接近参考 App 的核心原因之一。

---

## 10. 为什么之前会“字不对、顺序不对”

这和数据生成有直接关系：

1. 如果用占位/合成笔画代替真实 path  
- 会出现“能播放，但字写错了”

2. 如果没有 `medianPoints`  
- 当前笔高亮只能粗糙截取 SVG path，播放观感会差

3. 如果数据坐标系方向没处理好  
- 会出现字形倒置、位置偏移、顺序看起来不对

本项目最终通过两件事解决：

- 换成真实字形数据
- 在运行时对含中线数据的字自动启用 `flipYAxis`

---

## 11. 如果以后要重新生成，建议的最小脚本职责

如果你后面打算把转换流程真正脚本化，建议脚本至少完成这些职责：

1. 下载或读取本地的 `graphics.txt` 与 `dictionary.txt`
2. 用汉字为 key 建立两个索引
3. 合并出项目目标结构
4. 校验 `strokeCount == strokes.length`
5. 校验每笔都至少有 `order + svgPath`
6. 输出 UTF-8 JSON 数组到目标文件
7. 打印统计信息：
- 总条目数
- 有 `medianPoints` 的条目数
- 缺失 `pinyin` 的条目数
- 缺失 `radical` 的条目数

---

## 12. 当前仓库里和字库最相关的文件

- `/Users/jyy/Documents/bihua/assets/data/chars_3500.json`
- `/Users/jyy/Documents/bihua/assets/data/LICENSE.md`
- `/Users/jyy/Documents/bihua/lib/features/dictionary/domain/stroke_path.dart`
- `/Users/jyy/Documents/bihua/lib/features/dictionary/domain/character_entry.dart`
- `/Users/jyy/Documents/bihua/lib/features/dictionary/data/asset_dictionary_repository.dart`
- `/Users/jyy/Documents/bihua/lib/features/detail/presentation/widgets/stroke_canvas.dart`

