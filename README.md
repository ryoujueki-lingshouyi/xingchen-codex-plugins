# 星辰 Codex 插件

星辰 Codex 插件仓库，用于开发、测试和分发商业宣传片智能素材筛选能力。

## 当前插件

- `xingchen-editor-copilot`：星辰智能素材助手 V1.0，提供项目创建、素材安全导入、文件校验、镜头索引、内容理解、自然语言检索和候选素材筛选流程。

V1.0 的终点是把可追溯的候选镜头交给剪辑师，不生成粗剪时间线、不自动完成成片，也不修改 Premiere 或 DaVinci Resolve 正式工程。

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

## V1.0 首测指令

安装后开启新任务，依次使用自然语言指令：

1. `创建项目：<项目名称>`
2. `补充项目需求：<客户要求和筛选重点>`
3. `把 <素材路径> 导入当前项目`
4. `开始筛选素材`
5. `找出 <人物、场景、动作或讲话内容> 的镜头`

## 版本原则

- 新功能先由试验剪辑师在真实项目中验证。
- 只有确认节省时间且不降低成片质量的功能，才进入稳定版。
- 发布时同步更新 `.codex-plugin/plugin.json` 中的语义化版本号。
- 仓库不存放客户原始素材、剪辑工程、代理文件、导出成片或账号密钥。
