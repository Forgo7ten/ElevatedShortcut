# Shared Windows PowerShell 5.1 / PowerShell 7 implementation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectName = 'ElevatedShortcut'
$script:TaskFolderPath = '\ElevatedShortcut'
$script:TaskMarker = 'ElevatedShortcut:'
$script:ShortcutMarker = 'ElevatedShortcut:v1|'

function Assert-Windows {
    if ($env:OS -ne 'Windows_NT') {
        throw 'ElevatedShortcut 仅支持 Windows 10/11。'
    }
}

function Get-CurrentIdentity {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent()
}

function Get-CurrentSid {
    return (Get-CurrentIdentity).User.Value
}

function Test-IsElevated {
    $identity = Get-CurrentIdentity
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ToolRoot {
    return (Join-Path $env:ProgramFiles $script:ProjectName)
}

function Get-DataRoot {
    return (Join-Path $env:LOCALAPPDATA $script:ProjectName)
}

function Assert-InstalledLauncher {
    $launcher = Join-Path (Get-ToolRoot) 'Launcher.vbs'
    if (-not [IO.File]::Exists($launcher)) {
        throw '尚未安装 ElevatedShortcut，请先运行 cli.ps1 install 完成安装后再创建管理员快捷方式。'
    }
}

function Get-Hash24([string]$Value) {
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $hasher.ComputeHash($bytes)
        return (([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 24).ToLowerInvariant())
    }
    finally {
        $hasher.Dispose()
    }
}

function Get-SpecId([object]$Spec) {
    $fields = @(
        'v1',
        (Get-CurrentSid),
        ([string]$Spec.TargetPath).ToLowerInvariant(),
        [string]$Spec.Arguments,
        ([string]$Spec.WorkingDirectory).ToLowerInvariant()
    )
    # Length-prefix each field so the ID is unambiguous and byte-stable
    # across PowerShell 5.1 and 7 JSON serialization differences.
    $builder = [System.Text.StringBuilder]::new()
    foreach ($field in $fields) {
        $text = [string]$field
        $null = $builder.Append($text.Length.ToString([Globalization.CultureInfo]::InvariantCulture))
        $null = $builder.Append(':')
        $null = $builder.Append($text)
    }
    return (Get-Hash24 $builder.ToString())
}

function Get-GenericTaskName {
    return ('Generic-' + (Get-Hash24 (Get-CurrentSid)))
}

function Get-TaskDisplayToken([object]$Spec) {
    $raw = [IO.Path]::GetFileNameWithoutExtension([string]$Spec.TargetPath)
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = 'App' }
    # Task Scheduler names cannot contain path separators or control characters.
    # Keep Unicode names readable while replacing reserved punctuation.
    $token = [regex]::Replace($raw, '[\x00-\x1F\\/:*?"<>|]+', '_')
    $token = $token.Trim([char[]]@(' ', '.', '_', '-'))
    if ([string]::IsNullOrWhiteSpace($token)) { $token = 'App' }
    if ($token.Length -gt 40) { $token = $token.Substring(0, 40) }
    return $token
}

function Get-FixedTaskNameInfo([string]$Name) {
    if ($Name -cmatch '^Run-(.+)-([0-9a-f]{24})$') {
        return [pscustomobject]@{ Id = [string]$Matches[2] }
    }
    return $null
}

