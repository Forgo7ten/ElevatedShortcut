<div align="center">
  <img src="assets/icon.svg" alt="ElevatedShortcut" width="128" height="128" />
  <h1>ElevatedShortcut</h1>
  <p>A Windows 10/11 "Send to → Create Admin LNK" utility for creating UAC-free elevated shortcuts via pre-approved scheduled tasks.</p>
  <p>
    <strong>English</strong> | <a href="README.zh-CN.md">简体中文</a>
  </p>
</div>

> Pre-authorize a highest-privilege Task Scheduler entry through a one-time UAC prompt, then launch the target app from the generated shortcut without repeating UAC prompts. **System UAC stays enabled and original EXE/LNK files are never modified.**

## Features

- **Fixed-target mode (default)**: Binds the EXE path, launch arguments, and working directory to a dedicated scheduled task. Identical configurations reuse the same task, named with a readable executable token and stable SHA-256 hash; task descriptions display the app name, full path, arguments, and working directory.
- **Optional generic mode**: When explicitly enabled, registers one shared generic task per Windows user that can launch different local EXEs via a request queue. **High risk (arbitrary elevated execution for same-user processes); disabled by default.** Read [SECURITY.md](SECURITY.md) first.
- **Icon & metadata preservation**: Keeps EXE icons directly, and inherits `IconLocation`, icon index, target path, arguments, and working directory from source `.lnk` files.
- **Smart output location**: Right-clicking a `.lnk` writes the new shortcut in **that `.lnk`'s own directory**; right-clicking an `.exe` writes in **that `.exe`'s directory**. If the source directory is not writable, falls back **directly to the Desktop root** (no extra subfolder).
- **Scheduled task manager**: List managed tasks, inspect details, run fixed tasks, and delete tasks. The manager **only manages scheduled tasks** and never searches for or deletes user shortcuts.
- **Unified CLI**: Root `cli.ps1` and double-clickable `cli.bat` (plus `install.bat` / `uninstall.bat`). Dispatchers stay thin while implementations live in `src/`. Prefers PowerShell 7 and falls back automatically to Windows PowerShell 5.1.
- **Installer & uninstaller**: Installs the SendTo entries and the `ElevatedShortcut 任务管理器` Start Menu shortcut. Uninstalling removes managed tasks, installed files, and verifiable shortcuts at their recorded locations.

## Requirements

Windows 10/11 (x64), Task Scheduler, Windows Script Host, and a Windows account with administrator privileges able to approve UAC prompts. Windows PowerShell 5.1 is built in; PowerShell 7 (`pwsh.exe`) is preferred when available. No Python, AutoHotkey, or third-party PowerShell modules are required.

**PowerShell fallback note:** Root `cli.bat` checks for PowerShell 7 on every launch and falls back to Windows PowerShell 5.1. Installed SendTo and Start Menu shortcuts pin **the interpreter path selected at install time**; if you later uninstall PowerShell 7, run `cli.ps1 install` to refresh shortcuts (or `sendto-install` for SendTo only).

## Quick Start

Download and extract the release/repository archive, then in the repository root:

```powershell
# Recommended: PowerShell 7
.\cli.ps1 install

# Or double-click install.bat, or double-click cli.bat and choose Install

# If script execution policy blocks scripts:
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\cli.ps1 install
# Without PowerShell 7:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\cli.ps1 install
```

The installer requests UAC once, copies runtime scripts and the icon to `%ProgramFiles%\ElevatedShortcut`, and adds **Create Admin LNK** to `%APPDATA%\Microsoft\Windows\SendTo`. After installation, the repository folder can be moved or deleted.

On Windows 11: right-click an `.exe` or `.lnk` → **Show more options → Send to → Create Admin LNK**. Creating a new fixed task requires UAC on the first run; subsequent shortcuts with the same configuration reuse it without UAC. If you right-click a shared Start Menu `.lnk` (for example under `C:\ProgramData\Microsoft\Windows\Start Menu`), standard Explorer processes cannot write there, so falling back to Desktop is expected.

Example output:

```text
Source: D:\Shortcuts\Demo.lnk
Output: D:\Shortcuts\Demo (Admin).lnk

Source: C:\Program Files\Demo\Demo.exe  (source directory not writable)
Output: %USERPROFILE%\Desktop\Demo (Admin).lnk
```

Fixed tasks are named `Run-<executable>-<24-hex-ID>` (for example `Run-Chrome-aabbcc...`) for readability and collision-free uniqueness. Line 1 of the task description holds `ElevatedShortcut:<24-hex-ID>`, followed by the application name, target path, arguments, and working directory.

## Unified CLI

Run all commands from the repository **root**:

| Command | Description |
|---|---|
| `.\cli.ps1` or double-click `cli.bat` | Interactive main menu |
| `.\cli.ps1 install` | Install fixed-mode SendTo entry and task manager |
| `.\cli.ps1 install -EnableGeneric` | Also enable the high-risk generic task |
| `.\cli.ps1 create -Path 'D:\Tools\Demo.exe'` | Create a fixed-task elevated shortcut for an EXE |
| `.\cli.ps1 create -Path 'D:\Shortcuts\Demo.lnk'` | Preserve source LNK arguments, icon, and working directory |
| `.\cli.ps1 tasks` | Open the interactive task manager |
| `.\cli.ps1 list` | List managed tasks for the current user |
| `.\cli.ps1 details -TaskName Run-...` | Show task details |
| `.\cli.ps1 delete -TaskName Run-...` | Delete a managed scheduled task (prompts for confirmation) |
| `.\cli.ps1 run -TaskName Run-...` | Manually trigger an authorized fixed task |
| `.\cli.ps1 sendto-install` | Install/restore SendTo entries only (does not touch tasks) |
| `.\cli.ps1 sendto-remove` | Remove SendTo entries only (keeps tasks and shortcuts) |
| `.\cli.ps1 uninstall` | Full uninstall (tasks, entries, installed files, records) |
| `.\cli.ps1 help` | Show all commands |

