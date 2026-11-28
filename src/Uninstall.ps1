<#
.SYNOPSIS
    Remove this user's managed shortcuts, tasks, profiles and SendTo entries.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

if (-not (Test-IsElevated)) {
    $engine = Get-PowerShellPath
    $args = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
        (Quote-WindowsPath $PSCommandPath)
    $child = Start-Process -FilePath $engine -ArgumentList $args -Verb RunAs -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw "卸载失败或已取消 UAC 授权（退出码 $($child.ExitCode)）。" }
    Write-Host '卸载已完成。' -ForegroundColor Green
    exit 0
}

$root = Get-ToolRoot
$data = Get-DataRoot
$records = Join-Path $data 'records'

if ([IO.Directory]::Exists($records)) {
    foreach ($file in @(Get-ChildItem -LiteralPath $records -Filter '*.json' -File)) {
        try {
            $record = Read-JsonFile $file.FullName
            if ([int]$record.schema -eq 1 -and
                [string]$record.mode -in @('Fixed', 'Generic') -and
                [string]$record.id -match '^[0-9a-f]{24}$' -and
                (Test-IsManagedShortcut ([string]$record.path) ([string]$record.mode) ([string]$record.id))) {
                Remove-Item -LiteralPath ([string]$record.path) -Force
                Write-Host "已移除快捷方式：$($record.path)"
            }
            Remove-Item -LiteralPath $file.FullName -Force
        }
        catch { Write-Warning "无法清理记录文件 $($file.FullName)：$($_.Exception.Message)" }
    }
}

# Remove only this user's owned SendTo links. Do not affect unrelated files.
& (Join-Path $PSScriptRoot 'Manage-SendTo.ps1') -Action Remove
$shell = New-Object -ComObject WScript.Shell

$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$managerShortcutPath = Join-Path $programs 'ElevatedShortcut 任务管理器.lnk'
if (Test-Path -LiteralPath $managerShortcutPath -PathType Leaf) {
    try {
        $managerShortcut = $shell.CreateShortcut($managerShortcutPath)
        if ([string]$managerShortcut.Description -ceq 'ElevatedShortcut:TaskManager:v1' -and
            ([string]$managerShortcut.Arguments).Contains('Manage-Tasks.ps1')) {
            Remove-Item -LiteralPath $managerShortcutPath -Force
            Write-Host "已移除开始菜单任务管理器：$managerShortcutPath"
        }
    }
    catch { Write-Warning "无法移除开始菜单快捷方式 $managerShortcutPath ：$_" }
}

$service = New-TaskService
$folder = Get-ToolTaskFolder $service $false
if ($null -ne $folder) {
    $all = $folder.GetTasks(1)
    $names = @()
    for ($i = 1; $i -le $all.Count; $i++) {
        $task = $all.Item($i)
        $description = [string]$task.Definition.RegistrationInfo.Description
        $sid = Resolve-PrincipalSid ([string]$task.Definition.Principal.UserId)
        if ($description.StartsWith($script:TaskMarker, [StringComparison]::Ordinal) -and
            $sid -eq (Get-CurrentSid)) {
            $names += [string]$task.Name
        }
    }
    foreach ($name in $names) {
        $folder.DeleteTask($name, 0)
        Write-Host "已移除计划任务：$($script:TaskFolderPath)\$name"
    }
    $left = $folder.GetTasks(1)
    if ($left.Count -eq 0) {
        try { $service.GetFolder('\').DeleteFolder($script:ProjectName, 0) }
        catch { Write-Warning "无法删除空的计划任务文件夹：$_" }
    }
}

# Delete only known tool-owned data formats, never an arbitrary nested tree.
foreach ($sub in @('queue', 'profiles', 'records')) {
    $folderPath = Join-Path $data $sub
    if ([IO.Directory]::Exists($folderPath)) {
        $patterns = @('*.json')
        if ($sub -eq 'queue') { $patterns += @('*.tmp', '*.working') }
        foreach ($pattern in $patterns) {
            foreach ($item in @(Get-ChildItem -LiteralPath $folderPath -Filter $pattern -File -ErrorAction SilentlyContinue)) {
                try { Remove-Item -LiteralPath $item.FullName -Force }
                catch { Write-Warning "无法删除文件 $($item.FullName)：$_" }
            }
        }
        try { [IO.Directory]::Delete($folderPath, $false) }
        catch { Write-Warning "目录 $folderPath 中仍存在未识别文件，已保留。" }
    }
}
if ([IO.Directory]::Exists($data)) {
    try { [IO.Directory]::Delete($data, $false) }
    catch { Write-Warning '用户数据目录中仍存在其他文件，已保留。' }
}

$canRemoveRoot = $true
$checkFolder = Get-ToolTaskFolder $service $false
if ($null -ne $checkFolder -and $checkFolder.GetTasks(1).Count -gt 0) {
    $canRemoveRoot = $false
    Write-Warning '系统中仍存在其他用户的受管任务，已保留 Program Files 共享组件。'
}
if ($canRemoveRoot -and (Test-Path -LiteralPath $root)) {
    foreach ($name in @('Common.ps1','New-ElevatedShortcut.ps1','Register-FixedTask.ps1',
        'Invoke-Generic.ps1','GenericWorker.ps1','Manage-Tasks.ps1','Manage-SendTo.ps1','Install.ps1','Uninstall.ps1',
        'Launcher.vbs','settings.json','EnginePath.txt','icon.ico')) {
        $path = Join-Path $root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try { Remove-Item -LiteralPath $path -Force }
            catch { Write-Warning "无法删除已安装文件 $path ：$_" }
        }
    }
    try { [IO.Directory]::Delete($root, $false) }
    catch { Write-Warning '安装目录中仍存在其他文件，已保留。' }
}
Write-Host '卸载完成。未识别或已被修改的快捷方式不会被删除。'
