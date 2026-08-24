# Android 打包指南

> 适用环境：Mac（公司机，Homebrew Flutter）。Windows 机器无 Android SDK，打不了包。
> 最后验证：2026-08-24，Flutter 3.41.1 stable。

## 前置条件

| 依赖 | 检查命令 | 说明 |
|------|---------|------|
| Flutter（在 PATH） | `flutter --version` | 本机 `/opt/homebrew/bin/flutter` |
| JDK | `java -version` | 当前 OpenJDK 22 可用 |
| Android SDK | `flutter doctor` | 需接受对应 SDK Platform 许可 |

## 关键坑：必须给 Gradle 注入代理

Gradle JVM **不读** shell 的 `HTTP_PROXY/HTTPS_PROXY` 环境变量，直连 maven central 会
被 403。打包前必须通过 `GRADLE_OPTS` 注入 JVM 代理参数：

```bash
export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"
```

端口号是本机 Clash 代理端口，换网络环境时先确认代理在跑。

## 打包命令

```bash
# 通用包（单 APK，所有 ABI，体积最大 ~65MB）
flutter build apk --release

# 按 ABI 拆分（推荐分发用）
flutter build apk --release --split-per-abi
```

## 产物位置

```
build/app/outputs/flutter-apk/
├── app-release.apk            # 通用包 (~64.8MB)
├── app-arm64-v8a-release.apk      # 现代 Android 手机 (~32.9MB) ← 主力
├── app-armeabi-v7a-release.apk    # 老设备 (~30.4MB)
└── app-x86_64-release.apk         # 模拟器 (~34.3MB)
```

## 完整一键流程（复制即用）

```bash
cd /Users/jyy/Documents/opensources/codex-bihua
export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"
flutter clean && flutter pub get
flutter build apk --release --split-per-abi
ls -lh build/app/outputs/flutter-apk/*.apk
```

> 注意：`flutter run` 会话可以同时存在，不冲突；但不要并行跑两个 build。

## 安装到真机自测

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

本机无 AVD（`flutter emulators` 为空），只能真机装。

## 版本号

版本在 `android/app/build.gradle.kts` 中由 Flutter 默认配置管理：
`versionCode/versionName` 取自 `pubspec.yaml` 的 `version:` 字段，发版前记得递增。

## 常见问题

| 症状 | 原因 | 处理 |
|------|------|------|
| Could not GET maven central / 403 | Gradle 未走代理 | 确认 `GRADLE_OPTS` 已 export 且代理存活 |
| Gradle daemon 卡住 | 上次构建残留 | `./gradlew stop` 或 `pkill -f gradle` 后重试 |
| License not accepted | SDK 许可未签 | `flutter doctor --android-licenses` |
| 换机器后签名不一致 | debug key 不同 | release 当前用 debug 签名，仅自测用；正式发布需配 keystore |

## 待办

- [ ] 正式发布前生成独立 keystore 并在 `build.gradle.kts` 配置 signingConfig（当前 release 包是 debug 签名，不能上架）
