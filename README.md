# Codex Token Monitor

一个原生 macOS WidgetKit 小组件，可从桌面右键的“小组件”入口添加。它不会悬浮在其他应用上方，也没有普通窗口的关闭按钮。

轻量伴随 App 每 15 分钟从本机已登录的 Codex app-server 与本机当天会话日志读取一次，并把快照交给沙盒内的小组件展示。不上传 Token、会话正文或认证信息，也不会调用模型消耗 Codex Token。

## 展示口径

- `额度剩余`：只显示官方剩余百分比。官方没有返回绝对 Token 总额，且额度消耗不是原始 Token 的简单比例，因此不显示误导性的“剩余 M”。
- `下次重置`：官方账户接口返回的当前额度窗口重置时间。
- `账户累计` / `今日消耗`：官方账户 Token 用量汇总与 UTC 日桶。
- `当前最高消耗任务`：本机当天、最近 3 小时有更新的 Codex 会话中，最新累计 Token 最大的一项；仅读取 `token_count` 事件，不读取或显示会话正文。

## 安装与使用

需要 macOS 14 或更高版本、Xcode Command Line Tools，以及
[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```zsh
git clone https://github.com/ElLLIEXIAO/codex-token-monitor.git
cd codex-token-monitor
zsh scripts/build-native-widget.sh
open ".xcode-derived/Build/Products/Release/Codex Token.app"
```

如需长期使用，可将构建好的 `Codex Token.app` 拖入 `/Applications`。

首次使用先打开一次 `Codex Token`，并让它保持运行；然后在桌面空白处右键 → “编辑小组件” → 搜索 `Codex Token` → 选择中号或大号。伴随 App 约每 15 分钟更新一次本地快照，WidgetKit 的实际刷新时刻由 macOS 调度。

## 隐私

所有数据均在本机读取和缓存。应用不会上传认证信息、Token 统计或会话正文，也不会调用模型，因此刷新小组件本身不消耗 Codex 额度。

## License

[MIT](LICENSE)
