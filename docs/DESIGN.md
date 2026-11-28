# 产品设计与技术规格 — ElevatedShortcut v0.1.0

本文件统一记录 ElevatedShortcut 的**产品功能需求、交付边界与技术设计**，后续修改应以此为准。未列入本文档的特性不应在重构时擅自加入。

## 目标与使用范围

Windows 10/11 当前用户通过「发送到」为 `.exe` 或指向本地 EXE 的 `.lnk` 创建管理员快捷方式。**新计划任务注册需要管理员同意，已经授权的固定任务可以重复启动而无需再次弹 UAC。** 不修改原文件、不全局关闭 UAC；用户必须具备合法管理员授权。

## 功能需求与验收标准

| 编号 | 需求 | 验收标准 |
|---|---|---|
| R01 | SendTo 右键入口 | 默认安装固定模式；通用模式仅显式启用时出现 |
| R02 | EXE 和 LNK | EXE 直接使用原文件；LNK 解析目标 EXE、参数、工作目录、自定义图标和索引 |
| R03 | **源目录优先** | 选中 LNK 输出在**所选 LNK 自身**的目录；选中 EXE 输出在 EXE 目录；不跟随快捷方式的 `TargetPath` 选择输出路径 |
| R04 | **桌面回退** | 源目录不可写时，直接在桌面根目录创建新 LNK；**不创建「管理员快捷方式」子目录** |
| R05 | 图标及名称 | 保留原图标/索引；固定模式名称：`原名称 (Admin).lnk`，通用模式：`原名称(Admin-G).lnk` |
| R06 | 防覆盖 | 复用可验证的同一快捷方式；同名但无关的 LNK 不覆盖，增加 ` (2)` 等编号 |
| R07 | 固定计划任务 | 绑定 EXE 路径、原始参数及工作目录；交互式当前用户令牌、最高权限 |
| R08 | 唯一命名 | 使用用户 SID + 目标路径 + 参数 + 工作目录的稳定哈希；任务名 `Run-<可读进程名>-<24hex>`；同配置直接复用，避免重复注册 |
| R09 | **可读任务描述** | 保留首行机器身份标记；包含「应用、目标程序、启动参数、工作目录」等中文信息；通用任务显示风险说明 |
| R10 | 任务安全控制 | 拒绝已存在但身份、动作、账户不一致的任务；任务 ACL 限制普通令牌对动作的修改 |
| R11 | 通用任务模式 | 需显式选择，当前用户只注册一个 `Generic-<SID哈希>`，复用同一受保护 worker 和 JSON 请求队列；**高风险** |
| R12 | **任务管理器** | 提供列表、详情、运行固定任务、删除；只作用于当前用户、本工具身份匹配的计划任务 |
| R13 | **管理器不动 LNK** | 删除任务不会搜索、修改、删除生成的快捷方式（用户可能移动这些快捷方式） |
| R14 | **根目录 CLI** | `cli.ps1` 负责简单命令分发；`cli.bat` 可双击进入交互菜单；管理操作实现在 `src/Manage-Tasks.ps1` |
| R14a | **独立 SendTo 管理** | `sendto-install` / `sendto-remove` 仅增删右键菜单入口，不删除计划任务、快捷方式或安装文件；完整卸载另用 `uninstall` |
| R15 | PowerShell 双兼容 | PS 7 优先，没装时回退到系统 Windows PowerShell 5.1；使用 5.1 可解析的语法，文件 UTF-8 BOM |
| R16 | 安装/卸载 | 安装到 Program Files，安装 SendTo 以及开始菜单管理器；卸载删除可验证的已记录原位置快捷方式、任务和本工具文件 |
| R17 | 文档 | `docs/` 与根目录说明文档使用中文；README 解释安装、CLI 与安全边界 |
| R18 | 自动测试 | Windows GitHub Actions 分别在 5.1 / 7 上运行语法、逻辑、LNK COM、CLI 与任务元数据回归测试 |

## 交付边界

- 不支持 UWP、Shell AppsFolder、URL 或非本地 EXE 的 LNK；也不支持 UNC EXE、BAT/CMD 本身作为目标。
- 源目录位于 `C:\Program Files`、公共开始菜单等受保护路径时，普通 Explorer 无法写入，此时回退桌面是正确行为。
- 不为通用模式提供安全白名单；它是一项风险明确的可选特性，不应默认开启。
- 不执行后台自动更新，不创建周期性触发器。
- 不声称已通过真实 Windows UAC/Task Scheduler 集成验证，除非有对应实测结果；CI 不负责这些需要交互许可的场景。

