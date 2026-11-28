<#
.SYNOPSIS
    Install ElevatedShortcut into Program Files and register SendTo menu entries.
.EXAMPLE
    .\Install.ps1
.EXAMPLE
    .\Install.ps1 -EnableGeneric
#>
[CmdletBinding()]
param([switch]$EnableGeneric)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

if (-not (Test-IsElevated)) {
    $engine = Get-PowerShellPath
    $args = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
        (Quote-WindowsPath $PSCommandPath)
    if ($EnableGeneric) { $args += ' -EnableGeneric' }
    $child = Start-Process -FilePath $engine -ArgumentList $args -Verb RunAs -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw "安装失败或已取消 UAC 授权（退出码 $($child.ExitCode)）。" }
    Write-Host '安装已完成。右键点击 EXE 或 LNK 文件，选择「发送到 -> Create Admin LNK」即可使用。' -ForegroundColor Green
    exit 0
}

$root = Get-ToolRoot
$null = New-Item -ItemType Directory -Path $root -Force
$source = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$files = @(
    'Common.ps1',
    'New-ElevatedShortcut.ps1',
    'Register-FixedTask.ps1',
    'Invoke-Generic.ps1',
    'GenericWorker.ps1',
    'Manage-Tasks.ps1',
    'Manage-SendTo.ps1',
    'Install.ps1',
    'Uninstall.ps1',
    'Launcher.vbs'
)
foreach ($file in $files) {
    $from = Join-Path $source $file
    $to = Join-Path $root $file
    if (-not [string]::Equals($from, $to, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $from -Destination $to -Force
    }
}

$repoRoot = Split-Path -Parent $source
$iconCandidates = @(
    (Join-Path (Join-Path $repoRoot 'assets') 'icon.ico'),
    (Join-Path $source 'icon.ico')
)
foreach ($iconSource in $iconCandidates) {
    if ([IO.File]::Exists($iconSource)) {
        $iconDest = Join-Path $root 'icon.ico'
        if (-not [string]::Equals($iconSource, $iconDest, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $iconSource -Destination $iconDest -Force
        }
        break
    }
}

$engine = Get-PowerShellPath
[IO.File]::WriteAllText((Join-Path $root 'EnginePath.txt'), $engine, [Text.Encoding]::Unicode)
$settingsPath = Join-Path $root 'settings.json'
$allowGeneric = [bool]$EnableGeneric
Write-JsonFile $settingsPath ([ordered]@{schema = 1; allowGeneric = $allowGeneric})

if ($allowGeneric) {
    $wscriptPath = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
    $args = (Quote-WindowsPath (Join-Path $root 'Launcher.vbs')) + ' worker'
    $status = Ensure-ElevatedTask (Get-GenericTaskName) `
        (Get-GenericTaskDescription) `
        $wscriptPath $args $root 0
    Write-Host "通用计划任务：$status"
}

# Per-user SendTo operations are isolated from installer/task logic, so users
# can also remove/reinstall the right-click menu without deleting tasks.
& (Join-Path $root 'Manage-SendTo.ps1') -Action Install
$shell = New-Object -ComObject WScript.Shell

# Add a standalone task-management program to the current user's Start Menu.
$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$null = New-Item -ItemType Directory -Path $programs -Force
$managerShortcutPath = Join-Path $programs 'ElevatedShortcut 任务管理器.lnk'
if (Test-Path -LiteralPath $managerShortcutPath -PathType Leaf) {
    $previousManager = $shell.CreateShortcut($managerShortcutPath)
    if ([string]$previousManager.Description -cne 'ElevatedShortcut:TaskManager:v1') {
        throw "开始菜单快捷方式名称已被占用：$managerShortcutPath"
    }
}
$managerLink = $shell.CreateShortcut($managerShortcutPath)
$managerLink.TargetPath = $engine
$managerLink.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
    (Quote-WindowsPath (Join-Path $root 'Manage-Tasks.ps1'))
$managerLink.WorkingDirectory = $root
$managerLink.Description = 'ElevatedShortcut:TaskManager:v1'
$installedIcon = Join-Path $root 'icon.ico'
if ([IO.File]::Exists($installedIcon)) {
    $managerLink.IconLocation = $installedIcon + ',0'
}
else {
    $managerLink.IconLocation = (Join-Path ([Environment]::GetFolderPath('System')) 'shell32.dll') + ',44'
}
$managerLink.Save()
Write-Host "已安装开始菜单任务管理器：$managerShortcutPath"

Write-Host "安装目录：$root"
Write-Host "PowerShell 引擎：$engine"
Write-Host ("通用模式：{0}" -f $(if ($allowGeneric) { '已启用' } else { '未启用（仅固定模式）' }))
Write-Host '右键点击 EXE 或 LNK 文件，选择「发送到 -> Create Admin LNK」即可使用。'
