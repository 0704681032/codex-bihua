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

- **Web E2E 需要 chromedriver 且大版本必须与 Chrome 一致**（本机 Chrome 151，brew 装的 152 会 `SessionNotCreatedException`）。匹配版已下载到：
  `/var/folders/5w/thhptkk90tn_xflxyg_nhqgm0000gn/T/opencode/cft151/chromedriver-mac-arm64/chromedriver`
  运行前先起服务：`chromedriver --port=4444 &`，再：
  `flutter drive -d chrome --headless --driver=test_driver/integration_test.dart --target=integration_test/e2e_test.dart`
  并设置 `NO_PROXY=127.0.0.1,localhost`（本机代理 127.0.0.1:7897 会劫持 localhost 导致 502）。
- **Android 打包必须给 Gradle 注入代理**（Gradle JVM 不读 HTTP_PROXY 环境变量，直连 maven central 被 403）：
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

### 后续可选优化

- 首页性能已解决（38MB→435KB 索引启动）。若需进一步优化详情页首开，可把分片粒度从 256 字降到 64 字。
- `definitions_zh.json` 约 3.9MB，如嫌大可截断 more 字段或按需分片。
- 数据再生成完整流程见 `docs/字库更新指南.md`（含源头更新、降级行为、测试校验）。

