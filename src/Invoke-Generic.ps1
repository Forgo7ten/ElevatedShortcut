<#
.SYNOPSIS
    Enqueue a dynamically selected EXE for the explicitly enabled generic task.
.EXAMPLE
    .\Invoke-Generic.ps1 -TargetPath 'C:\Tools\App.exe' -Arguments '--demo' -WorkingDirectory 'C:\Tools'
.EXAMPLE
    .\Invoke-Generic.ps1 -ProfileId '1234567890abcdef12345678'
#>
[CmdletBinding(DefaultParameterSetName = 'Direct')]
param(
    [Parameter(ParameterSetName = 'Profile', Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{24}$')]
    [string]$ProfileId,
    [Parameter(ParameterSetName = 'Direct', Mandatory = $true)]
    [string]$TargetPath,
    [Parameter(ParameterSetName = 'Direct')]
    [string]$Arguments = '',
    [Parameter(ParameterSetName = 'Direct')]
    [string]$WorkingDirectory = ''
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

try {
    $genericTask = Assert-GenericTaskRegistered
    if ($PSCmdlet.ParameterSetName -eq 'Profile') {
        $profilePath = Join-Path (Join-Path (Get-DataRoot) 'profiles') ($ProfileId + '.json')
        if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "未找到通用任务配置文件：$ProfileId" }
        $profile = Read-JsonFile $profilePath
        if ([int]$profile.schema -ne 1 -or [string]$profile.id -cne $ProfileId) { throw '通用任务配置文件无效。' }
        $TargetPath = [string]$profile.targetPath
        $Arguments = [string]$profile.arguments
        $WorkingDirectory = [string]$profile.workingDirectory
    }

    $TargetPath = [Environment]::ExpandEnvironmentVariables($TargetPath)
    if (-not (Test-LocalExecutable $TargetPath)) { throw "目标必须是本地已存在的 EXE 文件：$TargetPath" }
    $TargetPath = [IO.Path]::GetFullPath($TargetPath)
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = [IO.Path]::GetDirectoryName($TargetPath)
    }
    $WorkingDirectory = [Environment]::ExpandEnvironmentVariables($WorkingDirectory)
    if (-not [IO.Path]::IsPathRooted($WorkingDirectory) -or
        -not [IO.Directory]::Exists($WorkingDirectory)) { throw '工作目录无效。' }
    if ($Arguments.Length -gt 32768) { throw '启动参数超过最大长度限制。' }

    $queue = Join-Path (Get-DataRoot) 'queue'
    $null = New-Item -ItemType Directory -Path $queue -Force
    $id = [guid]::NewGuid().ToString('N')
    $temp = Join-Path $queue ($id + '.tmp')
    $ready = Join-Path $queue ($id + '.json')
    Write-JsonFile $temp ([ordered]@{
        schema = 1
        id = $id
        targetPath = $TargetPath
        arguments = $Arguments
        workingDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
    })
    [IO.File]::Move($temp, $ready) # Publish atomically only after write completes.

    try {
        $null = $genericTask.Run($null)
    }
    catch {
        Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
        throw "无法触发通用计划任务：$($_.Exception.Message)"
    }
    exit 0
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
