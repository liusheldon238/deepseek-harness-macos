# DeepSeek Harness Desktop 内置预设与模型搜索插件设计

## 目标

将现有 `dsh-agent-preset-advisor` 简化并拆分成两个职责单一、可独立发布的 DSH 客户端插件：

1. `dsh-preset-catalog`：提供可维护的领域预设目录，并增强官方 Agent 预设页面的搜索、分类、安装和启用体验。
2. `dsh-model-search`：为对话输入区的模型选择弹窗和 `/model` 命令弹窗增加轻量搜索过滤。

DeepSeek Harness Desktop 默认捆绑并幂等安装两个插件到应用自有 Profile。插件故障不得阻止 DSH 启动；Desktop 现有自修复机制可以禁用故障插件并记录原因。

## 仓库与发布边界

三个仓库分别维护和发布：

- `liusheldon238/deepseek-harness-macos`：Swift/AppKit Desktop、运行时准备、插件安装、自修复和 macOS 打包。
- `liusheldon238/dsh-preset-catalog`：预设目录插件及其预设资产。
- `liusheldon238/dsh-model-search`：模型选择搜索增强插件。

两个插件均使用 MIT License，拥有独立版本、测试和 GitHub Release。Desktop 在源码中固定插件版本/提交，在应用包中携带经过验证的插件快照，不在每次启动时从 GitHub 执行任意代码。后续插件升级仍走 Desktop 的版本检查、快照、回滚和健康验证流程。

Desktop 构建使用固定提交的 Git submodule 放置插件源，打包时复制到 `Contents/Resources/Plugins/`。Release 构建必须验证 submodule 已初始化、插件清单版本与 Desktop 锁定版本一致。

## DSH 预设语义

Agent 预设是一次会话的 Agent-plane Cordis 组合：它决定该会话启用的工具插件、Skills、人格/系统提示、命令与工作流。Host/UI 基础设施（模型路由、设置、插件市场、模型搜索、预设目录页面等）保持全局，不放入领域预设。

预设在新会话创建或空会话选择时固定。修改默认预设只影响之后创建的会话，不重新组装正在运行的会话。

DSH 当前没有稳定的“继承官方 standard 文件”声明，因此领域预设不在运行时引用安装目录里的可变文件。仓库保存一个与支持的 DSH 版本对应的标准基线，由生成/同步脚本复制基线并应用受控的领域差异；升级 DSH 时通过差异检查人工确认基线变化。

## `dsh-preset-catalog`

### 职责

- 删除旧 advisor 的任务监听、关键词分类、自动推荐和自动切换逻辑。
- 提供领域预设目录、分类、搜索、详情、安装、卸载和“设为默认”入口。
- 复用 DSH 官方 `agentPresets` 与 `settings` API，不建立第二套预设存储。
- 将已安装预设写入 `$DSH_HOME/.agent-presets/<preset-id>/`，保持官方预设页面和会话选择器可见。
- 仅安装用户明确选择的领域预设；插件自身默认安装不等于自动改变默认 Agent 预设。

### 第一版预设

| ID | 名称 | 领域差异 |
| --- | --- | --- |
| `general-assistant` | 通用助手 | 标准工具集，使用面向通用任务的简洁人格和工作规范。 |
| `software-development` | 软件开发 | 强化代码探索、实现、测试、调试和代码审查流程。 |
| `game-development` | 游戏开发 | 增加玩法设计、引擎/运行时、资产管线、性能与游戏测试指引。 |
| `video-creation` | 视频创作 | 增加策划、脚本、分镜、镜头、素材组织、后期与交付指引。 |
| `product-design` | 产品设计 | 增加需求、信息架构、交互、视觉系统、原型和体验审查指引。 |
| `research-analysis` | 研究分析 | 强化资料检索、来源核验、对比分析、结构化结论和报告输出。 |

第一版以官方标准能力集为安全基线，主要通过领域 persona、说明和仓库内 Skills 增强。只有在已有插件经过单独兼容验证后，才加入额外工具插件，避免一个预设隐式引入未验证依赖。

### 目录与维护格式

每个预设是独立目录：

```text
presets/<preset-id>/
├── agent.cordis.yml
├── preset.yml
└── skills/
```

`preset.yml` 除官方名称、说明和排序字段外，增加目录展示使用的分类、标签、兼容 DSH 范围和能力摘要。插件在安装前验证 ID、YAML、组合顶层结构、依赖包以及目标目录占用情况；安装采用临时目录加原子重命名，不覆盖用户已修改的同名预设。

### 页面增强

插件新增“预设目录”设置区，并在可稳定扩展时为官方 Agent 预设管理区增加搜索入口。页面支持：

- 按名称、ID、分类、标签和说明进行大小写不敏感的连续子串搜索。
- “全部、通用、开发、创作、设计、研究”分类过滤。
- 区分“内置目录”“已安装”“当前默认”“存在本地修改”。
- 查看预设包含的工具、Skills 和工作规范摘要。
- 安装、卸载未修改的目录预设、设为后续新会话默认。
- 搜索为空时恢复完整列表，无结果时显示清晰空状态。

若官方设置槽位发生不兼容，目录插件自己的设置区仍可使用；增强失败只写警告，不抛出阻断 Web boot 的异常。

## `dsh-model-search`

### 选择的实现方式

