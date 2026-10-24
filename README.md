<div align="center">

<img src="assets/images/icon.png" alt="KFusion" width="88">

# KFusion

A proxy client for **Android and Windows**, based on [FlClash](https://github.com/chen08209/FlClash) and the mihomo (Clash.Meta) core.

**English** · [简体中文](README_zh_CN.md)

[![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square)](LICENSE)

</div>

KFusion takes the strengths of two open-source clients:

- **FlClash** — Material You UI, a modern Riverpod/Drift Flutter architecture, profile editor and override scripts, live views of connections / requests / DNS / logs.
- **Karing** — all-format subscription compatibility, one routing template applied across subscriptions, and a beginner-friendly mode (planned; its design will be absorbed in later phases, see `NOTICE.md`).

KFusion deliberately ships **only Android and Windows**. The upstream macOS and Linux targets were removed in P0 to shrink the build, test and maintenance surface.

## Status

- **P0 (current)** — baseline: forked from FlClash v0.9.1, stripped to Android + Windows, rebranded to KFusion. Single core (mihomo) only; not yet built or verified on a real toolchain.
- **P1** — configuration hub: universal subscription import (Clash / sing-box / V2ray / generic Sub / share links) into an intermediate representation, plus a routing-template engine and a beginner mode.
- **P2** — dual core: a sing-box adapter next to mihomo.
- **P3** — sync (WebDAV / LAN / ZIP) and polish.

## Features (inherited from FlClash)

- **mihomo (Clash.Meta) core** with rule routing, proxy groups, latency tests, system proxy and TUN mode.
- **Profiles** from a subscription link or a file, with a built-in editor, override scripts, and custom rules, proxies and proxy groups.
- **Live views** of connections, requests, DNS queries and logs.
- **Material You design**: dynamic color, light and dark themes, layouts that adapt from phones to desktops.
- **Backup and restore** through WebDAV or a local file.
- **Platform touches**: a Quick Settings tile, per-app proxy and Android TV support on Android; a tray menu and global hotkeys on Windows.
- Deep links: `clash://`, `clashmeta://` and `flclash://` (kept for compatibility with upstream FlClash links).

## Download

No official KFusion release yet. Build from source (below), or use upstream
[FlClash releases](https://github.com/chen08209/FlClash/releases/latest) in the meantime.

| Platform | Packages |
| --- | --- |
| Android | APK for `arm64-v8a`, `armeabi-v7a` and `x86_64` |
| Windows 10 and later | Installer (`.exe`) or portable `.zip`, for x64 and ARM64 |

> The Android application id is `com.kfusion.app`, so KFusion installs as a separate app next to FlClash and does not inherit its data.

## Build from source

You need Flutter 3.47 (release builds use 3.47.6), Go 1.27 and Rust (via rustup). Android builds on any host; Windows builds on a Windows host.

```bash
git clone --recursive <KFusion repository>
cd src
flutter pub get
dart setup.dart android   # or windows
```

Packages land in `dist/`. The Go core and the Rust libraries are compiled as part of the Flutter build.

## License

KFusion is released under the [GPL-3.0 license](LICENSE), the same license as FlClash. See [NOTICE.md](NOTICE.md) for upstream attribution.

---

## 简介（简体中文）

KFusion 是一个只做 **Android + Windows** 的代理客户端，基于 [FlClash](https://github.com/chen08209/FlClash) 与 mihomo（Clash.Meta）内核：

- 取 FlClash 之长：Material You 界面、现代 Flutter 架构、配置编辑器与覆写脚本、连接/请求/DNS/日志实时视图；
- 取 Karing 之长（后续阶段吸收其设计）：全格式订阅兼容、一套路由模板套全部订阅、新手模式；
- 当前为 **P0 基线**：已剥离 macOS/Linux 并完成改名，仍为 mihomo 单核，尚未在真实工具链上构建验证；
- 许可证 GPL-3.0，上游署名见 [NOTICE.md](NOTICE.md)。
