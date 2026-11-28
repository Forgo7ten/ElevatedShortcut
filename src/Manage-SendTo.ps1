<#
.SYNOPSIS
    Install or remove only the current user's SendTo shortcuts.
.DESCRIPTION
    This does not create, update or delete any scheduled task or generated launcher.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Remove')]
    [string]$Action
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

$sendTo = Join-Path $env:APPDATA 'Microsoft\Windows\SendTo'
$entries = @(
    [pscustomobject]@{ Name = 'Create Admin LNK'; Mode = 'Fixed' },
    [pscustomobject]@{ Name = 'Create Admin LNK (Generic)'; Mode = 'Generic' }
)
$shell = New-Object -ComObject WScript.Shell

function Test-OwnedSendToLink([object]$Link, [string]$Mode) {
    if ([string]$Link.Description -cne ('ElevatedShortcut:SendTo:' + $Mode)) { return $false }
    $arguments = [string]$Link.Arguments
    return ($arguments.Contains('Launcher.vbs') -or $arguments.Contains('New-ElevatedShortcut.ps1'))
}

function Remove-OwnedSendToLink([object]$Entry) {
    $path = Join-Path $sendTo ($Entry.Name + '.lnk')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $link = $shell.CreateShortcut($path)
    if (-not (Test-OwnedSendToLink $link $Entry.Mode)) {
        Write-Warning "SendTo 文件并非本工具创建，已保留：$path"
        return
    }
    Remove-Item -LiteralPath $path -Force
    Write-Host "已移除 SendTo：$path"
}

function Write-OwnedSendToLink([object]$Entry) {
    $path = Join-Path $sendTo ($Entry.Name + '.lnk')
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $link = $shell.CreateShortcut($path)
        if (-not (Test-OwnedSendToLink $link $Entry.Mode)) {
            throw "SendTo 文件名被非本工具快捷方式占用：$path"
        }
    }
    $root = Get-ToolRoot
    $wscriptPath = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
    $launcherPath = Join-Path $root 'Launcher.vbs'
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $wscriptPath
    $link.Arguments = (Quote-WindowsPath $launcherPath) + ' create ' + $Entry.Mode
    $link.WorkingDirectory = $root
    $link.Description = 'ElevatedShortcut:SendTo:' + $Entry.Mode
    $iconPath = Join-Path $root 'icon.ico'
    if ([IO.File]::Exists($iconPath)) {
        $link.IconLocation = $iconPath + ',0'
    }
    else {
        $link.IconLocation = (Join-Path ([Environment]::GetFolderPath('System')) 'shell32.dll') + ',44'
    }
    $link.Save()
    Write-Host "已安装 SendTo：$path"
}

if ($Action -eq 'Remove') {
    foreach ($entry in $entries) { Remove-OwnedSendToLink $entry }
    Write-Host '仅移除了 SendTo 入口；没有改动计划任务或已生成的快捷方式。'
    return
}

Assert-InstalledLauncher
$settings = Get-InstalledSettings
$null = New-Item -ItemType Directory -Path $sendTo -Force
Write-OwnedSendToLink $entries[0]
if ([bool]$settings.allowGeneric) {
    Write-OwnedSendToLink $entries[1]
}
else {
    # If the generic mode was disabled, remove only an owned stale entry.
    Remove-OwnedSendToLink $entries[1]
}
Write-Host 'SendTo 菜单已更新；没有改动计划任务。'
