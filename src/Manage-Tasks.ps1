<#
.SYNOPSIS
    只管理 ElevatedShortcut 为当前 Windows 用户创建的计划任务。
.DESCRIPTION
    默认提供交互式管理菜单。列出、查看、运行以及删除计划任务；
    不定位、不移动、不删除用户生成的快捷方式。
.EXAMPLE
    .\Manage-Tasks.ps1
.EXAMPLE
    .\Manage-Tasks.ps1 -Action List
.EXAMPLE
    .\Manage-Tasks.ps1 -Action Delete -TaskName Run-App-0123456789abcdef01234567
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'List', 'Details', 'Delete', 'Run')]
    [string]$Action = 'Menu',
    [string]$TaskName = '',
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

function Get-ManagedTaskInfo([object]$Task) {
    try {
        $name = [string]$Task.Name
        $definition = $Task.Definition
        if ((Resolve-PrincipalSid ([string]$definition.Principal.UserId)) -ne (Get-CurrentSid)) { return $null }
        if ([int]$definition.Principal.RunLevel -ne 1 -or [int]$definition.Principal.LogonType -ne 3) { return $null }
        if ([int]$definition.Actions.Count -ne 1) { return $null }
        $taskAction = $definition.Actions.Item(1)
        if ([int]$taskAction.Type -ne 0) { return $null }

        $mode = ''
        $id = ''
        $identity = ''
        $label = ''
        $target = [string]$taskAction.Path
        $arguments = [string]$taskAction.Arguments
        $workingDirectory = [string]$taskAction.WorkingDirectory
        $nameInfo = Get-FixedTaskNameInfo $name
        if ($null -ne $nameInfo) {
            $mode = 'Fixed'
            $id = [string]$nameInfo.Id
        }
        if ($mode -eq 'Fixed') {
            $identity = $script:TaskMarker + $id
            $spec = [pscustomobject]@{
                TargetPath = $target
                Arguments = $arguments
                WorkingDirectory = $workingDirectory
            }
            # A task with a changed action or a forged readable prefix must
            # not be treated as an intact tool-owned fixed task.
            if ((Get-SpecId $spec) -cne $id) { return $null }
            $expectedName = Get-TaskName 'Fixed' $id $spec
            if (-not [string]::Equals($name, $expectedName, [StringComparison]::OrdinalIgnoreCase)) { return $null }
            $label = [IO.Path]::GetFileName($target)
        }
        elseif ([string]::Equals($name, (Get-GenericTaskName), [StringComparison]::OrdinalIgnoreCase)) {
            $mode = 'Generic'
            $identity = $script:TaskMarker + 'generic:' + (Get-CurrentSid)
            $root = Get-ToolRoot
            $wscriptPath = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
            $expectedArgs = (Quote-WindowsPath (Join-Path $root 'Launcher.vbs')) + ' worker'
            if (-not [string]::Equals($target, $wscriptPath, [StringComparison]::OrdinalIgnoreCase) -or
                $arguments -cne $expectedArgs -or
                -not [string]::Equals($workingDirectory, $root, [StringComparison]::OrdinalIgnoreCase)) {
                return $null
            }
            $label = '通用管理员任务（可执行任意用户指定程序）'
        }
        else { return $null }
        $description = [string]$definition.RegistrationInfo.Description
        if (-not (Test-TaskDescriptionIdentity $description $identity)) { return $null }
        $states = @('未知', '已禁用', '排队中', '就绪', '运行中')
        $stateValue = [int]$Task.State
        $state = '未知'
        if ($stateValue -ge 0 -and $stateValue -lt $states.Count) { $state = $states[$stateValue] }
        return [pscustomobject]@{
            Name = $name
            Mode = $mode
            Id = $id
            Application = $label
            TargetPath = $target
            Arguments = $arguments
            WorkingDirectory = $workingDirectory
            Description = $description
            State = $state
            LastRunTime = $Task.LastRunTime
            LastTaskResult = $Task.LastTaskResult
            Task = $Task
        }
    }
    catch {
        Write-Verbose ("Skipping an unreadable task: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-ManagedTasks {
    $service = New-TaskService
    $folder = Get-ToolTaskFolder $service $false
    if ($null -eq $folder) { return }
    $tasks = $folder.GetTasks(1)
    for ($i = 1; $i -le $tasks.Count; $i++) {
        $item = Get-ManagedTaskInfo ($tasks.Item($i))
        if ($null -ne $item) { Write-Output $item }
    }
}

function Get-OneManagedTask([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { throw '请使用 -TaskName 指定完整任务名称。' }
    foreach ($item in @(Get-ManagedTasks)) {
        if ([string]::Equals($item.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            return $item
        }
    }
    throw "未找到属于当前用户的受管任务：$Name"
}

function Write-TaskList {
    $items = @(Get-ManagedTasks | Sort-Object Application, Name)
    if ($items.Count -eq 0) {
        Write-Host '当前没有可管理的 ElevatedShortcut 计划任务。'
        return
    }
    $rows = foreach ($item in $items) {
        [pscustomobject]@{
            '任务名称' = $item.Name
            '类型' = $(if ($item.Mode -eq 'Fixed') { '固定目标' } else { '通用' })
            '程序' = $item.Application
            '状态' = $item.State
        }
    }
    $rows | Format-Table -AutoSize -Wrap | Out-Host
    Write-Host ("当前用户共有 {0} 个受管任务。可使用 Details 查看路径/参数。" -f $items.Count)
}

function Write-TaskDetails([object]$Item) {
    [pscustomobject]@{
        '任务名称' = $Item.Name
        '模式' = $(if ($Item.Mode -eq 'Fixed') { '固定目标' } else { '通用' })
        '应用' = $Item.Application
        '可执行文件' = $Item.TargetPath
        '启动参数' = $Item.Arguments
        '工作目录' = $Item.WorkingDirectory
        '运行状态' = $Item.State
        '上次执行' = $Item.LastRunTime
        '上次结果' = $Item.LastTaskResult
        '任务描述' = $Item.Description
    } | Format-List | Out-Host
}

function Invoke-ElevatedManager([string]$Operation, [string]$Name = '') {
    $engine = Get-PowerShellPath
    # Prefer the administrator-protected installation copy. Never elevate a
    # user-writable repository script if a protected installed copy exists.
    $installedManager = Join-Path (Get-ToolRoot) 'Manage-Tasks.ps1'
    $helper = $PSCommandPath
    if (Test-Path -LiteralPath $installedManager -PathType Leaf) {
        $helper = $installedManager
    }
    $command = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
        (Quote-WindowsPath $helper) + ' -Action ' + $Operation + ' -Force'
    if (-not [string]::IsNullOrEmpty($Name)) {
        $command += ' -TaskName ' + (Quote-WindowsPath $Name)
    }
    $child = Start-Process -FilePath $engine -ArgumentList $command -Verb RunAs -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw "操作失败或已取消 UAC 确认（退出码 $($child.ExitCode)）。" }
}

function Remove-OneTask([string]$Name, [switch]$SkipConfirm) {
    $item = Get-OneManagedTask $Name
    if (-not $SkipConfirm) {
        Write-TaskDetails $item
        $answer = Read-Host '确定删除这个计划任务？请输入 DELETE 确认'
        if ($answer -cne 'DELETE') { Write-Host '已取消删除。'; return }
    }
    if (-not (Test-IsElevated)) {
        Invoke-ElevatedManager 'Delete' $item.Name
        Write-Host ("已删除：{0}\{1}" -f $script:TaskFolderPath, $item.Name) -ForegroundColor Green
        Write-Host '未修改或删除任何快捷方式；此前指向该任务的快捷方式会失效。'
        return
    }
    # Recheck ownership and identity after UAC elevation; never blindly delete.
    $null = Get-OneManagedTask $item.Name
    $service = New-TaskService
    $folder = Get-ToolTaskFolder $service $false
    if ($null -eq $folder) { throw '计划任务文件夹不存在。' }
    $folder.DeleteTask($item.Name, 0)
    Write-Host ("已删除：{0}\{1}" -f $script:TaskFolderPath, $item.Name) -ForegroundColor Green
    Write-Host '未修改或删除任何快捷方式；此前指向该任务的快捷方式会失效。'
}

function Read-SelectedTaskName {
    $items = @(Get-ManagedTasks | Sort-Object Application, Name)
    if ($items.Count -eq 0) { Write-Host '当前无可管理任务。'; return '' }
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ("[{0}] {1} - {2}" -f ($i + 1), $items[$i].Application, $items[$i].Name)
    }
    $choice = Read-Host '输入序号或完整任务名称（直接回车取消）'
    if ([string]::IsNullOrWhiteSpace($choice)) { return '' }
    $index = 0
    if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $items.Count) {
        return $items[$index - 1].Name
    }
    return (Get-OneManagedTask $choice).Name
}

function Show-ManagerMenu {
    while ($true) {
        Write-Host ''
        Write-Host '======= ElevatedShortcut 任务管理器 =======' -ForegroundColor Cyan
        Write-Host '[1] 列出任务'
        Write-Host '[2] 查看任务详情'
        Write-Host '[3] 删除指定任务'
        Write-Host '[4] 运行固定目标任务'
        Write-Host '[0] 退出'
        $choice = Read-Host '请选择'
        try {
            switch ($choice) {
                '1' { Write-TaskList }
                '2' { $name = Read-SelectedTaskName; if ($name) { Write-TaskDetails (Get-OneManagedTask $name) } }
                '3' { $name = Read-SelectedTaskName; if ($name) { Remove-OneTask $name } }
                '4' {
                    $name = Read-SelectedTaskName
                    if ($name) { Start-OneTask $name }
                }
                '0' { return }
                default { Write-Warning '未知选项。' }
            }
        }
        catch { Write-Warning $_.Exception.Message }
    }
}

function Start-OneTask([string]$Name) {
    $item = Get-OneManagedTask $Name
    if ($item.Mode -ne 'Fixed') { throw '通用任务需要请求队列；请使用 Invoke-Generic.ps1 启动。' }
    $fullName = $script:TaskFolderPath + '\' + $item.Name
    try {
        $null = $item.Task.Run($null)
    }
    catch {
        throw "任务启动失败：$($_.Exception.Message)"
    }
    Write-Host "已触发：$fullName"
}

try {
    switch ($Action) {
        'Menu' { Show-ManagerMenu }
        'List' { Write-TaskList }
        'Details' { Write-TaskDetails (Get-OneManagedTask $TaskName) }
        'Delete' { Remove-OneTask $TaskName -SkipConfirm:$Force }
        'Run' { Start-OneTask $TaskName }
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
