# Test task identity and metadata validation without administrator rights.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Common.ps1')
Assert-Windows

$spec = [pscustomobject]@{
    TargetPath = 'C:\Demo\app.exe'
    Arguments = '--profile default'
    WorkingDirectory = 'C:\Demo'
}
$id = Get-SpecId $spec
$marker = 'ElevatedShortcut:' + $id
$newDescription = Get-FixedTaskDescription $id $spec
$action = [pscustomobject]@{
    Type = 0
    Path = $spec.TargetPath
    Arguments = $spec.Arguments
    WorkingDirectory = $spec.WorkingDirectory
}
$actions = [pscustomobject]@{ Count = 1; TestAction = $action }
$actions | Add-Member -MemberType ScriptMethod -Name Item -Value {
    param([int]$Index)
    if ($Index -ne 1) { throw 'Invalid test action index.' }
    return $this.TestAction
}
$definition = [pscustomobject]@{
    Principal = [pscustomobject]@{
        UserId = (Get-CurrentSid)
        LogonType = 3
        RunLevel = 1
    }
    Actions = $actions
    RegistrationInfo = [pscustomobject]@{Description = $newDescription}
}
$task = [pscustomobject]@{Name = ('Run-app-' + $id); Definition = $definition}
$expectedTaskName = Get-TaskName 'Fixed' $id $spec
if ($task.Name -cne $expectedTaskName) { throw "Unexpected new task name: $($task.Name)" }
if ($null -ne (Get-FixedTaskNameInfo ('Other-' + $id))) { throw 'Non-Run task name should be rejected.' }
Write-Host 'PASS: Run- task name validation'

Assert-TaskMatches $task $newDescription $spec.TargetPath $spec.Arguments $spec.WorkingDirectory
Write-Host 'PASS: full task description matches'

Assert-TaskMatches $task $marker $spec.TargetPath $spec.Arguments $spec.WorkingDirectory
Write-Host 'PASS: marker identity matches readable task description'

$definition.RegistrationInfo.Description = ($newDescription -replace "`r`n", "`n")
Assert-TaskMatches $task $newDescription $spec.TargetPath $spec.Arguments $spec.WorkingDirectory
Write-Host 'PASS: CRLF-to-LF normalized Task Scheduler description matches'

function Assert-Rejected([scriptblock]$Action, [string]$Case) {
    $rejected = $false
    try { & $Action }
    catch { $rejected = $true }
    if (-not $rejected) { throw "FAIL: $Case" }
    Write-Host "PASS: $Case"
}

Assert-Rejected { Assert-TaskMatches $task ($marker + 'x') $spec.TargetPath $spec.Arguments $spec.WorkingDirectory } 'marker mismatch rejected'
Assert-Rejected { Assert-TaskMatches $task $marker $spec.TargetPath 'tampered' $spec.WorkingDirectory } 'arguments mismatch rejected'
$definition.Principal.RunLevel = 0
Assert-Rejected { Assert-TaskMatches $task $marker $spec.TargetPath $spec.Arguments $spec.WorkingDirectory } 'run level mismatch rejected'
Write-Host 'Task metadata checks passed.'