保留官方 `@deepseek-ai/dsh-client-ui-model-selection`，使用客户端 DOM decorator 为它增加搜索，而不复制其 `ModelDirectory`、选中逻辑和推理等级状态机。官方插件目前只公开 directory 服务，没有公开 `ModelSelect` 组件或 popupSelect 内部扩展点；完整替换会把插件与 DSH 私有 UI 实现紧耦合。

Decorator 使用菜单的无障碍角色、触发器关系和结构语义识别目标，不依赖构建时生成的 CSS 类名。每次弹窗挂载时添加一次搜索区，卸载时释放监听器；识别不到兼容结构时记录一次警告并保持官方弹窗原样可用。

### 搜索行为

- 同时覆盖 composer 模型弹窗和 `/model` popupSelect。
- 匹配模型显示名称、模型 ID 和 Provider 名称。
- 大小写不敏感，采用连续子串匹配。
- 保留 Provider 分组并隐藏空分组。
- 清空输入恢复全部模型；无匹配时显示本地化空状态。
- 弹窗打开后可直接聚焦搜索；`Escape` 先清空搜索，再由官方菜单处理关闭。
- 搜索只改变显示，不改变选择、Provider/模型 ID、Reasoning Effort 或 RPC 数据。
- 每次打开使用空查询，不跨会话保存筛选状态。

过滤核心实现为无 DOM 依赖的纯函数，DOM decorator 只负责读取行元数据、应用可见性和键盘交互。

## Desktop 集成与迁移

Desktop 删除 `Resources/dsh-agent-preset-advisor` 及 `presetAdvisorPackage`，不再安装旧包。启动时幂等安装：

1. `dshmarket`。
2. 应用内置的 `dsh-preset-catalog`。
3. 应用内置的 `dsh-model-search`。

安装目标保持 `~/Library/Application Support/DeepSeek Harness Desktop/dsh-home/profiles/web/`，使用与主机架构匹配的应用 Node；不安装到系统全局 npm，也不修改用户的默认 `~/.dsh`。

迁移时若旧 advisor 仍在 manifest、lockfile 或 bundles 中，Desktop 使用 DSH plugin 命令卸载它；卸载失败时至少从 bundles 中禁用并记录迁移日志。两个新插件分别安装和验证，一个失败不回滚另一个。

每个内置插件有独立的健康标识。Web boot 冲突解析到某个新插件时，自修复流程只禁用该插件并重启；预设目录或模型搜索不可用不影响官方预设、官方模型选择和基本会话能力。

## 预设故障与后台连接修复

当前现场验证显示活动 DSH 的 `agentPreset.list`、`settings.describe` 和 `settings.openDocument` 均成功；同时发现一个 Desktop 遗留的孤儿 DSH 后台。截图中“预设加载失败”和“配置文件无法打开”同时出现，更符合 WebView 连接到旧或已失效后台，而不是预设文件缺失。

Desktop 因此增加以下防护：

- 启动时读取 Desktop 自有 PID 记录，并在验证 UID、可执行文件位于应用支持目录、参数为 DSH Web 后才清理遗留进程。
- 首页 HTTP 200 后继续调用 `agentPreset.list` 和 `settings.describe`，领域 API 成功后才加载 WebView。
- 运行期间监测后台进程退出和连续健康检查失败；确认失联后进入现有自修复重启流程。
- 重启成功后以忽略本地缓存的请求重新加载当前 WebView，避免旧客户端脚本继续连接失效服务。
- 内嵌日志记录 PID、端口、领域检查、重启、插件禁用和最终恢复结果。

不通过匹配进程名称的大范围 kill 清理后台，避免终止用户自己启动的 DSH。

## 测试与验收

### 插件测试

- 预设元数据、YAML 结构、依赖和兼容版本验证。
- 六个预设均可发现、安装并由 `agentPreset.list` 返回。
- 安装不覆盖同名本地修改；卸载不删除未知或已修改内容。
- 目录搜索覆盖名称、ID、分类、标签和说明。
- 模型搜索覆盖名称、ID、Provider、大小写、空查询、空分组和无结果。
- DOM 结构不兼容时两个插件均降级而不阻止 Web boot。

### Desktop 测试

- 首次启动安装两个插件，重复启动不重复安装。
- 旧 advisor 从启用列表迁移移除。
- 一个内置插件故障时仅禁用该插件，DSH 仍成功启动。
- PID 校验只回收 Desktop 自己留下的 DSH。
- `agentPreset.list` 或 `settings.describe` 失败会触发恢复，不进入错误 WebView。
- 后台运行中退出后自动重启并刷新页面。

### 真实 UI 验收

- composer 和 `/model` 两个入口均可筛选大量模型并完成选择。
- 预设目录可搜索、分类、安装、查看并设为默认。
- 新会话使用新预设，既有会话保持原预设。
- 官方 Agent 预设页面可正常加载和查看。
- “打开配置文件”能够打开应用自有 `settings.yaml`。
- 退出 Desktop 后本次后台被回收，再次启动没有旧端口页面。

## 非目标

- 不恢复任务文本分析、关键词推荐或自动切换预设。
- 不将插件或预设安装到系统全局 Node/npm。
- 不在后台自动覆盖用户修改过的预设。
- 不修改 DeepSeek Harness 官方 npm 包文件。
- 第一版不提供远程社区预设市场、评分或遥测。
