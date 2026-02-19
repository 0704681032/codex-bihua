# 中文汉字笔画应用（Flutter）

本项目实现了一个 Android 优先的中文汉字笔画应用首版，包含：

- 首页：1~20 汉字查询、拼音/笔画/部首筛选、汉字举例、易错汉字。
- 详情页：汉字笔顺展示、播放/暂停、上一笔/下一笔控制。
- 离线字库：`assets/data/chars_3500.json`（当前为 9565 个真实汉字笔画条目）。

## 目录

- `lib/features/home` 首页
- `lib/features/detail` 详情页与播放器
- `lib/features/dictionary` 字库模型、仓储、查询与过滤
- `assets/data` 离线数据
- `test` 单元测试与 Widget 测试

## 运行

1. 安装 Flutter（建议稳定版）。
2. 在项目根目录执行：

```bash
flutter pub get
flutter test
flutter test integration_test
flutter run
```

## 说明

- 当前仓库通过手工初始化 Flutter 代码结构；若你本机首次运行报缺失平台目录，可执行：

```bash
flutter create .
```

执行后会补齐 `android/ios/...` 目录，不会覆盖已实现的 `lib/` 业务代码。

- `assets/data/chars_3500.json` 来自 Make Me a Hanzi 数据集并已预生成，可直接离线查询与播放笔顺。
