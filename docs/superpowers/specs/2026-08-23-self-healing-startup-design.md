# DeepSeek Harness Desktop 自修复启动器设计

## 目标

桌面应用启动时自动准备一个与主机架构匹配的 Node.js，检查并更新 DeepSeek Harness 与已安装插件，在更新后验证 Web UI 和客户端插件是否正常加载；失败时回滚、隔离冲突插件，并在界面中给出可复制的诊断信息。

## 架构

`StartupOrchestrator` 串联四个阶段：`NodeRuntimeManager`、`DSHUpdateManager`、`PluginUpdateManager`、`DSHProcessManager`。所有状态写入 app-owned support 目录，现有 `dsh-home` profile 不修改用户的 `~/.dsh`。

Node 检测同时验证版本、`process.arch`、可执行的 `node`/`npx` 和原生模块架构。Apple Silicon 只接受 arm64；x86_64 Node 可以被识别但不作为 DSH 运行时。缺失或不匹配时下载并校验官方 arm64 Node，保留上一份 runtime 直到新版本通过启动验证。

DSH 更新读取官方 npm/GitHub 元数据，使用固定的安全版本范围和缓存。插件更新读取 profile 的真实依赖清单，逐项更新，不执行未知构建脚本。更新前将 `package.json`、lockfile、profile patch 和禁用清单复制到带时间戳的快照目录。

## 自修复流程

1. 创建本次启动日志和快照。
2. 选择架构匹配的 Node。
3. 查询并安装较新的 DSH 版本。
4. 逐个更新已安装插件；每一步失败可回滚该插件。
5. 启动 DSH 并等待 HTTP 200。
6. 检查 Web boot manifest 和客户端插件状态。
7. 若出现插件冲突，按更新顺序从后向前禁用可疑插件，重启并重试；核心 DSH 插件不可自动禁用。
8. 健康启动成功后提交快照；失败则恢复最近一次可用快照。

网络不可用时跳过更新，使用已验证的本地版本启动。任何自动更新都不能让应用失去启动能力。

## UI 与错误处理

启动页显示阶段、当前包、进度和重试次数。失败页继续显示红色可选择日志，并列出 Node 架构、DSH 版本、被禁用插件、冲突错误和回滚结果。用户可以复制日志、重试，或恢复被自动禁用的插件。

## 测试

- Node arm64/x86_64 识别及自动切换。
- DSH/插件版本比较、离线缓存和更新失败回滚。
- lockfile/profile 快照恢复。
- 单个插件冲突隔离后 Web UI 成功启动。
- 原生模块架构不匹配时给出明确诊断。
- 退出时更新进程和 DSH 子进程均被回收。