## 模块职责

| 文件 | 职责 |
|---|---|
| `cli.bat` | 双击入口；先查找 `pwsh.exe`，否则执行 Windows 内置 `powershell.exe`；调用 `cli.ps1` |
| `install.bat` | 一键安装批处理入口；调用 `cli.bat install` |
| `uninstall.bat` | 一键卸载批处理入口；调用 `cli.bat uninstall` |
| `cli.ps1` | 命令行和交互主菜单，只负责将操作转发到 `src` 脚本 |
| `src/Common.ps1` | 路径校验、源文件解析、哈希、计划任务 COM、描述、LNK COM、桌面回退 |
| `src/New-ElevatedShortcut.ps1` | 处理 SendTo 输入；按模式注册/复用任务并写快捷方式 |
| `src/Register-FixedTask.ps1` | 仅在需要创建固定任务时请求管理员权限，完成任务注册 |
| `src/Manage-Tasks.ps1` | 列出、查看、启动、删除受管任务；**不接触生成的快捷方式** |
| `src/Manage-SendTo.ps1` | 独立安装/移除当前用户的 SendTo 入口，不操作任务或快捷方式 |
| `src/Install.ps1` | 将脚本复制到 Program Files、调用 Manage-SendTo、安装开始菜单管理器，选择通用模式 |
| `src/Uninstall.ps1` | 清理受管计划任务、SendTo/开始菜单入口、受验证的原位置快捷方式、配置 |
| `src/Invoke-Generic.ps1` | 用户可写请求队列发布（仅显式启用的高风险通用模式） |
| `src/GenericWorker.ps1` | 通用任务的高权限队列处理器 |
| `src/Launcher.vbs` | 无窗口启动器；通过计划任务 COM 直接触发固定任务，或静默执行 SendTo 创建、提权注册及通用 worker |

## 运行模式与命名模型

ElevatedShortcut 提供**固定目标模式（`Fixed`）**与**通用模式（`Generic`）**两种运行模型，它们在代码入口、快捷方式元数据、任务身份标记和 Task Scheduler 可见名称之间各有分工：

- **固定目标模式（默认）**：核心概念是“一次授权、绑定单一启动配置”。每一个唯一的 `(目标 EXE, 启动参数, 工作目录)` 组合对应一个独立的计划任务。
  - 在入口参数、快捷方式描述（`ElevatedShortcut:v1|Fixed|<ID>`）与启动参数（`fixed <ID>`）中，以 `Fixed` / `fixed` 表达“配置不可变的固定目标”这一语义（包括测试与脚本名称中的 `Register-FixedTask.ps1`、`fixed-task`）；而计划任务描述首行的机器身份标记则直接简化为 `ElevatedShortcut:<ID>`，去除冗余前缀。
  - 在 Task Scheduler 中注册任务时，为了让用户在任务计划程序或任务管理器中一眼看出该任务实际会启动哪个程序，可见任务名采用更具动作语义的 `\ElevatedShortcut\Run-<目标 EXE 文件名>-<ID>`。快捷方式（`原名称 (Admin).lnk`）本身只携带固定配置哈希 `<ID>`，启动时由 `Launcher.vbs` 遍历 `\ElevatedShortcut` 文件夹按 `-<ID>` 后缀定位对应的 `Run-` 任务，并校对描述首行的 `ElevatedShortcut:<ID>` 身份标记后触发运行。
- **通用模式（显式启用，高风险）**：核心概念是“每用户一个共享高权限执行器”。在入口参数与快捷方式元数据（`原名称(Admin-G).lnk`）中使用 `Generic` / `generic` 标识，在 Task Scheduler 中则只注册一个以用户 SID 哈希命名的 `\ElevatedShortcut\Generic-<SID 哈希>` 任务（身份标记为 `ElevatedShortcut:generic:<SID>`），通过 `%LOCALAPPDATA%` 下的队列文件动态传递要启动的本地 EXE。

## 固定任务的身份与可读描述

固定任务标识算法：按长度前缀拼接版本字符串、用户 SID、统一小写的绝对目标 EXE 路径、**未经修改的原始参数字符串**、统一小写的工作目录；取 SHA-256 前 24 个十六进制字符。任务名为 `Run-<目标 EXE 文件名>-<ID>`。目标文件名经过非法字符清理并限制为 40 字符；稳定 ID 保证唯一性与确定性复用。

任务 `RegistrationInfo.Description` 第一行为机器身份标记，后面是可读信息：

```text
ElevatedShortcut:aabbccddeeff001122334455
应用：Demo.exe
目标程序：D:\Tools\Demo.exe
启动参数：--profile default
工作目录：D:\Tools
```