`cli.bat` accepts the same arguments (for example `cli.bat list`) or can be double-clicked with no arguments. All implementations live under `src/`.

**`sendto-remove` vs. `uninstall`:** `sendto-remove` only removes the current user's SendTo menu entries while leaving all scheduled tasks and generated shortcuts intact (and can be restored with `sendto-install`). Use `uninstall` for complete removal.

### Task Manager

After installation, search for `ElevatedShortcut 任务管理器` in the Windows Start Menu, or run:

```powershell
.\cli.ps1 tasks
# Or launch directly from Program Files if the repo folder was removed:
& "$env:ProgramFiles\ElevatedShortcut\Manage-Tasks.ps1"
```

The manager only lists tasks under `\ElevatedShortcut` that belong to the current user and pass name, identity marker, and action verification. Deleting a task requires confirmation and UAC elevation if needed; moved or renamed shortcuts are not deleted (clicking them afterwards will report the missing task).

### Optional Generic Mode

```powershell
.\cli.ps1 install -EnableGeneric
.\cli.ps1 create -Path 'D:\Tools\Demo.exe' -Mode Generic
```

Registers a single `Generic-<SID-hash>` task for the current account and dispatches launches through a per-user queue, creating shortcuts named `<Name>(Admin-G).lnk`. Runtime arguments can also be passed via `Invoke-Generic.ps1`. **This mode lets any unprivileged process under the same Windows user request elevated execution of arbitrary local EXEs and is not a safe UAC allowlist.** Leave disabled on shared, managed, or sensitive machines. See [SECURITY.md](SECURITY.md).

## Uninstall

```powershell
.\cli.ps1 uninstall
# Or double-click uninstall.bat in the repo root
# Or run from Program Files if the repo folder was deleted:
& "$env:ProgramFiles\ElevatedShortcut\Uninstall.ps1"
```

Uninstalling removes verified scheduled tasks owned by the current user, SendTo and Start Menu entries, installed files in `%ProgramFiles%\ElevatedShortcut` (unless tasks from other Windows users remain), tool data in `%LOCALAPPDATA%\ElevatedShortcut`, and managed shortcuts that still exist and verify at their recorded paths. **Moved or renamed shortcuts are not tracked and must be removed manually.** Original EXEs and source LNKs are never modified or deleted.

## Repository Structure

```text
ElevatedShortcut/
├── assets/
│   ├── icon.svg                    # Vector source icon
│   └── icon.ico                    # Multi-resolution Windows icon for SendTo & manager
├── cli.bat                         # Double-click launcher / PowerShell selector
├── install.bat                     # Double-click installer (calls cli.bat install)
├── uninstall.bat                   # Double-click uninstaller (calls cli.bat uninstall)
├── cli.ps1                         # Unified CLI dispatcher
├── src/
│   ├── Common.ps1                  # Shared validation, Task Scheduler COM, shortcut COM
│   ├── New-ElevatedShortcut.ps1    # EXE/LNK shortcut creation entry point
│   ├── Register-FixedTask.ps1      # Elevated fixed-task registration helper
│   ├── Manage-Tasks.ps1            # Task manager (tasks only, never touches shortcuts)
│   ├── Manage-SendTo.ps1           # Standalone SendTo entry installer/remover
│   ├── Install.ps1                 # Program Files installer
│   ├── Uninstall.ps1               # Uninstaller
│   ├── Invoke-Generic.ps1          # Optional generic-mode queue publisher
│   ├── GenericWorker.ps1           # Optional generic-mode elevated queue worker
│   └── Launcher.vbs                # Hidden console launcher
├── tests/                          # Non-elevated regression tests
├── docs/                           # Product & technical design docs (Chinese)
└── .github/workflows/validate.yml  # Windows PowerShell 5.1 / 7 CI
```

## Verification & Limitations

```powershell
.\tests\Test-Parser.ps1
.\tests\Test-PureLogic.ps1
.\tests\Test-ShortcutCom.ps1
.\tests\Test-TaskMetadata.ps1
.\tests\Test-Cli.ps1
```

Automated CI runs across both Windows PowerShell 5.1 and PowerShell 7 on Windows runners. Interactive UAC prompts, Task Scheduler registration/deletion, and Explorer SendTo integration require manual testing on a Windows machine. This project does not bypass security boundaries—an administrator must approve task creation upfront, and child processes that self-elevate may still trigger UAC.

Unsupported targets: `.url` files, UWP/AppsFolder shortcuts, `.bat`/`.cmd` scripts, UNC paths, and standard users without administrator approval. On execution errors, inspect `\ElevatedShortcut` in `taskschd.msc` and the Task Scheduler Operational log.

## License

[MIT License](LICENSE) · See [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.
