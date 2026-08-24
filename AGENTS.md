# 开发环境备注

## Flutter SDK 路径（两台电脑不同，注意区分）

| 设备 | Flutter 路径 | 备注 |
|------|-------------|------|
| Windows（家用） | `E:\flutter\bin` | 不在 PATH 中，需用完整路径调用，如 `/e/flutter/bin/flutter.bat` |
| Mac（公司） | `/opt/homebrew/share/flutter/bin/flutter` | Homebrew 安装，`flutter` 已在 PATH，可直接调用 |

## 国内镜像（Windows 下 pub get / run 前先设置）

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 常用命令

```bash
# Web 启动（Chrome）
/e/flutter/bin/flutter.bat run -d chrome --web-port 8765

# 拉依赖
/e/flutter/bin/flutter.bat pub get
```

## Windows 已知限制

- 未装 Visual Studio C++ 工具链 → 不能构建 Windows 桌面应用
- 未装 Android SDK → 不能构建 Android
- Web（Chrome/Edge）可用 ✅

## 明日待办（2026-08-24 已完成 ✅）

- [x] Mac（公司）Flutter 路径补充到上表：`/opt/homebrew/share/flutter/bin/flutter`（已在 PATH）
- [x] 动画节奏：按笔画长度归一化时长 —— `StrokePlayerKey.strokeWeights` + 控制器按权重推进，权重由中轴线长度归一化（0.3~1.0）
- [x] 组词库扩充 —— CC-CEDICT → `assets/data/words.json`（6122 字，带调拼音，儿童过滤），`tools/build_words_dictionary.py`；详情页懒加载
- [x] 汉字解释中文释义 —— 新华字典数据 → `assets/data/definitions_zh.json`（7451 字），`tools/build_definitions_zh.py`；英文释义降为补充
- [x] 笔画名称分类器 —— 双轨制：cnchar-order 权威名称（6807 字）+ `StrokeClassifier` 几何回退（重构为独立模块）；32 字官方金样集回归测试通过
- [x] 浏览器返回键联动 —— URL pushState + popstate 监听 + NavigatorObserver 统一同步（`app.dart` / `web_url_web.dart`）

### 后续可选优化

- 首页性能已解决（38MB→435KB 索引启动）。若需进一步优化详情页首开，可把分片粒度从 256 字降到 64 字。
- `definitions_zh.json` 约 3.9MB，如嫌大可截断 more 字段或按需分片。
- 数据再生成完整流程见 `docs/字库更新指南.md`（含源头更新、降级行为、测试校验）。

