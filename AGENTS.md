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

### Mac 端到端测试 / Android 打包备注（2026-08-24 踩坑记录）

- **Web E2E 需要 chromedriver 且大版本必须与 Chrome 一致**（2026-08-26 更新：Chrome 已升 152，brew 的 chromedriver 152 匹配，直接用 `/opt/homebrew/bin/chromedriver` 即可）。运行前先起服务：`chromedriver --port=4444 &`，再：
  `flutter drive -d chrome --headless --driver=test_driver/integration_test.dart --target=integration_test/e2e_test.dart`
  并设置 `NO_PROXY=127.0.0.1,localhost`（本机代理 127.0.0.1:7897 会劫持 localhost 导致 502）。
  ⚠️ 踩坑（2026-08-26）：若 4444 端口残留旧版本 chromedriver（`curl 127.0.0.1:4444/status` 看版本），`flutter drive` 会无限挂起（headless Chrome 停在 `data:,` 空白页、frontend_server 0 CPU）——先 `pkill -f "chromedriver --port=4444"` 再起新版。全套 8 用例正常约 1~2 分钟跑完。
- **Android 打包必须给 Gradle 注入代理**（Gradle JVM 不读 HTTP_PROXY 环境变量，直连 maven central 被 403），完整流程见 `docs/Android打包指南.md`：
  ```bash
  export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"
  flutter build apk --release [--split-per-abi]
  ```
- 本机无 AVD 镜像，`flutter emulators` 为空；Android 真机集成测试（app_flow_test.dart）待有设备再跑。

## Windows 已知限制

- 未装 Visual Studio C++ 工具链 → 不能构建 Windows 桌面应用
- 未装 Android SDK → 不能构建 Android
- Web（Chrome/Edge）可用 ✅

## 明日待办（2026-08-24 已完成 ✅）

- [x] 端到端测试补齐并全绿：integration_test/e2e_test.dart 8 个用例（深链冷启动/首页渲染/搜索全量数据/播放状态机/速度切换/TTS/词卡/浏览器返回前进联动），`flutter drive -d chrome --headless` 全过
- [x] 修复 setSpeed 钳制上限 3.0 与「快速」预设 3.2 冲突（快速永远无法选中的 bug）
- [x] 修复 Web 引擎分段推送裸 `/detail`、`/` 路由时落到错误页的问题（现统一落首页，深链详情页点返回不再见到"详情页参数缺失"）
- [x] 统一深链 URL 格式为 `#/detail/<字>`（与引擎写法一致；旧 `#/char/<字>` 链接仍兼容）
- [x] Android 打包打通：app-release.apk 64.8MB + 按 ABI 拆分（arm64 32.9MB / armeabi-v7a 30.4MB / x86_64 34.3MB）

- [x] Mac（公司）Flutter 路径补充到上表：`/opt/homebrew/share/flutter/bin/flutter`（已在 PATH）
- [x] 动画节奏：按笔画长度归一化时长 —— `StrokePlayerKey.strokeWeights` + 控制器按权重推进，权重由中轴线长度归一化（0.3~1.0）
- [x] 组词库扩充 —— CC-CEDICT → `assets/data/words.json`（6122 字，带调拼音，儿童过滤），`tools/build_words_dictionary.py`；详情页懒加载
- [x] 汉字解释中文释义 —— 新华字典数据 → `assets/data/definitions_zh.json`（7451 字），`tools/build_definitions_zh.py`；英文释义降为补充
- [x] 笔画名称分类器 —— 双轨制：cnchar-order 权威名称（6807 字）+ `StrokeClassifier` 几何回退（重构为独立模块）；32 字官方金样集回归测试通过
- [x] 浏览器返回键联动 —— URL pushState + popstate 监听 + NavigatorObserver 统一同步（`app.dart` / `web_url_web.dart`）

## 已解决（2026-08-27）：release 构建 web 中文豆腐块 ☒ ✅

- 现象：`flutter build web --release` 后大量汉字渲染成 ☒（且每个浏览器不同：
  无头直连 Chrome 完美、走代理/内嵌浏览器烂一片），debug `flutter run` 却正常。
- 根因：CanvasKit 渲染器的中文回退字体在运行时从 fonts.gstatic.com 按
  unicode 区块分块下载，墙内/代理下部分区块静默失败 → 命中区块的字全部
  tofu。debug 会话曾正常纯属缓存运气。这是墙内真实用户必踩的生产级问题。
