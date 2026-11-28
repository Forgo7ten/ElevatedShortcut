<div align="center">
  <img src="assets/icon.svg" alt="ElevatedShortcut" width="128" height="128" />
  <h1>ElevatedShortcut</h1>
  <p>Windows 10/11 的「发送到 → Create Admin LNK」工具：基于 Task Scheduler 预先审批，为可信应用创建免 UAC 弹窗的管理员启动快捷方式。</p>
  <p>
    <a href="README.md">English</a> | <strong>简体中文</strong>
  </p>
</div>

> 预先通过 UAC 授权创建最高权限的计划任务，随后从生成的快捷方式启动指定程序，无需每次确认 UAC。**不关闭系统 UAC、不修改原始 EXE/LNK。**

## 功能

- **固定目标模式（默认）**：EXE 路径、启动参数、工作目录与计划任务绑定。相同配置复用任务，任务名称以稳定哈希区分；任务**描述**中显示程序名、完整路径、参数、工作目录。
- **可选通用模式**：显式启用后，每位 Windows 用户只创建一个通用任务；不同的本地 EXE 可复用它。**这是任意管理员程序执行入口，风险很高；默认关闭。** 请先阅读 [SECURITY.md](SECURITY.md)。
- **保留图标**：EXE 使用自身图标，LNK 继承原有 `IconLocation` 和图标索引；同时继承原 LNK 的目标程序、参数和工作目录。
- **正确的输出目录**：右键选中 `.lnk` 就优先放在**该 LNK 文件所在目录**；选中 `.exe` 就优先放在**该 EXE 文件所在目录**。源目录不可写时，**直接创建在桌面**，不另建子文件夹。
- **计划任务管理器**：查看已有任务、详细信息、运行固定任务、删除任务。管理器**只管理计划任务**，不会查找或删除已生成的快捷方式。
- **统一 CLI**：仓库根目录 `cli.ps1` 与可双击的 `cli.bat`（另附 `install.bat` / `uninstall.bat`）。脚本仅分发命令，实际操作保留在 `src/` 中；支持 PowerShell 7，自动回退 Windows PowerShell 5.1。
- **安装/卸载**：自动安装 SendTo 菜单与开始菜单中的 `ElevatedShortcut 任务管理器`。卸载可清理受管任务、安装文件与可验证的原位置快捷方式。

## 系统要求

Windows 10/11（x64）、Task Scheduler、Windows Script Host，以及具有管理员权限并能确认 UAC 的当前 Windows 账户。Windows 自带 PowerShell 5.1；如果安装 PowerShell 7，会优先使用 `pwsh.exe`。无需 Python、AHK 或第三方 PowerShell 模块。

**解释器回退说明：** 根目录 `cli.bat` 每次启动时都会优先查找 PowerShell 7，找不到则回退系统 5.1。已安装的 SendTo 和开始菜单入口使用**安装时选定的解释器路径**；若安装后卸载了 PowerShell 7，请运行 `cli.ps1 install` 更新快捷方式（或只运行 `sendto-install` 更新 SendTo）。

## 快速开始

下载项目 ZIP 并解压，在项目根目录：

```powershell
# 推荐：PowerShell 7
.\cli.ps1 install

# 或者直接双击 install.bat，或双击 cli.bat 后选择「安装」

# 如果 PowerShell 执行策略限制脚本，可用：
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\cli.ps1 install
# 未安装 PowerShell 7：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\cli.ps1 install
```

安装程序会请求一次 UAC，将所需脚本与图标复制到 `%ProgramFiles%\ElevatedShortcut`，并在 `%APPDATA%\Microsoft\Windows\SendTo` 中添加 **「Create Admin LNK」**。安装后仓库目录可以移动或删除；已安装工具无需依赖源码目录。

在 Windows 11 中：右键 EXE 或 LNK → **显示更多选项 → 发送到 → Create Admin LNK**。第一次创建某个新的固定任务需要 UAC；同样配置再次使用时直接复用。如果你右键的是开始菜单中面向所有用户的 LNK（例如位于 `C:\ProgramData\Microsoft\Windows\Start Menu`），该目录通常需要管理员写入权限，正常回退桌面是预期行为。

输出示例：

```text
源文件：D:\Shortcuts\Demo.lnk
新文件：D:\Shortcuts\Demo (Admin).lnk

源文件：C:\Program Files\Demo\Demo.exe  （原目录不可写）
新文件：%USERPROFILE%\Desktop\Demo (Admin).lnk
```

任务使用 `Run-<进程名>-<24 位哈希>` 命名，例如 `Run-Chrome-aabbcc...`：进程名便于人工识别，哈希保证唯一和稳定。任务描述首行为 `ElevatedShortcut:<24 位哈希>`，随后记录应用名、完整路径、参数和工作目录。

## 统一 CLI

下面的命令均在项目**根目录**运行：

| 命令 | 功能 |
|---|---|
| `./cli.ps1` 或双击 `cli.bat` | 交互式主菜单 |
| `.\cli.ps1 install` | 安装固定模式的 SendTo 入口与管理器 |
| `.\cli.ps1 install -EnableGeneric` | 额外启用通用任务，需自行承担风险 |
| `.\cli.ps1 create -Path 'D:\Tools\Demo.exe'` | 为 EXE 创建固定任务快捷方式 |
| `.\cli.ps1 create -Path 'D:\Shortcuts\Demo.lnk'` | 保留原 LNK 参数、图标、工作目录 |
| `.\cli.ps1 tasks` | 打开交互式任务管理器 |
| `.\cli.ps1 list` | 列出当前用户的受管任务 |
| `.\cli.ps1 details -TaskName Run-...` | 查看任务详细信息 |
| `.\cli.ps1 delete -TaskName Run-...` | 删除指定计划任务，要求确认 |
| `.\cli.ps1 run -TaskName Run-...` | 手动启动已授权的固定目标任务 |
| `.\cli.ps1 sendto-install` | 仅安装/恢复 SendTo 菜单，不操作任务 |
| `.\cli.ps1 sendto-remove` | 仅卸载 SendTo 菜单，保留所有任务和快捷方式 |
| `.\cli.ps1 uninstall` | 完整卸载工具及当前用户的受管任务 |
| `.\cli.ps1 help` | 显示全部命令 |