function Test-LocalExecutable([string]$TargetPath) {
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $false }
    if (-not [System.IO.Path]::IsPathRooted($TargetPath)) { return $false }
    if ($TargetPath.StartsWith('\\') -or $TargetPath.StartsWith('\\?\') -or $TargetPath.StartsWith('\\.\')) {
        return $false
    }
    if (-not $TargetPath.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return [System.IO.File]::Exists($TargetPath)
}

function Resolve-Source([string]$SourcePath) {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) { throw '请提供 EXE 或 LNK 文件路径。' }
    $item = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
    if ($item.PSIsContainer) { throw "路径不是文件：$SourcePath" }
    $ext = $item.Extension.ToLowerInvariant()
    if ($ext -notin @('.exe', '.lnk')) { throw "仅支持 .exe 和 .lnk 文件：$($item.FullName)" }

    $target = $item.FullName
    $arguments = ''
    $workingDirectory = Split-Path -Parent $target
    $icon = $target + ',0'

    if ($ext -eq '.lnk') {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($item.FullName)
        if ([string]$link.Description -like ($script:ShortcutMarker + '*')) {
            throw '所选快捷方式已是由 ElevatedShortcut 生成的管理员快捷方式，请选择原始程序或原始快捷方式。'
        }
        $target = [string]$link.TargetPath
        $arguments = [string]$link.Arguments
        $workingDirectory = [string]$link.WorkingDirectory
        $icon = [string]$link.IconLocation
    }

    $target = [Environment]::ExpandEnvironmentVariables($target)
    if (-not [System.IO.Path]::IsPathRooted($target)) { throw "不支持的快捷方式目标：$target" }
    $target = [System.IO.Path]::GetFullPath($target)
    if (-not (Test-LocalExecutable $target)) {
        throw "快捷方式目标必须是本地已存在的 .exe 文件：$target"
    }
    if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
        $workingDirectory = Split-Path -Parent $target
    }
    $workingDirectory = [Environment]::ExpandEnvironmentVariables($workingDirectory)
    if (-not [System.IO.Path]::IsPathRooted($workingDirectory)) {
        throw "工作目录必须是绝对路径：$workingDirectory"
    }
    $workingDirectory = [System.IO.Path]::GetFullPath($workingDirectory)
    if (-not [System.IO.Directory]::Exists($workingDirectory)) {
        throw "工作目录不存在：$workingDirectory"
    }
    if ([string]::IsNullOrWhiteSpace($icon) -or $icon -eq ',0') { $icon = $target + ',0' }

    return [pscustomobject]@{
        SourcePath       = $item.FullName
        SourceDirectory  = $item.DirectoryName
        DisplayName      = $item.BaseName
        TargetPath       = $target
        Arguments        = $arguments
        WorkingDirectory = $workingDirectory
        IconLocation     = $icon
    }
}

function Write-JsonFile([string]$Path, [object]$Data) {
    $json = ConvertTo-Json -InputObject $Data -Depth 8 -Compress
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json)
}

function Quote-WindowsPath([string]$Path) {
    if ($Path.Contains('"')) { throw 'Windows 文件路径不能包含双引号。' }
    return ('"' + $Path + '"')
}

function Test-UsablePowerShellBinary([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # Exclude Microsoft Store / MSIX AppExecLink and WindowsApps package binaries,
    # which are per-user or fail across UAC RunAs elevation due to package ACLs.
    if ($Path -match '(?i)[\\/]WindowsApps[\\/]') { return $false }
    return [System.IO.File]::Exists($Path)
}

function Get-PowerShellPath {
    $current = (Get-Process -Id $PID).Path
    if ((Split-Path -Leaf $current) -ieq 'pwsh.exe' -and (Test-UsablePowerShellBinary $current)) {
        return $current
    }
    foreach ($candidate in @(Get-Command pwsh.exe -All -ErrorAction SilentlyContinue)) {
        if (Test-UsablePowerShellBinary ([string]$candidate.Source)) {
            return [string]$candidate.Source
        }
    }
    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw '未找到可用的 PowerShell 7 或 Windows PowerShell 5.1。'
    }
    return $windowsPowerShell
}

function New-TaskService {
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    return $service
}

function Get-TaskSecurityDescriptor {
    # The task is owned by Administrators. An unelevated instance of this user
    # can READ/RUN but cannot UPDATE the task's action or change its DACL.
    # TASK_DONT_ADD_PRINCIPAL_ACE must be set when registering (see below).
    return ('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FRFX;;;' + (Get-CurrentSid) + ')')
}

function Get-FolderSecurityDescriptor {
    # All interactive users can list/traverse the folder, but only elevated
    # Administrators can add or modify task definitions in it.
    return 'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FRFX;;;BU)'
}

