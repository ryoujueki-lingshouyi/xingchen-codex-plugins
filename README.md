# 星辰 Codex 插件

星辰公司内部 Codex 插件仓库，用于开发、测试和分发商业宣传片剪辑辅助能力。

## 当前插件

- `xingchen-editor-copilot`：星辰剪辑助手 V0.1，提供项目初始化、素材盘点流程、环境检查和交付质检模板。

V0.1 优先减少剪辑师的机械工作，不声称能够自动完成成片，也不直接修改 Premiere 或 DaVinci Resolve 正式工程。

## 仓库结构

```text
.agents/plugins/marketplace.json
plugins/
  xingchen-editor-copilot/
    .codex-plugin/plugin.json
    skills/
    scripts/
    assets/
```

## 安装

首次添加星辰插件市场：

```powershell
codex plugin marketplace add ryoujueki-lingshouyi/xingchen-codex-plugins --ref main
```

然后在 Codex 桌面端的 Plugins 页面中，从“星辰内部插件”安装 `xingchen-editor-copilot`。安装后开启新任务使用。

## 更新

刷新星辰插件市场：

```powershell
codex plugin marketplace upgrade xingchen-internal
```

刷新后在 Plugins 页面更新插件，并开启新任务加载新版本。

## 版本原则

- 新功能先由试验剪辑师在真实项目中验证。
- 只有确认节省时间且不降低成片质量的功能，才进入稳定版。
- 发布时同步更新 `.codex-plugin/plugin.json` 中的语义化版本号。
- 仓库不存放客户原始素材、剪辑工程、代理文件、导出成片或账号密钥。