`cli.bat` 可以带相同参数，例如 `cli.bat list`，也可以无参数双击使用。所有命令只在 `src/` 目录中分发执行；CLI 不直接修改计划任务。

**`sendto-remove` 与 `uninstall` 不同：** 前者只移除当前用户的右键菜单，已经注册的计划任务和现有快捷方式都不会动；以后可以运行 `sendto-install` 恢复菜单。后者才是完整卸载。

### 任务管理器

安装后在 Windows 开始菜单搜索 `ElevatedShortcut 任务管理器`，也可以执行：

```powershell
.\cli.ps1 tasks
# 若源码已移走，仍可直接从安装目录启动：
& "$env:ProgramFiles\ElevatedShortcut\Manage-Tasks.ps1"
```

管理器只显示 **`\ElevatedShortcut` 文件夹下、属于当前登录用户、任务名称/标记/启动配置都符合本工具规则** 的任务。操作包括：列表、详情、运行固定任务、删除。删除时先确认，再根据需要触发一次 UAC；任务被删除后，已经移动到其他位置的快捷方式会保留，但再次点击会失效。

### 可选通用模式

```powershell
.\cli.ps1 install -EnableGeneric
.\cli.ps1 create -Path 'D:\Tools\Demo.exe' -Mode Generic
```

同一账户只注册一个 `Generic-<SID 哈希>` 任务，之后通过用户目录中的请求队列复用，生成的快捷方式为 `<原名称>(Admin-G).lnk`。也可使用安装目录内的 `Invoke-Generic.ps1` 传入运行时参数。**这种模式允许同一 Windows 用户下的其他非管理员进程请求执行任意本地管理员程序；不能视为安全的 UAC 白名单。** 默认不要启用；不适合共享机器、受管电脑或敏感工作环境。参见 [SECURITY.md](SECURITY.md)。

## 卸载

```powershell
.\cli.ps1 uninstall
# 或直接双击根目录的 uninstall.bat
# 解压的项目已删除时也可以调用已安装脚本：
& "$env:ProgramFiles\ElevatedShortcut\Uninstall.ps1"
```

卸载将清理已验证的当前用户计划任务、SendTo/开始菜单入口、安装文件和本工具数据。它还会尝试删除**记录位置上仍能验证为本工具创建**的快捷方式。**移动或重命名过的快捷方式不被追踪，也不会被管理器删除**；请自行清理这些失效链接。卸载不会删除原始程序或原始 LNK。

## 目录结构

```text
ElevatedShortcut/
├── assets/
│   ├── icon.svg                    # 图标矢量源文件
│   └── icon.ico                    # SendTo 与管理器使用的 Windows 图标
├── cli.bat                         # 双击入口 / 调用 PowerShell
├── install.bat                     # 双击安装快捷入口（调用 cli.bat install）
├── uninstall.bat                   # 双击卸载快捷入口（调用 cli.bat uninstall）
├── cli.ps1                         # 统一命令分发器
├── src/
│   ├── Common.ps1                  # 公共逻辑、Task Scheduler COM、快捷方式 COM
│   ├── New-ElevatedShortcut.ps1    # EXE/LNK 入口
│   ├── Register-FixedTask.ps1      # 提权注册固定目标计划任务
│   ├── Manage-Tasks.ps1            # 任务管理器（只管理计划任务）
│   ├── Manage-SendTo.ps1           # 单独安装/移除 SendTo 入口
│   ├── Install.ps1                 # 安装 SendTo / 管理器
│   ├── Uninstall.ps1               # 卸载
│   ├── Invoke-Generic.ps1          # 可选通用任务入队
│   ├── GenericWorker.ps1           # 可选通用任务处理器
│   └── Launcher.vbs                # 隐藏控制台启动
├── tests/                          # 无管理员权限的回归测试
├── docs/                           # 中文产品与技术设计文档
└── .github/workflows/validate.yml  # Windows PowerShell 5.1 / 7 CI
```

## 验证与限制

```powershell
.\tests\Test-Parser.ps1
.\tests\Test-PureLogic.ps1
.\tests\Test-ShortcutCom.ps1
.\tests\Test-TaskMetadata.ps1
.\tests\Test-Cli.ps1
```

自动化验证在 GitHub Actions 的 Windows 环境下分别调用 PowerShell 5.1 和 PowerShell 7。计划任务实际注册、UAC、任务删除与资源管理器 SendTo 需在真实 Windows 上手工验证。本项目不会利用权限漏洞；管理员需预先批准任务创建。应用本身另起进程并自行调用提权时，仍可能出现新的 UAC 请求。

不支持 `.url`、UWP/AppsFolder 快捷方式、`.bat`、`.cmd`、UNC 目标，也不支持标准用户无管理员授权启动需要管理员权限的应用。任务执行失败时请查看 `taskschd.msc` 中的 `\ElevatedShortcut` 和 Task Scheduler Operational 日志。

## 开源许可

[MIT License](LICENSE) · 贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
