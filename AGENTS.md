# 开发环境备注

## Flutter SDK 路径（两台电脑不同，注意区分）

| 设备 | Flutter 路径 | 备注 |
|------|-------------|------|
| Windows（家用） | `E:\flutter\bin` | 不在 PATH 中，需用完整路径调用，如 `/e/flutter/bin/flutter.bat` |
| Mac（公司） | TODO: 明天补充实际路径 | 待确认 |

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

## 明日待办（2026-08-24 继续）

- [ ] Mac（公司）Flutter 路径补充到上表
- [ ] 动画节奏：按笔画长度归一化时长（短笔画如"点"应更快），目前每笔等时长
- [ ] 组词库扩充：目前只有 母/笔/火/马/万 有真实词语，其余显示"词库建设中"；考虑引入 CC-CEDICT 等词库按需生成
- [ ] 汉字解释目前是数据里的英文释义（chars_3500.json 的 examples 字段），可考虑接中文释义数据源
- [ ] 笔画名称分类器是几何启发式（detail_page.dart `_classifyStroke`），复杂折笔（如 竖弯钩、横折折撇）可能误判，可抽查常用字
- [ ] 浏览器返回键未与 Flutter 路由联动（hash 用 replaceState，只保证刷新正确）

