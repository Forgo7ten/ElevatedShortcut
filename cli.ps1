<#
.SYNOPSIS
    ElevatedShortcut 仓库根目录统一入口；实际操作由 src 下的脚本实现。
.EXAMPLE
    .\cli.ps1
.EXAMPLE
    .\cli.ps1 install
.EXAMPLE
    .\cli.ps1 create -Path 'C:\Tools\App.exe'
.EXAMPLE
    .\cli.ps1 tasks
.EXAMPLE
    .\cli.ps1 delete -TaskName Run-App-0123456789abcdef01234567
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'menu',
    [string[]]$Path,
    [ValidateSet('Fixed', 'Generic')]
    [string]$Mode = 'Fixed',
    [string]$TaskName = '',
    [switch]$EnableGeneric,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'

function Invoke-Entry([string]$File, [hashtable]$Parameters = @{}) {
    $path = Join-Path $src $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "项目不完整，缺少文件：$path"
    }
    & $path @Parameters
    if (-not $?) { throw "操作失败：$File" }
}

function Show-Help {
    @'
ElevatedShortcut CLI (PowerShell 7 / Windows PowerShell 5.1)

  .\cli.bat                               双击进入交互式菜单
  .\cli.ps1                               交互式菜单
  .\cli.ps1 install                       安装 SendTo / 任务管理器
  .\cli.ps1 install -EnableGeneric        显式启用通用管理员任务（高风险）
  .\cli.ps1 uninstall                     完整卸载工具及受管任务
  .\cli.ps1 sendto-install                仅恢复 SendTo 菜单（无 UAC）
  .\cli.ps1 sendto-remove                 仅移除 SendTo 菜单（保留任务）
  .\cli.ps1 create -Path 'C:\App\a.exe'   创建固定目标快捷方式
  .\cli.ps1 create -Path 'C:\App\a.lnk' -Mode Generic
  .\cli.ps1 tasks                         打开任务管理器
  .\cli.ps1 list                          列出计划任务
  .\cli.ps1 details -TaskName Run-...      查看任务信息
  .\cli.ps1 delete -TaskName Run-...       删除任务（要求确认）
  .\cli.ps1 delete -TaskName Run-... -Force 不再额外确认删除
  .\cli.ps1 run -TaskName Run-...          运行已授权固定任务
  .\cli.ps1 help                          显示帮助

注意：管理器只修改计划任务，不会删除任何生成的 .lnk 快捷方式。
'@ | Write-Host
}

function Show-MainMenu {
    while ($true) {
        Write-Host ''
        Write-Host '========== ElevatedShortcut ==========' -ForegroundColor Cyan
        Write-Host '[1] 安装「发送到」右键入口（固定模式）'
        Write-Host '[2] 安装并开启通用任务（高风险）'
        Write-Host '[3] 创建管理员快捷方式'
        Write-Host '[4] 计划任务管理器'
        Write-Host '[5] 卸载'
        Write-Host '[6] 查看 CLI 帮助'
        Write-Host '[7] 仅安装 SendTo 菜单（保留现有任务）'
        Write-Host '[8] 仅移除 SendTo 菜单（保留现有任务）'
        Write-Host '[0] 退出'
        $selection = Read-Host '请选择'
        try {
            switch ($selection) {
                '1' { Invoke-Entry 'Install.ps1' }
                '2' {
                    Write-Warning '通用任务允许同用户进程请求运行任意管理员程序。'
                    $answer = Read-Host '请输入 ENABLE 表示明确接受风险'
                    if ($answer -ceq 'ENABLE') {
                        Invoke-Entry 'Install.ps1' @{ EnableGeneric = $true }
                    }
                }
                '3' {
                    $source = Read-Host '输入 EXE 或 LNK 的完整路径'
                    if (-not [string]::IsNullOrWhiteSpace($source)) {
                        Invoke-Entry 'New-ElevatedShortcut.ps1' @{
                            Mode = 'Fixed'; SourcePath = @($source.Trim('"'))
                        }
                    }
                }
                '4' { Invoke-Entry 'Manage-Tasks.ps1' }
                '5' {
                    $answer = Read-Host '卸载将清理受管计划任务和已记录的快捷方式，输入 UNINSTALL 确认'
                    if ($answer -ceq 'UNINSTALL') { Invoke-Entry 'Uninstall.ps1' }
                }
                '6' { Show-Help }
                '7' { Invoke-Entry 'Manage-SendTo.ps1' @{ Action = 'Install' } }
                '8' { Invoke-Entry 'Manage-SendTo.ps1' @{ Action = 'Remove' } }
                '0' { return }
                default { Write-Warning '未知选项。' }
            }
        }
        catch { Write-Warning $_.Exception.Message }
    }
}

try {
    switch ($Command.ToLowerInvariant()) {
        'menu' { Show-MainMenu }
        'help' { Show-Help }
        'install' { Invoke-Entry 'Install.ps1' @{ EnableGeneric = [bool]$EnableGeneric } }
        'uninstall' { Invoke-Entry 'Uninstall.ps1' }
        'sendto-install' { Invoke-Entry 'Manage-SendTo.ps1' @{ Action = 'Install' } }
        'sendto-remove' { Invoke-Entry 'Manage-SendTo.ps1' @{ Action = 'Remove' } }
        'create' {
            if (-not $Path -or $Path.Count -eq 0) { throw '请传入 -Path EXE/LNK 完整路径。' }
            Invoke-Entry 'New-ElevatedShortcut.ps1' @{ Mode = $Mode; SourcePath = $Path }
        }
        'tasks' { Invoke-Entry 'Manage-Tasks.ps1' @{ Action = 'Menu' } }
        'list' { Invoke-Entry 'Manage-Tasks.ps1' @{ Action = 'List' } }
        'details' { Invoke-Entry 'Manage-Tasks.ps1' @{ Action = 'Details'; TaskName = $TaskName } }
        'delete' { Invoke-Entry 'Manage-Tasks.ps1' @{ Action = 'Delete'; TaskName = $TaskName; Force = [bool]$Force } }
        'run' { Invoke-Entry 'Manage-Tasks.ps1' @{ Action = 'Run'; TaskName = $TaskName } }
        default { throw "未知命令：$Command。使用 .\cli.ps1 help 查看用法。" }
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
