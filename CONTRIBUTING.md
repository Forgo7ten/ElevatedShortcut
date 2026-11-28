# 贡献指南

1. 保持默认行为为**固定目标模式（fixed-target）**，绝不静默启用通用任务。
2. 保持对 Windows PowerShell 5.1 与 PowerShell 7 的兼容。所有 PowerShell 脚本（`.ps1`）必须使用带 BOM 的 UTF-8 编码，因为 PowerShell 5.1 在缺少 BOM 时无法可靠解析包含中文字符的 UTF-8 源码。
3. 严禁将不可信的目标路径或启动参数直接拼接后交给 `cmd /c` 执行。动态执行能力仅存在于显式启用的通用模式中。
4. 提交修改前需在两种 PowerShell 解释器下运行 `tests/Test-Parser.ps1`、`tests/Test-PureLogic.ps1`、`tests/Test-ShortcutCom.ps1`、`tests/Test-Cli.ps1` 和 `tests/Test-TaskMetadata.ps1`；涉及 COM、UAC 或资源管理器行为的改动需在真实 Windows 环境下手工验证。
5. 保持 `cli.ps1` 作为薄分发层：计划任务相关操作应在 `src/Manage-Tasks.ps1` 或 `src/` 下的其他模块中实现。不要让任务管理器去搜索或删除用户生成的快捷方式文件。
6. `docs/` 下的文档统一使用中文编写，并保持固定任务 ID 哈希算法、内部 `ElevatedShortcut:<ID>` 任务标记以及 `Run-<可执行文件名>-<ID>` 任务命名规则。
7. 在 PR 中说明与安全相关的变更，并保持 `README.md`、`README.zh-CN.md` 与 `docs/DESIGN.md` 及实际行为一致。

欢迎提交 Issue 与 PR。在公开日志中请勿包含凭据信息或可识别个人身份的本地任务路径。
