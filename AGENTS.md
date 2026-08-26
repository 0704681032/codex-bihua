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

## 待办（2026-08-25 记录）：灰笔在黑笔旁「看起来突然加粗」

- [ ] 现象：播放到「阳」后两笔（日内短横）时，灰色横杠显得突然变粗。
- [ ] 已查明（像素级测量，非墨迹变粗）：灰色横杠厚度在所有播放状态下恒定
      （约 33~40 设备px / 11~13 逻辑px）；观感变化来自交接处——字库轮廓在
      笔画交接处互相重叠，全灰时同色重叠不可见，前序笔画变黑后灰色横杠的
      圆头端帽/重叠区以黑为衬底显形，读作「加粗」。
- [ ] 已试并搁置：两遍绘制（先灰后黑，黑压灰）——凸起仍在，且测量发现
      个别列灰色游程出现 12/11 断裂（疑似黑笔轮廓啃掉灰笔边缘的新伪影），
      该实验已回退，勿直接重用。
- [ ] 候选方向（明天从这里开始）：
      a) 灰色未完成笔画合并成单一 silhouette（`Path.combine(PathOperation.union)`）
         再填充，消除内部重叠与接缝；
      b) 调大灰色与黑色的明度差或给灰笔描一圈更浅的边，降低黑底衬出的轮廓感；
      c) 数据侧：生成字库时对交接处做去重叠处理（成本高，最后考虑）。
- [ ] 复现/测量方法：widget test 里 `RepaintBoundary` 只包 300×300 画布，
      `tester.runAsync(() => boundary.toImage(pixelRatio: 3))` 取 rawRGBA，
      按列统计 `strokeGrey(0xFFCFCFD4)` 竖向游程；注意 toImage 不包在
      runAsync 里会永久挂起。

### 后续可选优化

- 首页性能已解决（38MB→435KB 索引启动）。若需进一步优化详情页首开，可把分片粒度从 256 字降到 64 字。
- `definitions_zh.json` 约 3.9MB，如嫌大可截断 more 字段或按需分片。
- 数据再生成完整流程见 `docs/字库更新指南.md`（含源头更新、降级行为、测试校验）。


## 待办（2026-08-25）：灰笔在黑笔旁「看起来突然加粗」——三次修复尝试均已回退 ⚠️

- [ ] 现象：播放到「阳」后两笔（日内短横）时，灰色横杠显得突然变粗（像素级测量：
      灰杠厚度恒定 ~33-40 设备px，非真变粗；观感来自笔画交接处的轮廓重叠）。
- 尝试过并全部回退（本地已 reset 回 e6af5d0）：
      ① 两遍绘制（先灰后黑）——凸起仍在，且黑笔轮廓啃灰笔边缘出新伪影；
      ② 黑剪影外缘描底色细缝——切开红笔/灰笔与黑笔的连接，播放中整字碎裂；
      ③ **整字 union 剪影**（`Path.combine(union)` 合并全部轮廓做灰影层）——
        宿主 Skia 正常，但 **web/CanvasKit 的 `Path.combine(union)` 会吞掉字腔**
        （「日」的内部白洞被填实，完成态整个字变黑疙瘩）。
        探针实证（2026-08-25，Chrome headless + CanvasKit）：
        单笔原始路径字腔 G=255 透出 ✓；`Path.combine(union)` 后 G=0 被填 ✗；
        且 union 结果 fillType 在 web 为 nonZero、`contains(字腔点)=true`，
        宿主为 evenOdd、contains=false —— 同一代码两引擎几何结果不同。
- 结论/约束：**任何依赖 `Path.combine` 多笔合并的方案在 web 上不可用**，
  除非按平台分叉或先做多边形布尔自算。下次再攻此问题请从「不改几何、只改
  观感」入手（如灰墨透明度/色相微调、交接处抗性纹理）。