`Assert-TaskMatches` 核对**标记首行身份一致**，同时独立核对 SID、LogonType、RunLevel、动作 EXE、参数及工作目录。

Task Scheduler COM 的 Description 只用于任务管理 UI；**实际启动配置始终以动作字段为准**。为了避免极长参数使 Description 难以展示，描述总长度限制为 920 字符，并对源字段的换行进行压平，不对真实参数内容做修改。

## 输出目录选择

`Resolve-Source` 保存两个不同的路径：

- `SourcePath`/`SourceDirectory`：用户右键**选中的那个文件**及其目录（可为 LNK 或 EXE）；
- `TargetPath`：对原始 LNK 完成解析后得到的 EXE 目标路径。

`Save-ManagedShortcut` 只能用 `SourceDirectory` 决定首选目录，不得改用 `TargetPath` 的目录。若写入该目录失败，候选目标为 Windows Shell 返回的**桌面根目录** `DesktopDirectory`。不创建新的 `管理员快捷方式` 子目录。若两个位置相同，则只尝试一次。遇到同名文件时先验证是否属于相同任务，未匹配则编号避让。

常见误解：开始菜单内的 `.lnk` 可能存放在所有用户共享的 `ProgramData\...\Start Menu` 中；该目录通常不可由普通 Explorer 修改，所以**回退桌面本身不代表路径解析错误**。

## 管理器的数据来源与边界

管理器不依赖用户目录下的快捷方式记录，而是直接枚举 `\ElevatedShortcut` 任务文件夹。仅接受同时满足以下条件的任务：

1. 名称满足 `Run-<可读进程名>-<24hex>`，或等于当前用户的 `Generic-<SID 哈希>`；
2. 描述首行与对应的机器身份标记一致；
3. Principal SID 等于当前登录用户 SID，LogonType 为 InteractiveToken，RunLevel 为 Highest；
4. 仅有一条 EXE 动作；固定任务的动作重新计算哈希必须等于任务名中的 ID，且名称中的进程名必须与目标 EXE 匹配；通用任务必须与已安装的固定 worker 动作相符。

列出与查看操作可在当前用户权限下执行；删除使用 UAC 请求管理员确认，然后**重新核对**管理边界以防对象被修改。运行固定任务直接调用计划任务 COM 接口（`RegisteredTask.Run`）。通用任务若无请求队列不允许直接从管理器运行。

任务删除只影响**一个计划任务**，不应误删其他任务；删任务**不删除快捷方式**，移动位置后的 LNK 也不跟踪。文件与已记录原位置快捷方式的清理属于卸载器行为，不属于管理器行为。卸载器只删除历史记录中路径仍存在、且身份一致的 LNK。

## 权限与通用任务

固定任务由管理员安装，任务和文件夹采用受保护 ACL，当前用户低权限令牌可读/运行但不能随意改写任务动作；`TASK_DONT_ADD_PRINCIPAL_ACE` 防止计划任务服务重新加入宽松主体 ACL。应用本身若位于用户可写目录，其二进制文件仍可能被替换，固定路径不等于固定文件内容。

可选通用任务：**当前用户一个最高权限 worker**、用户可写 JSON 原子请求队列、任务需要时主动启动。它是**任意管理员程序执行入口**，不能把原子队列或 Program Files ACL 误解释为执行授权机制。更多风险见 `../SECURITY.md`。

## 兼容性与编码

- PowerShell 7 优先，5.1 回退；所有 `.ps1` 保持 **UTF-8 BOM**，避免 5.1 将中文解析为其他编码。
- `EnginePath.txt` 使用 UTF-16，供 VBS 读取；数据 JSON 为无 BOM UTF-8。
- 创建 LNK 使用 `WScript.Shell` COM；计划任务操作使用 `Schedule.Service` COM。
- CLI 不能复制复杂业务逻辑，所有任务实际写操作留在 `src`。
- 自动测试可验证纯逻辑和 COM 快捷方式创建；真实 UAC、管理器的高权限删除/更新需 Windows 实机验收。

## Microsoft API 参考

- [注册计划任务：TaskFolder.RegisterTaskDefinition](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskfolder-registertaskdefinition)
- [任务注册标记：TASK_CREATION](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_creation)
- [任务描述：RegistrationInfo.Description](https://learn.microsoft.com/en-us/windows/win32/taskschd/registrationinfo)
- [任务最高权限：Principal.RunLevel](https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-runlevel)
- [命令行运行任务：schtasks /Run](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-run)
