<div align="center">

<img src="assets/images/icon.png" alt="KFusion" width="88">

# KFusion

只做 **Android 与 Windows** 的代理客户端，基于 [FlClash](https://github.com/chen08209/FlClash) 与 mihomo（Clash.Meta）内核。

[English](README.md) · **简体中文**

</div>

## 定位

- **FlClash 的皮与工程**：Material You 动态取色、自适应布局、Riverpod + Drift 架构、配置内置编辑器与覆写脚本、连接/请求/DNS/日志实时视图、WebDAV 备份恢复。
- **Karing 的脑子（后续阶段吸收设计）**：全格式订阅兼容（Clash / sing-box / V2ray / 通用 Sub / 分享链接）、一套路由模板套全部订阅、新手模式、多端同步。
- **只做两端**：P0 已删除上游的 macOS / Linux 目标，构建、测试与维护面只剩 Android + Windows。

## 状态

- **P0（当前）**：fork FlClash v0.9.1 → 平台剥离 + 改名 KFusion。mihomo 单核；尚未经真实工具链（Flutter/Go/Rust）构建验证。
- **P1**：配置中台（万能导入 → 中间表示 → 路由模板引擎）+ 新手模式。
- **P2**：双核（新增 sing-box 适配器）。
- **P3**：同步（WebDAV / 局域网 / ZIP）与打磨。

Android 应用 ID 为 `com.kfusion.app`，与 FlClash 是两个独立应用，数据不互通。深链接 `flclash://` 保留兼容。

## 许可证

GPL-3.0，见 [LICENSE](LICENSE)；上游署名见 [NOTICE.md](NOTICE.md)。