function Get-ToolTaskFolder([object]$Service, [bool]$Create) {
    try { return $Service.GetFolder($script:TaskFolderPath) }
    catch {
        if (-not $Create) { return $null }
        return $Service.GetFolder('\').CreateFolder($script:ProjectName, (Get-FolderSecurityDescriptor))
    }
}

function Find-RegisteredTask([object]$Folder, [string]$Name) {
    if ($null -eq $Folder) { return $null }
    $tasks = $Folder.GetTasks(1)
    for ($i = 1; $i -le $tasks.Count; $i++) {
        $task = $tasks.Item($i)
        if ([string]::Equals([string]$task.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            return $task
        }
    }
    return $null
}

function Resolve-PrincipalSid([string]$PrincipalId) {
    if ($PrincipalId -match '^S-1-') { return $PrincipalId }
    try {
        return ([System.Security.Principal.NTAccount]::new($PrincipalId)).Translate(
            [System.Security.Principal.SecurityIdentifier]
        ).Value
    }
    catch { return '' }
}

# The first line is an immutable machine-readable identity marker.
# Subsequent lines provide human-readable task details.
function Test-TaskDescriptionIdentity([string]$Description, [string]$Identity) {
    # Task Scheduler XML storage normalizes CRLF to LF on RegistrationInfo.Description.
    $normalizedDescription = $Description -replace "`r`n", "`n"
    $normalizedIdentity = $Identity -replace "`r`n", "`n"
    if ([string]::Equals($normalizedDescription, $normalizedIdentity, [StringComparison]::Ordinal)) { return $true }
    return $normalizedDescription.StartsWith(($normalizedIdentity + "`n"), [StringComparison]::Ordinal)
}

function Limit-DescriptionText([string]$Text, [int]$Limit = 920) {
    if ($null -eq $Text) { return '' }
    $value = $Text.Trim()
    if ($value.Length -le $Limit) { return $value }
    return ($value.Substring(0, [Math]::Max(0, $Limit - 3)) + '...')
}

function Get-FixedTaskDescription([string]$Id, [object]$Spec) {
    $marker = $script:TaskMarker + $Id
    $lines = @(
        $marker,
        ('应用：' + ([IO.Path]::GetFileName([string]$Spec.TargetPath) -replace '[\r\n]+', ' ')),
        ('目标程序：' + ([string]$Spec.TargetPath -replace '[\r\n]+', ' ')),
        ('启动参数：' + ([string]$Spec.Arguments -replace '[\r\n]+', ' ')),
        ('工作目录：' + ([string]$Spec.WorkingDirectory -replace '[\r\n]+', ' '))
    )
    return (Limit-DescriptionText ($lines -join "`r`n") 920)
}

function Get-GenericTaskDescription {
    $marker = $script:TaskMarker + 'generic:' + (Get-CurrentSid)
    return ($marker + "`r`n" + '用途：通用管理员启动任务（显式启用）' + "`r`n" +
        '说明：按需执行用户队列中的本地 EXE；存在任意管理员程序执行风险。')
}

function Assert-TaskMatches([object]$Task, [string]$Description,
        [string]$Executable, [string]$Arguments, [string]$WorkingDirectory) {
    $definition = $Task.Definition
    if (-not (Test-TaskDescriptionIdentity ([string]$definition.RegistrationInfo.Description) $Description)) {
        throw "计划任务名称冲突或身份标记已被修改：$($Task.Name)"
    }
    if ([int]$definition.Principal.RunLevel -ne 1 -or [int]$definition.Principal.LogonType -ne 3) {
        throw "计划任务权限级别或登录类型异常：$($Task.Name)"
    }
    if ((Resolve-PrincipalSid ([string]$definition.Principal.UserId)) -ne (Get-CurrentSid)) {
        throw "计划任务属于其他用户账户：$($Task.Name)"
    }
    if ([int]$definition.Actions.Count -ne 1) {
        throw "计划任务动作数量异常：$($Task.Name)"
    }
    $action = $definition.Actions.Item(1)
    if (-not [string]::Equals([string]$action.Path, $Executable, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$action.Arguments -cne $Arguments -or
        -not [string]::Equals([string]$action.WorkingDirectory, $WorkingDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        throw "计划任务执行动作已被篡改：$($Task.Name)"
    }
}

function Ensure-ElevatedTask([string]$Name, [string]$Description,
        [string]$Executable, [string]$Arguments, [string]$WorkingDirectory,
        [int]$MultipleInstances = 0) {
    if (-not (Test-IsElevated)) { throw '注册最高权限计划任务需要管理员权限。' }
    $service = New-TaskService
    $folder = Get-ToolTaskFolder $service $true
    $existing = Find-RegisteredTask $folder $Name
    if ($null -ne $existing) {
        Assert-TaskMatches $existing $Description $Executable $Arguments $WorkingDirectory
        return '已复用'
    }

    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = $Description
    $definition.RegistrationInfo.Author = 'ElevatedShortcut'
    $definition.Principal.UserId = (Get-CurrentSid)
    $definition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
    $definition.Principal.RunLevel = 1  # TASK_RUNLEVEL_HIGHEST
    $definition.Settings.Enabled = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT0S'
    $definition.Settings.MultipleInstances = $MultipleInstances
    $definition.Settings.Priority = 4   # NORMAL_PRIORITY_CLASS + normal I/O and memory priority
    $action = $definition.Actions.Create(0) # TASK_ACTION_EXEC
    $action.Path = $Executable
    $action.Arguments = $Arguments
    $action.WorkingDirectory = $WorkingDirectory
    # TASK_CREATE (2) | TASK_DONT_ADD_PRINCIPAL_ACE (0x10) = 18.
    # Without 0x10, Scheduler can add a broad principal ACE that turns even
    # fixed tasks into a same-user arbitrary-elevation vector.
    $sddl = Get-TaskSecurityDescriptor
    $null = $folder.RegisterTaskDefinition($Name, $definition, 18, $null, $null, 3, $sddl)
    return '已创建'
}

function Get-TaskName([string]$Mode, [string]$Id, [object]$Spec = $null) {
    if ($Mode -eq 'Generic') { return (Get-GenericTaskName) }
    if ($Mode -ne 'Fixed') { throw "不支持的任务模式：$Mode" }
    if ($null -eq $Spec) { throw '构建固定任务名称需要传入目标配置。' }
    # Task names identify the purpose and executable, while the
    # stable ID keeps names unique and preserves deterministic reuse.
    return ('Run-' + (Get-TaskDisplayToken $Spec) + '-' + $Id)
}

function Get-ManagedShortcutArguments([string]$Mode, [string]$Id) {
    $launcher = Join-Path (Get-ToolRoot) 'Launcher.vbs'
    return ((Quote-WindowsPath $launcher) + ' ' + $Mode.ToLowerInvariant() + ' ' + $Id)
}

function Test-IsManagedShortcut([string]$Path, [string]$Mode, [string]$Id) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)
        $wscriptPath = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
        return ([string]$shortcut.Description -ceq ($script:ShortcutMarker + $Mode + '|' + $Id) -and
            [string]::Equals([string]$shortcut.TargetPath, $wscriptPath, [StringComparison]::OrdinalIgnoreCase) -and
            [string]$shortcut.Arguments -ceq (Get-ManagedShortcutArguments $Mode $Id))
    }
    catch { return $false }
}

function Get-OutputName([string]$DisplayName, [string]$Mode) {
    if ($Mode -eq 'Generic') { return $DisplayName + '(Admin-G)' }
    return $DisplayName + ' (Admin)'
}

function Get-OutputDirectories([object]$Spec, [string]$DesktopDirectory) {
    # SourcePath is the selected item in Explorer, NOT the target of an LNK.
    # The optional SourceDirectory value is derived from Get-Item on the source.
    $sourceDirectory = [string]$Spec.SourceDirectory
    if ([string]::IsNullOrWhiteSpace($sourceDirectory)) {
        $sourceDirectory = [IO.Path]::GetDirectoryName([string]$Spec.SourcePath)
    }
    if ([string]::IsNullOrWhiteSpace($sourceDirectory)) { throw '无法确定源文件所在目录。' }
    if ([string]::IsNullOrWhiteSpace($DesktopDirectory)) { throw '无法定位当前用户桌面目录。' }
    $sourceDirectory = [IO.Path]::GetFullPath($sourceDirectory)
    $DesktopDirectory = [IO.Path]::GetFullPath($DesktopDirectory)
    Write-Output $sourceDirectory
    if (-not [string]::Equals($sourceDirectory, $DesktopDirectory,
            [StringComparison]::OrdinalIgnoreCase)) {
        Write-Output $DesktopDirectory
    }
}

function Save-ManagedShortcut([object]$Spec, [string]$Mode, [string]$Id,
        [string]$DesktopDirectory = '') {
    $baseName = Get-OutputName ([string]$Spec.DisplayName) $Mode
    if ([string]::IsNullOrWhiteSpace($DesktopDirectory)) {
        $DesktopDirectory = [Environment]::GetFolderPath('DesktopDirectory')
    }
    $folders = @(Get-OutputDirectories $Spec $DesktopDirectory)
    foreach ($folder in $folders) {
        try {
            if (-not [System.IO.Directory]::Exists($folder)) {
                $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop
            }
            for ($suffix = 1; $suffix -le 99; $suffix++) {
                $name = $baseName
                if ($suffix -gt 1) { $name += " ($suffix)" }
                $candidate = Join-Path $folder ($name + '.lnk')
                if (Test-IsManagedShortcut $candidate $Mode $Id) { return $candidate }
                if (Test-Path -LiteralPath $candidate) { continue }
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $shortcut = $shell.CreateShortcut($candidate)
                    $shortcut.TargetPath = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
                    $shortcut.Arguments = Get-ManagedShortcutArguments $Mode $Id
                    $shortcut.WorkingDirectory = [string]$Spec.WorkingDirectory
                    $shortcut.Description = $script:ShortcutMarker + $Mode + '|' + $Id
                    try { $shortcut.IconLocation = [string]$Spec.IconLocation }
                    catch { $shortcut.IconLocation = ([string]$Spec.TargetPath + ',0') }
                    $shortcut.Save()
                    return $candidate
                }
                catch {
                    # Do not delete a file unless this invocation created it.
                    # In particular, do not overwrite someone else's existing .lnk.
                    throw
                }
            }
            throw "目录中无可用的快捷方式名称：$folder"
        }
        catch {
            if ($folder -eq $folders[-1]) { throw }
            Write-Warning "无法写入源文件所在目录，已回退到桌面：$($_.Exception.Message)"
        }
    }
}

