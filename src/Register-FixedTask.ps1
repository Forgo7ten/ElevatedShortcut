<#
.SYNOPSIS
    Elevated helper invoked only when a fixed task must be registered.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9+/=]+$')]
    [string]$SpecBase64
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

try {
    if (-not (Test-IsElevated)) { throw '请以管理员权限运行任务注册程序。' }
    $json = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($SpecBase64))
    $spec = $json | ConvertFrom-Json
    if (-not (Test-LocalExecutable ([string]$spec.TargetPath))) {
        throw '固定任务目标必须是本地已存在的 EXE 文件。'
    }
    if (-not [IO.Directory]::Exists([string]$spec.WorkingDirectory)) {
        throw '工作目录已不存在。'
    }
    $rawArguments = [string]$spec.Arguments
    if ($rawArguments.Length -gt 32768) { throw '启动参数超过最大长度限制。' }
    $id = Get-SpecId $spec
    $name = Get-TaskName 'Fixed' $id $spec
    $description = Get-FixedTaskDescription $id $spec

    $service = New-TaskService
    $folder = Get-ToolTaskFolder $service $true

    $status = Ensure-ElevatedTask $name $description ([string]$spec.TargetPath) `
        ([string]$spec.Arguments) ([string]$spec.WorkingDirectory)
    $newTask = Find-RegisteredTask $folder $name
    if ($null -eq $newTask) { throw "计划任务注册未成功创建：$name" }
    Assert-TaskMatches $newTask $description ([string]$spec.TargetPath) `
        ([string]$spec.Arguments) ([string]$spec.WorkingDirectory)
    Write-Host "[$status] $($script:TaskFolderPath)\$name"
    exit 0
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
