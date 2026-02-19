# 中文汉字笔画应用（Flutter）

本项目实现了一个 Android 优先的中文汉字笔画应用首版，包含：

- 首页：1~20 汉字查询、拼音/笔画/部首筛选、汉字举例、易错汉字。
- 详情页：汉字笔顺展示、打开页面自动播放（慢速）、播放/暂停、上一笔/下一笔控制。
- 离线字库：`assets/data/chars_3500.json`（当前为 9565 个真实汉字笔画条目）。

## 目录

- `lib/features/home` 首页
- `lib/features/detail` 详情页与播放器
- `lib/features/dictionary` 字库模型、仓储、查询与过滤
- `assets/data` 离线数据
- `test` 单元测试与 Widget 测试

## 环境与运行

1. 安装 Flutter（建议 stable）。
2. 在项目根目录执行：

```bash
flutter pub get
flutter test
```

3. 按目标平台运行：

```bash
# Web（推荐本地调试）
flutter run -d chrome

# macOS
flutter run -d macos

# Android（需本机已安装 Android SDK/设备）
flutter run -d android
```

## Android 安装运行（首次配置）

如果执行 `flutter doctor -v` 出现 `Unable to locate Android SDK`，请按下面配置：

1. 安装 Android Studio，并在首次启动时安装 Android SDK 与 Command-line Tools。
2. 配置 SDK 路径（将路径替换为你本机实际路径）：

```bash
flutter config --android-sdk ~/Library/Android/sdk
```

3. 接受 Android 许可证：

```bash
flutter doctor --android-licenses
```

4. 再次检查环境：

```bash
flutter doctor -v
```

5. 连接真机（开启开发者模式与 USB 调试）或启动模拟器后运行：

```bash
flutter devices
flutter run -d android
```

## 关键行为

- 详情页默认状态：整字黑色。
- 打开详情页后自动进入播放，速度为慢速（`speed=0.6`）。
- 当前笔为红色，已播放笔画为黑色，未播放笔画为浅灰。

## 数据说明

- `assets/data/chars_3500.json` 已替换为真实数据（9565 个 CJK 字），不再使用合成占位笔画。
- 数据来源：Make Me a Hanzi（`graphics.txt` + `dictionary.txt`）。
- 许可证说明见：`assets/data/LICENSE.md`。

## 常见问题

- 页面效果看起来和代码不一致（常见于 web 缓存）：

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

然后在浏览器执行强刷：`Cmd + Shift + R`。