function Save-ShortcutRecord([string]$ShortcutPath, [string]$Mode, [string]$Id) {
    $directory = Join-Path (Get-DataRoot) 'records'
    $null = New-Item -ItemType Directory -Path $directory -Force
    $recordId = Get-Hash24 ($ShortcutPath.ToLowerInvariant())
    $path = Join-Path $directory ($recordId + '.json')
    Write-JsonFile $path ([ordered]@{
        schema = 1
        path = $ShortcutPath
        mode = $Mode
        id = $Id
        savedUtc = [DateTime]::UtcNow.ToString('o')
    })
}

function Get-InstalledSettings {
    $path = Join-Path (Get-ToolRoot) 'settings.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '尚未安装本工具，请先运行 cli.ps1 install 完成安装。' }
    return (Read-JsonFile $path)
}

function Assert-GenericEnabled {
    $settings = Get-InstalledSettings
    if (-not [bool]$settings.allowGeneric) {
        throw '通用模式未启用。如需启用，请以管理员身份运行 cli.ps1 install -EnableGeneric。'
    }
}

function Assert-GenericTaskRegistered {
    Assert-GenericEnabled
    $service = New-TaskService
    $folder = Get-ToolTaskFolder $service $false
    $task = Find-RegisteredTask $folder (Get-GenericTaskName)
    if ($null -eq $task) { throw '通用计划任务尚未注册，请重新运行 cli.ps1 install -EnableGeneric。' }
    $root = Get-ToolRoot
    $wscriptPath = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
    $args = (Quote-WindowsPath (Join-Path $root 'Launcher.vbs')) + ' worker'
    Assert-TaskMatches $task ($script:TaskMarker + 'generic:' + (Get-CurrentSid)) $wscriptPath $args $root
    return $task
}