- 修复：中文随包字体。`tools/build_font_subset.py` 从 Noto Sans SC 可变字体
  （下载地址在脚本头部，需代理）实例化 wght 400/700 并按应用实际字符集
  （lib 字符串 + 字库/组词/释义 JSON + 拼音音标 + CJK 标点，1.1 万字符）
  裁剪出 ~3.9MB×2 的 TTF，经 pubspec `fonts:` 进 FontManifest，主题设
  `fontFamily: 'NotoSansSC'`。不再依赖 CDN，任何网络确定性渲染。
  ⚠️ 新增 UI 文案/字库数据后需重跑该脚本，否则新字符仍走 CDN 回退。
- 注意：`flutter run` debug 服务器连续重启后可能进入坏状态——对它自己
  拉起的 Chrome 正常、对其它浏览器静默白屏（main.dart.js 仅 8.7KB stub、
  控制台零错误、Dart main 不执行）。给用户演示/测试一律用
  `flutter build web --release` + 静态服务器（如 `python3 -m http.server
  8766 -d build/web`）。
- 已知小问题（不阻塞）：应用已打开时在地址栏改 hash（如 /#/home →
  /#/detail/阳）不会切换路由；冷启动深链和应用内导航正常。

## 已解决（2026-08-27）：灰笔在黑笔旁「看起来突然加粗」✅

- 根因（像素级取证）：灰杠厚度全程恒定（~33-40 设备px），非真变粗。待写笔画
  用**不透明**浅灰（#CFCFD4）且绘制在黑笔之后，圆头端帽伸进黑笔画范围，
  在黑底上显形成亮灰轮廓，读作「加粗」。
- 最终方案：**幽灵墨图层**（不改几何、纯合成）。待写笔画画进一个
  `saveLayer` 图层，层内用不透明墨色 strokeBlack（重叠处颜色均匀、交接处
  不显形），整层以 16.5% alpha 叠加（`AppPalette.strokeGhost =
  Color(0x2B24242A)`，saveLayer 只取其透明度）。合成数学：
  叠底色 ≈ #CFD0D3（与旧灰观感一致）；叠黑笔精确还原成墨色（端帽隐形）；
  叠红笔加深 ~13%（读作墨层叠合）；完成态不建图层，逐像素不变。
- 历史教训（前三次尝试均回退，勿重走）：
  ① 两遍绘制（先灰后黑）——凸起仍在 + 黑啃灰新伪影；
  ② 黑剪影外缘描底色细缝——播放中整字碎裂；
  ③ `Path.combine(union)` 整字剪影——**web CanvasKit 吞字腔**（fillType
     nonZero/evenOdd 与宿主 Skia 分歧，同一代码两引擎几何结果不同）。
  约束不变：任何依赖 `Path.combine` 多笔合并的方案在 web 上不可用。
- 验证闭环（2026-08-27 全绿）：
  - 宿主金样矩阵：`flutter test --update-goldens` 重生成 yang/字 两套，
    14_complete 与基线**逐字节一致**；idle 观感一致；交接态端帽消失。
  - 全量 `flutter test` 62/62。
  - **CanvasKit 像素探针** `integration_test/canvas_probe_test.dart`
    （flutter drive headless Chrome）：透明度真引擎生效、左右端帽压黑区
    精确还原墨色、三种状态「日」字腔全程镂空（防 union 吞腔回归）。
  - ⚠️ 探针/集成测试取字例数据必须走 `AssetDictionaryRepository` 分片链路
    —— chars_3500.json 已不在 pubspec 资产清单，web 上 rootBundle 404
    （宿主测试 dart:io 直读文件所以不暴露）。
- 已知微小观感变化：灰笔经过处米字格红虚线隐约透出（原被不透明灰盖住，
  幅度 ~16%，似铅笔稿压辅助线）；灰笔与红笔交接处红轻微加深（即修复目标）。

### 后续可选优化

- 首页性能已解决（38MB→435KB 索引启动）。若需进一步优化详情页首开，可把分片粒度从 256 字降到 64 字。
- `definitions_zh.json` 约 3.9MB，如嫌大可截断 more 字段或按需分片。
- 数据再生成完整流程见 `docs/字库更新指南.md`（含源头更新、降级行为、测试校验）。
